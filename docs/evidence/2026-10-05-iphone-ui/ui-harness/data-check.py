#!/usr/bin/env python3
"""Reads app-state.json from a simulator container and prints the checks used in the README."""
import json, sys, subprocess, os
udid = sys.argv[1]
env = dict(os.environ, DEVELOPER_DIR="/Applications/Xcode.app/Contents/Developer")
container = subprocess.check_output(["xcrun", "simctl", "get_app_container", udid, "com.devsom.ProteinTracker", "data"], env=env).decode().strip()
d = json.load(open(os.path.join(container, "Library/Application Support/HelloProtein/app-state.json")))
logs = {l["day"]: l for l in d["logs"]}
def total(day):
    l = logs.get(day)
    if not l: return None
    return sum(r["protein"] for r in l.get("records", [])) + (l.get("legacyAdjustmentCentigrams") or 0)
ids = [r["id"] for l in d["logs"] for r in l.get("records", [])]
today = sys.argv[2]
today_log = logs.get(today, {"records": []})
names = [r.get("name") for r in today_log["records"]]
out = {
    "udid": udid,
    "day_2026-09-23": {
        "originalCentigrams": logs["2026-09-23"]["legacyAggregate"]["importedTotalCentigrams"],
        "detailCentigrams": sum(r["protein"] for r in logs["2026-09-23"]["records"]),
        "adjustmentCentigrams": logs["2026-09-23"].get("legacyAdjustmentCentigrams"),
        "totalCentigrams": total("2026-09-23"),
        "recordCount": len(logs["2026-09-23"]["records"]),
    },
    "day_2026-09-20": {
        "originalCentigrams": logs["2026-09-20"]["legacyAggregate"]["importedTotalCentigrams"],
        "totalCentigrams": total("2026-09-20"),
        "recordCount": len(logs["2026-09-20"]["records"]),
    },
    "today": today,
    "todayRecords": [{"name": r.get("name"), "centigrams": r["protein"]} for r in today_log["records"]],
    "todayTotalCentigrams": total(today),
    "pendingRowCount": sum(1 for n in names if n and n.startswith("Pending save")),
    "lifecycleRowAbsent": not any(n and n.startswith("Grilled chicken") for n in names),
    "uniqueRecordIDs": len(ids) == len(set(ids)),
    "goals": d["goals"],
    "favoriteCount": len(d["favorites"]),
    "searchHistoryCount": len(d["searchHistory"]),
    "migrationCompletedAt": d["migration"]["completedAt"],
}
print(json.dumps(out, ensure_ascii=False, indent=2))
