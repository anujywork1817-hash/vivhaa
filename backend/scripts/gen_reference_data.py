#!/usr/bin/env python3
"""Regenerates the embedded geography files in internal/reference/data.

The upstream countries-states-cities dataset is ~46 MB and carries far more
per-record detail than the pickers need (coordinates, timezones, currencies,
translations). This strips it down to the three files the API actually
serves, which together come to well under a megabyte on disk:

    countries.json    code / name / flag emoji, sorted by name
    states.json       country code -> [{code, name}]
    cities.json.gz    country code -> state code -> [city name]

Cities are gzipped because they are ~2 MB uncompressed and ~780 KB packed;
the server inflates them once at startup.

Usage:
    python scripts/gen_reference_data.py [path/to/countries+states+cities.json]

With no argument the source is downloaded to a temp file. Re-run this after
an upstream dataset refresh and commit the regenerated files.
"""

import gzip
import io
import json
import os
import sys
import tempfile
import urllib.request

SOURCE_URL = (
    "https://raw.githubusercontent.com/dr5hn/countries-states-cities-database"
    "/master/json/countries+states+cities.json"
)

OUT_DIR = os.path.join(
    os.path.dirname(os.path.abspath(__file__)), "..", "internal", "reference", "data"
)


def load_source(path=None):
    if path:
        print("reading {}".format(path))
        with io.open(path, encoding="utf-8") as fh:
            return json.load(fh)

    print("downloading {}".format(SOURCE_URL))
    with urllib.request.urlopen(SOURCE_URL) as resp:
        raw = resp.read()
    tmp = os.path.join(tempfile.gettempdir(), "countries+states+cities.json")
    with io.open(tmp, "wb") as fh:
        fh.write(raw)
    print("cached source at {} ({} bytes)".format(tmp, len(raw)))
    return json.loads(raw.decode("utf-8"))


def build(source):
    countries, states, cities = [], {}, {}

    for country in sorted(source, key=lambda c: c["name"]):
        code = (country.get("iso2") or "").strip()
        if not code:
            # A country with no ISO code can't be keyed or looked up, and the
            # dataset has none today — but skip rather than emit a bad key.
            print("skipping {}: no iso2".format(country.get("name")))
            continue

        countries.append(
            {
                "code": code,
                "name": country["name"],
                "emoji": country.get("emoji") or "",
            }
        )

        country_states = sorted(country.get("states") or [], key=lambda s: s["name"])
        if not country_states:
            continue

        states[code] = [
            {"code": s["iso2"], "name": s["name"]} for s in country_states
        ]

        by_state = {}
        for state in country_states:
            # De-duplicated: the dataset carries a few repeated city rows that
            # differ only by coordinates, which would show as double entries.
            names = sorted(
                {
                    (c.get("name") or "").strip()
                    for c in (state.get("cities") or [])
                    if (c.get("name") or "").strip()
                }
            )
            if names:
                by_state[state["iso2"]] = names
        if by_state:
            cities[code] = by_state

    return countries, states, cities


def write_json(obj, name):
    path = os.path.join(OUT_DIR, name)
    blob = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    with io.open(path, "wb") as fh:
        fh.write(blob)
    print("{:<18} {:>9,} bytes".format(name, len(blob)))
    return blob


def write_gzip(obj, name):
    blob = json.dumps(obj, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
    # mtime=0 keeps the output byte-identical between runs, so regenerating
    # from an unchanged source produces an empty diff.
    packed = gzip.compress(blob, compresslevel=9, mtime=0)
    path = os.path.join(OUT_DIR, name)
    with io.open(path, "wb") as fh:
        fh.write(packed)
    print("{:<18} {:>9,} bytes ({:,} raw)".format(name, len(packed), len(blob)))


def main():
    source = load_source(sys.argv[1] if len(sys.argv) > 1 else None)
    countries, states, cities = build(source)

    os.makedirs(OUT_DIR, exist_ok=True)
    write_json(countries, "countries.json")
    write_json(states, "states.json")
    write_gzip(cities, "cities.json.gz")

    print(
        "\n{:,} countries, {:,} states, {:,} cities".format(
            len(countries),
            sum(len(v) for v in states.values()),
            sum(len(c) for m in cities.values() for c in m.values()),
        )
    )


if __name__ == "__main__":
    main()
