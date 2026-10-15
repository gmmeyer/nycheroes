class_name PropMeshes
extends RefCounted
## Low-poly meshes for the city's props (see CityProps), built in code at unit
## size: the prop's base point at the origin, its top at y = 1, and its crown
## or tank 1 wide (x and z from -0.5 to 0.5). Each instance scales the mesh to
## its real height and width; the shaders turn it to its yaw and add the
## per-prop variety.
##
## UV.x says which part a vertex belongs to (the shaders color by part) and
## UV.y how far up that part it is; UV2 carries a part's own data (below).
## Trees (shaders/tree.gdshader), one mesh in three shapes, so one MultiMesh
## draws every kind of tree:
##   VERTEX, NORMAL, UV, UV2  a broadleaf with a round crown
##   CUSTOM0, CUSTOM1         (position, UV.y), (normal, UV2.x) of a narrow one
##   CUSTOM2, CUSTOM3         the same of a conifer
##   UV = (PART_TRUNK or PART_CROWN, 0 at the crown's bottom .. 1 at its top)
##   UV2.x = a shade offset per blob (-1..1), so lumps read apart
##   trunks TRUNK_RADIUS (of the crown's width) around, which the shader
##   scales to the tree's real trunk
## Crowns are clusters of lumpy blobs (icosahedra) whose normals lean toward
## the normals of one ellipsoid around the whole crown, so the toon light
## wraps the crown as one soft ball while the outline stays lumpy. A
## conifer's blobs become stacked five-sided cones.
## Water towers (shaders/water_tower.gdshader):
##   UV = (part, 0 at the part's bottom .. 1 at its top)
##   UV2.x = around the tank (0..1) on the wall and roof, for staves and seams
## Street lights (shaders/street_light.gdshader), one mesh with both styles,
## the other style's parts folded away by the shader, and not at unit size:
## each part is measured from what the shader stretches it to.
##   UV = (part, 0 at the part's bottom .. 1 at its top)
##   cobra-head: the pole's y in its height (0..1); the mast arm's z in its
##   length (0..1, reaching along +z) and y in meters from the pole's top;
##   the luminaire (housing and lens) in meters from the arm's end
##   post-top: everything's y in the lamp's height (0..1), x and z in meters
## Plus their glows (street_light_glow.gdshader, a quad the shader turns to
## the camera) and pools of light on the ground (street_light_pool.gdshader,
## a 2D quad drawn into StreetLightMap).

const PART_TRUNK := 0
const PART_CROWN := 1

const PART_TANK := 0
const PART_TANK_BOTTOM := 1
const PART_ROOF := 2
const PART_FINIAL := 3
const PART_STEEL := 4
const PART_PLATFORM := 5

const PART_POLE := 0
const PART_ARM := 1
const PART_HOUSING := 2
const PART_LENS := 3
const PART_POST := 4
const PART_LANTERN := 5
const PART_CAP := 6
## The sizes the street light mesh is built at (m): a cobra-head's pole and
## arm, and a post-top's height.
const COBRA_HEAD_HEIGHT := 9.0
const COBRA_HEAD_ARM := 2.6
const POST_TOP_HEIGHT := 4.4

## How far blob normals lean toward the whole crown's (0 = each blob its own
## ball, 1 = one smooth ball).
const CROWN_NORMAL_BLEND := 0.6
## Where conifers' crowns start (share of the height).
const CONIFER_BOTTOM := 0.12
## Trees' trunks' radius halfway up (they flare at the foot), as a share of
## the crown's width; shaders/tree.gdshader assumes it.
const TRUNK_RADIUS := 0.04


## Every tree: a short trunk under a crown of four blobs, in three shapes
## (see above). 90 triangles.
static func tree() -> ArrayMesh:
	var round := _Builder.new()
	_trunk(round, 0.5)
	var crown := _Crown.new(0.36, 1.0, round)
	# Blobs: center, radii (unit space: 1 = the crown's width and the tree's height).
	crown.blob(Vector3(0.02, 0.80, -0.03), Vector3(0.30, 0.20, 0.30), 0.3)
	crown.blob(Vector3(-0.21, 0.61, 0.11), Vector3(0.27, 0.18, 0.27), -0.5)
	crown.blob(Vector3(0.20, 0.63, 0.13), Vector3(0.27, 0.18, 0.27), 0.9)
	crown.blob(Vector3(0.04, 0.59, -0.21), Vector3(0.27, 0.17, 0.27), -0.1)
	# Columnar or oval (Callery pear, ginkgo): stacked blobs on a slimmer trunk.
	var narrow := _Builder.new()
	_trunk(narrow, 0.4)
	crown = _Crown.new(0.22, 1.0, narrow)
	crown.blob(Vector3(0.0, 0.42, 0.01), Vector3(0.47, 0.21, 0.47), -0.4)
	crown.blob(Vector3(0.03, 0.62, -0.02), Vector3(0.45, 0.21, 0.45), 0.6)
	crown.blob(Vector3(-0.02, 0.80, 0.01), Vector3(0.35, 0.16, 0.35), 0.0)
	crown.blob(Vector3(0.01, 0.92, 0.0), Vector3(0.21, 0.08, 0.21), 0.4)
	# Conifer: four cones (base height, radius, apex height), smaller going up.
	var conifer := _Builder.new()
	_trunk(conifer, 0.3)
	crown = _Crown.new(CONIFER_BOTTOM, 1.0, conifer)
	crown.cone(CONIFER_BOTTOM, 0.5, 0.56, -0.3)
	crown.cone(0.33, 0.42, 0.73, 0.4)
	crown.cone(0.53, 0.32, 0.88, -0.1)
	crown.cone(0.70, 0.2, 1.0, 0.5)
	return round.commit([narrow, conifer])


## A stand-in that casts trees' shadows, cheaper than a tree: a trunk and one
## plain ball (or cone) a little inside the crown, so the crown's own lumps on
## the sunny side stay lit. In the same three shapes. 30 triangles.
static func tree_shadow() -> ArrayMesh:
	var round := _Builder.new()
	_trunk(round, 0.5)
	_Crown.new(0.36, 1.0, round).blob(Vector3(0.0, 0.68, 0.0), Vector3(0.4, 0.26, 0.4), 0.0)
	var narrow := _Builder.new()
	_trunk(narrow, 0.4)
	_Crown.new(0.22, 1.0, narrow).blob(Vector3(0.0, 0.62, 0.0), Vector3(0.38, 0.33, 0.38), 0.0)
	var conifer := _Builder.new()
	_trunk(conifer, 0.3)
	_Crown.new(CONIFER_BOTTOM, 1.0, conifer).cone(CONIFER_BOTTOM, 0.42, 1.0, 0.0)
	return round.commit([narrow, conifer])


## New York's rooftop water tank: a wooden (or steel) tank with a conical
## roof and a finial, on a platform over six braced steel legs. 140 triangles.
static func water_tower() -> ArrayMesh:
	var b := _Builder.new()
	const SIDES := 12
	const RADIUS := 0.5
	const TANK_BOTTOM := 0.36
	const TANK_TOP := 0.8
	const ROOF_RADIUS := 0.53
	const ROOF_TOP := 0.95
	# Tank wall, with a seam of doubled vertices so UV2.x runs 0..1 around.
	var bottom_ring := PackedInt32Array()
	var top_ring := PackedInt32Array()
	for i in SIDES + 1:
		var a := TAU * i / SIDES
		var out := Vector3(cos(a), 0.0, sin(a))
		bottom_ring.append(b.vertex(out * RADIUS + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_TANK, 0.0), Vector2(float(i) / SIDES, 0.0)))
		top_ring.append(b.vertex(out * RADIUS + Vector3.UP * TANK_TOP, out, Vector2(PART_TANK, 1.0), Vector2(float(i) / SIDES, 0.0)))
	for i in SIDES:
		var out := Vector3(cos(TAU * (i + 0.5) / SIDES), 0.0, sin(TAU * (i + 0.5) / SIDES))
		b.quad(bottom_ring[i], bottom_ring[i + 1], top_ring[i + 1], top_ring[i], out)
	# Tank bottom, seen from the street.
	var floor_ring := PackedInt32Array()
	for i in SIDES:
		var a := TAU * i / SIDES
		floor_ring.append(b.vertex(Vector3(cos(a) * RADIUS, TANK_BOTTOM, sin(a) * RADIUS), Vector3.DOWN, Vector2(PART_TANK_BOTTOM, 0.0)))
	for i in range(1, SIDES - 1):
		b.triangle(floor_ring[0], floor_ring[i], floor_ring[i + 1], Vector3.DOWN)
	# Conical roof overhanging the tank a little (the material is double-sided,
	# so its underside shows from below).
	var slope := Vector2(ROOF_TOP - TANK_TOP, ROOF_RADIUS).normalized()
	var eave := PackedInt32Array()
	for i in SIDES + 1:
		var a := TAU * i / SIDES
		var n := Vector3(cos(a) * slope.x, slope.y, sin(a) * slope.x)
		eave.append(b.vertex(Vector3(cos(a) * ROOF_RADIUS, TANK_TOP, sin(a) * ROOF_RADIUS), n, Vector2(PART_ROOF, 0.0), Vector2(float(i) / SIDES, 0.0)))
	for i in SIDES:
		var a := TAU * (i + 0.5) / SIDES
		var n := Vector3(cos(a) * slope.x, slope.y, sin(a) * slope.x)
		var apex := b.vertex(Vector3(0.0, ROOF_TOP, 0.0), n, Vector2(PART_ROOF, 1.0), Vector2((i + 0.5) / SIDES, 0.0))
		b.triangle(eave[i], eave[i + 1], apex, n)
	# Finial: a little six-sided spike on top.
	_spike(b, 6, Vector3(0.0, ROOF_TOP - 0.01, 0.0), 0.035, 1.0, PART_FINIAL)
	# Platform under the tank: a hexagonal slab, sides and underside.
	const PLATFORM_BOTTOM := 0.32
	const PLATFORM_RADIUS := 0.48
	var under := PackedInt32Array()
	for k in 6:
		var a0 := TAU * (k + 0.5) / 6.0
		var a1 := TAU * (k + 1.5) / 6.0
		var p0 := Vector3(cos(a0), 0.0, sin(a0)) * PLATFORM_RADIUS
		var p1 := Vector3(cos(a1), 0.0, sin(a1)) * PLATFORM_RADIUS
		var out := ((p0 + p1) * 0.5).normalized()
		var uv := Vector2(PART_PLATFORM, 0.0)
		b.quad(b.vertex(p0 + Vector3.UP * PLATFORM_BOTTOM, out, uv), b.vertex(p1 + Vector3.UP * PLATFORM_BOTTOM, out, uv),
			b.vertex(p1 + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_PLATFORM, 1.0)),
			b.vertex(p0 + Vector3.UP * TANK_BOTTOM, out, Vector2(PART_PLATFORM, 1.0)), out)
		under.append(b.vertex(p0 + Vector3.UP * PLATFORM_BOTTOM, Vector3.DOWN, uv))
	for k in range(1, 5):
		b.triangle(under[0], under[k], under[k + 1], Vector3.DOWN)
	# Six steel legs, splayed a little, with X bracing between neighbors.
	const LEG_HALF := 0.022
	var feet: Array[Vector3] = []
	var heads: Array[Vector3] = []
	for k in 6:
		var a := TAU * (k + 0.5) / 6.0
		var dir := Vector3(cos(a), 0.0, sin(a))
		feet.append(dir * 0.42)
		heads.append(dir * 0.37 + Vector3.UP * PLATFORM_BOTTOM)
		_beam(b, feet[k], heads[k], LEG_HALF)
	for k in 6:
		var n := (k + 1) % 6
		var out := ((feet[k] + feet[n]) * 0.5).normalized()
		var low := 0.04 / PLATFORM_BOTTOM
		var high := 0.92
		_strut(b, feet[k].lerp(heads[k], low), feet[n].lerp(heads[n], high), out, 0.012)
		_strut(b, feet[n].lerp(heads[n], low), feet[k].lerp(heads[k], high), out, 0.012)
	return b.commit()


## New York's street lights, both styles in one mesh (see above):
## a cobra-head, a tapered steel pole whose mast arm curves up and out over
## the street to a long luminaire with a lens underneath (52 triangles); and a
## historic post-top, a fluted cast-iron post with a glass lantern under a
## cap (78 triangles).
static func street_light() -> ArrayMesh:
	var b := _Builder.new()
	# Cobra-head: the pole, flaring into a base at the foot.
	_lathe(b, 6, [Vector2(0.0, 0.16), Vector2(0.55, 0.13), Vector2(COBRA_HEAD_HEIGHT, 0.07)], PART_POLE)
	# The mast arm, from just below the pole's top, rising to the luminaire.
	var top := COBRA_HEAD_HEIGHT
	var arm := [Vector3(0.0, top - 0.6, 0.0), Vector3(0.0, top - 0.2, COBRA_HEAD_ARM * 0.45), Vector3(0.0, top - 0.08, COBRA_HEAD_ARM)]
	for k in 2:
		_beam(b, arm[k], arm[k + 1], 0.045, PART_ARM)
	# The luminaire: a long housing, wider and lower toward its front, with
	# the lens underneath.
	var end := Vector3(0.0, top - 0.08, COBRA_HEAD_ARM)
	var back := [Vector3(-0.13, 0.05, -0.12), Vector3(0.13, 0.05, -0.12), Vector3(0.13, -0.09, -0.12), Vector3(-0.13, -0.09, -0.12)]
	var front := [Vector3(-0.17, 0.0, 0.62), Vector3(0.17, 0.0, 0.62), Vector3(0.17, -0.12, 0.62), Vector3(-0.17, -0.12, 0.62)]
	var corners: Array[int] = []
	for k in 4:
		var p: Vector3 = back[k]
		corners.append(b.vertex(end + p, p.normalized(), Vector2(PART_HOUSING, 0.0 if p.y < 0.0 else 1.0)))
	for k in 4:
		var p: Vector3 = front[k]
		corners.append(b.vertex(end + p, p.normalized(), Vector2(PART_HOUSING, 0.0 if p.y < 0.0 else 1.0)))
	var center := end + Vector3(0.0, -0.04, 0.25)
	for face in [[0, 1, 5, 4], [1, 2, 6, 5], [3, 0, 4, 7], [0, 3, 2, 1], [4, 5, 6, 7]]:
		var mid := Vector3.ZERO
		for k in face:
			mid += b.positions[corners[k]]
		b.quad(corners[face[0]], corners[face[1]], corners[face[2]], corners[face[3]], mid / 4.0 - center)
	var lens: Array[int] = []
	for k in [2, 3, 7, 6]:
		var p: Vector3 = (back + front)[k]
		lens.append(b.vertex(end + p + Vector3(0.0, -0.005, 0.0), Vector3.DOWN, Vector2(PART_LENS, 0.0)))
	b.quad(lens[0], lens[1], lens[2], lens[3], Vector3.DOWN)
	# Post-top: a fluted post on a stepped base, a glass lantern, a cap.
	_lathe(b, 6, [Vector2(0.0, 0.19), Vector2(0.75, 0.14), Vector2(0.9, 0.085), Vector2(3.4, 0.065)], PART_POST)
	_lathe(b, 6, [Vector2(3.4, 0.09), Vector2(3.75, 0.25), Vector2(4.15, 0.2)], PART_LANTERN)
	_lathe(b, 6, [Vector2(4.13, 0.23), Vector2(4.3, 0.08), Vector2(POST_TOP_HEIGHT, 0.0)], PART_CAP)
	# Measured from what the shader stretches them to (see above).
	for i in b.positions.size():
		var p := b.positions[i]
		match int(b.uvs[i].x):
			PART_POLE:
				p.y /= COBRA_HEAD_HEIGHT
			PART_ARM:
				p.y -= COBRA_HEAD_HEIGHT
				p.z /= COBRA_HEAD_ARM
			PART_HOUSING, PART_LENS:
				p.y -= COBRA_HEAD_HEIGHT
				p.z -= COBRA_HEAD_ARM
			_:
				p.y /= POST_TOP_HEIGHT
		b.positions[i] = p
	return b.commit()


## A street light's glow: a quad (corners -1..1 in UV) that the shader turns
## to face the camera at the lamp's head.
static func street_light_glow() -> ArrayMesh:
	var b := _Builder.new()
	var corners: Array[int] = []
	for c in [Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)]:
		corners.append(b.vertex(Vector3(c.x, c.y, 0.0), Vector3.BACK, c))
	b.quad(corners[0], corners[1], corners[2], corners[3], Vector3.BACK)
	return b.commit()


## A street light's pool of light, as a 2D quad from -1 to 1 (StreetLightMap).
static func light_pool() -> ArrayMesh:
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_TEX_UV] = PackedVector2Array([Vector2(-1, -1), Vector2(1, -1), Vector2(1, 1), Vector2(-1, 1)])
	arrays[Mesh.ARRAY_INDEX] = PackedInt32Array([0, 1, 2, 0, 2, 3])
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## A turned shape around the y axis through `profile`'s points (height,
## radius), bottom to top, with `sides` flat sides; a radius of 0 closes it to
## a point. UV.y runs 0..1 up it.
static func _lathe(b: _Builder, sides: int, profile: Array[Vector2], part: int) -> void:
	var bottom := profile[0].x
	var height := profile[profile.size() - 1].x - bottom
	for k in profile.size() - 1:
		var p0 := profile[k]
		var p1 := profile[k + 1]
		# Each side leans out by the profile's slope.
		var slope := Vector2(p1.x - p0.x, p0.y - p1.y).normalized()
		for i in sides:
			var a0 := TAU * i / sides
			var a1 := TAU * (i + 1) / sides
			var out := Vector3(cos((a0 + a1) * 0.5), 0.0, sin((a0 + a1) * 0.5))
			var n := (out * slope.x + Vector3.UP * slope.y).normalized()
			var v0 := b.vertex(Vector3(cos(a0) * p0.y, p0.x, sin(a0) * p0.y), n, Vector2(part, (p0.x - bottom) / height))
			var v1 := b.vertex(Vector3(cos(a1) * p0.y, p0.x, sin(a1) * p0.y), n, Vector2(part, (p0.x - bottom) / height))
			var v2 := b.vertex(Vector3(cos(a1) * p1.y, p1.x, sin(a1) * p1.y), n, Vector2(part, (p1.x - bottom) / height))
			if p1.y <= 0.0:
				b.triangle(v0, v1, v2, n)
			else:
				var v3 := b.vertex(Vector3(cos(a0) * p1.y, p1.x, sin(a0) * p1.y), n, Vector2(part, (p1.x - bottom) / height))
				b.quad(v0, v1, v2, v3, n)


## A small pointed cone (a water tower's finial).
static func _spike(b: _Builder, sides: int, base: Vector3, radius: float, apex_y: float, part: int) -> void:
	var rim := PackedInt32Array()
	for i in sides:
		var a := TAU * i / sides
		var out := Vector3(cos(a), 0.0, sin(a))
		rim.append(b.vertex(base + out * radius, (out + Vector3.UP * 0.5).normalized(), Vector2(part, 0.0)))
	for i in sides:
		var a := TAU * (i + 0.5) / sides
		var n := (Vector3(cos(a), 0.0, sin(a)) + Vector3.UP * 0.5).normalized()
		b.triangle(rim[i], rim[(i + 1) % sides], b.vertex(Vector3(base.x, apex_y, base.z), n, Vector2(part, 1.0)), n)


## A square steel column from `from` to `to`, open at the ends (8 triangles).
static func _beam(b: _Builder, from: Vector3, to: Vector3, half: float, part := PART_STEEL) -> void:
	var axis := (to - from).normalized()
	var side := axis.cross(Vector3.FORWARD).normalized()
	var front := side.cross(axis).normalized()
	var corners: Array[Vector3] = [side + front, -side + front, -side - front, side - front]
	for k in 4:
		var c0 := corners[k] * half
		var c1 := corners[(k + 1) % 4] * half
		var out := (corners[k] + corners[(k + 1) % 4]).normalized()
		var uv0 := Vector2(part, 0.0)
		var uv1 := Vector2(part, 1.0)
		b.quad(b.vertex(from + c0, out, uv0), b.vertex(from + c1, out, uv0), b.vertex(to + c1, out, uv1), b.vertex(to + c0, out, uv1), out)


## A flat strip (a brace) from `from` to `to`, facing `out` (2 triangles;
## the material is double-sided).
static func _strut(b: _Builder, from: Vector3, to: Vector3, out: Vector3, half: float) -> void:
	var across := (to - from).cross(out).normalized() * half
	var uv := Vector2(PART_STEEL, 0.5)
	b.quad(b.vertex(from - across, out, uv), b.vertex(from + across, out, uv), b.vertex(to + across, out, uv), b.vertex(to - across, out, uv), out)


## A tree trunk: an open five-sided prism from the ground up into the crown.
static func _trunk(b: _Builder, top: float) -> void:
	const SIDES := 5
	var radius := TRUNK_RADIUS
	var ring_bottom := PackedInt32Array()
	var ring_top := PackedInt32Array()
	for i in SIDES:
		var a := TAU * i / SIDES
		var out := Vector3(cos(a), 0.0, sin(a))
		# Flares a little at the foot.
		ring_bottom.append(b.vertex(out * radius * 1.25, out, Vector2(PART_TRUNK, 0.0)))
		ring_top.append(b.vertex(out * radius * 0.8 + Vector3.UP * top, out, Vector2(PART_TRUNK, 1.0)))
	for i in SIDES:
		var n := (i + 1) % SIDES
		var out := Vector3(cos(TAU * (i + 0.5) / SIDES), 0.0, sin(TAU * (i + 0.5) / SIDES))
		b.quad(ring_bottom[i], ring_bottom[n], ring_top[n], ring_top[i], out)


## Collects vertices and triangles, then makes an ArrayMesh.
class _Builder:
	var positions := PackedVector3Array()
	var normals := PackedVector3Array()
	var uvs := PackedVector2Array()
	var uv2s := PackedVector2Array()
	var indices := PackedInt32Array()

	func vertex(position: Vector3, normal: Vector3, uv: Vector2, uv2 := Vector2.ZERO) -> int:
		positions.append(position)
		normals.append(normal.normalized())
		uvs.append(uv)
		uv2s.append(uv2)
		return positions.size() - 1

	## A triangle whose front faces `outward`. Godot draws clockwise triangles
	## as front-facing, so a counter-clockwise one (as seen from outside) is
	## flipped.
	func triangle(a: int, b: int, c: int, outward: Vector3) -> void:
		var normal := (positions[b] - positions[a]).cross(positions[c] - positions[a])
		if normal.dot(outward) > 0.0:
			indices.append_array([a, c, b])
		else:
			indices.append_array([a, b, c])

	## Two triangles over the corners a, b, c, d in order around the quad.
	func quad(a: int, b: int, c: int, d: int, outward: Vector3) -> void:
		triangle(a, b, c, outward)
		triangle(a, c, d, outward)

	## The mesh. Each of `shapes` (built from the same vertices in the same
	## order; their triangles are ignored) goes in two custom arrays, CUSTOM0
	## and CUSTOM1 for the first, CUSTOM2 and CUSTOM3 for the second:
	## (position, UV.y) and (normal, UV2.x). Vertex colors are white, so a
	## MultiMesh's instance colors reach the shader as they are (without a
	## color array, the Compatibility renderer leaves whatever was last set).
	func commit(shapes: Array[_Builder] = []) -> ArrayMesh:
		var arrays := []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = positions
		arrays[Mesh.ARRAY_NORMAL] = normals
		arrays[Mesh.ARRAY_TEX_UV] = uvs
		arrays[Mesh.ARRAY_TEX_UV2] = uv2s
		var white := PackedColorArray()
		white.resize(positions.size())
		white.fill(Color.WHITE)
		arrays[Mesh.ARRAY_COLOR] = white
		arrays[Mesh.ARRAY_INDEX] = indices
		const SHIFTS: Array[int] = [Mesh.ARRAY_FORMAT_CUSTOM0_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM1_SHIFT,
				Mesh.ARRAY_FORMAT_CUSTOM2_SHIFT, Mesh.ARRAY_FORMAT_CUSTOM3_SHIFT]
		var flags := 0
		for k in shapes.size():
			var shape := shapes[k]
			assert(shape.positions.size() == positions.size(), "A mesh's other shapes need the same vertices.")
			var places := PackedFloat32Array()
			var shading := PackedFloat32Array()
			for i in positions.size():
				var p := shape.positions[i]
				var n := shape.normals[i]
				places.append_array([p.x, p.y, p.z, shape.uvs[i].y])
				shading.append_array([n.x, n.y, n.z, shape.uv2s[i].x])
			arrays[Mesh.ARRAY_CUSTOM0 + 2 * k] = places
			arrays[Mesh.ARRAY_CUSTOM1 + 2 * k] = shading
			flags |= (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << SHIFTS[2 * k]) | (Mesh.ARRAY_CUSTOM_RGBA_FLOAT << SHIFTS[2 * k + 1])
		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays, [], {}, flags)
		return mesh


## A tree crown being built from blobs between heights `bottom` and `top`.
## Blobs are icosahedra with a corner at each pole: the top corner, a ring of
## five above the middle, a ring of five below (turned half a step), and the
## bottom corner.
class _Crown:
	var bottom: float
	var top: float
	var builder: _Builder
	var center: Vector3
	var radii: Vector3

	func _init(bottom_y: float, top_y: float, b: _Builder) -> void:
		bottom = bottom_y
		top = top_y
		builder = b
		# The ellipsoid around the whole crown, whose normals the blobs lean toward.
		center = Vector3(0.0, (bottom + top) * 0.5, 0.0)
		radii = Vector3(0.5, (top - bottom) * 0.5, 0.5)

	## The 12 corners of a unit icosahedron with a corner at each pole.
	static func corners() -> Array[Vector3]:
		var out: Array[Vector3] = [Vector3.UP]
		var ring_y := 1.0 / sqrt(5.0)
		var ring_r := 2.0 / sqrt(5.0)
		for k in 5:
			out.append(Vector3(cos(TAU * k / 5.0) * ring_r, ring_y, sin(TAU * k / 5.0) * ring_r))
		for k in 5:
			out.append(Vector3(cos(TAU * (k + 0.5) / 5.0) * ring_r, -ring_y, sin(TAU * (k + 0.5) / 5.0) * ring_r))
		out.append(Vector3.DOWN)
		return out

	## An icosahedron blob at `blob_center` with `blob_radii`, turned by an
	## angle from `shade` (which also shades it a little lighter or darker).
	func blob(blob_center: Vector3, blob_radii: Vector3, shade: float) -> void:
		var turn := Basis(Vector3(0.3, 1.0, 0.2).normalized(), 1.3 + shade * 2.0)
		var first := builder.positions.size()
		for corner in corners():
			var dir := turn * corner
			var p := blob_center + dir * blob_radii
			var own := dir / blob_radii
			var whole := (p - center) / (radii * radii)
			var n := own.normalized().lerp(whole.normalized(), PropMeshes.CROWN_NORMAL_BLEND)
			builder.vertex(p, n, Vector2(PropMeshes.PART_CROWN, _up(p.y)), Vector2(shade, 0.0))
		# Faces: the top cap, the band between the rings, the bottom cap.
		for k in 5:
			var u0 := first + 1 + k
			var u1 := first + 1 + (k + 1) % 5
			var l0 := first + 6 + k
			var l1 := first + 6 + (k + 1) % 5
			for face in [[first, u0, u1], [u0, l0, u1], [l0, l1, u1], [first + 11, l1, l0]]:
				var mid: Vector3 = (builder.positions[face[0]] + builder.positions[face[1]] + builder.positions[face[2]]) / 3.0
				builder.triangle(face[0], face[1], face[2], mid - blob_center)

	## The same 12 corners as a conifer's tier: the top corner at the apex, the
	## upper ring part way up the cone, the lower ring around its base, the
	## bottom corner in the middle of its shallow underside. Adds no triangles
	## (it's a second shape for a blob's).
	func cone(base_y: float, radius: float, apex_y: float, shade: float) -> void:
		var slope := Vector2(apex_y - base_y, radius).normalized()
		var places: Array[Vector3] = [Vector3(0.0, apex_y, 0.0)]
		var faces: Array[Vector3] = [Vector3.UP]
		for k in 5:
			var out := Vector3(cos(TAU * k / 5.0), 0.0, sin(TAU * k / 5.0))
			places.append(out * radius * 0.55 + Vector3.UP * lerpf(base_y, apex_y, 0.45))
			faces.append(Vector3(out.x * slope.x, slope.y, out.z * slope.x))
		for k in 5:
			var out := Vector3(cos(TAU * (k + 0.5) / 5.0), 0.0, sin(TAU * (k + 0.5) / 5.0))
			places.append(out * radius + Vector3.UP * base_y)
			# The rim is shared by the cone and the underside: halfway between.
			faces.append((out + Vector3.UP * 0.2).normalized())
		places.append(Vector3(0.0, base_y + 0.05, 0.0))
		faces.append(Vector3.DOWN)
		for i in places.size():
			builder.vertex(places[i], faces[i], Vector2(PropMeshes.PART_CROWN, _up(places[i].y)), Vector2(shade, 0.0))

	func _up(y: float) -> float:
		return clampf((y - bottom) / (top - bottom), 0.0, 1.0)
