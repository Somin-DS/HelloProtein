#!/usr/bin/env python3
"""Reproduce exact SR Legacy matches. Supply the official USDA CSV ZIP; no API key.
Usage: python3 scripts/verify_english_catalog.py /path/to/official.zip [--write]
--write changes only verification metadata, never Food/Protein values or order.
"""
import argparse
import csv
import hashlib
import io
import json
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path
import zipfile

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / 'ProteinTracker/ProteinTracker/Assets/Protein-En.json'
REPORT = ROOT / 'docs/evidence/2026-10-08-search-correction/catalog-verification.json'
SOURCE = 'https://fdc.nal.usda.gov/fdc-datasets/FoodData_Central_sr_legacy_food_csv_2018-04.zip'
# Pin the actual official archive so a different edition cannot silently attest rows.
ARCHIVE_SHA = 'b80817294b8850530aaedf2e515c02593b1824f763a0ff356e5c2081643e6fd0'

def verify(archive, write=False):
    digest = hashlib.sha256(archive.read_bytes()).hexdigest()
    if digest != ARCHIVE_SHA:
        raise ValueError('Official archive digest differs; review source edition first')
    with zipfile.ZipFile(archive) as z:
        def rows(name):
            path = next(p for p in z.namelist() if p.endswith('/' + name))
            return list(csv.DictReader(io.TextIOWrapper(z.open(path))))
        nutrients = {r['id']: r for r in rows('nutrient.csv')}
        assert nutrients['1003']['name'] == 'Protein' and nutrients['1003']['unit_name'] == 'G'
        foods = defaultdict(list)
        for r in rows('food.csv'):
            assert r['data_type'] == 'sr_legacy_food'
            foods[r['description']].append(r['fdc_id'])
        protein = {r['fdc_id']: Decimal(r['amount']) for r in rows('food_nutrient.csv') if r['nutrient_id'] == '1003'}
    raw = CATALOG.read_text()
    catalog = json.loads(raw, parse_float=Decimal)
    report = []
    # JSON is rewritten using its existing numeric tokens, not binary floating point.
    for index, row in enumerate(catalog):
        candidates = foods[row['Food']]
        matches = [fid for fid in candidates if protein.get(fid) == Decimal(row['Protein'])]
        verified = matches[0] if len(matches) == 1 else None
        status = 'exact' if verified else 'different' if candidates else 'missing'
        report.append({'row': index, 'name': row['Food'], 'protein': str(row['Protein']),
                       'status': status, 'fdcID': verified,
                       'candidates': [{'fdcID': fid, 'protein': str(protein.get(fid))} for fid in candidates]})
        row['VerifiedFDCID'] = verified
    def encode_row(row):
        return '  {"Food": ' + json.dumps(row['Food'], ensure_ascii=False) + ', "Protein": ' + str(row['Protein']) + ', "VerifiedFDCID": ' + json.dumps(row['VerifiedFDCID']) + '}'
    generated = '[\n' + ',\n'.join(encode_row(r) for r in catalog) + '\n]\n'
    summary = {'sourceURL': SOURCE, 'archiveSHA256': digest,
               'catalogSHA256': hashlib.sha256(generated.encode()).hexdigest(),
               'counts': dict(Counter(r['status'] for r in report)), 'rows': report}
    if write:
        CATALOG.write_text(generated)
        REPORT.parent.mkdir(parents=True, exist_ok=True)
        REPORT.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + '\n')
    else:
        assert raw == generated, 'Catalog metadata is stale; run --write and review the diff'
        assert json.loads(REPORT.read_text()) == summary, 'Verification report differs'
    print(json.dumps({k:v for k,v in summary.items() if k != 'rows'}, indent=2))

if __name__ == '__main__':
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('archive', type=Path)
    parser.add_argument('--write', action='store_true')
    args = parser.parse_args()
    verify(args.archive, args.write)
