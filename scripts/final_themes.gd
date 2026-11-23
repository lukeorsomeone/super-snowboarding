extends RefCounted
## The last three levels' worlds: the shopping mall, the volcano and the moon.
## course.gd asks this for the ground beside the track, the props and anything animated.

const MeshUtil := preload("res://scripts/mesh_util.gd")

const MALL_WALL := 6.0          # shop fronts stand this far past the fence
const MALL_BAY := 12.0          # one shop front
const MALL_FLOOR_H := 5.2
const MALL_SHOPS := ["BAO & CO", "SOCK WORLD", "PRETZEL PALACE", "BOARD BARN", "FOOD COURT",
	"VIDEO VAULT", "CANDLE HUT", "MEGA TOYS", "PET PALACE", "GAME CAVE", "JUICE BOX", "SHOE TOWN",
	"TOTALLY TEES", "CHINCHILLA CHIC", "BARNEY'S BONES", "50% OFF"]
const LAVA_DEPTH := 4.5         # lava sits this far below the track edge
const LAVA_NEAR := 7.0
const LAVA_FAR := 34.0

var c   # the course
var theme := ""

var _bays: Array[Mesh] = []
var _roof: Mesh
var _escalator: Mesh
var _blade: Mesh
var _spires: Mesh
var _lava_mat: ShaderMaterial
var _rocks: Mesh
var _dome: Mesh
var _lander: Mesh
var _dish: Mesh
var _flag: Mesh
var _backdrop: Node3D
var _embers: CPUParticles3D
var _bombs: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()


func _init(course, theme_name: String) -> void:
	c = course
	theme = theme_name
	_rng.seed = 90210


func _glow(col: Color, phase: float) -> Color:
	return Color(col.r, col.g, col.b, clampf(phase, 0.02, 0.9))


## An unlit vertex-colour material that fog can't reach, for things on the horizon.
func _sky_mat() -> StandardMaterial3D:
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.vertex_color_use_as_albedo = true
	m.disable_fog = true
	return m


# ---------------------------------------------------------------- ground beside the track

## Height added past the fence, once the course has removed its valley bowl.
func edge_height(e: float, x: float, z: float) -> float:
	match theme:
		"mall":
			return 0.15
		"volcano":
			var h := e * 0.1 if e < 4.0 else 0.4 - minf(e - 4.0, 4.0) * 1.7
			if e > LAVA_FAR:
				h += (e - LAVA_FAR) * 1.15 + c._mtn_noise.get_noise_2d(x, z) * minf(e - LAVA_FAR, 40.0) * 0.8
			return h
		"moon":
			var h: float = e * 0.05 + c._mtn_noise.get_noise_2d(x, z) * minf(e, 40.0) * 0.3
			if e > 62.0:
				h += (e - 62.0) * 0.38
			return h + _crater(x, z) * smoothstep(1.0, 10.0, e)
	return 0.0


## A crater in each 64 m grid cell. Worked out from the cell so it's the same every run.
func _crater(x: float, z: float) -> float:
	var cx := int(floor(x / 64.0))
	var cz := int(floor(z / 64.0))
	var s := (cx * 73856093) ^ (cz * 19349663)
	if s & 3 == 0:
		return 0.0
	var r := 7.0 + float((s >> 3) & 11)
	var ox := 26.0 + float((s >> 8) & 11)
	var oz := 26.0 + float((s >> 13) & 11)
	var t := Vector2(x - (cx * 64.0 + ox), z - (cz * 64.0 + oz)).length() / r
	if t >= 1.4:
		return 0.0
	var rim := r * 0.1
	if t < 1.0:
		return rim * t * t - r * 0.28 * (1.0 - t * t)
	var f := 1.0 - (t - 1.0) / 0.4
	return rim * f * f


# ---------------------------------------------------------------- shared meshes

func build_meshes() -> void:
	match theme:
		"mall":
			_build_mall()
		"volcano":
			_build_volcano()
		"moon":
			_build_moon()


func _build_mall() -> void:
	var prop := ShaderMaterial.new()
	prop.shader = load("res://shaders/ps1_city.gdshader")
	c._prop_mat = prop
	var cream := Color(0.88, 0.83, 0.72)
	var trim := Color(0.56, 0.5, 0.46)
	var glass := Color(0.62, 0.86, 0.95)
	var brands := [Color(0.95, 0.2, 0.3), Color(0.15, 0.55, 0.95), Color(1.0, 0.72, 0.1),
		Color(0.2, 0.78, 0.45), Color(0.8, 0.3, 0.9), Color(1.0, 0.45, 0.65)]
	var rooms := [Color(1.0, 0.9, 0.66), Color(0.86, 0.95, 1.0), Color(1.0, 0.78, 0.82)]
	for v in 6:
		var parts := [
			[MeshUtil.box(Vector3(12.1, 17.0, 0.6)), MeshUtil.at(Vector3(0, 8.5, -0.7)), cream],
			[MeshUtil.box(Vector3(0.6, 17.0, 0.7)), MeshUtil.at(Vector3(-6.0, 8.5, -0.1)), trim],
		]
		for f in 3:
			var y := f * MALL_FLOOR_H
			var brand: Color = brands[(v + f * 2) % brands.size()]
			parts.append([MeshUtil.box(Vector3(10.4, 3.5, 0.1)), MeshUtil.at(Vector3(0, y + 1.9, -0.35)),
				rooms[(v + f) % rooms.size()]])
			# things on show in the window
			for k in 4:
				var kx := -3.9 + k * 2.6
				var tall := 0.7 + float((v * 3 + k * 5 + f) % 4) * 0.35
				parts.append([MeshUtil.box(Vector3(1.3, tall, 0.1)), MeshUtil.at(Vector3(kx, y + 0.5 + tall * 0.5, -0.29)),
					brands[(v + k + f) % brands.size()].darkened(0.1)])
			for k in 3:
				parts.append([MeshUtil.box(Vector3(0.12, 3.6, 0.14)), MeshUtil.at(Vector3(-2.6 + k * 2.6, y + 1.9, -0.25)), trim])
			parts.append([MeshUtil.box(Vector3(11.4, 0.8, 0.26)), MeshUtil.at(Vector3(0, y + 4.1, -0.2)), brand])
			parts.append([MeshUtil.box(Vector3(11.0, 0.12, 0.3)), MeshUtil.at(Vector3(0, y + 3.72, -0.18)), _glow(Color(1, 0.96, 0.8), 0.3 + v * 0.1)])
			if f < 2:
				parts.append([MeshUtil.box(Vector3(12.1, 0.34, 2.4)), MeshUtil.at(Vector3(0, y + 5.0, 0.8)), cream.darkened(0.12)])
				parts.append([MeshUtil.box(Vector3(12.1, 0.9, 0.07)), MeshUtil.at(Vector3(0, y + 5.62, 1.98)), glass])
				parts.append([MeshUtil.box(Vector3(12.1, 0.1, 0.14)), MeshUtil.at(Vector3(0, y + 6.1, 1.98)), trim])
		_bays.append(MeshUtil.merge_parts(parts))

	# Glass roof, one piece per shop front, spanning the whole hall.
	var span: float = (c.HALF_WIDTH + MALL_WALL + 1.0) * 2.0
	_roof = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(span, 0.4, 14.2)), MeshUtil.at(Vector3(0, 17.0, 0)), Color(0.8, 0.76, 0.68)],
		[MeshUtil.box(Vector3(span * 0.62, 0.1, 10.5)), MeshUtil.at(Vector3(0, 16.76, 0)), Color(0.72, 0.92, 1.0)],
		[MeshUtil.box(Vector3(span, 0.7, 0.7)), MeshUtil.at(Vector3(0, 16.5, 6.0)), Color(0.46, 0.42, 0.42)],
		[MeshUtil.box(Vector3(0.3, 0.3, 14.2)), MeshUtil.at(Vector3(0, 16.68, 0)), Color(0.46, 0.42, 0.42)],
		[MeshUtil.box(Vector3(span * 0.6, 0.12, 0.4)), MeshUtil.at(Vector3(0, 16.1, 0)), _glow(Color(1, 1, 0.9), 0.5)],
	])

	var steel := Color(0.62, 0.65, 0.7)
	var dark := Color(0.15, 0.15, 0.18)
	var run := 10.4
	var tilt := Basis(Vector3.FORWARD, -atan2(MALL_FLOOR_H, 9.0))
	var esc := []
	for z in [-0.8, 0.8]:
		esc.append([MeshUtil.box(Vector3(run, 0.95, 0.14)), Transform3D(tilt, Vector3(0, 2.95, z)), steel])
		esc.append([MeshUtil.box(Vector3(run, 0.12, 0.2)), Transform3D(tilt, Vector3(0, 3.45, z)), dark])
	esc.append([MeshUtil.box(Vector3(run, 0.3, 1.5)), Transform3D(tilt, Vector3(0, 2.5, 0)), dark])
	for i in 13:
		var t := (i + 0.5) / 13.0 - 0.5
		esc.append([MeshUtil.box(Vector3(0.28, 0.08, 1.45)), Transform3D(tilt, Vector3(t * 9.0, 2.68 + t * MALL_FLOOR_H, 0)), steel])
	_escalator = MeshUtil.merge_parts(esc)

	_blade = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(0.12, 3.6, 0.12)), MeshUtil.at(Vector3(-3.0, 8.4, 0)), steel],
		[MeshUtil.box(Vector3(0.12, 3.6, 0.12)), MeshUtil.at(Vector3(3.0, 8.4, 0)), steel],
		[MeshUtil.box(Vector3(8.0, 2.1, 0.18)), MeshUtil.at(Vector3(0, 6.2, 0)), Color(0.08, 0.1, 0.24)],
		[MeshUtil.box(Vector3(8.2, 0.12, 0.24)), MeshUtil.at(Vector3(0, 7.28, 0)), _glow(Color(1, 0.86, 0.3), 0.4)],
		[MeshUtil.box(Vector3(8.2, 0.12, 0.24)), MeshUtil.at(Vector3(0, 5.12, 0)), _glow(Color(1, 0.86, 0.3), 0.4)],
	])

	# Obstacle: a potted palm in a round planter (radius 1.4, about 5 m tall).
	var planter := [
		[MeshUtil.cylinder(1.35, 1.1, 1.1, 10), MeshUtil.at(Vector3(0, 0.55, 0)), Color(0.72, 0.5, 0.36)],
		[MeshUtil.cylinder(1.42, 1.42, 0.16, 10), MeshUtil.at(Vector3(0, 1.1, 0)), cream],
		[MeshUtil.cylinder(1.22, 1.22, 0.06, 10), MeshUtil.at(Vector3(0, 1.17, 0)), Color(0.26, 0.17, 0.12)],
	]
	planter.append_array(c._palm_parts(Vector3(0, 1.1, 0), 3.7, 0.3, 0.8))
	c._tree_mesh = MeshUtil.merge_parts(planter)

	# Obstacle: a runaway trolley piled up with shopping (radius 0.85, 2.4 m tall).
	var chrome := Color(0.76, 0.8, 0.86)
	var cart := [
		[MeshUtil.box(Vector3(1.05, 0.08, 1.45)), MeshUtil.at(Vector3(0, 0.45, 0)), chrome],
		[MeshUtil.box(Vector3(1.1, 0.62, 0.05)), MeshUtil.at(Vector3(0, 0.8, 0.74)), chrome],
		[MeshUtil.box(Vector3(1.1, 0.62, 0.05)), MeshUtil.at(Vector3(0, 0.8, -0.74)), chrome],
		[MeshUtil.box(Vector3(0.05, 0.62, 1.5)), MeshUtil.at(Vector3(-0.55, 0.8, 0)), chrome],
		[MeshUtil.box(Vector3(0.05, 0.62, 1.5)), MeshUtil.at(Vector3(0.55, 0.8, 0)), chrome],
		[MeshUtil.box(Vector3(1.15, 0.1, 0.1)), MeshUtil.at(Vector3(0, 1.3, 0.92)), Color(0.9, 0.12, 0.18)],
		[MeshUtil.box(Vector3(0.82, 0.62, 1.0)), MeshUtil.at(Vector3(-0.05, 1.05, 0)), Color(0.2, 0.55, 0.95)],
		[MeshUtil.box(Vector3(0.62, 0.48, 0.7)), MeshUtil.at(Vector3(0.05, 1.6, 0.05), Basis(Vector3.UP, 0.4)), Color(1.0, 0.75, 0.15)],
		[MeshUtil.box(Vector3(0.42, 0.34, 0.46)), MeshUtil.at(Vector3(-0.04, 2.01, 0), Basis(Vector3.UP, -0.3)), Color(0.92, 0.25, 0.55)],
		[MeshUtil.box(Vector3(0.1, 0.26, 0.1)), MeshUtil.at(Vector3(-0.04, 2.3, 0)), Color(0.3, 0.85, 0.45)],
	]
	for wx in [-0.48, 0.48]:
		for wz in [-0.62, 0.62]:
			cart.append([MeshUtil.box(Vector3(0.05, 0.42, 0.05)), MeshUtil.at(Vector3(wx, 0.24, wz)), chrome])
			cart.append([MeshUtil.sphere(0.1, 6), MeshUtil.at(Vector3(wx, 0.1, wz)), dark])
	c._snowman_mesh = MeshUtil.merge_parts(cart)


func _build_volcano() -> void:
	var prop := ShaderMaterial.new()
	prop.shader = load("res://shaders/ps1_city.gdshader")
	c._prop_mat = prop
	_lava_mat = ShaderMaterial.new()
	_lava_mat.shader = load("res://shaders/ps1_lava.gdshader")
	var rock := Color(0.15, 0.11, 0.12)
	var dark := Color(0.07, 0.055, 0.07)
	var hot := Color(1.0, 0.36, 0.05)
	var white := Color(1.0, 0.82, 0.3)

	# Obstacle: a jagged obsidian spire split by lava (radius 1.4, 5 m tall).
	c._tree_mesh = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.9, 1.45, 1.8, 6), MeshUtil.at(Vector3(0, 0.9, 0), Basis(Vector3.UP, 0.3)), rock],
		[MeshUtil.cylinder(0.32, 0.9, 2.3, 5), MeshUtil.at(Vector3(0.08, 2.9, 0), Basis(Vector3.FORWARD, -0.05)), dark],
		[MeshUtil.cylinder(0.0, 0.34, 1.1, 5), MeshUtil.at(Vector3(0.14, 4.55, 0)), rock],
		[MeshUtil.cylinder(0.0, 0.55, 1.9, 5), MeshUtil.at(Vector3(-0.85, 1.0, 0.35), Basis(Vector3.FORWARD, 0.18)), dark],
		[MeshUtil.cylinder(0.0, 0.42, 1.5, 5), MeshUtil.at(Vector3(0.82, 0.8, -0.45), Basis(Vector3.FORWARD, -0.2)), rock],
		[MeshUtil.box(Vector3(0.13, 3.1, 0.13)), MeshUtil.at(Vector3(0.26, 1.7, 0.86), Basis(Vector3.FORWARD, -0.12)), _glow(hot, 0.2)],
		[MeshUtil.box(Vector3(0.1, 2.3, 0.1)), MeshUtil.at(Vector3(-0.48, 1.3, 0.9), Basis(Vector3.FORWARD, 0.2)), _glow(white, 0.45)],
		[MeshUtil.cylinder(1.5, 1.5, 0.07, 8), MeshUtil.at(Vector3(0, 0.04, 0)), _glow(hot, 0.7)],
	])
	# Obstacle: a cooling lava boulder (radius 0.85).
	c._snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(1.02, 7), MeshUtil.at(Vector3(0, 0.82, 0), Basis.from_scale(Vector3(1.0, 0.88, 0.92))), _glow(hot, 0.3)],
		[MeshUtil.box(Vector3(1.32, 0.7, 1.1)), MeshUtil.at(Vector3(0.15, 1.15, 0.2), Basis(Vector3.UP, 0.5)), rock],
		[MeshUtil.box(Vector3(1.05, 0.72, 1.32)), MeshUtil.at(Vector3(-0.2, 0.5, 0.18), Basis(Vector3.RIGHT, 0.4)), dark],
		[MeshUtil.box(Vector3(0.9, 0.62, 1.0)), MeshUtil.at(Vector3(0.3, 0.42, -0.34), Basis(Vector3.UP, -0.6)), rock],
		[MeshUtil.box(Vector3(0.68, 0.44, 0.72)), MeshUtil.at(Vector3(-0.1, 1.68, 0.02), Basis(Vector3.UP, 0.9)), dark],
	])
	# Burnt trees and spikes along the shoulders.
	var ash := Color(0.08, 0.065, 0.07)
	_spires = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.1, 0.32, 4.4, 5), MeshUtil.at(Vector3(0, 2.2, 0)), ash],
		[MeshUtil.cylinder(0.03, 0.13, 1.9, 4), MeshUtil.at(Vector3(0.65, 3.0, 0), Basis(Vector3.FORWARD, -0.85)), ash],
		[MeshUtil.cylinder(0.03, 0.11, 1.5, 4), MeshUtil.at(Vector3(-0.55, 3.5, 0.1), Basis(Vector3.FORWARD, 0.8)), ash],
		[MeshUtil.cylinder(0.02, 0.09, 1.1, 4), MeshUtil.at(Vector3(0.15, 4.2, 0.4), Basis(Vector3.RIGHT, 0.7)), ash],
		[MeshUtil.box(Vector3(0.06, 0.8, 0.06)), MeshUtil.at(Vector3(0.1, 0.5, 0.3)), _glow(hot, 0.6)],
	])

	# The erupting peak on the horizon, always the same distance ahead.
	_backdrop = Node3D.new()
	c.add_child(_backdrop)
	var flow := Color(1.0, 0.42, 0.05)
	var peak := [
		[MeshUtil.cylinder(95.0, 560.0, 500.0, 14), MeshUtil.at(Vector3(0, 250, 0)), Color(0.13, 0.07, 0.09)],
		[MeshUtil.cylinder(70.0, 165.0, 120.0, 12), MeshUtil.at(Vector3(120, 95, 180)), Color(0.11, 0.06, 0.08)],
		[MeshUtil.cylinder(92.0, 92.0, 3.0, 14), MeshUtil.at(Vector3(0, 501, 0)), Color(1.0, 0.75, 0.2)],
		[MeshUtil.cylinder(62.0, 62.0, 3.0, 14), MeshUtil.at(Vector3(0, 503, 0)), Color(1.0, 0.95, 0.65)],
	]
	for k in 7:
		var a := -0.95 + k * 0.32
		var lean := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, -atan2(465.0, 500.0))   # lies on the slope
		var w := 16.0 + float((k * 7) % 5) * 5.0
		var mid := Vector3(sin(a), 0, cos(a)) * 331.0 + Vector3.UP * 250.0
		peak.append([MeshUtil.box(Vector3(w, 680.0, 5.0)), Transform3D(lean, mid), flow if k % 2 == 0 else Color(1.0, 0.62, 0.1)])
	for k in 9:
		var t := k / 8.0
		var r := 58.0 + t * 190.0
		var shade := Color(0.24, 0.11, 0.13).lerp(Color(0.1, 0.06, 0.1), t)
		peak.append([MeshUtil.sphere(r, 9), MeshUtil.at(Vector3(sin(k * 2.1) * 30.0 * (1.0 + t * 4.0) + t * 190.0,
			540.0 + t * 520.0, cos(k * 1.4) * 30.0), Basis.from_scale(Vector3(1.25, 0.72, 1.0))), shade])
	var mi := MeshInstance3D.new()
	mi.mesh = MeshUtil.merge_parts(peak)
	mi.material_override = _sky_mat()
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.custom_aabb = AABB(Vector3(-2000, -500, -2000), Vector3(4000, 3000, 4000))
	_backdrop.add_child(mi)

	# Lava bombs thrown up out of the channels (just for show).
	var bomb := MeshUtil.merge_parts([
		[MeshUtil.sphere(1.0, 6), MeshUtil.at(Vector3.ZERO), Color(1.0, 0.55, 0.08)],
		[MeshUtil.box(Vector3(1.2, 1.2, 1.2)), MeshUtil.at(Vector3(0.1, 0.1, 0), Basis(Vector3.UP, 0.7)), Color(0.45, 0.08, 0.04)],
	])
	for i in 9:
		var n := MeshInstance3D.new()
		n.mesh = bomb
		n.material_override = c._prop_mat
		n.scale = Vector3.ONE * _rng.randf_range(0.7, 1.5)
		c.add_child(n)
		var b := {"node": n, "t": 0.0, "life": 0.0, "start": Vector3.ZERO, "v": Vector3.ZERO}
		_bombs.append(b)
		b.t = 1.0
		b.life = _rng.randf_range(0.2, 2.5)

	# Embers drifting up past the rider.
	_embers = CPUParticles3D.new()
	_embers.amount = 260
	_embers.lifetime = 3.2
	_embers.preprocess = 3.2
	_embers.local_coords = false
	_embers.emission_shape = CPUParticles3D.EMISSION_SHAPE_BOX
	_embers.emission_box_extents = Vector3(42, 5, 55)
	_embers.direction = Vector3(0.15, 1, 0)
	_embers.spread = 25.0
	_embers.gravity = Vector3(0, 1.0, 0)
	_embers.initial_velocity_min = 2.0
	_embers.initial_velocity_max = 5.5
	var q := QuadMesh.new()
	q.size = Vector2(0.17, 0.17)
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	m.albedo_color = Color(1.0, 0.55, 0.12)
	m.disable_fog = true
	q.material = m
	_embers.mesh = q
	c.add_child(_embers)


func _build_moon() -> void:
	var grey := Color(0.5, 0.5, 0.53)
	var dark := Color(0.3, 0.3, 0.34)
	var white := Color(0.94, 0.94, 0.96)
	var gold := Color(0.95, 0.72, 0.18)
	var steel := Color(0.62, 0.65, 0.72)
	var glass := Color(0.3, 0.72, 0.95)

	# Obstacle: a stack of moon rock (radius 1.4, 5 m tall).
	c._tree_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(1.5, 7), MeshUtil.at(Vector3(0, 0.95, 0), Basis.from_scale(Vector3(1.0, 0.72, 0.95))), grey],
		[MeshUtil.sphere(1.05, 6), MeshUtil.at(Vector3(0.75, 0.5, 0.45), Basis.from_scale(Vector3(1.0, 0.65, 0.9))), dark],
		[MeshUtil.cylinder(0.35, 1.0, 2.4, 6), MeshUtil.at(Vector3(-0.15, 2.8, 0)), grey],
		[MeshUtil.cylinder(0.0, 0.42, 1.0, 5), MeshUtil.at(Vector3(-0.1, 4.5, 0)), dark],
	])
	# Obstacle: a snowman made of moon dust, in a space helmet.
	c._snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(0.58, 9), MeshUtil.at(Vector3(0, 0.52, 0)), Color(0.82, 0.82, 0.85)],
		[MeshUtil.sphere(0.42, 9), MeshUtil.at(Vector3(0, 1.28, 0)), Color(0.86, 0.86, 0.88)],
		[MeshUtil.sphere(0.27, 8), MeshUtil.at(Vector3(0, 1.84, 0)), Color(0.9, 0.9, 0.92)],
		[MeshUtil.sphere(0.46, 9), MeshUtil.at(Vector3(0, 1.88, 0.02)), Color(0.42, 0.78, 1.0)],
		[MeshUtil.cylinder(0.42, 0.42, 0.13, 10), MeshUtil.at(Vector3(0, 1.48, 0)), white],
		[MeshUtil.box(Vector3(0.62, 0.72, 0.28)), MeshUtil.at(Vector3(0, 1.3, -0.46)), white],
		[MeshUtil.cylinder(0.0, 0.05, 0.3, 6), MeshUtil.at(Vector3(0, 1.84, 0.4), Basis(Vector3.RIGHT, PI * 0.5)), Color(1.0, 0.5, 0.1)],
		[MeshUtil.cylinder(0.015, 0.015, 0.5, 4), MeshUtil.at(Vector3(0.22, 2.48, 0)), steel],
		[MeshUtil.sphere(0.06, 5), MeshUtil.at(Vector3(0.22, 2.74, 0)), Color(1, 0.2, 0.2)],
	])
	_rocks = MeshUtil.merge_parts([
		[MeshUtil.sphere(1.0, 6), MeshUtil.at(Vector3(0, 0.3, 0), Basis.from_scale(Vector3(1.0, 0.65, 0.85))), grey],
		[MeshUtil.sphere(0.6, 5), MeshUtil.at(Vector3(0.8, 0.15, 0.3), Basis.from_scale(Vector3(1.0, 0.7, 0.9))), dark],
	])
	_dome = MeshUtil.merge_parts([
		[MeshUtil.sphere(7.0, 12), MeshUtil.at(Vector3(0, 0, 0), Basis.from_scale(Vector3(1, 0.72, 1))), Color(0.8, 0.84, 0.9)],
		[MeshUtil.cylinder(7.1, 7.1, 0.6, 12), MeshUtil.at(Vector3(0, 0.3, 0)), steel],
		[MeshUtil.box(Vector3(2.4, 2.6, 2.0)), MeshUtil.at(Vector3(0, 1.3, 6.8)), white],
		[MeshUtil.box(Vector3(1.3, 1.7, 0.1)), MeshUtil.at(Vector3(0, 1.0, 7.85)), glass],
		[MeshUtil.box(Vector3(9.0, 1.2, 0.1)), MeshUtil.at(Vector3(0, 3.8, 5.25), Basis(Vector3.RIGHT, -0.5)), glass],
		[MeshUtil.cylinder(1.2, 1.2, 7.0, 8), MeshUtil.at(Vector3(10.0, 1.0, 0), Basis(Vector3.FORWARD, PI * 0.5)), white],
		[MeshUtil.sphere(3.2, 9), MeshUtil.at(Vector3(15.0, 0.2, 0), Basis.from_scale(Vector3(1, 0.8, 1))), Color(0.75, 0.8, 0.86)],
	])
	var lander := [
		[MeshUtil.box(Vector3(3.2, 1.8, 3.2)), MeshUtil.at(Vector3(0, 2.7, 0), Basis(Vector3.UP, PI * 0.25)), gold],
		[MeshUtil.cylinder(1.2, 1.7, 1.7, 7), MeshUtil.at(Vector3(0, 4.4, 0)), white],
		[MeshUtil.cylinder(0.3, 1.2, 0.8, 7), MeshUtil.at(Vector3(0, 5.65, 0)), steel],
		[MeshUtil.box(Vector3(0.8, 0.55, 0.12)), MeshUtil.at(Vector3(0, 4.55, 1.45)), Color(0.08, 0.1, 0.2)],
		[MeshUtil.cylinder(0.3, 0.75, 0.9, 8), MeshUtil.at(Vector3(0, 1.45, 0)), dark],
		[MeshUtil.cylinder(0.02, 0.02, 1.4, 4), MeshUtil.at(Vector3(0.4, 6.5, 0)), steel],
	]
	for k in 4:
		var a := k * PI * 0.5 + PI * 0.25
		var out := Vector3(cos(a), 0, sin(a))
		var leg := (out * 1.7 + Vector3.UP * 2.1).normalized()
		var b := Basis(Quaternion(Vector3.UP, leg))
		lander.append([MeshUtil.cylinder(0.08, 0.08, 2.9, 5), Transform3D(b, out * 2.15 + Vector3.UP * 1.05), steel])
		lander.append([MeshUtil.cylinder(0.5, 0.5, 0.08, 8), MeshUtil.at(out * 3.0 + Vector3.UP * 0.05), steel])
	_lander = MeshUtil.merge_parts(lander)
	var tilt := Basis(Vector3.RIGHT, 0.75)
	var dish := [
		[MeshUtil.cylinder(0.18, 0.3, 3.2, 6), MeshUtil.at(Vector3(0, 1.6, 0)), steel],
		[MeshUtil.cylinder(2.5, 0.25, 0.9, 12), Transform3D(tilt, Vector3(0, 3.4, 0)), white],
		[MeshUtil.cylinder(0.03, 0.03, 1.8, 4), Transform3D(tilt, Vector3(0, 4.05, 0.62)), steel],
		[MeshUtil.sphere(0.15, 5), MeshUtil.at(Vector3(0, 4.72, 1.2)), Color(1, 0.2, 0.2)],
	]
	_dish = MeshUtil.merge_parts(dish)
	# A flag claiming the moon for the team, stiffly held out like on a real moon landing.
	_flag = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.04, 0.04, 3.2, 5), MeshUtil.at(Vector3(0, 1.6, 0)), steel],
		[MeshUtil.cylinder(0.025, 0.025, 1.8, 4), MeshUtil.at(Vector3(0.9, 3.15, 0), Basis(Vector3.FORWARD, PI * 0.5)), steel],
		[MeshUtil.box(Vector3(1.76, 1.08, 0.03)), MeshUtil.at(Vector3(0.9, 2.6, 0)), Color(1.0, 0.45, 0.08)],
		[MeshUtil.sphere(0.27, 8), MeshUtil.at(Vector3(0.9, 2.6, 0.02), Basis.from_scale(Vector3(1, 1, 0.12))), white],
	])

	# Earth, hanging over the horizon.
	_backdrop = Node3D.new()
	c.add_child(_backdrop)
	var sea := Color(0.1, 0.32, 0.9)
	var land := Color(0.22, 0.66, 0.28)
	var cloud := Color(0.95, 0.97, 1.0)
	var earth := [[MeshUtil.sphere(1.0, 20), MeshUtil.at(Vector3.ZERO), sea]]
	var patches := [[0.3, 0.42, 0.42, land], [-0.42, 0.1, 0.34, land], [0.08, -0.32, 0.36, land],
		[0.55, -0.12, 0.22, land], [-0.22, 0.62, 0.32, cloud], [0.42, 0.14, 0.2, cloud],
		[-0.52, -0.36, 0.25, cloud], [0.1, 0.92, 0.3, cloud], [-0.06, -0.92, 0.32, cloud]]
	for pa in patches:
		var v := Vector3(pa[0], pa[1], 0.0)
		v.z = sqrt(maxf(1.0 - v.length_squared(), 0.0))
		var r: float = pa[2]
		earth.append([MeshUtil.sphere(r, 9), MeshUtil.at(v.normalized() * (1.0 - r * 0.1), Basis.from_scale(Vector3(1.25, 0.8, 0.28))), pa[3]])
	var e := MeshInstance3D.new()
	e.mesh = MeshUtil.merge_parts(earth)
	e.material_override = _sky_mat()
	e.scale = Vector3.ONE * 88.0
	e.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_backdrop.add_child(e)


# ---------------------------------------------------------------- per-chunk scenery

func add_extras(rng: RandomNumberGenerator, chunk: int, d0: float, node: Node3D) -> void:
	match theme:
		"mall":
			_mall_extras(rng, chunk, d0, node)
		"volcano":
			_volcano_extras(rng, chunk, d0, node)
		"moon":
			_moon_extras(rng, chunk, d0, node)


## Height of the mall floor along a line beside the track.
func _mall_point(d: float, lx: float) -> Vector3:
	var hw: float = c.HALF_WIDTH
	return Vector3(c.center_x(d) + lx, c.base_height(d) + hw * hw * 0.0025 + 0.15, -d)


## Sheared along the slope so the shop fronts and balconies follow the floor without steps.
func _bay_xform(d: float, side: float, wall: float) -> Transform3D:
	var lx: float = side * (c.HALF_WIDTH + wall)
	var p0 := _mall_point(d - MALL_BAY * 0.5, lx)
	var p1 := _mall_point(d + MALL_BAY * 0.5, lx)
	var xa := (p1 - p0) / MALL_BAY * -side
	return Transform3D(Basis(xa, Vector3.UP, xa.cross(Vector3.UP).normalized()), (p0 + p1) * 0.5)


func _mall_extras(rng: RandomNumberGenerator, chunk: int, d0: float, node: Node3D) -> void:
	var bays: Array = [[], [], [], [], [], []]
	var roofs: Array[Transform3D] = []
	var planters: Array[Transform3D] = []
	var bay_count := int(c.CHUNK_LEN / MALL_BAY)
	for i in bay_count:
		var d := d0 + (i + 0.5) * MALL_BAY
		for side in [-1.0, 1.0]:
			bays[rng.randi() % 6].append(_bay_xform(d, side, MALL_WALL))
			if rng.randf() < 0.3:
				var p := _mall_point(d + rng.randf_range(-4.0, 4.0), side * (c.HALF_WIDTH + 3.0))
				planters.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * 0.8), p))
		var a := _mall_point(d + 7.0, 0.0)
		var b := _mall_point(d - 7.0, 0.0)
		var back := (b - a) / 14.0
		var right := (a - b).cross(Vector3.UP)
		right.y = 0.0
		roofs.append(Transform3D(Basis(right.normalized(), Vector3.UP, back), (a + b) * 0.5))
	for v in 6:
		var xf: Array[Transform3D] = []
		xf.assign(bays[v])
		c._add_multimesh(node, _bays[v], xf, c._prop_mat)
	c._add_multimesh(node, _roof, roofs, c._prop_mat)
	c._add_multimesh(node, c._tree_mesh, planters, c._prop_mat)
	if chunk < 0:
		return
	# An escalator up to the first floor, alternating sides.
	var ed := d0 + rng.randf_range(16.0, c.CHUNK_LEN - 16.0)
	var eside := -1.0 if chunk % 2 == 0 else 1.0
	var exf := _bay_xform(ed, eside, MALL_WALL - 3.6)
	var esc := MeshInstance3D.new()
	esc.mesh = _escalator
	esc.material_override = c._prop_mat
	esc.transform = exf
	node.add_child(esc)
	for i in 3:
		_mall_sign(rng, node, d0 + (i + rng.randf()) * c.CHUNK_LEN / 3.0, -1.0 if rng.randf() < 0.5 else 1.0)


func _mall_sign(rng: RandomNumberGenerator, node: Node3D, d: float, side: float) -> void:
	var p := _mall_point(d, side * (c.HALF_WIDTH + 1.0))
	var board: MeshInstance3D = c._add_mesh(node, _blade, c._prop_mat, p)
	board.rotation.y = c.track_yaw(d) - side * 0.55   # angled to face the oncoming rider
	var text: String = MALL_SHOPS[rng.randi() % MALL_SHOPS.size()]
	var colors := [Color(1.0, 0.86, 0.3), Color(1, 1, 1), Color(0.5, 0.92, 1.0), Color(1.0, 0.55, 0.75)]
	var label := Label3D.new()
	label.text = text
	label.font = Screen.pixel_font
	label.font_size = 64
	label.pixel_size = clampf(7.4 / (text.length() * 48.0), 0.012, 0.026)
	label.outline_size = 0
	label.modulate = colors[rng.randi() % colors.size()]
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = Vector3(0, 6.2, 0.11)
	board.add_child(label)


func _volcano_extras(rng: RandomNumberGenerator, _chunk: int, d0: float, node: Node3D) -> void:
	_lava_strip(node, d0)
	var dead: Array[Transform3D] = []
	var spikes: Array[Transform3D] = []
	var d := d0
	while d < d0 + c.CHUNK_LEN:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.32:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var x: float = c.center_x(dd) + side * (c.HALF_WIDTH + rng.randf_range(1.3, 3.4))
				dead.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.7, 1.2)),
					Vector3(x, c.height(x, -dd) - 0.1, -dd)))
			if rng.randf() < 0.7:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var x: float = c.center_x(dd) + side * (c.HALF_WIDTH + LAVA_FAR + rng.randf_range(2.0, 75.0))
				var s := rng.randf_range(1.2, 3.4)
				var mesh_list := dead if rng.randf() < 0.35 else spikes
				mesh_list.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(x, c.height(x, -dd) - 0.3, -dd)))
		d += 6.0
	# spires poking up out of the lava
	for i in 7:
		var dd := d0 + rng.randf_range(0.0, c.CHUNK_LEN)
		var side := -1.0 if rng.randf() < 0.5 else 1.0
		var x: float = c.center_x(dd) + side * (c.HALF_WIDTH + rng.randf_range(LAVA_NEAR + 2.0, LAVA_FAR - 1.0))
		spikes.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(0.9, 2.4)),
			Vector3(x, _lava_y(dd) - 0.4, -dd)))
	c._add_multimesh(node, _spires, dead, c._prop_mat)
	c._add_multimesh(node, c._tree_mesh, spikes, c._prop_mat)


func _lava_y(d: float) -> float:
	var hw: float = c.HALF_WIDTH
	return c.base_height(d) + hw * hw * 0.0025 - LAVA_DEPTH


## A river of lava down each side of the track.
func _lava_strip(parent: Node3D, d0: float) -> void:
	var steps := 8
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var idx := PackedInt32Array()
	var hw: float = c.HALF_WIDTH
	var near := hw + LAVA_NEAR - 2.0
	var far := hw + LAVA_FAR + 6.0
	for side in [-1.0, 1.0]:
		var base := verts.size()
		for r in steps + 1:
			var d: float = d0 + c.CHUNK_LEN * r / steps
			var cx: float = c.center_x(d)
			var y := _lava_y(d)
			verts.append(Vector3(cx + side * near, y, -d))
			verts.append(Vector3(cx + side * far, y, -d))
			nrm.append(Vector3.UP)
			nrm.append(Vector3.UP)
		for r in steps:
			var a := base + r * 2
			idx.append_array(PackedInt32Array([a, a + 2, a + 1, a + 1, a + 2, a + 3]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	c._add_mesh(parent, mesh, _lava_mat, Vector3.ZERO)


func _moon_extras(rng: RandomNumberGenerator, chunk: int, d0: float, node: Node3D) -> void:
	var rocks: Array[Transform3D] = []
	var d := d0
	while d < d0 + c.CHUNK_LEN:
		for side in [-1.0, 1.0]:
			if rng.randf() < 0.75:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var x: float = c.center_x(dd) + side * (c.HALF_WIDTH + 1.5 + pow(rng.randf(), 1.5) * 105.0)
				var s := rng.randf_range(0.4, 2.3)
				rocks.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3(s, s * rng.randf_range(0.7, 1.2), s)),
					Vector3(x, c.height(x, -dd) - 0.15, -dd)))
		d += 4.0
	c._add_multimesh(node, _rocks, rocks)
	if chunk < 0:
		return
	var mat = MeshUtil.vertex_color_material()
	_moon_prop(rng, node, _dish, mat, d0, 8.0, 24.0, 0.45)
	_moon_prop(rng, node, _flag, mat, d0, 2.0, 5.0, 0.35)
	_moon_prop(rng, node, _lander, mat, d0, 16.0, 46.0, 0.3)
	_moon_prop(rng, node, _dome, mat, d0, 34.0, 78.0, 0.35)


func _moon_prop(rng: RandomNumberGenerator, node: Node3D, mesh: Mesh, mat: Material, d0: float,
		near: float, far: float, chance: float) -> void:
	if rng.randf() > chance:
		return
	var d: float = d0 + rng.randf_range(4.0, c.CHUNK_LEN - 4.0)
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var x: float = c.center_x(d) + side * (c.HALF_WIDTH + rng.randf_range(near, far))
	var mi: MeshInstance3D = c._add_mesh(node, mesh, mat, Vector3(x, c.height(x, -d) - 0.05, -d))
	mi.rotation.y = c.track_yaw(d) + (PI * 0.5 * -side) + rng.randf_range(-0.5, 0.5)


# ---------------------------------------------------------------- animation

func update(delta: float) -> void:
	var f: float = c.focus_d
	if theme == "volcano":
		_backdrop.position = Vector3(c.center_x(f) - 170.0, c.base_height(f) - 215.0, -(f + 1120.0))
		var ahead := f + 22.0
		_embers.position = Vector3(c.center_x(ahead), c.base_height(ahead) + 4.0, -ahead)
		for b in _bombs:
			_update_bomb(b, delta, f)
	elif theme == "moon":
		_backdrop.position = Vector3(c.center_x(f) + 300.0, c.base_height(f) - 25.0, -(f + 1050.0))
		_backdrop.rotation.y += delta * 0.02


func _update_bomb(b: Dictionary, delta: float, f: float) -> void:
	b.t += delta
	var n: MeshInstance3D = b.node
	if b.t >= b.life:
		var dd := f + _rng.randf_range(30.0, 300.0)
		var side := -1.0 if _rng.randf() < 0.5 else 1.0
		var x: float = c.center_x(dd) + side * (c.HALF_WIDTH + _rng.randf_range(LAVA_NEAR + 2.0, LAVA_FAR - 2.0))
		var vy := _rng.randf_range(20.0, 34.0)
		b.start = Vector3(x, _lava_y(dd), -dd)
		b.v = Vector3(_rng.randf_range(-3.0, 3.0), vy, _rng.randf_range(-3.0, 3.0))
		b.life = 2.0 * vy / 24.0
		b.t = 0.0
	var t: float = b.t
	var v: Vector3 = b.v
	n.position = (b.start as Vector3) + v * t + Vector3.DOWN * 12.0 * t * t
	n.rotation = Vector3(t * 3.0, t * 2.0, 0.0)
