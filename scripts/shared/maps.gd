extends RefCounted
# Map definitions as plain data (lists of boxes), shared by client and server.
# The client builds meshes + colliders from the boxes; the server only uses the
# solid box list for its own ray tests, so it never needs a physics world per room.
# "Decor" boxes are visual only (no collision, ignored by the server).
# Team 0 (red) has its base at -Z, team 1 (blue) at +Z.

const NAMES := ["Open Field", "City Streets", "Sky Platforms"]
const COUNT := 3

const RED := Color(0.85, 0.2, 0.2)
const BLUE := Color(0.2, 0.4, 0.95)
const STONE := Color(0.55, 0.55, 0.58)
const WOOD := Color(0.6, 0.42, 0.24)
const GRASS := Color(0.36, 0.62, 0.3)
const LEAF := Color(0.2, 0.5, 0.2)
const DIRT := Color(0.5, 0.38, 0.25)
const BRICK := Color(0.62, 0.3, 0.25)
const CONCRETE := Color(0.72, 0.72, 0.74)
const TAN := Color(0.78, 0.68, 0.5)
const ASPHALT := Color(0.3, 0.3, 0.33)
const SAND := Color(0.82, 0.74, 0.52)
const GLASS := Color(0.25, 0.45, 0.65)
const WATER := Color(0.25, 0.5, 0.9)
const WHITE := Color(0.95, 0.95, 0.97)
const LAMP := Color(1.0, 0.9, 0.5)

static var _cache := {}
static var _mats := {}
static var _tex: ImageTexture


static func get_map(id: int) -> Dictionary:
	if not _cache.has(id):
		var l := []
		var size: Vector2
		match id:
			1:
				size = _city(l)
			2:
				size = _platforms(l)
			_:
				size = _field(l)
		_clouds(l, size)
		var solid := []
		var decor := []
		for b: Dictionary in l:
			if b.has("d"):
				decor.append(b)
			else:
				b.inv = (b.t as Transform3D).affine_inverse()
				b.aabb = AABB(-b.s * 0.5, b.s)
				b.waabb = (b.t as Transform3D) * (b.aabb as AABB)
				solid.append(b)
		_cache[id] = {"id": id, "boxes": solid, "decor": decor, "hx": size.x, "hz": size.y}
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
		# Cheap world-space bounds test first; most boxes are rejected here.
		if not (b.waabb as AABB).intersects_segment(from, to):
			continue
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


# Sky, sun and the map itself, added under `parent`.
static func build_scene(parent: Node, map: Dictionary) -> void:
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color(0.3, 0.55, 0.95)
	sky_mat.sky_horizon_color = Color(0.75, 0.87, 1.0)
	sky_mat.ground_horizon_color = Color(0.75, 0.87, 1.0)
	sky_mat.ground_bottom_color = Color(0.4, 0.5, 0.6)
	var sky := Sky.new()
	sky.sky_material = sky_mat
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color.WHITE
	env.ambient_light_energy = 0.5
	var we := WorldEnvironment.new()
	we.environment = env
	parent.add_child(we)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-50, 35, 0)
	sun.light_energy = 0.7
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS   # 2 shadow passes instead of 4
	sun.directional_shadow_max_distance = 70.0
	parent.add_child(sun)
	parent.add_child(build(map))


# One collider per solid box; meshes are batched into one MultiMesh per color.
static func build(map: Dictionary) -> StaticBody3D:
	var body := StaticBody3D.new()
	for b: Dictionary in map.boxes:
		var shape := BoxShape3D.new()
		shape.size = b.s
		var col := CollisionShape3D.new()
		col.shape = shape
		col.transform = b.t
		body.add_child(col)
	_batch(body, map.boxes, true)
	_batch(body, map.decor, false)
	return body


static func _batch(parent: Node, boxes: Array, shadows: bool) -> void:
	var groups := {}
	for b: Dictionary in boxes:
		if not groups.has(b.c):
			groups[b.c] = []
		groups[b.c].append(b)
	for c: Color in groups:
		var list: Array = groups[c]
		var mesh := BoxMesh.new()
		mesh.material = material(c)
		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		mm.mesh = mesh
		mm.instance_count = list.size()
		for i in list.size():
			var t: Transform3D = list[i].t
			mm.set_instance_transform(i, Transform3D(t.basis * Basis.from_scale(list[i].s), t.origin))
		var mi := MultiMeshInstance3D.new()
		mi.multimesh = mm
		if not shadows:
			mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mi)


# ---------- building helpers ----------

# Box with its bottom centre at (x, y, z).
static func _box(l: Array, x: float, y: float, z: float, sx: float, sy: float, sz: float, c: Color) -> void:
	l.append({"t": Transform3D(Basis(), Vector3(x, y + sy * 0.5, z)), "s": Vector3(sx, sy, sz), "c": c})


# Box plus its twin rotated 180 degrees around the map centre (keeps maps fair).
static func _sym(l: Array, x: float, y: float, z: float, sx: float, sy: float, sz: float, c: Color) -> void:
	_box(l, x, y, z, sx, sy, sz, c)
	if x != 0.0 or z != 0.0:
		_box(l, -x, y, -z, sx, sy, sz, c)


# Visual-only box (and its twin).
static func _decor(l: Array, x: float, y: float, z: float, sx: float, sy: float, sz: float, c: Color) -> void:
	_sym(l, x, y, z, sx, sy, sz, c)
	l[-1].d = true
	if x != 0.0 or z != 0.0:
		l[-2].d = true


# Sloped slab whose top surface runs from `from` to `to` (and its twin).
static func _ramp(l: Array, from: Vector3, to: Vector3, width: float, c: Color) -> void:
	for s: float in [1.0, -1.0]:
		var a := from * Vector3(s, 1, s)
		var b := to * Vector3(s, 1, s)
		var z := (b - a).normalized()
		var x := Vector3.UP.cross(z).normalized()
		var y := z.cross(x)
		l.append({"t": Transform3D(Basis(x, y, z), (a + b) * 0.5 - y * 0.2), "s": Vector3(width, 0.4, a.distance_to(b)), "c": c})


static func _tree(l: Array, x: float, z: float, h := 4.0) -> void:
	_sym(l, x, 0, z, 1, h, 1, WOOD)
	_sym(l, x, h, z, 3, 2, 3, LEAF)
	_decor(l, x, h + 2, z, 1.6, 0.8, 1.6, LEAF.lightened(0.12))


# Hollow hut with a doorway on both Z sides and a flat roof.
static func _house(l: Array, x: float, z: float, w: float, d: float, h: float, c: Color) -> void:
	for s: float in [-1.0, 1.0]:
		_sym(l, x + s * (w * 0.5 - 0.25), 0, z, 0.5, h, d, c)
		_sym(l, x - (w * 0.25 + 0.5), 0, z + s * (d * 0.5 - 0.25), w * 0.5 - 1.0, h, 0.5, c)
		_sym(l, x + (w * 0.25 + 0.5), 0, z + s * (d * 0.5 - 0.25), w * 0.5 - 1.0, h, 0.5, c)
	_sym(l, x, h, z, w + 0.6, 0.4, d + 0.6, c.darkened(0.25))


# Raised lookout (top at y=4) with a ramp coming up from the -Z side... of the first copy.
static func _tower(l: Array, x: float, z: float, ramp_dir: float) -> void:
	_sym(l, x, 3.6, z, 5, 0.4, 5, WOOD)
	for sx: float in [-2.0, 2.0]:
		for sz: float in [-2.0, 2.0]:
			_sym(l, x + sx, 0, z + sz, 0.6, 3.6, 0.6, WOOD.darkened(0.3))
	_sym(l, x, 4, z + ramp_dir * -2.3, 5, 0.9, 0.4, WOOD.darkened(0.15))
	_sym(l, x - 2.3, 4, z, 0.4, 0.9, 5, WOOD.darkened(0.15))
	_sym(l, x + 2.3, 4, z, 0.4, 0.9, 5, WOOD.darkened(0.15))
	_ramp(l, Vector3(x, 0, z + ramp_dir * 12.0), Vector3(x, 4, z + ramp_dir * 2.5), 2.4, WOOD)


static func _car(l: Array, x: float, z: float, along_z: bool, c: Color) -> void:
	var sx := 2.0 if along_z else 4.2
	var sz := 4.2 if along_z else 2.0
	_sym(l, x, 0.25, z, sx, 0.8, sz, c)
	_sym(l, x, 1.05, z, sx * (0.9 if along_z else 0.5), 0.7, sz * (0.5 if along_z else 0.9), GLASS)
	_decor(l, x, 0, z, sx * 0.95 + (0.2 if along_z else -1.4), 0.5, sz * 0.95 + (-1.4 if along_z else 0.2), Color(0.1, 0.1, 0.1))


# Rows of windows on all four faces of a building.
static func _windows(l: Array, x: float, z: float, w: float, h: float, d: float) -> void:
	var y := 1.6
	while y < h - 1.5:
		var i := -w * 0.5 + 1.6
		while i < w * 0.5 - 1.0:
			_decor(l, x + i, y, z + d * 0.5, 1.2, 1.3, 0.12, GLASS)
			_decor(l, x + i, y, z - d * 0.5, 1.2, 1.3, 0.12, GLASS)
			i += 2.6
		i = -d * 0.5 + 1.6
		while i < d * 0.5 - 1.0:
			_decor(l, x + w * 0.5, y, z + i, 0.12, 1.3, 1.2, GLASS)
			_decor(l, x - w * 0.5, y, z + i, 0.12, 1.3, 1.2, GLASS)
			i += 2.6
		y += 3.0


static func _clouds(l: Array, size: Vector2) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 11
	for i in 9:
		var x := rng.randf_range(-size.x - 30, size.x + 30)
		var z := rng.randf_range(0, size.y + 40)
		var w := rng.randf_range(10, 20)
		_decor(l, x, rng.randf_range(42, 58), z, w, 2.5, w * 0.6, WHITE)
		_decor(l, x + 3, l[-1].t.origin.y + 1.0, z + 1, w * 0.5, 2.0, w * 0.4, WHITE)


# Ground, outer walls and the two team bases.
static func _arena(l: Array, hx: float, hz: float, ground: Color, wall: Color) -> void:
	_box(l, 0, -1, 0, hx * 2, 1, hz * 2, ground)
	_sym(l, hx + 0.5, 0, 0, 1, 12, hz * 2 + 2, wall)
	_sym(l, 0, 0, hz + 0.5, hx * 2, 12, 1, wall)
	for team in 2:
		var s := -1.0 if team == 0 else 1.0
		var c: Color = RED if team == 0 else BLUE
		_box(l, 0, -0.98, s * (hz - 6.5), 20, 1, 11, c)
		_box(l, 0, 0, s * (hz - 0.25), 20, 5, 0.5, c)
		_box(l, -7, 0, s * (hz - 13), 6, 2.5, 1, c.darkened(0.25))
		_box(l, 7, 0, s * (hz - 13), 6, 2.5, 1, c.darkened(0.25))
		_box(l, 0, 0, s * (hz - 15.5), 4, 1.2, 1, c.darkened(0.25))
		for fx: float in [-11.0, 11.0]:
			_box(l, fx, 0, s * (hz - 1.5), 0.3, 8, 0.3, WHITE)
			l.append({"t": Transform3D(Basis(), Vector3(fx - s * 1.4, 7.0, s * (hz - 1.5))), "s": Vector3(2.5, 1.6, 0.1), "c": c, "d": true})


# ---------- the maps ----------

# Open grassland with a central hill, huts, lookout towers, trees and scattered cover.
static func _field(l: Array) -> Vector2:
	_arena(l, 40, 55, GRASS, STONE.darkened(0.2))
	# Stepped hill with a stone gazebo on top.
	_box(l, 0, 0, 0, 18, 1, 18, GRASS.darkened(0.1))
	_box(l, 0, 1, 0, 12, 1, 12, GRASS.darkened(0.2))
	_box(l, 0, 2, 0, 6, 1, 6, STONE)
	for sx: float in [-2.5, 2.5]:
		for sz: float in [-2.5, 2.5]:
			_box(l, sx, 3, sz, 1, 2.5, 1, STONE.lightened(0.1))
	_box(l, 0, 5.5, 0, 6.6, 0.5, 6.6, STONE.darkened(0.15))
	_decor(l, 0, 0, 28, 4, 0.03, 34, DIRT)
	# Huts on the flanks, lookout towers near each base.
	_house(l, 26, 12, 9, 7, 3, STONE)
	_house(l, -27, 20, 8, 6, 3, WOOD.lightened(0.1))
	_tower(l, -24, 40, -1.0)
	# Cover: crates, low walls, rocks, fences.
	_sym(l, -14, 0, 4, 4, 1.2, 1, STONE)
	_sym(l, 14, 0, 4, 1, 1.2, 4, STONE)
	_sym(l, 5, 0, 14, 2, 2, 2, WOOD)
	_sym(l, 7, 0, 14, 2, 2, 2, WOOD)
	_sym(l, 6, 2, 14, 2, 2, 2, WOOD)
	_sym(l, -5, 0, 20, 7, 1.2, 1, STONE)
	_sym(l, 16, 0, 22, 1, 2.5, 7, STONE)
	_sym(l, -19, 0, 10, 3, 2, 3, STONE.darkened(0.1))
	_sym(l, -18, 0, 30, 2, 2, 2, WOOD)
	_sym(l, 9, 0, 30, 5, 1.2, 1, STONE)
	_sym(l, 30, 0, 28, 3, 1.6, 3, STONE.darkened(0.1))
	_sym(l, 22, 0, 34, 6, 1.1, 0.3, WOOD)
	_sym(l, -8, 0, 36, 2, 2, 2, WOOD)
	_sym(l, 2, 0, 36, 2, 2, 2, WOOD)
	_sym(l, 34, 0, 2, 2, 2, 2, WOOD)
	_sym(l, 12, 0, 42, 0.3, 1.1, 6, WOOD)
	for p: Vector2 in [Vector2(33, 9), Vector2(36, 20), Vector2(30, 40), Vector2(-35, 6), Vector2(-33, 30), Vector2(-36, 46), Vector2(20, 46), Vector2(-12, 27), Vector2(24, 24)]:
		_tree(l, p.x, p.y, 3.5 + fmod(absf(p.x), 2.0))
	for p: Vector2 in [Vector2(11, 9), Vector2(-7, 12), Vector2(20, 16), Vector2(-24, 32), Vector2(28, 44), Vector2(-3, 44)]:
		_sym(l, p.x, 0, p.y, 1.8, 1.1, 1.8, LEAF.lightened(0.08))
	return Vector2(40, 55)


# Narrow streets between tall buildings, a central plaza, parked cars, two climbable roofs.
static func _city(l: Array) -> Vector2:
	_arena(l, 40, 55, ASPHALT, BRICK.darkened(0.35))
	var cols := [BRICK, CONCRETE, TAN, STONE, BRICK.lightened(0.15)]
	var i := 0
	for z: float in [7.5, 21.0, 34.5]:
		for x: float in [-31.0, -15.5, 0.0, 15.5, 31.0]:
			i += 1
			if z == 7.5 and x == 0.0:
				continue   # plaza
			var low := z == 21.0 and x == -15.5
			var h := 3.5 if low else 6.0 + (i * 5) % 7
			var c: Color = cols[i % 5]
			_sym(l, x, 0, z, 11, h, 9, c)
			_sym(l, x, h, z, 11.4, 0.3, 9.4, c.darkened(0.3))
			_windows(l, x, z, 11, h, 9)
	# Ramp up to the low roof (and its twin), with cover on top.
	_ramp(l, Vector3(-9, 0, 16.5), Vector3(-9, 3.8, 25.2), 2, CONCRETE.darkened(0.2))
	_sym(l, -15.5, 3.8, 18, 6, 1.1, 0.5, CONCRETE)
	_sym(l, -19, 3.8, 23, 2, 1.5, 2, WOOD)
	# Plaza with a fountain.
	_box(l, 0, 0, 0, 6, 0.6, 6, STONE)
	_box(l, 0, 0.6, 0, 1.2, 2.6, 1.2, STONE.lightened(0.1))
	_decor(l, 0, 0.6, 0, 5, 0.12, 5, WATER)
	_sym(l, 4.5, 0, 8, 1, 1, 4, CONCRETE)
	_sym(l, -4.5, 0, 8, 1, 1, 4, CONCRETE)
	# Cars, crates, lamps, road markings.
	_car(l, 9, 1.6, false, RED.darkened(0.2))
	_car(l, -23.3, 8, true, BLUE.darkened(0.1))
	_car(l, 22, 14.2, false, Color(0.9, 0.8, 0.2))
	_car(l, -7.6, 33, true, WHITE)
	_car(l, 30, 27.6, false, Color(0.2, 0.6, 0.3))
	_sym(l, 7.2, 0, 21, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 23.3, 0, 27, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 23.3, 1.5, 27, 1.5, 1.5, 1.5, WOOD)
	_sym(l, -38.5, 0, 14, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 38.5, 0, 30, 1.5, 3, 1.5, WOOD)
	_sym(l, -12, 0, 40.5, 4, 1.2, 1, CONCRETE)
	_sym(l, 14, 0, 40.5, 1.5, 1.5, 1.5, WOOD)
	_sym(l, 0, 0, 27.6, 3, 1.2, 1, CONCRETE)
	for x: float in [-23.3, -7.8, 7.8, 23.3]:
		_sym(l, x + 1.6, 0, 14.2, 0.25, 4.5, 0.25, Color(0.15, 0.15, 0.17))
		_decor(l, x + 1.6, 4.5, 14.2, 0.9, 0.3, 0.9, LAMP)
	var mx := -36.0
	while mx <= 36.0:
		if absf(mx) > 5.0:
			_decor(l, mx, 0, 0, 2.2, 0.03, 0.3, WHITE)
		mx += 6.0
	return Vector2(40, 55)


# Multi-level: raised central and side platforms joined by bridges, ramps and block stairs.
static func _platforms(l: Array) -> Vector2:
	_arena(l, 38, 52, SAND, STONE.darkened(0.25))
	# Central platform (top at y=4) on pillars, open underneath, with a cover block on top.
	_box(l, 0, 3.5, 0, 16, 0.5, 16, CONCRETE)
	for sx: float in [-7.0, 7.0]:
		for sz: float in [-7.0, 7.0]:
			_box(l, sx, 0, sz, 1.5, 3.5, 1.5, STONE)
	_box(l, 0, 4, 0, 5, 2.5, 5, STONE)
	_box(l, 0, 6.5, 0, 6, 0.4, 6, STONE.darkened(0.2))
	_ramp(l, Vector3(0, 0, 19), Vector3(0, 4, 8), 4, TAN)
	_sym(l, 5.5, 4, -6, 3, 1.2, 1, STONE)
	_sym(l, -6, 4, 4, 1.6, 1.4, 1.6, WOOD)
	# Side platforms with a ramp at each end, a railing outside and block stairs.
	_sym(l, 25, 3.5, 0, 10, 0.5, 22, CONCRETE)
	for sx: float in [21.0, 29.0]:
		for sz: float in [-10.0, 0.0, 10.0]:
			_sym(l, sx, 0, sz, 1.5, 3.5, 1.5, STONE)
	_sym(l, 29.75, 4, 0, 0.5, 1, 14, STONE)
	_ramp(l, Vector3(25, 0, 23), Vector3(25, 4, 11), 4, TAN)
	_ramp(l, Vector3(25, 0, -23), Vector3(25, 4, -11), 4, TAN)
	_sym(l, 19, 0, 8, 2, 1, 2, WOOD)
	_sym(l, 19, 0, 6, 2, 2, 2, WOOD)
	_sym(l, 19, 0, 4, 2, 3, 2, WOOD)
	_sym(l, 23, 4, 5, 2, 1.2, 2, WOOD)
	_sym(l, 27, 4, -6, 1, 1.4, 4, STONE)
	# Bridges between centre and sides.
	_sym(l, 14, 3.6, 0, 12, 0.4, 3, WOOD)
	_sym(l, 14, 4, 1.4, 12, 0.5, 0.2, WOOD.darkened(0.3))
	_sym(l, 14, 4, -1.4, 12, 0.5, 0.2, WOOD.darkened(0.3))
	# Sniper perch near each base.
	_tower(l, -15, 36, -1.0)
	# Ground cover.
	_sym(l, 10, 0, 14, 2, 2, 2, WOOD)
	_sym(l, -11, 0, 24, 2, 2, 2, WOOD)
	_sym(l, -11, 2, 24, 2, 2, 2, WOOD)
	_sym(l, -10, 0, 13, 1, 2.5, 5, STONE)
	_sym(l, 33, 0, 28, 2, 2, 2, WOOD)
	_sym(l, 6, 0, 28, 6, 1.2, 1, STONE)
	_sym(l, 13, 0, 4, 2, 2, 2, WOOD)
	_sym(l, -34, 0, 16, 3, 3, 3, STONE)
	_sym(l, 16, 0, 33, 1, 2.5, 6, STONE)
	_sym(l, -4, 0, 36, 2, 2, 2, WOOD)
	_sym(l, 34, 0, 40, 1.5, 6, 1.5, STONE)
	_sym(l, -30, 0, 34, 5, 1.2, 1, STONE)
	return Vector2(38, 52)
