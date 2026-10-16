"""MCP server exposing the Charlotte/Sarasota parcel + FEMA flood database to AI assistants.

Transports:
  python server.py            -> streamable HTTP on :8000 (path /mcp)
  python server.py --stdio    -> stdio (for `docker exec -i gis-mcp python server.py --stdio`)
"""
import datetime as dt
import decimal
import os
import re
import sys

import httpx
import psycopg
from psycopg.rows import dict_row
from mcp.server.fastmcp import FastMCP

DATABASE_URL = os.environ["DATABASE_URL"]
MAX_ROWS = 200

mcp = FastMCP(
    "swfl-property-flood",
    instructions=(
        "Property appraiser records (owner, values, sales, building facts, parcel polygons) and "
        "FEMA effective flood zones for Charlotte County and Sarasota County, Florida "
        "(includes Englewood, Venice, North Port, Sarasota, Punta Gorda, Port Charlotte, "
        "Rotonda, Boca Grande, Nokomis, Osprey, Longboat Key, Siesta Key). "
        "For 'what flood zone is <address>' use property_lookup. For counts/aggregates use "
        "query_database (call database_schema first). Always mention when an address matched "
        "more than one parcel, and that FEMA zones are for information, not an official determination."
    ),
    host="0.0.0.0",
    port=8000,
)

ZONE_INFO = {
    "VE": "Coastal high-hazard area (1% annual chance flood with wave action ≥3 ft). Flood insurance required with a federally backed mortgage; strictest building rules.",
    "V": "Coastal high-hazard area with wave action, no BFE determined. Insurance required with federally backed mortgage.",
    "AE": "Special Flood Hazard Area: 1% annual chance (100-year) flood, base flood elevation determined. Insurance required with federally backed mortgage.",
    "A": "Special Flood Hazard Area: 1% annual chance flood, no BFE determined. Insurance required with federally backed mortgage.",
    "AH": "Special Flood Hazard Area: shallow ponding 1–3 ft, BFE determined. Insurance required with federally backed mortgage.",
    "AO": "Special Flood Hazard Area: shallow sheet flow 1–3 ft, depth given. Insurance required with federally backed mortgage.",
    "A99": "Special Flood Hazard Area protected by a levee under construction.",
    "AR": "Special Flood Hazard Area being restored by levee/flood-control improvements.",
    "X_SHADED": "Moderate risk: 0.2% annual chance (500-year) flood area or 1% flood with depth <1 ft. Insurance optional.",
    "X": "Minimal risk: outside the 0.2% annual chance floodplain. Insurance optional.",
    "D": "Possible but undetermined flood hazard.",
    "OPEN WATER": "Open water.",
}


def explain(zone, subtype):
    if zone == "X" and subtype and "0.2" in subtype:
        return ZONE_INFO["X_SHADED"]
    return ZONE_INFO.get(zone or "", "")


def _clean(v):
    if isinstance(v, decimal.Decimal):
        return int(v) if v == v.to_integral_value() else float(v)
    if isinstance(v, (dt.date, dt.datetime)):
        return v.isoformat()
    return v


def rows(sql, params=None, limit=None):
    with psycopg.connect(DATABASE_URL, row_factory=dict_row, autocommit=True) as con:
        cur = con.execute(sql, params)
        if cur.description is None:
            return []
        data = cur.fetchmany(limit) if limit else cur.fetchall()
        return [{k: _clean(v) for k, v in r.items()} for r in data]


def flood_for_parcel(county, parcel_id):
    zones = rows("SELECT * FROM parcel_flood_zones(%s, %s)", (county, parcel_id))
    for z in zones:
        z["meaning"] = explain(z["fld_zone"], z["zone_subty"])
    panel = rows(
        """SELECT f.firm_pan, f.eff_date FROM parcels p JOIN firm_panels f
             ON ST_Intersects(f.geom, ST_PointOnSurface(p.geom))
           WHERE p.county = %s AND p.parcel_id = %s
           ORDER BY (f.county = p.county) DESC, f.eff_date DESC NULLS LAST LIMIT 1""",
        (county, parcel_id))
    return zones, (panel[0] if panel else None)


PROPERTY_COLS = """county, parcel_id, site_address, site_city, site_zip, owner_name, mail_address,
  mail_city, mail_state, mail_zip, land_use_code, land_use_desc, zoning, subdivision, just_value,
  assessed_value, taxable_value, land_value, building_value, homestead, exemptions, year_built,
  living_sqft, total_bldg_sqft, bedrooms, bathrooms, pool, waterfront, land_sqft, last_sale_price,
  last_sale_date, legal_description, appraiser_url,
  round(ST_Y(ST_PointOnSurface(geom))::numeric, 6) AS lat,
  round(ST_X(ST_PointOnSurface(geom))::numeric, 6) AS lon,
  round((ST_Area(geom::geography) / 4046.8564)::numeric, 3) AS parcel_acres"""


def census_geocode(address):
    """Fallback geocoder (US Census) for addresses not found in the appraiser rolls."""
    if not re.search(r"\b(FL|FLA|FLORIDA)\b", address, re.I):
        address += ", FL"
    try:
        r = httpx.get(
            "https://geocoding.geo.census.gov/geocoder/locations/onelineaddress",
            params={"address": address, "benchmark": "Public_AR_Current", "format": "json"},
            timeout=20,
        )
        for m in r.json()["result"]["addressMatches"]:
            x, y = m["coordinates"]["x"], m["coordinates"]["y"]
            # only accept matches inside Charlotte + Sarasota counties
            if -82.85 <= x <= -81.55 and 26.65 <= y <= 27.45:
                return {"matched_address": m["matchedAddress"], "lon": x, "lat": y}
    except Exception:  # noqa: BLE001
        pass
    return None


@mcp.tool()
def property_lookup(address: str, max_results: int = 3) -> dict:
    """Look up a property in Charlotte or Sarasota County, FL by street address and return its
    FEMA flood zone(s) plus appraiser details (owner, values, last sale, year built, etc.).

    Accepts loose input like "123 4th street englewood", "123 4th st 34224" or "123 4th st unit 2".
    Returns every flood zone touching the parcel with the % of the parcel it covers, which zone
    is at the parcel's center, base flood elevation (BFE, ft NAVD88) and the FIRM panel.
    If no parcel matches, falls back to the US Census geocoder and reports the zone at that point.
    """
    max_results = max(1, min(max_results, 10))
    matches = rows("SELECT * FROM find_parcels(%s, %s)", (address, max_results))
    if matches:
        best = matches[0]["score"]
        # keep near-ties so the caller can disambiguate (e.g. same address in two counties)
        matches = [m for m in matches if m["score"] >= best - 0.15]
        out = []
        for m in matches:
            prop = rows(f"SELECT {PROPERTY_COLS} FROM parcels WHERE county=%s AND parcel_id=%s",
                        (m["county"], m["parcel_id"]))[0]
            zones, panel = flood_for_parcel(m["county"], m["parcel_id"])
            prop["match_score"] = round(m["score"], 3)
            prop["flood_zones"] = zones
            prop["firm_panel"] = panel
            if not zones and prop.get("lat") is None:
                prop["note"] = "No parcel polygon for this account (e.g. a condo unit); flood zone unavailable."
            out.append(prop)
        return {"query": address, "matches": out, "source": data_freshness()}

    g = census_geocode(address)
    if not g:
        return {"query": address, "matches": [],
                "message": "No parcel matched and the address could not be geocoded. "
                           "Try including the house number and street type, or a ZIP code."}
    zones = rows("SELECT * FROM flood_zone_at(%s, %s)", (g["lon"], g["lat"]))
    for z in zones:
        z["meaning"] = explain(z["fld_zone"], z["zone_subty"])
    near = rows(f"""SELECT {PROPERTY_COLS} FROM parcels
                    WHERE ST_DWithin(geom::geography, ST_SetSRID(ST_MakePoint(%s,%s),4326)::geography, 30)
                    ORDER BY geom <-> ST_SetSRID(ST_MakePoint(%s,%s),4326) LIMIT 1""",
                (g["lon"], g["lat"], g["lon"], g["lat"]))
    return {"query": address, "matches": [],
            "geocoded": g, "flood_zones_at_point": zones,
            "parcel_at_point": near[0] if near else None,
            "message": "No appraiser address matched; result is from the US Census geocoder "
                       "(street-segment interpolation, less precise than a parcel match).",
            "source": data_freshness()}


@mcp.tool()
def flood_zone_at_location(latitude: float, longitude: float) -> dict:
    """FEMA flood zone at a WGS84 latitude/longitude, plus the parcel at that point (if any)."""
    zones = rows("SELECT * FROM flood_zone_at(%s, %s)", (longitude, latitude))
    for z in zones:
        z["meaning"] = explain(z["fld_zone"], z["zone_subty"])
    parcel = rows(f"""SELECT {PROPERTY_COLS} FROM parcels
                      WHERE ST_Intersects(geom, ST_SetSRID(ST_MakePoint(%s,%s),4326)) LIMIT 1""",
                  (longitude, latitude))
    return {"flood_zones": zones, "parcel": parcel[0] if parcel else None}


@mcp.tool()
def parcel_details(county: str, parcel_id: str) -> dict:
    """Full record for one parcel (county = 'CHARLOTTE' or 'SARASOTA'; parcel_id = appraiser
    account number), including flood zones and complete sales history."""
    county = county.strip().upper()
    prop = rows(f"SELECT {PROPERTY_COLS} FROM parcels WHERE county=%s AND parcel_id=%s",
                (county, parcel_id.strip()))
    if not prop:
        return {"error": f"No parcel {parcel_id} in {county}"}
    p = prop[0]
    p["flood_zones"], p["firm_panel"] = flood_for_parcel(county, parcel_id.strip())
    p["sales"] = rows("""SELECT sale_date, sale_price, deed_type, qual_code, book, page, instrument,
                                grantor, vacant_improved
                         FROM sales WHERE county=%s AND parcel_id=%s ORDER BY sale_date DESC NULLS LAST""",
                      (county, parcel_id.strip()))
    return p


@mcp.tool()
def search_by_owner(owner_name: str, county: str | None = None, limit: int = 25) -> list[dict]:
    """Find parcels by owner name (fuzzy). Optional county filter ('CHARLOTTE' or 'SARASOTA')."""
    return rows(
        """SELECT county, parcel_id, owner_name, site_address, site_city, just_value,
                  similarity(owner_name, upper(%(q)s)) AS score
           FROM parcels
           WHERE owner_name %% upper(%(q)s) AND (%(c)s::text IS NULL OR county = upper(%(c)s))
           ORDER BY score DESC LIMIT %(n)s""",
        {"q": owner_name, "c": county, "n": max(1, min(limit, MAX_ROWS))})


@mcp.tool()
def database_schema() -> dict:
    """Describe the tables, columns and helper SQL functions available to query_database."""
    cols = rows("""SELECT table_name, column_name, data_type FROM information_schema.columns
                   WHERE table_schema='public' AND table_name IN
                     ('parcels','sales','flood_zones','firm_panels','parcel_flood','data_sources','zip_city')
                   ORDER BY table_name, ordinal_position""")
    tables: dict[str, list[str]] = {}
    for c in cols:
        tables.setdefault(c["table_name"], []).append(f'{c["column_name"]} {c["data_type"]}')
    return {
        "tables": tables,
        "notes": [
            "All geometry is EPSG:4326. Use geom::geography for meters, ST_Area(geom::geography)/4046.86 for acres.",
            "parcels: one row per appraiser account; county is 'CHARLOTTE' or 'SARASOTA'. Condo units share the building polygon.",
            "parcel_flood (materialized view): primary_zone = FEMA zone at parcel center, worst_zone = riskiest zone touching parcel, in_sfha = center in 1% annual chance floodplain.",
            "flood_zones: FEMA NFHL S_FLD_HAZ_AR. fld_zone in (VE, AE, A, AO, AH, X, D, 'OPEN WATER'); zone X with zone_subty '0.2 PCT ANNUAL CHANCE FLOOD HAZARD' is the shaded X (500-year).",
            "Functions: find_parcels(address text, n int), parcel_flood_zones(county, parcel_id), flood_zone_at(lon, lat), norm_addr(text).",
            "site_city is uppercase (e.g. 'ENGLEWOOD', 'VENICE', 'NORTH PORT', 'PUNTA GORDA', 'PORT CHARLOTTE').",
        ],
        "source": data_freshness(),
    }


@mcp.tool()
def query_database(sql: str) -> dict:
    """Run a read-only SQL query (PostgreSQL/PostGIS) against the property + flood database.
    Use for counts, aggregates and custom filters, e.g.
    SELECT primary_zone, count(*) FROM parcel_flood WHERE site_city='ENGLEWOOD' GROUP BY 1.
    Results are capped at 200 rows; geometry columns are returned as WKT only if you select ST_AsText(...)."""
    if not re.match(r"^\s*(with|select|explain|table|values)\b", sql, re.I):
        return {"error": "Only read-only SELECT/WITH queries are allowed."}
    try:
        with psycopg.connect(DATABASE_URL, row_factory=dict_row) as con:
            con.read_only = True
            cur = con.execute(sql)
            data = cur.fetchmany(MAX_ROWS + 1)
            names = [d.name for d in cur.description or []]
            types = {d.name: d.type_code for d in cur.description or []}
    except Exception as e:  # noqa: BLE001
        return {"error": str(e).strip()}
    geom_oids = set()
    out = []
    for r in data[:MAX_ROWS]:
        row = {}
        for k in names:
            v = r[k]
            if isinstance(v, str) and len(v) > 40 and re.fullmatch(r"[0-9A-F]+", v) and k not in geom_oids:
                v = "<geometry: select ST_AsText(...) to see it>"
            row[k] = _clean(v)
        out.append(row)
    return {"columns": names, "rows": out, "truncated": len(data) > MAX_ROWS}


def data_freshness():
    return rows("SELECT source, file_date, loaded_at::date AS loaded FROM data_sources ORDER BY source")


if __name__ == "__main__":
    mcp.run(transport="stdio" if "--stdio" in sys.argv else "streamable-http")
