class_name CityTileDecoder
extends RefCounted
## Decodes .nyct city tiles written by tools/citygen/build_tiles.py.
##
## Layout (zstd-compressed, little-endian): "NYCT", u32 version, u32 surface_count,
## surface_count x (u32 kind, u32 vertex_count, u32 index_count), then per surface:
## positions f32x3, normals f32x3, uv f32x2, uv2 f32x2 (all per vertex), indices u32.
## Mesh surfaces are triangle lists; the lanes surface holds polylines along the
## sidewalks, separated by index 0xFFFFFFFF. The props surface (near tiles) is
## one vertex per prop, sorted by type, and no indices:
##   position  where it stands (a tree's trunk on the ground, a water tower's
##             legs on the roof, a street light's pole on the sidewalk),
##             tile-local
##   normal    (height m, width m, yaw radians): total height to the top; the
##             crown's or tank's diameter, or a street light's arm length;
##             rotation about +Y (a street light's arm reaches along
##             (sin yaw, 0, cos yaw), over the street)
##   uv        (variant, trunk diameter m): trees' foliage tone (TONE_*) and
##             trunk; water towers' tank (0 wood, 1 steel) and 0; street
##             lights' style (STREET_LIGHT_*) and 0
##   uv2       (PROP_* type, seed 0..1)

const MAGIC := "NYCT"
const VERSION := 6
const SURFACE_BUILDINGS := 0
const SURFACE_GROUND := 1
const SURFACE_LANES := 2
## Bridges: decks, columns, towers and cables (drawn with the ground material).
const SURFACE_STRUCTURES := 3
## Lakes, reservoirs and creeks above sea level (sea-level water is the ocean plane).
const SURFACE_WATER := 4
## Trees, rooftop water towers and street lights, one point each (near tiles only).
const SURFACE_PROPS := 5
## Paint on the streets (near tiles only): strips a few centimeters above the
## road, without collision. UV is local to each strip in meters (x along the
## street, y across it), uv2.x the kind (MARKING_*), whose pattern
## shaders/markings.gdshader paints.
const SURFACE_MARKINGS := 6
## Markings kinds (uv2.x of the markings surface).
const MARKING_WHITE := 10      ## solid: stop lines, highway edge lines
const MARKING_YELLOW := 11     ## double yellow center line
const MARKING_DASHED := 12     ## white lane line, 3 m dashes, 9 m gaps
const MARKING_CROSSWALK := 13  ## high-visibility crosswalk bars
## 0xFFFFFFFF read as a signed 32-bit index.
const LANE_BREAK := -1

## Prop types (uv2.x of the props surface).
const PROP_TREE := 0          ## broadleaf, round crown
const PROP_TREE_NARROW := 1   ## columnar or oval crown (Callery pear, ginkgo)
const PROP_CONIFER := 2       ## pine, spruce, fir, cedar
const PROP_WATER_TOWER := 3   ## rooftop water tank on a steel stand
const PROP_STREET_LIGHT := 4  ## lamp post at the curb, its arm over the street
const PROP_TYPE_COUNT := 5
## Trees' foliage tones (uv.x of the props surface).
const TONE_GREEN := 0
const TONE_LIGHT := 1  ## yellow-green: honeylocust, ginkgo, birch, willow
const TONE_DARK := 2   ## oaks, lindens, conifers
const TONE_RED := 3    ## purple-leaf plum, copper beech
## Street lights' styles (uv.x of the props surface).
const STREET_LIGHT_COBRA_HEAD := 0  ## modern: a 9 m pole, a 2.6 m arm
const STREET_LIGHT_POST_TOP := 1    ## historic: a 4.4 m post with a lantern, by parks


## Returns one dictionary per surface: {kind, mesh: ArrayMesh} for meshes,
## {kind, lanes: Array[PackedVector3Array]} (tile-local points) for lanes, or
## {kind, positions, normals: PackedVector3Array, uv, uv2: PackedVector2Array}
## for props (laid out as above). Returns [] if the data is bad.
static func decode(packed: PackedByteArray, raw_size: int) -> Array[Dictionary]:
	var surfaces: Array[Dictionary] = []
	var data := packed.decompress(raw_size, FileAccess.COMPRESSION_ZSTD)
	if data.size() != raw_size or data.slice(0, 4).get_string_from_ascii() != MAGIC:
		push_error("City tile is corrupt or truncated.")
		return surfaces
	if data.decode_u32(4) != VERSION:
		push_error("City tile version %d, expected %d. Rebuild the tiles." % [data.decode_u32(4), VERSION])
		return surfaces

	var count := data.decode_u32(8)
	var offset := 12 + count * 12
	for s in count:
		var header := 12 + s * 12
		var kind := data.decode_u32(header)
		var vertex_count := data.decode_u32(header + 4)
		var index_count := data.decode_u32(header + 8)

		var positions := data.slice(offset, offset + vertex_count * 12).to_vector3_array()
		offset += vertex_count * 12
		var normals := data.slice(offset, offset + vertex_count * 12).to_vector3_array()
		offset += vertex_count * 12
		var uv := data.slice(offset, offset + vertex_count * 8).to_vector2_array()
		offset += vertex_count * 8
		var uv2 := data.slice(offset, offset + vertex_count * 8).to_vector2_array()
		offset += vertex_count * 8
		var indices := data.slice(offset, offset + index_count * 4).to_int32_array()
		offset += index_count * 4

		if kind == SURFACE_LANES:
			surfaces.append({"kind": kind, "lanes": _split_lanes(positions, indices)})
			continue
		if kind == SURFACE_PROPS:
			surfaces.append({"kind": kind, "positions": positions, "normals": normals, "uv": uv, "uv2": uv2})
			continue
		if index_count == 0:
			continue
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uv
		arrays[Mesh.ARRAY_TEX_UV2] = uv2
		arrays[Mesh.ARRAY_INDEX] = indices
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		surfaces.append({"kind": kind, "mesh": mesh})
	return surfaces


static func _split_lanes(points: PackedVector3Array, indices: PackedInt32Array) -> Array[PackedVector3Array]:
	var lanes: Array[PackedVector3Array] = []
	var lane := PackedVector3Array()
	for index in indices:
		if index == LANE_BREAK:
			if lane.size() > 1:
				lanes.append(lane)
			lane = PackedVector3Array()
		else:
			lane.append(points[index])
	return lanes
