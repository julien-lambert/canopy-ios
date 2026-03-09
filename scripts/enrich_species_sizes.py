#!/usr/bin/env python3
import argparse
import csv
import html
import json
import os
import re
import sqlite3
import ssl
import sys
import time
import urllib.parse
import urllib.request
import xml.etree.ElementTree as ET
from dataclasses import dataclass
from typing import List, Optional, Tuple

BING_RSS = "https://www.bing.com/search?format=rss&q={query}"
USER_AGENT = "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/125 Safari/537.36"

HEIGHT_KEYS = ["hauteur", "height", "haut", "tall"]
SPREAD_KEYS = ["envergure", "largeur", "etalement", "étalement", "spread", "width", "crown"]

SSL_CTX = ssl._create_unverified_context()


def http_get(url: str, timeout: int = 20) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=timeout, context=SSL_CTX) as resp:
        return resp.read().decode("utf-8", errors="ignore")


def normalize_space(s: str) -> str:
    return re.sub(r"\s+", " ", s).strip()


def html_to_text(doc: str) -> str:
    doc = re.sub(r"(?is)<script.*?>.*?</script>", " ", doc)
    doc = re.sub(r"(?is)<style.*?>.*?</style>", " ", doc)
    doc = re.sub(r"(?is)<[^>]+>", " ", doc)
    doc = html.unescape(doc)
    return normalize_space(doc)


def to_meters(value: float, unit: str) -> float:
    u = unit.lower()
    if u == "m":
        return value
    if u == "cm":
        return value / 100.0
    if u == "ft":
        return value * 0.3048
    return value


def parse_num(s: str) -> Optional[float]:
    s = s.replace(",", ".")
    try:
        return float(s)
    except Exception:
        return None


def extract_candidates(fragment: str) -> List[Tuple[float, float]]:
    out: List[Tuple[float, float]] = []

    # range with unit
    for m in re.finditer(r"(\d{1,2}(?:[\.,]\d+)?)\s*(?:-|–|—|à|to)\s*(\d{1,2}(?:[\.,]\d+)?)\s*(m|cm|ft)\b", fragment, flags=re.I):
        a = parse_num(m.group(1))
        b = parse_num(m.group(2))
        u = m.group(3)
        if a is None or b is None:
            continue
        lo, hi = sorted([to_meters(a, u), to_meters(b, u)])
        out.append((lo, hi))

    # single value with unit
    for m in re.finditer(r"(\d{1,2}(?:[\.,]\d+)?)\s*(m|cm|ft)\b", fragment, flags=re.I):
        v = parse_num(m.group(1))
        u = m.group(2)
        if v is None:
            continue
        val = to_meters(v, u)
        out.append((val, val))

    return out


def pick_range(text: str, keywords: List[str], low: float, high: float) -> Optional[Tuple[float, float]]:
    # sentence-ish chunks
    chunks = re.split(r"[\.;\|\n]", text)
    scored: List[Tuple[int, float, float]] = []
    for ch in chunks:
        lch = ch.lower()
        if not any(k in lch for k in keywords):
            continue
        cand = extract_candidates(ch)
        for lo, hi in cand:
            if lo < low or hi > high:
                continue
            score = 1
            if any(k in lch for k in ["adulte", "mature", "max", "maximum"]):
                score += 1
            if "environ" in lch or "about" in lch or "approx" in lch:
                score -= 1
            scored.append((score, lo, hi))

    if not scored:
        return None

    # best score then narrowest plausible range
    scored.sort(key=lambda x: (-x[0], (x[2] - x[1])))
    _, lo, hi = scored[0]
    return (round(lo, 2), round(hi, 2))


@dataclass
class SpeciesRow:
    id: int
    latin_name: str
    common_name: str
    strata: Optional[str]
    height_min: Optional[float]
    height_max: Optional[float]



def fetch_species_local(db_path: str) -> List[SpeciesRow]:
    conn = sqlite3.connect(db_path)
    cur = conn.cursor()
    cur.execute(
        """
        SELECT id, latin_name, COALESCE(common_name,''), strata, height_min, height_max
        FROM species
        WHERE COALESCE(deleted,0)=0
        ORDER BY latin_name
        """
    )
    rows = [SpeciesRow(*r) for r in cur.fetchall()]
    conn.close()
    return rows


def search_links(latin_name: str, common_name: str) -> List[Tuple[str, str]]:
    q = f'{latin_name} {common_name} hauteur envergure'
    url = BING_RSS.format(query=urllib.parse.quote_plus(q))
    xml_text = http_get(url, timeout=25)
    links: List[Tuple[str, str]] = []
    try:
        root = ET.fromstring(xml_text)
        for item in root.findall("./channel/item"):
            link_el = item.find("link")
            desc_el = item.find("description")
            link = link_el.text.strip() if link_el is not None and link_el.text else ""
            desc = html.unescape(desc_el.text).strip() if desc_el is not None and desc_el.text else ""
            if link:
                links.append((link, desc))
    except Exception:
        return []
    # basic de-dup
    dedup = []
    seen = set()
    for l, d in links:
        if l in seen:
            continue
        seen.add(l)
        dedup.append((l, d))
    return dedup


def fallback_spread_from_height(height_max: Optional[float], strata: Optional[str]) -> Optional[Tuple[float, float]]:
    if not height_max or height_max <= 0:
        return None
    s = (strata or "").lower()
    # Ratios conservateurs par strate
    if "canop" in s:
        rmin, rmax = 0.45, 0.90
    elif "sous" in s:
        rmin, rmax = 0.40, 0.80
    elif "arbuste" in s:
        rmin, rmax = 0.60, 1.10
    elif "herbac" in s:
        rmin, rmax = 0.40, 0.90
    elif "couvre" in s:
        rmin, rmax = 0.50, 1.20
    else:
        rmin, rmax = 0.45, 0.95

    emin = round(max(0.2, height_max * rmin), 2)
    emax = round(max(emin, height_max * rmax), 2)
    return emin, emax


def supabase_patch_species(base_url: str, key: str, species_id: int, payload: dict) -> Tuple[bool, str]:
    qs = urllib.parse.urlencode({"id": f"eq.{species_id}"})
    url = f"{base_url.rstrip('/')}/rest/v1/species?{qs}"
    data = json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(
        url,
        data=data,
        method="PATCH",
        headers={
            "apikey": key,
            "Authorization": f"Bearer {key}",
            "Content-Type": "application/json",
            "Prefer": "return=minimal",
            "User-Agent": USER_AGENT,
        },
    )
    try:
        with urllib.request.urlopen(req, timeout=25, context=SSL_CTX) as resp:
            ok = 200 <= resp.status < 300
            return ok, f"HTTP {resp.status}"
    except Exception as e:
        return False, str(e)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--db", default="/Users/lambert/JardinForet/JardinForet/jardin.db")
    ap.add_argument("--apply", action="store_true", help="Push updates to Supabase")
    ap.add_argument("--limit", type=int, default=0)
    ap.add_argument("--sleep", type=float, default=0.25)
    ap.add_argument("--max-links", type=int, default=2)
    ap.add_argument("--report", default="/Users/lambert/JardinForet/supabase_species_size_enrichment_report.csv")
    args = ap.parse_args()

    supabase_url = os.getenv("SUPABASE_URL", "https://frmyjegzevwlkuxxejsj.supabase.co")
    supabase_key = os.getenv("SUPABASE_ANON_KEY", "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZybXlqZWd6ZXZ3bGt1eHhlanNqIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjM2ODUyMTEsImV4cCI6MjA3OTI2MTIxMX0.efCNUURNr_hGabyfMQBfQYeNHYvgyOXp9FwulnD-l7E")

    rows = fetch_species_local(args.db)
    if args.limit > 0:
        rows = rows[: args.limit]

    enriched = []
    patched_ok = 0
    patched_err = 0

    for idx, sp in enumerate(rows, start=1):
        links = search_links(sp.latin_name, sp.common_name)

        best_height = None
        best_spread = None
        chosen_link = ""

        for link, desc in links[: args.max_links]:
            if desc:
                if not best_height:
                    best_height = pick_range(desc, HEIGHT_KEYS, low=0.1, high=80.0)
                if not best_spread:
                    best_spread = pick_range(desc, SPREAD_KEYS, low=0.1, high=80.0)
                if best_height and best_spread:
                    chosen_link = link
                    break
            try:
                raw = http_get(link, timeout=8)
            except Exception:
                continue
            text = html_to_text(raw)
            h = pick_range(text, HEIGHT_KEYS, low=0.1, high=80.0)
            e = pick_range(text, SPREAD_KEYS, low=0.1, high=80.0)
            if h or e:
                chosen_link = link
                if h and not best_height:
                    best_height = h
                if e and not best_spread:
                    best_spread = e
                if best_height and best_spread:
                    break

        # keep existing if better known
        hmin = sp.height_min
        hmax = sp.height_max
        if best_height:
            # update only if empty or clearly inconsistent
            bhmin, bhmax = best_height
            if hmin is None:
                hmin = bhmin
            if hmax is None:
                hmax = bhmax

        if best_spread:
            emin, emax = best_spread
            spread_source = "web"
        else:
            fb = fallback_spread_from_height(hmax or hmin, sp.strata)
            if fb:
                emin, emax = fb
                spread_source = "fallback_from_height"
            else:
                emin, emax = (None, None)
                spread_source = "none"

        payload = {}
        if hmin is not None:
            payload["height_min"] = round(float(hmin), 2)
        if hmax is not None:
            payload["height_max"] = round(float(hmax), 2)
        if emin is not None:
            payload["envergure_min"] = round(float(emin), 2)
        if emax is not None:
            payload["envergure_max"] = round(float(emax), 2)

        status = "dry_run"
        status_msg = ""
        if args.apply and payload:
            ok, msg = supabase_patch_species(supabase_url, supabase_key, sp.id, payload)
            status = "patched" if ok else "error"
            status_msg = msg
            if ok:
                patched_ok += 1
            else:
                patched_err += 1

        enriched.append(
            {
                "id": sp.id,
                "latin_name": sp.latin_name,
                "common_name": sp.common_name,
                "strata": sp.strata or "",
                "height_min_old": sp.height_min,
                "height_max_old": sp.height_max,
                "height_min_new": payload.get("height_min"),
                "height_max_new": payload.get("height_max"),
                "envergure_min_new": payload.get("envergure_min"),
                "envergure_max_new": payload.get("envergure_max"),
                "spread_source": spread_source,
                "source_url": chosen_link,
                "status": status,
                "status_msg": status_msg,
            }
        )

        print(
            f"[{idx}/{len(rows)}] {sp.latin_name}: "
            f"h=({payload.get('height_min')},{payload.get('height_max')}) "
            f"e=({payload.get('envergure_min')},{payload.get('envergure_max')}) "
            f"[{spread_source}] {status}",
            flush=True,
        )
        time.sleep(args.sleep)

    fieldnames = list(enriched[0].keys()) if enriched else []
    with open(args.report, "w", newline="", encoding="utf-8") as f:
        w = csv.DictWriter(f, fieldnames=fieldnames)
        w.writeheader()
        for r in enriched:
            w.writerow(r)

    print("---")
    print(f"Report: {args.report}")
    print(f"Rows: {len(enriched)}")
    print(f"Patched ok: {patched_ok}")
    print(f"Patched err: {patched_err}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
