-- Final (query-facing) schema. Idempotent: safe to run on every load.
-- Run with: psql -v ON_ERROR_STOP=1 -v reader_password=... -f schema.sql

CREATE EXTENSION IF NOT EXISTS postgis;
CREATE EXTENSION IF NOT EXISTS pg_trgm;

CREATE SCHEMA IF NOT EXISTS raw;   -- staging tables, rebuilt on every load

---------------------------------------------------------------------------
-- Address normalization
---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS addr_abbr (word text PRIMARY KEY, abbr text NOT NULL);
INSERT INTO addr_abbr VALUES
  ('STREET','ST'),('STR','ST'),('AVENUE','AVE'),('AV','AVE'),('ROAD','RD'),('DRIVE','DR'),
  ('BOULEVARD','BLVD'),('BOUL','BLVD'),('COURT','CT'),('CIRCLE','CIR'),('LANE','LN'),
  ('PLACE','PL'),('TERRACE','TER'),('TERR','TER'),('PARKWAY','PKWY'),('HIGHWAY','HWY'),
  ('TRAIL','TRL'),('PLAZA','PLZ'),('SQUARE','SQ'),('POINT','PT'),('POINTE','PT'),
  ('EXTENSION','EXT'),('CROSSING','XING'),('COVE','CV'),('ISLE','IS'),('ISLAND','IS'),
  ('LOOP','LOOP'),('PASS','PASS'),('PATH','PATH'),('RUN','RUN'),('WALK','WALK'),('ALLEY','ALY'),
  ('NORTH','N'),('SOUTH','S'),('EAST','E'),('WEST','W'),
  ('NORTHEAST','NE'),('NORTHWEST','NW'),('SOUTHEAST','SE'),('SOUTHWEST','SW'),
  ('FIRST','1ST'),('SECOND','2ND'),('THIRD','3RD'),('FOURTH','4TH'),('FIFTH','5TH'),
  ('SIXTH','6TH'),('SEVENTH','7TH'),('EIGHTH','8TH'),('NINTH','9TH'),('TENTH','10TH'),
  ('ELEVENTH','11TH'),('TWELFTH','12TH'),
  ('SAINT','ST'),('MOUNT','MT'),('FORT','FT'),('FLORIDA','FL'),
  ('APARTMENT','APT'),('SUITE','STE'),('NUMBER','#'),('NO','#')
ON CONFLICT (word) DO UPDATE SET abbr = EXCLUDED.abbr;

-- '123 Fourth Street, Englewood' -> '123 4TH ST ENGLEWOOD'
CREATE OR REPLACE FUNCTION norm_addr(t text) RETURNS text
LANGUAGE sql STABLE PARALLEL SAFE AS $$
  SELECT nullif(string_agg(coalesce(a.abbr, s.w), ' ' ORDER BY s.ord), '')
  FROM regexp_split_to_table(
         trim(regexp_replace(upper(coalesce(t, '')), '[^A-Z0-9#]+', ' ', 'g')), ' ')
       WITH ORDINALITY AS s(w, ord)
  LEFT JOIN addr_abbr a ON a.word = s.w
  WHERE s.w <> ''
$$;

-- Postal city for Charlotte County site addresses (the appraiser file only has ZIP).
CREATE TABLE IF NOT EXISTS zip_city (zip text PRIMARY KEY, city text NOT NULL);
INSERT INTO zip_city VALUES
  ('33917','NORTH FORT MYERS'),('33921','BOCA GRANDE'),('33927','EL JOBEAN'),('33938','MURDOCK'),
  ('33946','PLACIDA'),('33947','ROTONDA WEST'),('33948','PORT CHARLOTTE'),
  ('33949','PORT CHARLOTTE'),('33950','PUNTA GORDA'),('33951','PUNTA GORDA'),
  ('33952','PORT CHARLOTTE'),('33953','PORT CHARLOTTE'),('33954','PORT CHARLOTTE'),
  ('33955','PUNTA GORDA'),('33980','PORT CHARLOTTE'),('33981','PORT CHARLOTTE'),
  ('33982','PUNTA GORDA'),('33983','PUNTA GORDA'),('34223','ENGLEWOOD'),
  ('34224','ENGLEWOOD'),('34295','ENGLEWOOD'),('34269','ARCADIA'),
  ('34286','NORTH PORT'),('34287','NORTH PORT'),('34288','NORTH PORT'),('34291','NORTH PORT')
ON CONFLICT (zip) DO UPDATE SET city = EXCLUDED.city;

-- Place names people use in queries -> postal city stored on parcels.
CREATE TABLE IF NOT EXISTS city_alias (alias text PRIMARY KEY, city text NOT NULL);
INSERT INTO city_alias VALUES
  ('ENGLEWOOD','ENGLEWOOD'),('MANASOTA KEY','ENGLEWOOD'),('ENGLEWOOD BEACH','ENGLEWOOD'),
  ('VENICE','VENICE'),('SOUTH VENICE','VENICE'),('NORTH VENICE','NORTH VENICE'),
  ('NORTH PORT','NORTH PORT'),('SARASOTA','SARASOTA'),('SIESTA KEY','SARASOTA'),
  ('LIDO KEY','SARASOTA'),('NOKOMIS','NOKOMIS'),('CASEY KEY','NOKOMIS'),('LAUREL','NOKOMIS'),
  ('OSPREY','OSPREY'),('LONGBOAT KEY','LONGBOAT KEY'),('LAKEWOOD RANCH','LAKEWOOD RANC'),
  ('MYAKKA CITY','MYAKKA CITY'),('PUNTA GORDA','PUNTA GORDA'),('PORT CHARLOTTE','PORT CHARLOTTE'),
  ('GULF COVE','PORT CHARLOTTE'),('EL JOBEAN','PORT CHARLOTTE'),('MURDOCK','PORT CHARLOTTE'),
  ('ROTONDA WEST','ROTONDA WEST'),('ROTONDA','ROTONDA WEST'),('PLACIDA','PLACIDA'),
  ('CAPE HAZE','PLACIDA'),('BOCA GRANDE','BOCA GRANDE'),('GASPARILLA','BOCA GRANDE'),
  ('NORTH FORT MYERS','NORTH FORT MYERS')
ON CONFLICT (alias) DO UPDATE SET city = EXCLUDED.city;

---------------------------------------------------------------------------
-- Helpers for messy source values
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION to_num(t text) RETURNS numeric
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
BEGIN
  t := nullif(regexp_replace(coalesce(t, ''), '[^0-9.\-]', '', 'g'), '');
  RETURN t::numeric;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

CREATE OR REPLACE FUNCTION to_date_any(t text) RETURNS date
LANGUAGE plpgsql IMMUTABLE PARALLEL SAFE AS $$
BEGIN
  t := nullif(trim(coalesce(t, '')), '');
  IF t IS NULL THEN RETURN NULL; END IF;
  IF t ~ '^\d{1,2}/\d{1,2}/\d{4}' THEN RETURN to_date(t, 'MM/DD/YYYY'); END IF;
  IF t ~ '^\d{4}-\d{2}-\d{2}' THEN RETURN left(t, 10)::date; END IF;
  IF t ~ '^\d{8}$' THEN RETURN to_date(t, 'YYYYMMDD'); END IF;
  RETURN NULL;
EXCEPTION WHEN others THEN RETURN NULL;
END $$;

---------------------------------------------------------------------------
-- Core tables
---------------------------------------------------------------------------
CREATE TABLE IF NOT EXISTS parcels (
  county          text NOT NULL,          -- 'CHARLOTTE' | 'SARASOTA'
  parcel_id       text NOT NULL,          -- appraiser account number
  owner_name      text,
  mail_address    text,
  mail_city       text,
  mail_state      text,
  mail_zip        text,
  mail_country    text,
  site_number     text,
  site_street     text,
  site_unit       text,
  site_city       text,
  site_zip        text,
  site_address    text,                   -- display form: '123 4TH ST UNIT 2'
  street_norm     text,                   -- normalized street without number: '4TH ST'
  addr_norm       text,                   -- normalized number + street: '123 4TH ST'
  land_use_code   text,
  land_use_desc   text,
  zoning          text,
  subdivision     text,
  just_value      numeric,
  assessed_value  numeric,
  taxable_value   numeric,
  land_value      numeric,
  building_value  numeric,
  exemptions      text,
  homestead       boolean,
  year_built      int,
  living_sqft     numeric,
  total_bldg_sqft numeric,
  bedrooms        numeric,
  bathrooms       numeric,
  pool            boolean,
  waterfront      text,
  land_sqft       numeric,
  last_sale_price numeric,
  last_sale_date  date,
  legal_description text,
  appraiser_url   text,
  geom            geometry(MultiPolygon, 4326),
  PRIMARY KEY (county, parcel_id)
);
CREATE INDEX IF NOT EXISTS parcels_geom_gix     ON parcels USING gist (geom);
CREATE INDEX IF NOT EXISTS parcels_number_ix    ON parcels (site_number);
CREATE INDEX IF NOT EXISTS parcels_addr_trgm    ON parcels USING gin (addr_norm gin_trgm_ops);
CREATE INDEX IF NOT EXISTS parcels_street_trgm  ON parcels USING gin (street_norm gin_trgm_ops);
CREATE INDEX IF NOT EXISTS parcels_owner_trgm   ON parcels USING gin (owner_name gin_trgm_ops);

CREATE TABLE IF NOT EXISTS sales (
  county      text NOT NULL,
  parcel_id   text NOT NULL,
  sale_date   date,
  sale_price  numeric,
  deed_type   text,
  qual_code   text,
  book        text,
  page        text,
  instrument  text,
  grantor     text,
  vacant_improved text
);
CREATE INDEX IF NOT EXISTS sales_parcel_ix ON sales (county, parcel_id, sale_date DESC);

-- FEMA National Flood Hazard Layer: S_FLD_HAZ_AR (effective flood zones)
CREATE TABLE IF NOT EXISTS flood_zones (
  id          serial PRIMARY KEY,
  county      text,
  dfirm_id    text,
  fld_ar_id   text,
  fld_zone    text,          -- AE, VE, A, AO, AH, X, D, OPEN WATER, ...
  zone_subty  text,          -- e.g. '0.2 PCT ANNUAL CHANCE FLOOD HAZARD', 'COASTAL FLOODPLAIN'
  sfha        boolean,       -- inside the Special Flood Hazard Area (1% annual chance)
  static_bfe  numeric,       -- base flood elevation (ft, NAVD88) when constant for the zone
  depth       numeric,       -- AO zone depth
  vert_datum  text,
  source_cit  text,
  geom        geometry(MultiPolygon, 4326)
);
CREATE INDEX IF NOT EXISTS flood_zones_geom_gix ON flood_zones USING gist (geom);

-- Same polygons cut into small pieces: much faster for point/parcel lookups.
CREATE TABLE IF NOT EXISTS flood_zones_sub (
  zone_id integer NOT NULL,
  geom    geometry(Polygon, 4326)
);
CREATE INDEX IF NOT EXISTS flood_zones_sub_gix ON flood_zones_sub USING gist (geom);

-- FEMA FIRM panels (panel number + effective date)
CREATE TABLE IF NOT EXISTS firm_panels (
  id         serial PRIMARY KEY,
  county     text,
  dfirm_id   text,
  firm_pan   text,
  panel_typ  text,
  eff_date   date,
  geom       geometry(MultiPolygon, 4326)
);
CREATE INDEX IF NOT EXISTS firm_panels_geom_gix ON firm_panels USING gist (geom);

-- What was loaded and when
CREATE TABLE IF NOT EXISTS data_sources (
  source       text PRIMARY KEY,
  url          text,
  file_date    text,
  rows_loaded  bigint,
  loaded_at    timestamptz DEFAULT now()
);

---------------------------------------------------------------------------
-- Flood risk ordering (most hazardous first)
---------------------------------------------------------------------------
CREATE OR REPLACE FUNCTION flood_zone_rank(zone text, subty text) RETURNS int
LANGUAGE sql IMMUTABLE PARALLEL SAFE AS $$
  SELECT CASE
    WHEN zone IN ('VE','V') THEN 1
    WHEN zone = 'AE' AND subty ILIKE '%FLOODWAY%' THEN 2
    WHEN zone = 'AE' THEN 3
    WHEN zone IN ('A','AH','AO','AR','A99') THEN 4
    WHEN zone = 'X' AND subty ILIKE '%0.2 PCT%' THEN 5
    WHEN zone = 'OPEN WATER' THEN 6
    WHEN zone = 'D' THEN 7
    WHEN zone = 'X' THEN 8
    ELSE 9 END
$$;

---------------------------------------------------------------------------
-- Lookup functions (used by the MCP server; handy in QGIS/psql too)
---------------------------------------------------------------------------

-- Fuzzy address search over appraiser site addresses.
--   SELECT * FROM find_parcels('123 4th street englewood');
CREATE OR REPLACE FUNCTION find_parcels(q text, max_results int DEFAULT 5)
RETURNS TABLE (county text, parcel_id text, site_address text, site_city text,
               site_zip text, owner_name text, score real)
LANGUAGE plpgsql STABLE AS $$
DECLARE
  qn    text := norm_addr(q);
  num   text;
  rest  text;
  qzip  text;
  qunit text;
  qcity text;
  qalias text;
BEGIN
  IF qn IS NULL THEN RETURN; END IF;
  num   := substring(qn FROM '^(\d+)\M');
  rest  := trim(regexp_replace(qn, '^\d+[A-Z]?\s*', ''));
  qzip  := substring(rest FROM '\m(3[34]\d{3})(?:\s+\d{4})?\s*$');
  rest  := trim(regexp_replace(rest, '\m(FL|USA|US)?\s*(3[34]\d{3}(\s+\d{4})?)?\s*$', ''));
  qunit := substring(rest FROM '(?:\m(?:APT|UNIT|STE|BLDG)|#)\s*([A-Z0-9]+)');
  rest  := trim(regexp_replace(rest, '(\m(APT|UNIT|STE|BLDG)|#)\s*[A-Z0-9]+', ''));
  -- a place name at the end of the query ("... englewood") becomes a city hint
  SELECT a.city, a.alias INTO qcity, qalias
    FROM city_alias a
   WHERE rest LIKE '% ' || a.alias
   ORDER BY length(a.alias) DESC LIMIT 1;
  IF qcity IS NOT NULL THEN
    rest := trim(left(rest, length(rest) - length(qalias)));
  END IF;

  IF num IS NOT NULL THEN
    RETURN QUERY
      SELECT p.county, p.parcel_id, p.site_address, p.site_city, p.site_zip, p.owner_name,
             ( word_similarity(p.street_norm, rest)
               + CASE WHEN qcity IS NULL THEN 0 WHEN p.site_city = qcity THEN 0.3 ELSE -0.3 END
               + CASE WHEN qzip IS NULL THEN 0 WHEN p.site_zip = qzip THEN 0.3 ELSE -0.2 END
               + CASE WHEN qunit IS NOT NULL AND p.site_unit = qunit THEN 0.2 ELSE 0 END
               - CASE WHEN qunit IS NULL AND p.site_unit IS NOT NULL THEN 0.05 ELSE 0 END
               - CASE WHEN p.geom IS NULL THEN 0.1 ELSE 0 END
             )::real AS score
      FROM parcels p
      WHERE p.site_number = num
        AND word_similarity(p.street_norm, rest) >= 0.5
        -- numbered streets must match exactly: 4TH ST never matches 6TH ST
        AND NOT EXISTS (
          SELECT 1 FROM regexp_matches(p.street_norm, '\m(\d+[A-Z]*)\M', 'g') m
          WHERE position(' ' || m[1] || ' ' IN ' ' || rest || ' ') = 0)
      ORDER BY score DESC, p.county, p.parcel_id
      LIMIT max_results;
  ELSE
    RETURN QUERY
      SELECT p.county, p.parcel_id, p.site_address, p.site_city, p.site_zip, p.owner_name,
             similarity(p.addr_norm, rest)::real AS score
      FROM parcels p
      WHERE p.addr_norm % rest
        AND (qcity IS NULL OR p.site_city = qcity)
      ORDER BY score DESC
      LIMIT max_results;
  END IF;
END $$;

-- Every flood zone touching a parcel, with % of the parcel's area in each.
--   SELECT * FROM parcel_flood_zones('SARASOTA', '0480120001');
CREATE OR REPLACE FUNCTION parcel_flood_zones(p_county text, p_parcel_id text)
RETURNS TABLE (fld_zone text, zone_subty text, sfha boolean, static_bfe numeric,
               depth numeric, pct_of_parcel numeric, at_parcel_center boolean, dfirm_id text)
LANGUAGE sql STABLE AS $$
  WITH p AS (
    SELECT geom, ST_PointOnSurface(geom) AS pt, ST_Area(geom::geography) AS area
    FROM parcels WHERE county = upper(p_county) AND parcel_id = p_parcel_id
  ), pieces AS (
    SELECT z.id, z.fld_zone, z.zone_subty, z.sfha, z.static_bfe, z.depth, z.dfirm_id,
           ST_Area(ST_Intersection(s.geom, p.geom)::geography) AS a,
           ST_Intersects(s.geom, p.pt) AS has_pt,
           p.area
    FROM p
    JOIN flood_zones_sub s ON ST_Intersects(s.geom, p.geom)
    JOIN flood_zones z ON z.id = s.zone_id
    -- each county's NFHL covers the whole county; using only the parcel's own county avoids
    -- double counting where the two datasets overlap along the county line
    WHERE z.county = upper(p_county)
  )
  SELECT fld_zone, zone_subty, sfha, static_bfe, depth,
         round((100 * sum(a) / nullif(max(area), 0))::numeric, 1),
         bool_or(has_pt), min(dfirm_id)
  FROM pieces
  GROUP BY fld_zone, zone_subty, sfha, static_bfe, depth
  HAVING sum(a) > 0.01 OR bool_or(has_pt)
  ORDER BY flood_zone_rank(fld_zone, zone_subty), 6 DESC
$$;

-- Flood zone at a point (WGS84 lon/lat).
CREATE OR REPLACE FUNCTION flood_zone_at(lon double precision, lat double precision)
RETURNS TABLE (fld_zone text, zone_subty text, sfha boolean, static_bfe numeric,
               depth numeric, dfirm_id text, firm_panel text, panel_eff_date date)
LANGUAGE sql STABLE AS $$
  WITH pt AS (SELECT ST_SetSRID(ST_MakePoint(lon, lat), 4326) AS g)
  SELECT DISTINCT ON (z.id) z.fld_zone, z.zone_subty, z.sfha, z.static_bfe, z.depth, z.dfirm_id,
         fp.firm_pan, fp.eff_date
  FROM pt
  JOIN flood_zones_sub s ON ST_Intersects(s.geom, pt.g)
  JOIN flood_zones z ON z.id = s.zone_id
  LEFT JOIN LATERAL (
    SELECT firm_pan, eff_date FROM firm_panels f
    WHERE ST_Intersects(f.geom, pt.g)
    ORDER BY (f.dfirm_id = z.dfirm_id) DESC, eff_date DESC NULLS LAST LIMIT 1
  ) fp ON true
$$;

---------------------------------------------------------------------------
-- Read-only role for the MCP server / QGIS viewers
---------------------------------------------------------------------------
SELECT format('CREATE ROLE gis_reader LOGIN PASSWORD %L', :'reader_password')
WHERE NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'gis_reader') \gexec
ALTER ROLE gis_reader PASSWORD :'reader_password';
ALTER ROLE gis_reader SET default_transaction_read_only = on;
ALTER ROLE gis_reader SET statement_timeout = '60s';
GRANT CONNECT ON DATABASE :"DBNAME" TO gis_reader;
GRANT USAGE ON SCHEMA public TO gis_reader;
GRANT SELECT ON ALL TABLES IN SCHEMA public TO gis_reader;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT SELECT ON TABLES TO gis_reader;
