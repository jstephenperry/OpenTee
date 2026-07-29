#!/usr/bin/env python3
"""Normalize harvested collector output into the generator's input format.

    python3 db/data/normalize.py db/data/collected/*.json > db/data/dfw_tx.json

Collectors return data close to the target shape but with human/source-level
variation that the schema would reject: "USA" instead of the ISO alpha-2 "US",
state as "TX" rather than a full name, empty ratings arrays, tees whose
"lengths" came back as nulls, and duplicate facilities across batches. This
module makes those consistent and drops what cannot be salvaged, so
generate.py sees a uniform dataset.
"""

import json
import sys
from collections import OrderedDict

STATES = {
    "TX": "Texas", "TEXAS": "Texas", "OK": "Oklahoma", "": "Texas", None: "Texas",
}
COUNTRIES = {
    "USA": "US", "US": "US", "UNITED STATES": "US", "": "US", None: "US",
}


def norm_facility(f):
    state = (f.get("state_province") or "").strip()
    country = (f.get("country") or "").strip()
    return {
        "name": (f.get("name") or "").strip(),
        "address": clean(f.get("address")),
        "city": clean(f.get("city")),
        "state_province": STATES.get(state.upper(), state or "Texas"),
        "country": COUNTRIES.get(country.upper(), "US"),
        "postal_code": clean(f.get("postal_code")),
        "website_url": clean_url(f.get("website_url")),
    }


def clean(v):
    if v is None:
        return None
    v = str(v).strip()
    return v or None


def clean_url(v):
    v = clean(v)
    if not v:
        return None
    if not v.startswith(("http://", "https://")):
        v = "https://" + v
    return v


def norm_course(c):
    holes = c.get("hole_count")
    out = {"name": (c.get("name") or "").strip(), "hole_count": holes}

    names = c.get("hole_names")
    if isinstance(names, list) and names and any(n for n in names):
        out["hole_names"] = [clean(n) or "" for n in names]

    pars = {}
    for gender, block in (c.get("pars") or {}).items():
        if not isinstance(block, dict):
            continue
        par = block.get("par")
        if not isinstance(par, list) or not par:
            continue
        entry = {"par": [int(p) for p in par if p is not None]}
        si = block.get("stroke_index")
        if isinstance(si, list) and si and all(s is not None for s in si):
            entry["stroke_index"] = [int(s) for s in si]
        pars[gender] = entry
    out["pars"] = pars

    tees = []
    for t in c.get("tees") or []:
        tee = {
            "name": (t.get("name") or "").strip(),
            "unit": t.get("unit") if t.get("unit") in ("yards", "meters") else "yards",
        }
        total = t.get("published_total")
        if isinstance(total, (int, float)) and total:
            tee["published_total"] = int(total)
        lengths = t.get("lengths")
        if isinstance(lengths, list) and lengths and all(isinstance(v, (int, float)) and v for v in lengths):
            tee["lengths"] = [int(v) for v in lengths]
        ratings = []
        for r in t.get("ratings") or []:
            g, rt, sl = r.get("gender"), r.get("rating"), r.get("slope")
            if g in ("men", "women") and rt and sl:
                ratings.append({"gender": g, "rating": round(float(rt), 1), "slope": int(sl)})
        # One rating per gender per tee (the schema enforces this).
        seen = set()
        tee["ratings"] = [r for r in ratings if not (r["gender"] in seen or seen.add(r["gender"]))]
        if tee["name"]:
            tees.append(tee)
    out["tees"] = tees
    return out


def main(paths):
    facilities = OrderedDict()
    dropped = []
    for path in paths:
        with open(path) as fh:
            for entry in json.load(fh):
                f = norm_facility(entry.get("facility") or {})
                if not f["name"]:
                    dropped.append(("<unnamed facility>", path))
                    continue
                key = (f["name"].lower(), (f["city"] or "").lower())
                courses = [norm_course(c) for c in entry.get("courses") or []]
                courses = [c for c in courses if c["name"] and c["hole_count"] and c["tees"]]
                if not courses:
                    dropped.append((f["name"], f"{path}: no usable course"))
                    continue
                sources = []
                for s in entry.get("sources") or []:
                    sources.append({
                        "type": s.get("type", "other"),
                        "url": clean_url(s.get("url")),
                        "note": clean(s.get("note")),
                    })
                if key in facilities:
                    # Same facility harvested twice — merge courses not already present.
                    have = {c["name"].lower() for c in facilities[key]["courses"]}
                    for c in courses:
                        if c["name"].lower() not in have:
                            facilities[key]["courses"].append(c)
                    facilities[key]["sources"].extend(sources)
                else:
                    facilities[key] = {"facility": f, "courses": courses, "sources": sources}

    out = list(facilities.values())
    print(json.dumps({
        "title": "DFW public golf courses",
        "description": ("Public (municipal, daily-fee, resort and public-access semi-private) golf "
                        "courses across the Dallas-Fort Worth Metroplex. Arlington's four municipal "
                        "courses are in db/data/arlington_tx.sql."),
        "date": "2026-07-29",
        "facilities": out,
    }, indent=1))

    for name, why in dropped:
        print(f"dropped  {name}: {why}", file=sys.stderr)
    print(f"\nnormalized {len(out)} facilities, "
          f"{sum(len(f['courses']) for f in out)} courses", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: normalize.py <collected.json> [...]")
    main(sys.argv[1:])
