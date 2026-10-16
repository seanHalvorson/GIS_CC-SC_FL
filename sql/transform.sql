-- Builds the public tables from the raw.* staging tables written by the loader.
-- Everything happens in one transaction so QGIS / MCP readers never see a half-loaded state.
\set ON_ERROR_STOP on
BEGIN;

---------------------------------------------------------------------------
-- Parcel geometry, one MultiPolygon per account
---------------------------------------------------------------------------
CREATE TEMP TABLE geom_cc ON COMMIT DROP AS
  SELECT account, geom FROM (
    SELECT trim(account) AS account,
           ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3)) AS geom,
           count(*) OVER (PARTITION BY trim(account)) AS n
    FROM raw.cc_parcels WHERE trim(coalesce(account, '')) <> ''
  ) s WHERE n = 1
  UNION ALL
  SELECT trim(account), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3))
  FROM raw.cc_parcels WHERE trim(coalesce(account, '')) <> ''
  GROUP BY trim(account) HAVING count(*) > 1;
CREATE INDEX ON geom_cc (account);

CREATE TEMP TABLE geom_sc ON COMMIT DROP AS
  SELECT account, geom FROM (
    SELECT trim(coalesce(nullif(trim(id), ''), account)) AS account,
           ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3)) AS geom,
           count(*) OVER (PARTITION BY trim(coalesce(nullif(trim(id), ''), account))) AS n
    FROM raw.sc_parcels_geom WHERE trim(coalesce(nullif(trim(id), ''), account, '')) <> ''
  ) s WHERE n = 1
  UNION ALL
  SELECT trim(coalesce(nullif(trim(id), ''), account)), ST_Multi(ST_CollectionExtract(ST_MakeValid(ST_Union(ST_MakeValid(geom))), 3))
  FROM raw.sc_parcels_geom WHERE trim(coalesce(nullif(trim(id), ''), account, '')) <> ''
  GROUP BY trim(coalesce(nullif(trim(id), ''), account)) HAVING count(*) > 1;
CREATE INDEX ON geom_sc (account);

---------------------------------------------------------------------------
-- Parcels
---------------------------------------------------------------------------
TRUNCATE parcels;

-- Charlotte County (ccappraiser.com cd.txt + county GIS accounts.zip)
INSERT INTO parcels
SELECT
  'CHARLOTTE',
  trim(c.account),
  nullif(trim(c.ownersname), ''),
  nullif(concat_ws(' ', nullif(trim(c.mailingaddress), ''), nullif(trim(c.suite), ''),
                        nullif(trim(c.mailingaddress2), '')), ''),
  nullif(trim(c.city), ''), nullif(trim(c.state), ''), nullif(trim(c.zipcode), ''),
  nullif(trim(c.country), ''),
  a.num,
  a.street,
  a.unit,
  zc.city,
  nullif(trim(c.padzip), ''),
  CASE WHEN a.num IS NOT NULL THEN concat_ws(' ', a.num, a.street, 'UNIT ' || a.unit) END,
  norm_addr(a.street),
  norm_addr(a.num || ' ' || a.street),
  nullif(trim(c.landuse), ''),
  lu.description,
  nullif(trim(c.zoning), ''),
  nullif(trim(c.shortlegal), ''),
  to_num(c.priorjust), to_num(c.priorassessed), to_num(c.priortaxable),
  to_num(c.landapprval), to_num(c.bldgdeprval),
  nullif(trim(c.exemptioncode), ''),
  NULL,
  nullif(to_num(c.yearbuilt), 0)::int,
  nullif(to_num(c.livingarea), 0),
  nullif(to_num(c.totalarea), 0),
  NULL, NULL,
  upper(trim(c.haspool)) IN ('TRUE', '1'),
  CASE upper(trim(c.waterfront)) WHEN 'TRUE' THEN 'Y' WHEN '1' THEN 'Y' ELSE 'N' END,
  NULL,
  nullif(to_num(c.saleprice), 0),
  to_date_any(c.saledate),
  nullif(trim(c.longlegal), ''),
  'https://www.ccappraiser.com/Show_parcel.asp?acct=' || trim(c.account) || '&gen=T&tax=T&bld=T&oth=T&sal=T&lnd=T&leg=T',
  g.geom
FROM raw.cc_cd c
CROSS JOIN LATERAL (
  SELECT nullif(nullif(trim(c.streetnumber), ''), '0') AS num,
         nullif(regexp_replace(trim(regexp_replace(c.streetname, '\s*-\s*UNIT\s+.*$', '', 'i')), '\s+', ' ', 'g'), '') AS street,
         nullif(trim(substring(c.streetname FROM '-\s*UNIT\s+(.*)$')), '') AS unit
) a
LEFT JOIN zip_city zc ON zc.zip = left(trim(c.padzip), 5)
LEFT JOIN raw.cc_land_use lu ON lu.code = trim(c.landuse)
LEFT JOIN geom_cc g ON g.account = trim(c.account)
WHERE trim(coalesce(c.account, '')) <> ''
ON CONFLICT DO NOTHING;

-- Sarasota County (sc-pa.com Sarasota.csv + county ParcelHosted feature service).
-- In the feature service, condo units are stacked copies under the master ACCOUNT; ID is the unit's own account.
INSERT INTO parcels
SELECT
  'SARASOTA',
  trim(s.account),
  nullif(trim(s.name1), ''),
  nullif(concat_ws(', ', nullif(trim(s.name_add2), ''), nullif(trim(s.name_add3), ''),
                         nullif(trim(s.name_add4), ''), nullif(trim(s.name_add5), '')), ''),
  nullif(trim(s.city), ''), nullif(trim(s.state), ''), nullif(trim(s.zip), ''),
  nullif(trim(s.country), ''),
  a.num,
  a.street,
  nullif(trim(s.unit), ''),
  nullif(upper(trim(s.loccity)), ''),
  nullif(left(trim(s.loczip), 5), ''),
  CASE WHEN a.num IS NOT NULL THEN concat_ws(' ', a.num, a.street, 'UNIT ' || nullif(trim(s.unit), '')) END,
  norm_addr(a.street),
  norm_addr(a.num || ' ' || a.street),
  nullif(trim(s.stcd), ''),
  lu.description,
  nullif(concat_ws(', ', nullif(trim(s.zoning_1), ''), nullif(trim(s.zoning_2), '')), ''),
  nullif(trim(s.subd), ''),
  to_num(s.just), to_num(s.assd), to_num(s.txbl),
  NULL, NULL,
  nullif(concat_ws(',', nullif(trim(s.exempt1), ''), nullif(trim(s.exempt2), ''), nullif(trim(s.exempt3), ''),
                        nullif(trim(s.exempt4), ''), nullif(trim(s.exempt5), '')), ''),
  upper(trim(s.homestead)) IN ('Y', 'YES', '1', 'TRUE', 'H', 'X'),
  nullif(to_num(s.yrbl), 0)::int,
  nullif(to_num(s.living), 0),
  nullif(to_num(s.grnd_area), 0),
  nullif(to_num(s.bedr), 0),
  nullif(coalesce(to_num(s.bath), 0) + 0.5 * coalesce(to_num(s.halfbath), 0), 0),
  upper(trim(s.pool)) IN ('Y', 'YES', '1', 'TRUE'),
  nullif(trim(s.gulfbay), ''),
  nullif(to_num(s.lsqft), 0),
  nullif(to_num(s.sale_amt), 0),
  to_date_any(s.sale_date),
  nullif(concat_ws(' ', nullif(trim(s.legal1), ''), nullif(trim(s.legal2), ''),
                        nullif(trim(s.legal3), ''), nullif(trim(s.legal4), '')), ''),
  'https://www.sarasotapropertyappraiser.gov/propertysearch/parcel/details/' || trim(s.account),
  g.geom
FROM raw.sc_parcels_csv s
CROSS JOIN LATERAL (
  SELECT nullif(nullif(trim(s.locn), ''), '0') AS num,
         nullif(regexp_replace(concat_ws(' ', nullif(trim(s.locd), ''), nullif(trim(s.locs), '')), '\s+', ' ', 'g'), '') AS street
) a
LEFT JOIN raw.sc_land_use lu ON lu.code = trim(s.stcd)
LEFT JOIN geom_sc g ON g.account = trim(s.account)
WHERE trim(coalesce(s.account, '')) <> ''
ON CONFLICT DO NOTHING;

---------------------------------------------------------------------------
-- Sales history
---------------------------------------------------------------------------
TRUNCATE sales;

INSERT INTO sales (county, parcel_id, sale_date, sale_price, deed_type, qual_code, book, page,
                   instrument, grantor, vacant_improved)
SELECT 'CHARLOTTE', trim(account), to_date_any(saledate), to_num(saleprice), nullif(trim(salecode), ''),
       nullif(trim(code), ''), nullif(trim(book), ''), nullif(trim(page), ''),
       nullif(trim(instrumentnumber), ''), NULL, nullif(trim(vacimp), '')
FROM raw.cc_sales WHERE trim(coalesce(account, '')) <> '';

INSERT INTO sales (county, parcel_id, sale_date, sale_price, deed_type, qual_code, instrument, grantor)
SELECT 'SARASOTA', trim(account), to_date_any(saledate), to_num(saleprice), nullif(trim(deedtype), ''),
       nullif(trim(qualcode), ''), nullif(trim(legalreference), ''), nullif(trim(grantor), '')
FROM raw.sc_sales WHERE trim(coalesce(account, '')) <> '';

---------------------------------------------------------------------------
-- FEMA flood zones
---------------------------------------------------------------------------
TRUNCATE flood_zones RESTART IDENTITY;
INSERT INTO flood_zones (county, dfirm_id, fld_ar_id, fld_zone, zone_subty, sfha, static_bfe,
                         depth, vert_datum, source_cit, geom)
SELECT county, dfirm_id, fld_ar_id, nullif(trim(fld_zone), ''), nullif(trim(zone_subty), ''),
       upper(trim(sfha_tf)) = 'T',
       CASE WHEN static_bfe::numeric > -9000 THEN static_bfe::numeric END,
       CASE WHEN depth::numeric > -9000 THEN depth::numeric END,
       nullif(trim(v_datum), ''), nullif(trim(source_cit), ''),
       ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
FROM raw.fema_fld_haz_ar
WHERE geom IS NOT NULL;

TRUNCATE flood_zones_sub;
INSERT INTO flood_zones_sub (zone_id, geom)
SELECT z.id, d.geom
FROM flood_zones z
CROSS JOIN LATERAL ST_Subdivide(z.geom, 128) AS d(geom)
WHERE GeometryType(d.geom) = 'POLYGON';

TRUNCATE firm_panels RESTART IDENTITY;
INSERT INTO firm_panels (county, dfirm_id, firm_pan, panel_typ, eff_date, geom)
SELECT county, dfirm_id, firm_pan, panel_typ, to_date_any(eff_date::text),
       ST_Multi(ST_CollectionExtract(ST_MakeValid(geom), 3))
FROM raw.fema_firm_pan WHERE geom IS NOT NULL;

COMMIT;

---------------------------------------------------------------------------
-- Parcel -> flood zone summary (for QGIS styling and bulk questions).
-- primary_zone = zone at the parcel's interior point; worst_zone = riskiest zone touching it.
---------------------------------------------------------------------------
DROP MATERIALIZED VIEW IF EXISTS parcel_flood;
CREATE MATERIALIZED VIEW parcel_flood AS
SELECT p.county, p.parcel_id, p.site_address, p.site_city, p.owner_name, p.just_value,
       pz.fld_zone   AS primary_zone,
       pz.zone_subty AS primary_zone_subtype,
       pz.static_bfe AS primary_bfe,
       coalesce(pz.sfha, false) AS in_sfha,
       wz.fld_zone   AS worst_zone,
       wz.zones      AS zones_touching,
       p.geom
FROM parcels p
LEFT JOIN LATERAL (
  SELECT z.fld_zone, z.zone_subty, z.static_bfe, z.sfha
  FROM flood_zones_sub s JOIN flood_zones z ON z.id = s.zone_id
  WHERE ST_Intersects(s.geom, ST_PointOnSurface(p.geom)) AND z.county = p.county
  ORDER BY flood_zone_rank(z.fld_zone, z.zone_subty) LIMIT 1
) pz ON true
LEFT JOIN LATERAL (
  SELECT (array_agg(z.fld_zone ORDER BY flood_zone_rank(z.fld_zone, z.zone_subty)))[1] AS fld_zone,
         string_agg(DISTINCT z.fld_zone, ',') AS zones
  FROM flood_zones_sub s JOIN flood_zones z ON z.id = s.zone_id
  WHERE ST_Intersects(s.geom, p.geom) AND z.county = p.county
) wz ON true
WHERE p.geom IS NOT NULL;

CREATE UNIQUE INDEX parcel_flood_pk ON parcel_flood (county, parcel_id);
CREATE INDEX parcel_flood_gix ON parcel_flood USING gist (geom);
CREATE INDEX parcel_flood_zone_ix ON parcel_flood (primary_zone);

GRANT SELECT ON ALL TABLES IN SCHEMA public TO gis_reader;

ANALYZE parcels; ANALYZE sales; ANALYZE flood_zones; ANALYZE flood_zones_sub;
ANALYZE firm_panels; ANALYZE parcel_flood;
