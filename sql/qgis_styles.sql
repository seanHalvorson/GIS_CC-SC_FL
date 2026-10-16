-- Default QGIS styles (QGIS applies these automatically when the layer is added).
CREATE TABLE IF NOT EXISTS public.layer_styles (id serial PRIMARY KEY, f_table_catalog varchar, f_table_schema varchar, f_table_name varchar, f_geometry_column varchar, stylename text, styleqml xml, stylesld xml, useasdefault boolean, description text, owner varchar(63) DEFAULT CURRENT_USER, ui xml, update_time timestamp DEFAULT CURRENT_TIMESTAMP, type varchar);
DELETE FROM public.layer_styles WHERE stylename LIKE 'swfl-gis %';
INSERT INTO public.layer_styles (f_table_catalog, f_table_schema, f_table_name, f_geometry_column, stylename, styleqml, useasdefault, type) VALUES (current_database(), 'public', 'flood_zones', 'geom', 'swfl-gis flood zones', $q$<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'><qgis version="3.34.0" styleCategories="Symbology">
<renderer-v2 type="categorizedSymbol" attr="CASE WHEN &quot;fld_zone&quot; = 'X' AND &quot;zone_subty&quot; LIKE '%0.2 PCT%' THEN 'X 0.2%' ELSE &quot;fld_zone&quot; END" enableorderby="0" symbollevels="0" forceraster="0" referencescale="-1">
<categories><category render="true" value="VE" symbol="0" label="VE – coastal high hazard (wave action)" type="string"/><category render="true" value="AE" symbol="1" label="AE – 1% annual chance, BFE set" type="string"/><category render="true" value="A" symbol="2" label="A – 1% annual chance, no BFE" type="string"/><category render="true" value="AO" symbol="3" label="AO – shallow sheet flow" type="string"/><category render="true" value="AH" symbol="4" label="AH – shallow ponding" type="string"/><category render="true" value="X 0.2%" symbol="5" label="X shaded – 0.2% annual chance (500-yr)" type="string"/><category render="true" value="X" symbol="6" label="X – minimal risk" type="string"/><category render="true" value="OPEN WATER" symbol="7" label="Open water" type="string"/><category render="true" value="D" symbol="8" label="D – undetermined" type="string"/></categories><symbols><symbol type="fill" name="0" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="190,20,40,150" type="QString"/><Option name="outline_color" value="140,0,20,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="1" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="30,110,220,140" type="QString"/><Option name="outline_color" value="10,60,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="2" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="80,160,240,140" type="QString"/><Option name="outline_color" value="10,60,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="3" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="120,90,210,140" type="QString"/><Option name="outline_color" value="70,40,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="4" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="150,110,230,140" type="QString"/><Option name="outline_color" value="70,40,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="5" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="250,170,40,120" type="QString"/><Option name="outline_color" value="200,120,0,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="6" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="200,200,200,40" type="QString"/><Option name="outline_color" value="160,160,160,120" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="7" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="120,200,240,90" type="QString"/><Option name="outline_color" value="80,160,210,150" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="8" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="160,120,80,90" type="QString"/><Option name="outline_color" value="120,80,40,150" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol></symbols></renderer-v2><blendMode>0</blendMode><featureBlendMode>0</featureBlendMode></qgis>$q$::xml, true, NULL);
INSERT INTO public.layer_styles (f_table_catalog, f_table_schema, f_table_name, f_geometry_column, stylename, styleqml, useasdefault, type) VALUES (current_database(), 'public', 'parcel_flood', 'geom', 'swfl-gis parcels by flood zone', $q$<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'><qgis version="3.34.0" styleCategories="Symbology">
<renderer-v2 type="categorizedSymbol" attr="CASE WHEN &quot;primary_zone&quot; = 'X' AND &quot;primary_zone_subtype&quot; LIKE '%0.2 PCT%' THEN 'X 0.2%' ELSE &quot;primary_zone&quot; END" enableorderby="0" symbollevels="0" forceraster="0" referencescale="-1">
<categories><category render="true" value="VE" symbol="0" label="VE – coastal high hazard (wave action)" type="string"/><category render="true" value="AE" symbol="1" label="AE – 1% annual chance, BFE set" type="string"/><category render="true" value="A" symbol="2" label="A – 1% annual chance, no BFE" type="string"/><category render="true" value="AO" symbol="3" label="AO – shallow sheet flow" type="string"/><category render="true" value="AH" symbol="4" label="AH – shallow ponding" type="string"/><category render="true" value="X 0.2%" symbol="5" label="X shaded – 0.2% annual chance (500-yr)" type="string"/><category render="true" value="X" symbol="6" label="X – minimal risk" type="string"/><category render="true" value="OPEN WATER" symbol="7" label="Open water" type="string"/><category render="true" value="D" symbol="8" label="D – undetermined" type="string"/></categories><symbols><symbol type="fill" name="0" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="190,20,40,150" type="QString"/><Option name="outline_color" value="140,0,20,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="1" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="30,110,220,140" type="QString"/><Option name="outline_color" value="10,60,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="2" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="80,160,240,140" type="QString"/><Option name="outline_color" value="10,60,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="3" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="120,90,210,140" type="QString"/><Option name="outline_color" value="70,40,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="4" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="150,110,230,140" type="QString"/><Option name="outline_color" value="70,40,160,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="5" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="250,170,40,120" type="QString"/><Option name="outline_color" value="200,120,0,255" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="6" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="200,200,200,40" type="QString"/><Option name="outline_color" value="160,160,160,120" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="7" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="120,200,240,90" type="QString"/><Option name="outline_color" value="80,160,210,150" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol><symbol type="fill" name="8" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="160,120,80,90" type="QString"/><Option name="outline_color" value="120,80,40,150" type="QString"/>
<Option name="outline_width" value="0.1" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="solid" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol></symbols></renderer-v2><blendMode>0</blendMode><featureBlendMode>0</featureBlendMode></qgis>$q$::xml, true, NULL);
INSERT INTO public.layer_styles (f_table_catalog, f_table_schema, f_table_name, f_geometry_column, stylename, styleqml, useasdefault, type) VALUES (current_database(), 'public', 'parcels', 'geom', 'swfl-gis parcel outlines', $q$<!DOCTYPE qgis PUBLIC 'http://mrcc.com/qgis.dtd' 'SYSTEM'><qgis version="3.34.0" styleCategories="Symbology">
<renderer-v2 type="singleSymbol" enableorderby="0" symbollevels="0" forceraster="0" referencescale="-1"><symbols><symbol type="fill" name="0" alpha="1" clip_to_extent="1" force_rhr="0" is_animated="0" frame_rate="10">
<layer class="SimpleFill" enabled="1" locked="0" pass="0"><Option type="Map">
<Option name="color" value="0,0,0,0" type="QString"/><Option name="outline_color" value="90,90,90,255" type="QString"/>
<Option name="outline_width" value="0.15" type="QString"/><Option name="outline_width_unit" value="MM" type="QString"/>
<Option name="style" value="no" type="QString"/><Option name="outline_style" value="solid" type="QString"/>
<Option name="joinstyle" value="bevel" type="QString"/></Option></layer></symbol></symbols></renderer-v2></qgis>$q$::xml, true, NULL);
GRANT SELECT ON public.layer_styles TO gis_reader;
