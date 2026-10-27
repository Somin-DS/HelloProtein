#!/bin/zsh
# usage: collect.sh <udid> <label>   (before-app-state.json must already be in the label dir)
set -u
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
U=$1; L=$2; OUT=/private/tmp/hp-quantity-sim/$L
C=$(xcrun simctl get_app_container $U com.devsom.ProteinTracker data)
D="$C/Library/Application Support/HelloProtein"
xcrun simctl io $U screenshot $OUT/after-launch.png >/dev/null 2>&1
cp "$D/app-state.json" $OUT/after-app-state.json
cp "$D/migration/schema2-app-state.json" $OUT/schema2-backup.json 2>/dev/null
cp "$D/migration/schema-promotion.json" $OUT/schema-promotion.json 2>/dev/null
cp "$D/migration/migration-completed.json" $OUT/migration-completed.json 2>/dev/null
ls -la "$D/migration" > $OUT/migration-dir-after.txt
python3 - $OUT <<'PY'
import json,hashlib,sys,os
o=sys.argv[1]
def info(p):
    b=open(p,'rb').read(); d=json.loads(b)
    return b,d,{'schema':d.get('schemaVersion'),'sha256':hashlib.sha256(b).hexdigest(),'bytes':len(b),'logs':len(d['logs']),
      'records':sum(len(l['records']) for l in d['logs']),'favorites':len(d['favorites']),'searchHistory':len(d['searchHistory']),
      'goals':len(d['goals']),'lastOperationID':d.get('lastOperationID'),'migration':d['migration'],
      'dayTotals':{l['day']:sum(r['protein'] for r in l['records'])+(l.get('legacyAdjustmentCentigrams') or 0) for l in d['logs']}}
bb,bd,bi=info(o+'/before-app-state.json'); ab,ad,ai=info(o+'/after-app-state.json')
res={'before':bi,'after':ai}
bd2=dict(bd); ad2=dict(ad); bd2.pop('schemaVersion',None); ad2.pop('schemaVersion',None)
res['contentIdenticalExceptSchemaVersion']= bd2==ad2
res['basisKeysInAfter']=sum('calculationBasis' in r for l in ad['logs'] for r in l['records'])
if os.path.exists(o+'/schema2-backup.json'):
    kb=open(o+'/schema2-backup.json','rb').read()
    res['backupIdenticalToBefore']= kb==bb
    res['backupSHA256']=hashlib.sha256(kb).hexdigest()
if os.path.exists(o+'/schema-promotion.json'):
    res['promotion']=json.load(open(o+'/schema-promotion.json'))
json.dump(res,open(o+'/summary.json','w'),indent=2,ensure_ascii=False)
print(json.dumps({k:res[k] for k in res if k not in('before','after')},indent=1))
print('before',{k:bi[k] for k in('schema','sha256','bytes','records','lastOperationID')})
print('after ',{k:ai[k] for k in('schema','sha256','bytes','records','lastOperationID')})
PY
