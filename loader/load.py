#!/usr/bin/env python3
"""Download Charlotte + Sarasota County property appraiser data, parcel polygons and
FEMA flood zones, stage them in PostGIS (schema `raw`) and build the public tables.

Usage (inside the loader container):
    python load.py              # re-download anything older than MAX_AGE_DAYS, then load
    python load.py --refresh    # force re-download of everything
    python load.py --no-download
"""
import argparse
import csv
import io
import json
import os
import re
import subprocess
import sys
import time
import urllib.request
import zipfile
from pathlib import Path

import openpyxl
import psycopg2

DATA = Path(os.environ.get("DATA_DIR", "/data"))
SQL = Path(os.environ.get("SQL_DIR", "/sql"))
MAX_AGE_DAYS = float(os.environ.get("MAX_AGE_DAYS", "6"))
UA = "Mozilla/5.0 (swfl-gis loader; personal research use)"

FEMA = "https://msc.fema.gov/portal/downloadProduct?productTypeID=NFHL&productSubTypeID=NFHL_COUNTY_DATA&productID=NFHL_{}"
SARASOTA_PARCELS_FS = ("https://services3.arcgis.com/icrWMv7eBkctFu1f/arcgis/rest/services/"
                       "ParcelHosted/FeatureServer/0")

DOWNLOADS = {
    # Charlotte County Property Appraiser (nightly) — https://www.ccappraiser.com/Downloads.aspx
    "charlotte/charlotte.zip": "https://www.ccappraiser.com/downloads/charlotte.zip",
    "charlotte/sales.zip": "https://www.ccappraiser.com/downloads/sales.zip",
    "charlotte/land_use_codes.xlsx": "https://www.ccappraiser.com/downloads/land%20use%20codes.xlsx",
    # Charlotte County GIS parcel polygons (weekly) — https://www.charlottecountyfl.gov/gis/shapefile-gallery.stml
    "charlotte/accounts.zip": "https://data.charlottecountyfl.gov/ccgis/data/zips/accounts.zip",
    # Sarasota County Property Appraiser — https://www.sc-pa.com/downloads/download-data/
    "sarasota/SCPA_Parcels_Sales_CSV.zip":
        "https://www.sarasotapropertyappraiser.gov/downloads/SCPA_Parcels_Sales_CSV.zip",
    # FEMA National Flood Hazard Layer, countywide effective data
    "fema/NFHL_12015C.zip": FEMA.format("12015C"),   # Charlotte
    "fema/NFHL_12115C.zip": FEMA.format("12115C"),   # Sarasota
}


def log(*a):
    print(time.strftime("%H:%M:%S"), *a, flush=True)


def stale(p: Path) -> bool:
    return not p.exists() or p.stat().st_size == 0 or (time.time() - p.stat().st_mtime) > MAX_AGE_DAYS * 86400


def fetch(url: str, dest: Path, attempts: int = 4):
    dest.parent.mkdir(parents=True, exist_ok=True)
    tmp = dest.with_suffix(dest.suffix + ".part")
    for i in range(1, attempts + 1):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": UA})
            with urllib.request.urlopen(req, timeout=600) as r, open(tmp, "wb") as f:
                final = r.geturl()
                expected = int(r.headers.get("Content-Length") or 0)
                while chunk := r.read(1 << 20):
                    f.write(chunk)
            # FEMA's server sometimes ends the stream early without an error
            got = tmp.stat().st_size
            if expected and got != expected:
                raise IOError(f"truncated: {got} of {expected} bytes")
            if dest.suffix in (".zip", ".xlsx"):
                with zipfile.ZipFile(tmp) as z:
                    if (bad := z.testzip()) is not None:
                        raise IOError(f"corrupt member {bad}")
            tmp.replace(dest)
            (dest.parent / (dest.name + ".url")).write_text(final)
            log(f"  downloaded {dest.name} ({dest.stat().st_size / 1e6:.1f} MB)")
            return
        except Exception as e:  # noqa: BLE001
            log(f"  attempt {i} failed for {url}: {e}")
            time.sleep(10 * i)
    raise RuntimeError(f"could not download {url}")


def fetch_featureserver(url: str, dest: Path, out_fields: str, page: int = 2000):
    """Page through an ArcGIS FeatureServer layer into a GeoJSON file (WGS84)."""
    total = json.load(urllib.request.urlopen(
        f"{url}/query?where=1%3D1&returnCountOnly=true&f=json", timeout=120))["count"]
    log(f"  {total} features to fetch from {url}")
    tmp = dest.with_suffix(".part")
    with open(tmp, "w") as out:
        out.write('{"type":"FeatureCollection","features":[\n')
        first, offset = True, 0
        while offset < total:
            q = (f"{url}/query?where=1%3D1&outFields={out_fields}&outSR=4326&f=geojson"
                 f"&orderByFields=OBJECTID&resultOffset={offset}&resultRecordCount={page}")
            for i in range(1, 6):
                try:
                    feats = json.load(urllib.request.urlopen(
                        urllib.request.Request(q, headers={"User-Agent": UA}), timeout=300))["features"]
                    break
                except Exception as e:  # noqa: BLE001
                    log(f"    page {offset} attempt {i} failed: {e}")
                    time.sleep(5 * i)
            else:
                raise RuntimeError(f"failed to fetch page at offset {offset}")
            for ft in feats:
                out.write(("" if first else ",\n") + json.dumps(ft, separators=(",", ":")))
                first = False
            offset += page
            if offset // page % 25 == 0:
                log(f"    {min(offset, total)}/{total}")
        out.write("\n]}\n")
    tmp.replace(dest)


def download(force: bool):
    for rel, url in DOWNLOADS.items():
        dest = DATA / "raw" / rel
        if force or stale(dest):
            log(f"downloading {rel}")
            fetch(url, dest)
        else:
            log(f"cached {rel}")
    dest = DATA / "raw" / "sarasota" / "parcels.geojson"
    if force or stale(dest):
        log("downloading Sarasota parcel polygons (feature service)")
        fetch_featureserver(SARASOTA_PARCELS_FS, dest, "ID,ACCOUNT")
    else:
        log("cached sarasota/parcels.geojson")


# --------------------------------------------------------------------------- DB helpers

def connect():
    return psycopg2.connect("")  # PG* env vars


def colname(h: str) -> str:
    c = re.sub(r"[^a-z0-9]+", "_", h.strip().lower()).strip("_")
    return c or "col"


def load_table(cur, table: str, header, rows):
    cols = []
    for h in header:
        c = colname(h)
        while c in cols:
            c += "_"
        cols.append(c)
    cur.execute(f"DROP TABLE IF EXISTS raw.{table}")
    cur.execute(f"CREATE UNLOGGED TABLE raw.{table} ({', '.join(f'{c} text' for c in cols)})")
    buf, n, bad = io.StringIO(), 0, 0
    w = csv.writer(buf)
    copy_sql = f"COPY raw.{table} FROM STDIN WITH (FORMAT csv)"
    for r in rows:
        if len(r) != len(cols):
            bad += 1
            r = (list(r) + [""] * len(cols))[:len(cols)]
        w.writerow([v.strip().replace("\x00", "") for v in r])
        n += 1
        if n % 50000 == 0:
            buf.seek(0)
            cur.copy_expert(copy_sql, buf)
            buf.seek(0)
            buf.truncate()
    buf.seek(0)
    cur.copy_expert(copy_sql, buf)
    log(f"  raw.{table}: {n} rows" + (f" ({bad} with wrong field count, padded/truncated)" if bad else ""))
    return n


def zip_member(zpath: Path, pattern: str):
    z = zipfile.ZipFile(zpath)
    for name in z.namelist():
        if re.search(pattern, name, re.I):
            return z, name
    raise FileNotFoundError(f"{pattern} not in {zpath}")


def load_zip_text(cur, zpath, pattern, table, delimiter=",", quoting=csv.QUOTE_MINIMAL):
    z, name = zip_member(zpath, pattern)
    with z.open(name) as f:
        text = io.TextIOWrapper(f, encoding="cp1252", errors="replace", newline="")
        r = csv.reader(text, delimiter=delimiter, quoting=quoting)
        header = next(r)
        return load_table(cur, table, header, r)


def load_xlsx_codes(cur, path, table):
    ws = openpyxl.load_workbook(path, read_only=True).worksheets[0]
    rows = []
    for row in ws.iter_rows(values_only=True):
        if row and row[0] is not None and row[1] is not None:
            code = str(row[0]).strip()
            if re.fullmatch(r"[0-9A-Z]{1,6}", code):
                rows.append([code, str(row[1]).strip()])
    return load_table(cur, table, ["code", "description"], rows)


def ogr(src: str, table: str, *extra):
    pg = "PG:" + " ".join(f"{k}={os.environ[v]}" for k, v in
                          [("host", "PGHOST"), ("dbname", "PGDATABASE"), ("user", "PGUSER")])
    cmd = ["ogr2ogr", "-f", "PostgreSQL", pg, src,
           "-nln", f"raw.{table}", "-t_srs", "EPSG:4326", "-nlt", "PROMOTE_TO_MULTI",
           "-lco", "GEOMETRY_NAME=geom", "-lco", "PRECISION=NO", "-lco", "SPATIAL_INDEX=NONE",
           "-lco", "UNLOGGED=ON", "--config", "PG_USE_COPY", "YES", "-skipfailures", *extra]
    subprocess.run(cmd, check=True)


def file_date(p: Path) -> str:
    return time.strftime("%Y-%m-%d", time.gmtime(p.stat().st_mtime))


def stage():
    raw = DATA / "raw"
    con = connect()
    con.autocommit = True
    cur = con.cursor()
    counts = {}

    log("staging Charlotte County appraiser data")
    counts["charlotte_cama"] = load_zip_text(cur, raw / "charlotte/charlotte.zip", r"\.txt$", "cc_cd",
                                             delimiter="|", quoting=csv.QUOTE_NONE)
    counts["charlotte_sales"] = load_zip_text(cur, raw / "charlotte/sales.zip", r"\.txt$", "cc_sales",
                                              delimiter="|", quoting=csv.QUOTE_NONE)
    load_xlsx_codes(cur, raw / "charlotte/land_use_codes.xlsx", "cc_land_use")

    log("staging Sarasota County appraiser data")
    sz = raw / "sarasota/SCPA_Parcels_Sales_CSV.zip"
    counts["sarasota_cama"] = load_zip_text(cur, sz, r"/Sarasota\.csv$", "sc_parcels_csv")
    counts["sarasota_sales"] = load_zip_text(cur, sz, r"/ParcelSales\.csv$", "sc_sales")
    load_zip_text(cur, sz, r"/LandUseCodes\.csv$", "sc_land_use")

    log("staging parcel polygons")
    _, shp = zip_member(raw / "charlotte/accounts.zip", r"\.shp$")
    ogr(f"/vsizip/{raw / 'charlotte/accounts.zip'}/{shp}", "cc_parcels", "-overwrite",
        "-select", "ACCOUNT")
    ogr(str(raw / "sarasota/parcels.geojson"), "sc_parcels_geom", "-overwrite")

    log("staging FEMA flood data")
    for i, (county, fips) in enumerate([("CHARLOTTE", "12015C"), ("SARASOTA", "12115C")]):
        zp = raw / f"fema/NFHL_{fips}.zip"
        mode = "-overwrite" if i == 0 else "-append"
        for layer, table in [("S_FLD_HAZ_AR", "fema_fld_haz_ar"), ("S_FIRM_PAN", "fema_firm_pan")]:
            _, shp = zip_member(zp, rf"(^|/){layer}\.shp$")
            ogr(f"/vsizip/{zp}/{shp}", table, mode,
                "-dialect", "OGRSQL", "-sql", f"SELECT *, '{county}' AS county FROM {layer}")

    log("building public tables (transform.sql)")
    con.close()
    psql("transform.sql")
    psql("qgis_styles.sql")

    con = connect()
    con.autocommit = True
    cur = con.cursor()
    sources = {
        "charlotte_cama": "charlotte/charlotte.zip", "charlotte_sales": "charlotte/sales.zip",
        "charlotte_parcels": "charlotte/accounts.zip",
        "sarasota_cama": "sarasota/SCPA_Parcels_Sales_CSV.zip", "sarasota_sales": "sarasota/SCPA_Parcels_Sales_CSV.zip",
        "sarasota_parcels": "sarasota/parcels.geojson",
        "fema_nfhl_charlotte": "fema/NFHL_12015C.zip", "fema_nfhl_sarasota": "fema/NFHL_12115C.zip",
    }
    for src, rel in sources.items():
        p = raw / rel
        url_file = p.parent / (p.name + ".url")
        url = url_file.read_text() if url_file.exists() else SARASOTA_PARCELS_FS
        m = re.search(r"_(\d{8})\.zip", url)
        cur.execute("""INSERT INTO data_sources (source, url, file_date, rows_loaded, loaded_at)
                       VALUES (%s, %s, %s, %s, now())
                       ON CONFLICT (source) DO UPDATE SET url = EXCLUDED.url, file_date = EXCLUDED.file_date,
                         rows_loaded = EXCLUDED.rows_loaded, loaded_at = now()""",
                    (src, url, m.group(1) if m else file_date(p), counts.get(src)))
    cur.execute("""SELECT county, count(*), count(geom), count(addr_norm) FROM parcels GROUP BY 1 ORDER BY 1""")
    for county, n, g, a in cur.fetchall():
        log(f"  {county}: {n} parcels, {g} with polygons, {a} with site addresses")
    cur.execute("SELECT county, count(*) FROM flood_zones GROUP BY 1 ORDER BY 1")
    for county, n in cur.fetchall():
        log(f"  {county}: {n} flood zone polygons")
    con.close()


def psql(name: str):
    subprocess.run(["psql", "-v", "ON_ERROR_STOP=1",
                    "-v", f"DBNAME={os.environ['PGDATABASE']}",
                    "-q", "-f", str(SQL / name)], check=True)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--refresh", action="store_true", help="force re-download of all sources")
    ap.add_argument("--no-download", action="store_true", help="load whatever is already in /data/raw")
    args = ap.parse_args()
    t0 = time.time()
    if not args.no_download:
        download(args.refresh)
    log("applying schema.sql")
    psql("schema.sql")
    stage()
    log(f"done in {(time.time() - t0) / 60:.1f} min")


if __name__ == "__main__":
    sys.exit(main())
