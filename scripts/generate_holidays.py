#!/usr/bin/env python3
"""Regenerates SupportCareKit/Sources/SupportCareCore/Resources/au_public_holidays.json.

    python3 -m pip install holidays && python3 scripts/generate_holidays.py 2025 2032

Data comes from the `python-holidays` package. Check it against your state's official
gazette each year, especially regional or part-day holidays such as Melbourne Cup and
Christmas Eve or NYE evenings.
"""
import json, sys, pathlib
import holidays

years = list(range(int(sys.argv[1]), int(sys.argv[2]) + 1)) if len(sys.argv) == 3 else list(range(2025, 2031))
out = {"source": f"python-holidays {holidays.__version__}", "years": years, "states": {}}
for st in ["ACT", "NSW", "NT", "QLD", "SA", "TAS", "VIC", "WA"]:
    out["states"][st] = [
        {"date": d.isoformat(), "name": n}
        for y in years
        for d, n in sorted(holidays.Australia(subdiv=st, years=y).items())
    ]
path = pathlib.Path(__file__).resolve().parent.parent / "SupportCareKit/Sources/SupportCareCore/Resources/au_public_holidays.json"
path.write_text(json.dumps(out, indent=1, ensure_ascii=False))
print(f"wrote {path}")
