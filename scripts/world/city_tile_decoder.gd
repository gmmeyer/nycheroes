class_name CityTileDecoder
extends RefCounted
## Decodes .nyct city tiles written by tools/citygen/build_tiles.py.
##
## Layout (zstd-compressed, little-endian): "NYCT", u32 version, u32 surface_count,
## surface_count x (u32 kind, u32 vertex_count, u32 index_count), then per surface:
## positions f32x3, normals f32x3, uv f32x2, uv2 f32x2 (all per vertex), indices u32.
## Mesh surfaces are triangle lists; the lanes surface holds polylines along the
## sidewalks, separated by index 0xFFFFFFFF.

const MAGIC := "NYCT"
const VERSION := 4
const SURFACE_BUILDINGS := 0
const SURFACE_GROUND := 1
const SURFACE_LANES := 2
## Bridges: decks, columns, towers and cables (drawn with the ground material).
const SURFACE_STRUCTURES := 3
## 0xFFFFFFFF read as a signed 32-bit index.
const LANE_BREAK := -1


## Returns one dictionary per surface: {kind, mesh: ArrayMesh} for meshes, or
## {kind, lanes: Array[PackedVector3Array]} (tile-local points) for lanes.
## Returns [] if the data is bad.
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
