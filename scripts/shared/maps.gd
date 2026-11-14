extends RefCounted
# Map definitions as plain data (lists of boxes), shared by client and server.
# The client builds meshes + colliders from the boxes; the server only uses the
# box list for its own ray tests, so it never needs a physics world per room.
# Team 0 (red) has its base at -Z, team 1 (blue) at +Z.

const NAMES := ["Open Field", "City Streets", "Sky Platforms"]
const COUNT := 3

const BRICK := Color(0.62, 0.3, 0.25)
const CONCRETE := Color(0.72, 0.72, 0.74)
const TAN := Color(0.78, 0.68, 0.5)
const ASPHALT := Color(0.3, 0.3, 0.33)
const SAND := Color(0.82, 0.74, 0.52)

const RED := Color(0.85, 0.2, 0.2)
const BLUE := Color(0.2, 0.4, 0.95)
const STONE := Color(0.55, 0.55, 0.58)
const WOOD := Color(0.6, 0.42, 0.24)
const GRASS := Color(0.36, 0.62, 0.3)
const LEAF := Color(0.2, 0.5, 0.2)

static var _cache := {}
static var _mats := {}
static var _tex: ImageTexture


static func get_map(id: int) -> Dictionary:
	if not _cache.has(id):
		var l := []
		var hz := 40.0
		match id:
			1:
				_city(l)
			2:
				_platforms(l)
			_:
				_field(l)
		for b: Dictionary in l:
			b.inv = (b.t as Transform3D).affine_inverse()
			b.aabb = AABB(-b.s * 0.5, b.s)
		_cache[id] = {"id": id, "boxes": l, "hz": hz}
	return _cache[id]


# Returns [position, yaw] for the n-th spawn slot of a team.
static func spawn_point(map: Dictionary, team: int, n: int) -> Array:
	var side := -1.0 if team == 0 else 1.0
	var hz: float = map.hz
	var x := ((n % 5) - 2) * 2.5
	var z := side * (hz - 6.0 + ((n / 5) % 2) * 2.5)
	return [Vector3(x, 0.1, z), PI if team == 0 else 0.0]


# Fraction (0..1) along the segment where it first hits map geometry; 1.0 = no hit.
static func ray_world(map: Dictionary, from: Vector3, to: Vector3) -> float:
	var best := 1.0
	for b: Dictionary in map.boxes:
		var inv: Transform3D = b.inv
		var lf := inv * from
		var lt := inv * to
		var hit: Variant = (b.aabb as AABB).intersects_segment(lf, lt)
		if hit != null:
			var f: float = lf.distance_to(hit) / maxf(lf.distance_to(lt), 0.001)
			if f < best:
				best = f
	return best


# ---------- client-side construction ----------

static func block_texture() -> ImageTexture:
	if _tex == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for y in 16:
			for x in 16:
				var v := rng.randf_range(0.8, 1.0)
				if x == 0 or y == 0:
					v *= 0.78
				img.set_pixel(x, y, Color(v, v, v))
		img.generate_mipmaps()
		_tex = ImageTexture.create_from_image(img)
	return _tex


static func material(c: Color) -> StandardMaterial3D:
	if not _mats.has(c):
		var m := StandardMaterial3D.new()
		m.albedo_color = c
		m.albedo_texture = block_texture()
		m.uv1_triplanar = true
		m.uv1_world_triplanar = true
		m.uv1_scale = Vector3.ONE * 0.5
		m.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST_WITH_MIPMAPS
		_mats[c] = m
	return _mats[c]


static func build(map: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	for b: Dictionary in map.boxes:
		var shape := BoxShape3D.new()
		shape.size = b.s
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = b.t
		body.add_child(col)
		var mesh := BoxMesh.new()
		mesh.size = b.s
		mesh.material = material(b.c)
		var mi := MeshInstance3D.new()
		mi.mesh = mesh
		mi.transform = b.t
		body.add_child(mi)
	return body


# ---------- building helpers ----------

# Box with its bottom centre at (x, y, z).
static func _box(l: Array, x: float, y: float, z: float, sx: float, sy: float, sz: float, c: Color) -> void:
	l.append({"t": Transform3D(Basis(), Vector3(x, y + sy * 0.5, z)), "s": Vector3(sx, sy, sz), "c": c})


# Box plus its twin rotated 180 degrees around the map centre (keeps maps fair).
static func _sym(l: Array, x: float, y: float, z: float, sx: float, sy: float, sz: float, c: Color) -> void:
	_box(l, x, y, z, sx, sy, sz, c)
	if x != 0.0 or z != 0.0:
		_box(l, -x, y, -z, sx, sy, sz, c)


# Sloped slab whose top surface runs from `from` to `to`.
static func _ramp(l: Array, from: Vector3, to: Vector3, width: float, c: Color) -> void:
	var z := (to - from).normalized()
	var x := Vector3.UP.cross(z).normalized()
	var y := z.cross(x)
	l.append({"t": Transform3D(Basis(x, y, z), (from + to) * 0.5 - y * 0.2), "s": Vector3(width, 0.4, from.distance_to(to)), "c": c})


static func _sym_ramp(l: Array, from: Vector3, to: Vector3, width: float, c: Color) -> void:
	_ramp(l, from, to, width, c)
	_ramp(l, from * Vector3(-1, 1, -1), to * Vector3(-1, 1, -1), width, c)


static func _tree(l: Array, x: float, z: float) -> void:
	_sym(l, x, 0, z, 1, 4, 1, WOOD)
	_sym(l, x, 4, z, 3, 2, 3, LEAF)


# Ground, outer walls and the two team bases.
static func _arena(l: Array, hx: float, hz: float, ground: Color, wall: Color) -> void:
	_box(l, 0, -1, 0, hx * 2, 1, hz * 2, ground)
	_sym(l, hx + 0.5, 0, 0, 1, 10, hz * 2 + 2, wall)
	_sym(l, 0, 0, hz + 0.5, hx * 2, 10, 1, wall)
	for team in 2:
		var s := -1.0 if team == 0 else 1.0
		var c: Color = RED if team == 0 else BLUE
		_box(l, 0, -0.98, s * (hz - 5), 16, 1, 9, c)
		_box(l, 0, 0, s * (hz - 0.25), 16, 4, 0.5, c)
		_box(l, -5.5, 0, s * (hz - 11), 5, 2.5, 1, c.darkened(0.25))
		_box(l, 5.5, 0, s * (hz - 11), 5, 2.5, 1, c.darkened(0.25))


static func _field(l: Array) -> void:
	_arena(l, 30, 40, GRASS, STONE.darkened(0.2))
	_sym(l, 0, 0, 0, 6, 3, 6, STONE)
	_sym(l, -9, 0, 0, 4, 1.2, 1, STONE)
	_sym(l, 8, 0, 7, 2, 2, 2, WOOD)
	_sym(l, -12, 0, 9, 2, 2, 2, WOOD)
	_sym(l, 18, 0, 4, 1, 2.5, 7, STONE)
	_sym(l, -22, 0, 14, 3, 4, 3, STONE)
	_sym(l, 3, 0, 15, 7, 1.2, 1, STONE)
	_sym(l, 14, 0, 18, 2, 2, 2, WOOD)
	_sym(l, 16, 0, 18, 2, 2, 2, WOOD)
	_sym(l, 15, 2, 18, 2, 2, 2, WOOD)
	_sym(l, -7, 0, 21, 1, 2.5, 6, STONE)
	_sym(l, -18, 0, 24, 2, 2, 2, WOOD)
	_sym(l, 9, 0, 24, 4, 1.2, 1, STONE)
	_tree(l, 25, 10)
	_tree(l, -26, 2)
	_tree(l, 22, 26)
	_tree(l, -14, 17)


# Narrow streets between a 4x4 grid of tall buildings: long sightlines, tight corners.
static func _city(l: Array) -> void:
	_arena(l, 30, 40, ASPHALT, BRICK.darkened(0.35))
	var cols := [BRICK, CONCRETE, TAN, STONE]
	var i := 0
	for z: float in [6.5, 19.5]:
		for x: float in [-22.5, -7.5, 7.5, 22.5]:
			var c: Color = cols[i % 4]
			_sym(l, x, 0, z, 11, 5.0 + (i * 3) % 5, 9, c)
			i += 1
	_sym(l, 0, 0, 0, 2, 1.5, 2, STONE)
	_sym(l, 1.2, 0, 13, 1.5, 1.5, 1.5, WOOD)
	_sym(l, -15.8, 0, 13, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 14.2, 0, 0.8, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 15.8, 0, 13, 1.5, 3, 1.5, WOOD)
	_sym(l, -8, 0, 26, 3, 1.2, 1, CONCRETE)
	_sym(l, 9, 0, 26.5, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 29, 0, 6.5, 1.5, 1.5, 1.5, WOOD)
	_sym(l, -0.9, 0, 6, 1.5, 1.5, 1.5, WOOD)


# Multi-level: raised central and side platforms joined by bridges, reached by ramps.
static func _platforms(l: Array) -> void:
	_arena(l, 30, 40, SAND, STONE.darkened(0.25))
	# Central platform (top at y=4) on four pillars, open underneath.
	_box(l, 0, 3.5, 0, 14, 0.5, 14, CONCRETE)
	_sym(l, 6, 0, 6, 1.5, 3.5, 1.5, STONE)
	_sym(l, -6, 0, 6, 1.5, 3.5, 1.5, STONE)
	_box(l, 0, 4, 0, 4, 2, 4, STONE)
	_sym_ramp(l, Vector3(0, 0, 17), Vector3(0, 4, 7), 4, TAN)
	# Side platforms with a ramp at each end and a railing on the outside.
	_sym(l, 19, 3.5, 0, 10, 0.5, 18, CONCRETE)
	_sym(l, 15, 0, 8, 1.5, 3.5, 1.5, STONE)
	_sym(l, 23, 0, 8, 1.5, 3.5, 1.5, STONE)
	_sym(l, 15, 0, -8, 1.5, 3.5, 1.5, STONE)
	_sym(l, 23, 0, -8, 1.5, 3.5, 1.5, STONE)
	_sym(l, 23.75, 4, 0, 0.5, 1, 10, STONE)
	_sym_ramp(l, Vector3(19, 0, 21), Vector3(19, 4, 9), 4, TAN)
	_sym_ramp(l, Vector3(19, 0, -21), Vector3(19, 4, -9), 4, TAN)
	# Bridges between centre and sides.
	_sym(l, 10.5, 3.6, 0, 7, 0.4, 3, WOOD)
	# Cover on the platforms and on the ground.
	_sym(l, 17, 4, 4, 2, 1.2, 2, WOOD)
	_sym(l, 5, 4, -5.5, 3, 1.2, 1, STONE)
	_sym(l, 9, 0, 13, 2, 2, 2, WOOD)
	_sym(l, -10, 0, 22, 2, 2, 2, WOOD)
	_sym(l, -9, 0, 12, 1, 2.5, 5, STONE)
	_sym(l, 26, 0, 24, 2, 2, 2, WOOD)
	_sym(l, 5, 0, 25, 5, 1.2, 1, STONE)
	_sym(l, 11, 0, 3, 2, 2, 2, WOOD)
