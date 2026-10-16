# SWFL Property + Flood Zone GIS

PostGIS in Docker, loaded with:

| Data | Source | Refresh at source |
|---|---|---|
| Charlotte County appraiser roll (owner, values, building, legal) | [ccappraiser.com `charlotte.zip`](https://www.ccappraiser.com/Downloads.aspx) | nightly |
| Charlotte County sales history | ccappraiser.com `sales.zip` | nightly |
| Charlotte County parcel polygons | [Charlotte County GIS `accounts.zip`](https://www.charlottecountyfl.gov/gis/shapefile-gallery.stml) | weekly |
| Sarasota County appraiser roll + sales | [sc-pa.com `SCPA_Parcels_Sales_CSV.zip`](https://www.sarasotapropertyappraiser.gov/downloads/download-data/) | daily |
| Sarasota County parcel polygons | Sarasota County GIS `ParcelHosted` feature service | daily |
| FEMA effective flood zones + FIRM panels | [FEMA NFHL countywide](https://msc.fema.gov/portal/advanceSearch) `12015C` (Charlotte), `12115C` (Sarasota) | as FEMA publishes LOMRs/revisions |

It is reachable three ways: **AI** (an MCP server for Claude or any MCP client), **QGIS** (direct PostGIS
connection, with flood-zone styles pre-loaded), and plain **SQL**.

## Quick start

```bash
cp .env.example .env        # then set the two passwords (already done if .env exists)
docker compose up -d        # PostGIS + MCP server
docker compose --profile load run --rm loader   # download + load everything (~10–20 min)
```

Re-run the loader any time to refresh. It re-downloads files older than 6 days; force with
`docker compose --profile load run --rm loader --refresh`, or reload what is already on disk with `--no-download`.
Downloads are kept in `./data/raw`.

## Ask Claude

The MCP server runs at `http://localhost:8000/mcp`.

**Claude Code:** this folder has a `.mcp.json`, so Claude Code started here picks the server up automatically
(approve it once). To use it from any folder:

```bash
claude mcp add --scope user --transport http swfl-gis http://localhost:8000/mcp
```

**Claude Desktop** (Settings → Developer → Edit Config, `claude_desktop_config.json`):

```json
{
  "mcpServers": {
    "swfl-gis": {
      "command": "docker",
      "args": ["exec", "-i", "gis-mcp", "python", "server.py", "--stdio"]
    }
  }
}
```

Then ask things like:

- "What's the flood zone on 123 4th Street, Englewood?"
- "Who owns 1234 Beach Rd Englewood and when did it last sell?"
- "How many homes in Englewood are in a VE zone?"
- "List waterfront parcels in Charlotte County in zone AE with a BFE of 9 or more."

Tools the server provides:

| Tool | What it does |
|---|---|
| `property_lookup(address)` | Fuzzy address match against both appraiser rolls → owner, values, last sale, every flood zone on the parcel with % coverage, BFE, FIRM panel. Falls back to the US Census geocoder if no parcel matches. |
| `flood_zone_at_location(lat, lon)` | Flood zone and parcel at a coordinate |
| `parcel_details(county, parcel_id)` | Full record + sales history |
| `search_by_owner(name)` | Fuzzy owner search |
| `database_schema()` / `query_database(sql)` | Read-only SQL for anything else (runs as `gis_reader`, 60 s timeout, 200-row cap) |

## QGIS

Layer → Add Layer → Add PostGIS Layers → New connection:

| Field | Value |
|---|---|
| Host | `localhost` |
| Port | `5432` (or `DB_PORT` from `.env`) |
| Database | `gis` |
| Username / password | `gis_reader` / `READER_PASSWORD` from `.env` (read-only), or `gis` / `POSTGRES_PASSWORD` |

Useful layers:

- `flood_zones`: FEMA flood hazard polygons. A default style (VE red, AE blue, shaded X orange, …) loads automatically.
- `parcel_flood`: every parcel with `primary_zone` (zone at the parcel center), `worst_zone`, `in_sfha`; styled by zone.
- `parcels`: all appraiser attributes + polygon; styled as outlines.
- `firm_panels`: FIRM panel boundaries and effective dates.

Basemap: install the *QuickMapServices* plugin, or add an XYZ tile layer for OpenStreetMap / Esri imagery.

## SQL examples

```sql
-- address -> parcel candidates
SELECT * FROM find_parcels('123 4th st englewood');

-- all flood zones on a parcel, with % of parcel area
SELECT * FROM parcel_flood_zones('SARASOTA', '0480120001');

-- zone at a coordinate
SELECT * FROM flood_zone_at(-82.35, 26.94);

-- parcels by zone in Englewood (both counties)
SELECT county, primary_zone, count(*) FROM parcel_flood
WHERE site_city = 'ENGLEWOOD' GROUP BY 1, 2 ORDER BY 1, 3 DESC;

-- what was loaded, and when
SELECT * FROM data_sources;
```

## Layout

```
docker-compose.yml   db (PostGIS 17 / 3.5), mcp (MCP server), loader (one-shot ETL, GDAL)
loader/load.py       downloads → raw.* staging tables
sql/schema.sql       public tables, address normalizer, lookup functions, read-only role
sql/transform.sql    raw.* → parcels, sales, flood_zones, firm_panels, parcel_flood
sql/qgis_styles.sql  default QGIS styles stored in layer_styles
mcp/server.py        MCP tools
```

## Troubleshooting

- **QGIS/MCP can't connect after Docker Desktop restarts** ("server closed the connection unexpectedly"):
  Docker's localhost port forward sometimes breaks. Run `docker compose up -d --force-recreate db mcp`. Data is kept in the `pgdata` volume.
- **Apple Silicon:** the official `postgis/postgis` image is amd64-only, so this uses `imresamu/postgis`, a multi-arch build of the same image.

## Caveats

- FEMA zones here are the *effective* NFHL. They are for information, not an official flood zone determination
  or elevation certificate, and pending/preliminary maps and LOMAs on individual lots aren't reflected.
- Charlotte's appraiser file has no site city, so the city is derived from the ZIP code (`zip_city` table).
- Condo units share their building's polygon. A few hundred accounts (new splits, personal property) have no polygon.
- Appraiser values are from the last certified roll. Ownership and sales update nightly.
