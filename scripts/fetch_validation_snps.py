#!/usr/bin/env python3
"""
Fetch HapMap3 rsIDs whose positions differ between GRCh37 and GRCh38.

This script reads rsIDs from data/hapmap3_snps.tsv, resolves positions via
Ensembl REST API, and writes out variants that move
between assemblies (up to the specified target count).
"""
from __future__ import annotations

import argparse
import json
import random
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path
from typing import Dict, Iterable, List, Optional, Tuple

GRCH37_BASE = "https://grch37.rest.ensembl.org"
GRCH38_BASE = "https://rest.ensembl.org"

HAPMAP3_PATH = Path(__file__).resolve().parent.parent / "data" / "hapmap3_snps.tsv"

VALID_SEQ_REGIONS = {str(i) for i in range(1, 23)} | {"X", "Y"}


def fetch_json(url: str, retries: int = 3, sleep_s: float = 0.5) -> Dict:
    """Fetch JSON from a URL, with retries and throttling."""
    headers = {"Accept": "application/json"}
    last_err: Optional[Exception] = None
    for attempt in range(retries):
        try:
            req = urllib.request.Request(url, headers=headers)
            with urllib.request.urlopen(req, timeout=30) as resp:
                return json.load(resp)
        except (urllib.error.HTTPError, urllib.error.URLError, TimeoutError) as err:
            last_err = err
            if isinstance(err, urllib.error.HTTPError) and err.code == 429:
                time.sleep(sleep_s * (attempt + 2))
            else:
                time.sleep(sleep_s * (attempt + 1))
    raise RuntimeError(f"Failed to fetch {url}: {last_err}")


def read_hapmap_rsids(path: Path) -> List[str]:
    """Read rsIDs from HapMap3 SNP list file (source: https://zenodo.org/records/7773502)."""
    if not path.exists():
        raise FileNotFoundError(f"HapMap3 SNP list not found: {path}")
    rsids: List[str] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            line = line.strip()
            if not line:
                continue
            if line.startswith("SNP"):
                continue
            rsid = line.split("\t", 1)[0]
            if rsid.startswith("rs"):
                rsids.append(rsid)
    return rsids


def get_variant_pos(base_url: str, rsid: str, desired_assembly: str) -> Optional[Tuple[str, int]]:
    """Resolve a variant rsID to a (chrom, position) tuple for an assembly."""
    url = f"{base_url}/variation/human/{rsid}?content-type=application/json"
    data = fetch_json(url)
    mappings = data.get("mappings", [])
    for mapping in mappings:
        if mapping.get("assembly_name") == desired_assembly:
            seq = str(mapping.get("seq_region_name"))
            pos = mapping.get("start")
            if seq in VALID_SEQ_REGIONS and isinstance(pos, int):
                return seq, pos
    for mapping in mappings:
        seq = str(mapping.get("seq_region_name"))
        pos = mapping.get("start")
        if seq in VALID_SEQ_REGIONS and isinstance(pos, int):
            return seq, pos
    return None


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Find HapMap3 rsIDs with different GRCh37/GRCh38 positions."
    )
    parser.add_argument("--target", type=int, default=150, help="Total number of variants to collect.")
    parser.add_argument("--output", type=str, default="validation_snps.tsv", help="TSV output path.")
    parser.add_argument("--debug", action="store_true", help="Print progress/debug messages.")
    args = parser.parse_args()

    def log(message: str) -> None:
        if args.debug:
            print(message, file=sys.stderr)

    results: List[Tuple[str, str, int, int]] = []
    checked = 0

    rsids = read_hapmap_rsids(HAPMAP3_PATH)
    rng = random.Random()
    rng.shuffle(rsids) # Shuffle the SNP list to distribute across locations

    for rsid in rsids:
        checked += 1
        try:
            pos_37 = get_variant_pos(GRCH37_BASE, rsid, "GRCh37")
            pos_38 = get_variant_pos(GRCH38_BASE, rsid, "GRCh38")
        except RuntimeError as err:
            print(f"warn: {err}", file=sys.stderr)
            continue

        if not pos_37 or not pos_38:
            continue
        
        # skip identical positions or different chr
        chr37, p37 = pos_37
        chr38, p38 = pos_38
        if chr37 != chr38:
            continue
        if p37 == p38:
            continue

        results.append((rsid, chr37, p37, p38))
        log(
            f"added variant: {rsid} chr={chr37} hg19={p37} hg38={p38} "
            f"({len(results)}/{args.target})"
        )
        if len(results) >= args.target:
            break

        if args.debug and checked % 200 == 0:
            log(f"checked {checked} rsids, found {len(results)}")

    if not results:
        print("No variants found.", file=sys.stderr)
        return 2

    with open(args.output, "w", encoding="utf-8") as f:
        f.write("rsid\tchr\tpos_hg19\tpos_hg38\n")
        for rsid, chrom, p37, p38 in results:
            f.write(f"{rsid}\t{chrom}\t{p37}\t{p38}\n")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
