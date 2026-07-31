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
import os
import sys
from collections import OrderedDict

STATES = {
    "TX": "Texas", "TEXAS": "Texas", "OK": "Oklahoma", "": "Texas", None: "Texas",
}
COUNTRIES = {
    "USA": "US", "US": "US", "UNITED STATES": "US", "": "US", None: "US",
}

# Facilities the discovery pass explicitly rejected — private member-only clubs,
# permanently closed courses, and practice-only sites. A later completeness pass
# can legitimately re-surface a name that an earlier pass rejected, so this
# blocklist is enforced here at the point data enters the dataset rather than
# relying on every upstream step to remember. Keyed by normalized facility name;
# the reason is kept so the exclusion is auditable rather than mysterious.
BLOCKLIST = {
    "heathgolfyachtclub": "private member-only (Roy Bechtol course inside a residential club)",
    "losriscountryclub": "permanently closed — now a city park",
    "theclubatlosrios": "permanently closed — now a city park",
    "gentlecreekcountryclub": "now private, member-only (Arcis)",
    "gentlecreekgolfclub": "now private, member-only (Arcis)",
    "cedarcreekcountryclub": "private",
    "theoakscountryclub": "private/member, no confirmable public tee times",
    "leonardgolflinks": "practice and instruction facility, no rated course",
    "leatherwoodranchgolfcourse": "permanently closed",
    "pecantrailsgolfcourse": "permanently closed",
    "northmesquitegolfcourse": "permanently closed",
    "hankhaneygolfranchatvistaridge": "permanently closed",
    "threeoakspar3golfcourse": "permanently closed",
    "funcitygolfcourse": "closed",
    "icarefitnesscentergolfcourse": "not verifiable as a real rated course",
}


def blocked(name):
    key = "".join(ch for ch in (name or "").lower() if ch.isalnum())
    for bad, reason in BLOCKLIST.items():
        if key == bad or key.startswith(bad) or bad.startswith(key):
            return reason
    return None


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


def load_corrections():
    """Corrections live in a data file, not in code, so each one carries its evidence."""
    try:
        with open(os.path.join(os.path.dirname(__file__), "corrections.json")) as fh:
            return json.load(fh)
    except FileNotFoundError:
        return {}


def match(a, b):
    ka = "".join(ch for ch in (a or "").lower() if ch.isalnum())
    kb = "".join(ch for ch in (b or "").lower() if ch.isalnum())
    return ka == kb or ka.startswith(kb) or kb.startswith(ka)


def apply_corrections(entry, corr, applied):
    """Returns the corrected entry, or None if the facility should be removed."""
    fname = entry["facility"]["name"]

    for rm in corr.get("remove_facilities", []):
        if match(fname, rm["name"]):
            applied.append(f"removed {fname}: {rm['reason'][:90]}")
            return None

    for rep in corr.get("replace_courses", []):
        if match(fname, rep["facility"]):
            for i, c in enumerate(entry["courses"]):
                if match(c["name"], rep["course"]):
                    entry["courses"][i] = norm_course(rep["course_data"])
                    applied.append(f"replaced {fname} / {rep['course']} with the correct published card")

    for rot in corr.get("rotate_nines", []):
        if not match(fname, rot["facility"]):
            continue
        for c in entry["courses"]:
            if not match(c["name"], rot["course"]):
                continue
            half = c["hole_count"] // 2
            for block in c["pars"].values():
                block["par"] = block["par"][half:] + block["par"][:half]
                block.pop("stroke_index", None)
            # A card printing a single handicap row applies to every par row it
            # publishes. Attach the replacement index to the genders that actually
            # carry par data rather than inventing a par-less gender block.
            for gender, si in (rot.get("replace_stroke_index") or {}).items():
                targets = [gender] if c["pars"].get(gender, {}).get("par") else list(c["pars"])
                for g in targets:
                    if c["pars"].get(g, {}).get("par"):
                        c["pars"][g]["stroke_index"] = si
            for t in c["tees"]:
                if t.get("lengths"):
                    t["lengths"] = t["lengths"][half:] + t["lengths"][:half]
                t["name"] = (rot.get("rename_tees") or {}).get(t["name"], t["name"])
            applied.append(f"rotated nines and re-keyed tees for {fname} / {c['name']}")

    for patch in corr.get("hole_length_patches", []):
        if not match(fname, patch["facility"]):
            continue
        for c in entry["courses"]:
            if not match(c["name"], patch["course"]):
                continue
            for t in c["tees"]:
                if match(t["name"], patch["tee"]) and t.get("lengths"):
                    idx = patch["hole"] - 1
                    if 0 <= idx < len(t["lengths"]):
                        old = t["lengths"][idx]
                        t["lengths"][idx] = patch["length"]
                        applied.append(
                            f"{fname} / {c['name']} [{t['name']}] hole {patch['hole']}: {old} -> {patch['length']}")
    return entry


def main(paths):
    facilities = OrderedDict()
    dropped = []
    corrections = load_corrections()
    applied = []
    for path in paths:
        with open(path) as fh:
            for entry in json.load(fh):
                f = norm_facility(entry.get("facility") or {})
                if not f["name"]:
                    dropped.append(("<unnamed facility>", path))
                    continue
                reason = blocked(f["name"])
                if reason:
                    dropped.append((f["name"], f"blocklisted: {reason}"))
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
                entry_obj = {"facility": f, "courses": courses, "sources": sources}
                entry_obj = apply_corrections(entry_obj, corrections, applied)
                if entry_obj is None:
                    continue
                f, courses, sources = entry_obj["facility"], entry_obj["courses"], entry_obj["sources"]
                courses = [c for c in courses if c["name"] and c["hole_count"] and c["tees"]]
                if not courses:
                    dropped.append((f["name"], "no usable course after corrections"))
                    continue

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

    for a in applied:
        print(f"corrected  {a}", file=sys.stderr)
    for name, why in dropped:
        print(f"dropped  {name}: {why}", file=sys.stderr)
    print(f"\nnormalized {len(out)} facilities, "
          f"{sum(len(f['courses']) for f in out)} courses", file=sys.stderr)


if __name__ == "__main__":
    if len(sys.argv) < 2:
        sys.exit("usage: normalize.py <collected.json> [...]")
    main(sys.argv[1:])
