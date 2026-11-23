extends Node3D
## Endless courses (Winter Valley, Desert Dunes, Sky Islands). The slope is an analytic height function that goes on forever;
## the visible course is built in 96 m chunks just ahead of the rider and freed behind.
## Every chunk is seeded from its index, so a given stretch always looks the same.
## Coordinates: "d" = distance downhill (world -Z), "lx" = offset from the track centreline.

const MeshUtil := preload("res://scripts/mesh_util.gd")
const AD_SHADER := preload("res://shaders/ads.gdshader")
const TERRAIN_SHADER := preload("res://shaders/ps1_terrain.gdshader")
const FinalThemes := preload("res://scripts/final_themes.gd")

# Course settings below are set per level by configure() (defaults = level 1).
var SEED := 20251225
const CHUNK_LEN := 96.0
const STEP_Z := 1.5
const ROWS_PER_CHUNK := 64          # CHUNK_LEN / STEP_Z
const CHUNKS_AHEAD := 7             # ~670 m of course ahead of the rider
const CHUNKS_BEHIND := 1
const RUNUP_CHUNKS := 3             # hill kept behind the start line for the intro shot
const MILESTONE := 500.0            # a distance gate every 500 m
const EXTRA_OBSTACLES := 0.08       # difficulty: added to every level's obstacle chance
const OBSTACLE_RAMP_LEN := 2500.0   # difficulty: lower = a stage gets busy sooner

var HALF_WIDTH := 20.0              # fenced track half width
const SIDE_EXTENT := 140.0          # how far the valley mesh reaches sideways
var SLOPE := 0.24
const START_FLAT := 30.0
const RAMP_LEN := 10.0
var RAMP_H := 2.6
const RAMP_HALF_W := 4.0
const SEG := 4.0                    # fence panel length (4:1 banners)
const AD_ATLASES := 6               # res://assets/ads/sponsor_atlas_N.png
const AD_ROWS := 4                  # 4 banners stacked in each atlas
const AD_INSET := 0.11             # board face is at 0.06, so banners sit 5 cm clear of it (no z-fighting)

const SNOW := Color(0.78, 0.86, 1.0)
const GROOMED := Color(0.82, 0.9, 1.0)
const ROCK := Color(0.33, 0.35, 0.72)
const ICE := Color(0.72, 0.87, 1.0)
const BEACH_SEA_START := 15.0       # beach level: where the sand gives way to sea...
const SEA_DEPTH := -2.4             # ...and how far below the track the sea sits
const CITY_STREET_DEPTH := -36.0    # city level: the streets far below the elevated highway
const CITY_SIGNS := ["NOODLES", "BAO CORP", "SYNTH", "DRAGONFRUIT", "24H RAMEN", "ARCADE",
	"NO SLEEP", "CYBER BAO", "SUGAR GLIDE", "RED PANDA", "HOTEL", "DATA BAR"]

var half_width := HALF_WIDTH
## Set by the game each frame: how far down the hill the rider is.
var focus_d := 0.0
## Roguelike stage: where the finish line is (0 = none). Nothing blocks the track past it.
var finish_d := 0.0
## True during the stage intro: keeps the run-up slope behind the start line loaded.
var runup := true
## Live obstacles and gifts across all loaded chunks.
var obstacles: Array[Dictionary] = []   # {pos, radius, height}
var gifts: Array[Dictionary] = []       # {node, pos, taken}

var _chunks := {}        # chunk index -> {node, obstacles, gifts}
var _ramp_cache := {}    # chunk index -> {d, x} or {}
var _noise := FastNoiseLite.new()
var _mtn_noise := FastNoiseLite.new()
var _cols := PackedFloat32Array()
var _ad_order: Array = []
var _ad_mats: Array = []
var _terrain_mat: Material
var _gift_mesh: Mesh
var _gift_mat: Material
var _tree_mesh: Mesh
var _snowman_mesh: Mesh
var _flag_mesh: Mesh
var _gate_meshes := {}
var _time := 0.0
var _building := false   # a chunk is being built in the background
var _gen := 0            # bumped on reset so stale background builds bail out

# Per-level settings (see levels.gd).
var _level: Dictionary = {}
var _theme := "snow"
var _level_name := "WINTER VALLEY"
var _gate_color := Color(0.1, 0.45, 1.0)
var _noise_seed := 7
var _mtn_seed := 11
var _curve_amp := 1.0
var _curve_freq := 1.0
var _ramp_chance := 0.6
var _obstacle_base := 0.35
var _obstacle_ramp := 0.3
var _scenery_density := 0.8
var _bumpiness := 1.0
var _final: RefCounted = null   # the mall, volcano and moon live in final_themes.gd


## Applies a level definition from levels.gd. Call before build().
func configure(level: Dictionary) -> void:
	_level = level
	_theme = level.get("theme", "snow")
	_level_name = level.name
	_gate_color = level.gate_color
	SEED = level.seed
	_noise_seed = level.noise_seed
	_mtn_seed = level.mtn_seed
	SLOPE = level.slope
	HALF_WIDTH = level.half_width
	half_width = HALF_WIDTH
	_curve_amp = level.curve_amp
	_curve_freq = level.curve_freq
	_ramp_chance = level.ramp_chance
	RAMP_H = level.ramp_h
	_obstacle_base = level.obstacle_base
	_obstacle_ramp = level.obstacle_ramp
	_scenery_density = level.get("scenery_density", 0.8)
	_bumpiness = level.get("bumpiness", 1.0)
	if _theme in ["mall", "volcano", "moon"]:
		_final = FinalThemes.new(self, _theme)


func build() -> void:
	_noise.seed = _noise_seed
	_noise.frequency = 0.02
	_noise.fractal_octaves = 2
	_mtn_noise.seed = _mtn_seed
	_mtn_noise.frequency = 0.012
	_mtn_noise.fractal_octaves = 4

	# Terrain columns across the valley: dense on the track, sparse on the mountainsides.
	var lx := -SIDE_EXTENT
	while lx < -30.0:
		_cols.append(lx)
		lx += 5.0
	lx = -30.0
	while lx <= 30.0:
		_cols.append(lx)
		lx += 2.0
	lx = 35.0
	while lx <= SIDE_EXTENT:
		_cols.append(lx)
		lx += 5.0

	# Fixed shuffle of the 24 sponsor banners.
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED
	for i in AD_ATLASES * AD_ROWS:
		_ad_order.append(i)
	for i in range(_ad_order.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = _ad_order[i]
		_ad_order[i] = _ad_order[j]
		_ad_order[j] = t
	for a in AD_ATLASES:
		var m := ShaderMaterial.new()
		m.shader = AD_SHADER
		m.set_shader_parameter("tex", load("res://assets/ads/sponsor_atlas_%d.png" % (a + 1)))
		_ad_mats.append(m)

	var tm := ShaderMaterial.new()
	tm.shader = TERRAIN_SHADER
	tm.set_shader_parameter("offpiste_tex", _tex(_level.get("offpiste_tex", "res://assets/textures/snow_offpiste.png")))
	tm.set_shader_parameter("track_tex", _tex(_level.get("track_tex", "res://assets/textures/snow_track.png")))
	tm.set_shader_parameter("rock_tex", _tex(_level.get("rock_tex", "res://assets/textures/rock.png")))
	if _level.has("shore_tex"):
		tm.set_shader_parameter("shore_tex", _tex(_level.shore_tex))
	for k in ["desaturate", "offpiste_tint", "track_tint", "rock_tint", "tile_size", "rock_tile_size",
			"track_scroll", "track_wobble", "shore_tint"]:
		if _level.has(k):
			var v = _level[k]
			tm.set_shader_parameter(k, Vector3(v.r, v.g, v.b) if v is Color else v)
	if _level.has("ramp_tint"):
		var rt: Color = _level.ramp_tint
		tm.set_shader_parameter("ice_tint", Vector3(rt.r, rt.g, rt.b))
	if _level.has("ramp_tex"):     # textured jumps (sand on the sky level)
		tm.set_shader_parameter("ramp_tex", _tex(_level.ramp_tex))
		tm.set_shader_parameter("use_ramp_tex", true)
		var rtt: Color = _level.get("ramp_tex_tint", Color(1, 1, 1))
		tm.set_shader_parameter("ramp_tex_tint", Vector3(rtt.r, rtt.g, rtt.b))
	_terrain_mat = tm
	_gift_mat = MeshUtil.ps1_material(Color(1.0, 0.75, 0.35), 0.2)
	_build_shared_meshes()


## Loads a texture, or reads the PNG straight from disk if the editor hasn't imported it yet.
func _tex(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path)
	var img := Image.load_from_file(ProjectSettings.globalize_path(path))
	return ImageTexture.create_from_image(img) if img and not img.is_empty() else null


## Throws away every chunk and regenerates the course around the start line.
func reset() -> void:
	_gen += 1
	_building = false
	for c in _chunks.keys():
		_free_chunk(c)
	_ramp_cache.clear()
	focus_d = 0.0
	_update_chunks(true)


## Debug warp: drops any half-built chunk and builds the course around distance d right away.
func debug_jump(d: float) -> void:
	_gen += 1
	_building = false
	focus_d = d
	_update_chunks(true)


func _process(delta: float) -> void:
	_time += delta
	_update_chunks(false)
	if _theme == "city":
		_update_traffic(delta)
	if _final:
		_final.update(delta)
	for g in gifts:
		if not g.taken:
			var n: Node3D = g.node
			n.rotation.y = _time * 2.0
			n.position.y = g.pos.y + sin(_time * 3.0 + n.position.z) * 0.15


func _update_chunks(build_all: bool) -> void:
	var pc := int(floor(focus_d / CHUNK_LEN))
	var lo := -RUNUP_CHUNKS if runup else maxi(pc - CHUNKS_BEHIND, -1)
	var hi := maxi(pc, 0) + CHUNKS_AHEAD
	var changed := false
	for c in _chunks.keys():
		if c < lo or c > hi:
			_free_chunk(c)
			changed = true
	for c in _ramp_cache.keys():
		if c < lo - 2:
			_ramp_cache.erase(c)
	for c in range(lo, hi + 1):
		if not _chunks.has(c):
			if build_all:
				_build_chunk(c, false)
				changed = true
			elif not _building:
				_build_chunk(c, true)  # spreads itself over a few frames
				break
			else:
				break
	if changed:
		_refresh_lists()


func _refresh_lists() -> void:
	obstacles.clear()
	gifts.clear()
	for c in _chunks:
		obstacles.append_array(_chunks[c].obstacles)
		gifts.append_array(_chunks[c].gifts)


func _free_chunk(c: int) -> void:
	_chunks[c].node.queue_free()
	_chunks.erase(c)


func _chunk_rng(c: int, salt: int) -> RandomNumberGenerator:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash([SEED, c, salt])
	return rng


# ---------------------------------------------------------------- height field

func center_x(d: float) -> float:
	var t := maxf(d, 0.0)
	var f := _curve_freq
	return _curve_amp * (30.0 * sin(t * 0.004 * f) + 12.0 * sin(t * 0.0115 * f + 0.7) - 12.0 * sin(0.7))


func center_slope(d: float) -> float:
	return center_x(d + 0.5) - center_x(d - 0.5)


func track_yaw(d: float) -> float:
	## Yaw that faces straight down the track at distance d.
	return atan2(-center_slope(d), 1.0)


func base_height(d: float) -> float:
	return -SLOPE * (d - START_FLAT * 0.5)   # the hill carries on behind the start line


func height(x: float, z: float) -> float:
	var d := -z
	var lx := x - center_x(d)
	var ax := absf(lx)
	var h := base_height(d) + lx * lx * 0.0025
	if ax > HALF_WIDTH:
		var e := ax - HALF_WIDTH
		if _theme == "sky":
			# floating island: a short grassy shoulder, then rocky cliffs dropping into the sky
			h -= e * e * 0.06 if e < 4.0 else 0.96 + (e - 4.0) * 3.2
			h += _mtn_noise.get_noise_2d(x, z) * minf(e, 30.0) * 0.45
		elif _theme == "beach":
			h -= (lx * lx - HALF_WIDTH * HALF_WIDTH) * 0.0025   # no valley bowl off the track
			h += _beach_profile(lx, e, x, z)
		elif _theme == "city":
			h -= (lx * lx - HALF_WIDTH * HALF_WIDTH) * 0.0025   # no valley bowl off the track
			h += 0.2 if e < 4.0 else maxf(0.2 - (e - 4.0) * 3.0, CITY_STREET_DEPTH)   # the highway's edge
		elif _final:
			h -= (lx * lx - HALF_WIDTH * HALF_WIDTH) * 0.0025
			h += _final.edge_height(e, x, z)
		else:
			h += e * e * 0.02 if e < 40.0 else 32.0 + (e - 40.0) * 1.6
			h += _mtn_noise.get_noise_2d(x, z) * minf(e, 40.0) * 0.5
	h += _noise.get_noise_2d(x, z) * 0.9 * _bumpiness
	h += _ramp_height(d, lx)
	return h


## Beach cross-section. Sea side (lx < 0): a sandy berm, then the beach runs down into
## open sea. Land side: beach, rolling dunes, then rocky cliffs.
func _beach_profile(lx: float, e: float, x: float, z: float) -> float:
	if lx < 0.0:
		if e < 5.0:
			return e * 0.14
		if e < BEACH_SEA_START:
			return 0.7 - (e - 5.0) * 0.26
		return SEA_DEPTH + _mtn_noise.get_noise_2d(x, z) * 0.25
	var h := e * e * 0.025 if e < 9.0 else 2.0 + (e - 9.0) * 0.32
	if e > 34.0:
		h += (e - 34.0) * 0.8
	return h + _mtn_noise.get_noise_2d(x, z) * minf(e, 40.0) * 0.35


func gradient(x: float, z: float) -> Vector2:
	var e := 0.4
	return Vector2(
		(height(x + e, z) - height(x - e, z)) / (2.0 * e),
		(height(x, z + e) - height(x, z - e)) / (2.0 * e))


## The (optional) kicker ramp that lives in chunk c. Deterministic, so the height
## function can ask about any chunk, loaded or not.
func _ramp_for_chunk(c: int) -> Dictionary:
	if _ramp_cache.has(c):
		return _ramp_cache[c]
	var r := {}
	if c >= 1:
		var rng := _chunk_rng(c, 1)
		if rng.randf() < _ramp_chance:
			r = {"d": c * CHUNK_LEN + rng.randf_range(RAMP_LEN + 6.0, CHUNK_LEN - 8.0),
				"x": rng.randf_range(-HALF_WIDTH + 7.0, HALF_WIDTH - 7.0)}
	_ramp_cache[c] = r
	return r


func _ramp_height(d: float, lx: float) -> float:
	var r := _ramp_for_chunk(int(floor(d / CHUNK_LEN)))
	if r.is_empty():
		return 0.0
	var t: float = d - (r.d - RAMP_LEN)
	if t < 0.0 or t > RAMP_LEN + 1.0:
		return 0.0
	var lat: float = absf(lx - r.x)
	if lat > RAMP_HALF_W + 2.0:
		return 0.0
	var prof: float
	if t <= RAMP_LEN:
		var u := t / RAMP_LEN
		prof = RAMP_H * u * u
	else:
		prof = RAMP_H * (1.0 - (t - RAMP_LEN))
	return prof * (1.0 - smoothstep(RAMP_HALF_W, RAMP_HALF_W + 2.0, lat))


## True if (d, lx) is on a ramp's run-up or in its landing zone.
func _near_ramp(d: float, lx: float) -> bool:
	var c := int(floor(d / CHUNK_LEN))
	for cc in [c, c - 1]:
		var r := _ramp_for_chunk(cc)
		if not r.is_empty() and d > r.d - RAMP_LEN - 6.0 and d < r.d + 60.0 and absf(lx - r.x) < 9.0:
			return true
	return false


# ---------------------------------------------------------------- chunk building

## Builds chunk c. With async = true the work is split across several frames
## (a few ms each) so streaming the course never causes a stutter.
func _build_chunk(c: int, async: bool) -> void:
	var gen := _gen
	if async:
		_building = true
	var node := Node3D.new()
	var data := {"node": node, "obstacles": [], "gifts": []}
	var d0 := c * CHUNK_LEN
	var rng := _chunk_rng(c, 2)

	# Terrain heights, in slices.
	var ncols := _cols.size()
	var grid_rows := ROWS_PER_CHUNK + 3
	var pos := PackedVector3Array()
	pos.resize(grid_rows * ncols)
	var slice := 23
	var r0 := 0
	while r0 < grid_rows:
		_terrain_rows(pos, d0, r0, mini(r0 + slice, grid_rows))
		r0 += slice
		if async:
			await get_tree().process_frame
			if gen != _gen or not is_inside_tree():
				node.free()
				return
	_terrain_mesh(node, d0, pos)
	if _theme == "beach":
		_far_sea_mesh(node, d0)
	if async:
		await get_tree().process_frame
		if gen != _gen or not is_inside_tree():
			node.free()
			return
	_build_fences(node, d0)
	if async:
		await get_tree().process_frame
		if gen != _gen or not is_inside_tree():
			node.free()
			return
	var trees: Array[Transform3D] = []
	var snowmen: Array[Transform3D] = []
	_place_obstacles(rng, d0, data, trees, snowmen)
	_place_scenery(rng, c, d0, trees, snowmen)
	_add_multimesh(node, _tree_mesh, trees, _prop_mat)
	_add_multimesh(node, _snowman_mesh, snowmen, _prop_mat)
	if _theme == "sky":
		_add_sky_extras(rng, c, d0, node)
	elif _theme == "beach":
		_add_beach_extras(rng, c, d0, node)
	elif _theme == "city":
		_add_city_extras(rng, c, d0, node)
	elif _final:
		_final.add_extras(rng, c, d0, node)
	_place_gifts(rng, d0, data, node)

	if finish_d > 0.0 and finish_d >= d0 and finish_d < d0 + CHUNK_LEN:
		_make_gate(node, finish_d, "FINISH", Color(1.0, 0.8, 0.1))
	var r := _ramp_for_chunk(c)
	if not r.is_empty():
		for side in [-1.0, 1.0]:
			var x: float = center_x(r.d) + r.x + side * (RAMP_HALF_W + 1.5)
			_add_mesh(node, _flag_mesh, MeshUtil.vertex_color_material(), Vector3(x, height(x, -r.d), -r.d))
		for off in [-5.0, -1.5]:
			var dd: float = r.d + off
			var gx: float = center_x(dd) + r.x
			_add_gift(node, data, Vector3(gx, height(gx, -dd) + 0.9, -dd))

	if c == 0:
		_make_gate(node, 6.0, _level_name, _gate_color)
	var m := ceilf(maxf(d0, 1.0) / MILESTONE) * MILESTONE
	while m < d0 + CHUNK_LEN:
		if finish_d <= 0.0 or m < finish_d:
			_make_gate(node, m, "%d M" % int(m), Color(0.95, 0.15, 0.35) if int(m) % 1000 == 0 else _gate_color)
		m += MILESTONE

	add_child(node)
	_chunks[c] = data
	_refresh_lists()
	if async:
		_building = false


## Fills grid rows [from, to) of a chunk's height grid. Row 0 is one step before the
## chunk starts (and the last row one step after) so normals are seamless across chunks.
func _terrain_rows(pos: PackedVector3Array, d0: float, from: int, to: int) -> void:
	var ncols := _cols.size()
	for i in range(from, to):
		var d := d0 + (i - 1) * STEP_Z
		var c := center_x(d)
		for j in ncols:
			var x := c + _cols[j]
			pos[i * ncols + j] = Vector3(x, height(x, -d), -d)


func _terrain_mesh(parent: Node3D, d0: float, pos: PackedVector3Array) -> void:
	var ncols := _cols.size()
	var rows := ROWS_PER_CHUNK + 1
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	verts.resize(rows * ncols)
	nrm.resize(rows * ncols)
	col.resize(rows * ncols)
	for r in rows:
		var i := r + 1
		var d := d0 + r * STEP_Z
		for j in ncols:
			var j0 := maxi(j - 1, 0)
			var j1 := mini(j + 1, ncols - 1)
			var a := pos[i * ncols + j1] - pos[i * ncols + j0]
			var b := pos[(i + 1) * ncols + j] - pos[(i - 1) * ncols + j]
			var nn := a.cross(b).normalized()
			if nn.y < 0.0:
				nn = -nn
			var p := pos[i * ncols + j]
			var k := r * ncols + j
			verts[k] = p
			nrm[k] = nn
			# Surface weights for the terrain shader: R = rock, G = groomed track, B = ramp ice.
			var rock := smoothstep(0.22, 0.42, (1.0 - nn.y) + _noise.get_noise_2d(p.x * 3.0, p.z * 3.0) * 0.12)
			var track := 1.0 - smoothstep(HALF_WIDTH - 1.0, HALF_WIDTH + 1.5, absf(_cols[j]))
			var shore := 0.0
			if _theme == "beach":
				var ax: float = absf(_cols[j])
				if _cols[j] < -(HALF_WIDTH + BEACH_SEA_START - 1.5):
					track = 1.0   # open sea
					rock = 0.0
				# pale sand along the water: the whole sea-side berm, a strip on the land side
				var sand_w := BEACH_SEA_START if _cols[j] < 0.0 else 7.0
				shore = 1.0 - smoothstep(HALF_WIDTH + sand_w - 2.0, HALF_WIDTH + sand_w + 1.0, ax)
			var ice := 1.0 if _ramp_height(d, _cols[j]) > 0.05 else 0.0
			col[k] = Color(rock * (1.0 - track), track, ice, 1.0 - shore * (1.0 - rock))

	var idx := PackedInt32Array()
	for r in rows - 1:
		for j in ncols - 1:
			var a := r * ncols + j
			var c := a + ncols
			idx.append_array(PackedInt32Array([a, c, a + 1, a + 1, c, c + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_add_mesh(parent, mesh, _terrain_mat, Vector3.ZERO)


func _edge_point(d: float, side: float) -> Vector3:
	var x := center_x(d) + side * (HALF_WIDTH + 0.3)
	return Vector3(x, height(x, -d), -d)


func _build_fences(parent: Node3D, d0: float) -> void:
	if d0 + CHUNK_LEN < -20.0:
		return
	var xforms: Array[Transform3D] = []
	var verts: Array = []
	var uvs: Array = []
	var norms: Array = []
	var idx: Array = []
	for a in AD_ATLASES:
		verts.append(PackedVector3Array())
		uvs.append(PackedVector2Array())
		norms.append(PackedVector3Array())
		idx.append(PackedInt32Array())

	var n_seg := int(CHUNK_LEN / SEG)
	for s in n_seg:
		var d := d0 + s * SEG
		var k := int(round(d / SEG))
		for side in [-1.0, 1.0]:
			var p0 := _edge_point(d, side)
			var p1 := _edge_point(d + SEG, side)
			var xa := (p1 - p0).normalized()
			var za := xa.cross(Vector3.UP).normalized()
			var ya := za.cross(xa)
			xforms.append(Transform3D(Basis(xa, ya, za), (p0 + p1) * 0.5 + Vector3.UP * 0.55))

			var banner: int = _ad_order[posmod(k * 2 + (0 if side < 0.0 else 1), _ad_order.size())]
			var atlas := int(banner / float(AD_ROWS))
			var row := banner % AD_ROWS
			var inward: Vector3 = -side * za
			var b0 := p0 + inward * AD_INSET
			var b1 := p1 + inward * AD_INSET
			var lo := Vector3.UP * 0.05
			var hi := Vector3.UP * 1.05
			var v_top := (row + 0.01) / AD_ROWS
			var v_bot := (row + 0.99) / AD_ROWS
			# Text reads left-to-right from the track: on the right fence that's downhill->uphill.
			var left := b1 if side > 0.0 else b0
			var right := b0 if side > 0.0 else b1
			var va: PackedVector3Array = verts[atlas]
			var ua: PackedVector2Array = uvs[atlas]
			var na: PackedVector3Array = norms[atlas]
			var ia: PackedInt32Array = idx[atlas]
			var base := va.size()
			va.append_array(PackedVector3Array([left + hi, right + hi, right + lo, left + lo]))
			ua.append_array(PackedVector2Array([
				Vector2(0, v_top), Vector2(1, v_top), Vector2(1, v_bot), Vector2(0, v_bot)]))
			na.append_array(PackedVector3Array([inward, inward, inward, inward]))
			ia.append_array(PackedInt32Array([base, base + 1, base + 2, base, base + 2, base + 3]))
			verts[atlas] = va
			uvs[atlas] = ua
			norms[atlas] = na
			idx[atlas] = ia

	if xforms.is_empty():
		return
	# Dark backing boards...
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.use_colors = true
	mm.mesh = MeshUtil.box(Vector3(SEG + 0.05, 1.0, 0.12))
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
		mm.set_instance_color(i, Color(0.05, 0.08, 0.25))
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = MeshUtil.vertex_color_material()
	parent.add_child(mmi)
	# ...with the sponsor banners on the track side.
	var mesh := ArrayMesh.new()
	for a in AD_ATLASES:
		if (verts[a] as PackedVector3Array).is_empty():
			continue
		var arr := []
		arr.resize(Mesh.ARRAY_MAX)
		arr[Mesh.ARRAY_VERTEX] = verts[a]
		arr[Mesh.ARRAY_TEX_UV] = uvs[a]
		arr[Mesh.ARRAY_NORMAL] = norms[a]
		arr[Mesh.ARRAY_INDEX] = idx[a]
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
		mesh.surface_set_material(mesh.get_surface_count() - 1, _ad_mats[a])
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	parent.add_child(mi)


func _make_gate(parent: Node3D, d: float, text: String, color: Color) -> void:
	var c := center_x(d)
	var gate := Node3D.new()
	gate.position = Vector3(c, height(c, -d), -d)
	gate.rotation.y = track_yaw(d)
	parent.add_child(gate)
	var key := color.to_html()
	if not _gate_meshes.has(key):
		var w := HALF_WIDTH * 2.0 + 1.0
		var post := Color(0.95, 0.96, 1.0)
		_gate_meshes[key] = MeshUtil.merge_parts([
			[MeshUtil.box(Vector3(w, 1.6, 0.3)), MeshUtil.at(Vector3(0, 6.0, 0)), color],
			[MeshUtil.cylinder(0.18, 0.18, 7.0), MeshUtil.at(Vector3(-w * 0.5, 3.5, 0)), post],
			[MeshUtil.cylinder(0.18, 0.18, 7.0), MeshUtil.at(Vector3(w * 0.5, 3.5, 0)), post],
		])
	_add_mesh(gate, _gate_meshes[key], MeshUtil.vertex_color_material(), Vector3.ZERO)
	var label := Label3D.new()
	label.text = text
	label.font = Screen.pixel_font
	label.font_size = 64
	label.pixel_size = 0.02
	label.outline_size = 0
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = Vector3(0, 6.0, 0.17)
	gate.add_child(label)


# ---------------------------------------------------------------- props

func _place_obstacles(rng: RandomNumberGenerator, d0: float, data: Dictionary,
		trees: Array[Transform3D], snowmen: Array[Transform3D]) -> void:
	var d := maxf(d0, 60.0) + rng.randf_range(0.0, 8.0)
	while d < d0 + CHUNK_LEN:
		# Gets busier the further you go, up to each level's cap.
		if finish_d > 0.0 and d > finish_d - 8.0:
			break
		var chance := minf(_obstacle_base + EXTRA_OBSTACLES + minf(d / OBSTACLE_RAMP_LEN, _obstacle_ramp), 0.92)
		if rng.randf() < chance:
			var lx := rng.randf_range(-HALF_WIDTH + 2.5, HALF_WIDTH - 2.5)
			if not _near_ramp(d, lx):
				var x := center_x(d) + lx
				var p := Vector3(x, height(x, -d), -d)
				if rng.randf() < 0.6:
					data.obstacles.append({"pos": p, "radius": 0.85, "height": 2.4})
					snowmen.append(Transform3D(Basis(Vector3.UP, rng.randf_range(-0.5, 0.5)), p))
				else:
					var s := rng.randf_range(0.9, 1.2)
					data.obstacles.append({"pos": p, "radius": 1.4 * s, "height": 5.0 * s})
					trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), p))
		d += rng.randf_range(9.0, 16.0)


func _place_scenery(rng: RandomNumberGenerator, c: int, d0: float,
		trees: Array[Transform3D], snowmen: Array[Transform3D]) -> void:
	if _theme == "sky":
		_place_sky_scenery(rng, c, d0, trees, snowmen)
		return
	if _theme == "beach" or _theme == "city" or _final:
		return   # their scenery is placed by their own extras functions
	var d := d0
	while d < d0 + CHUNK_LEN:
		for side in [-1.0, 1.0]:
			if rng.randf() < _scenery_density:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var lx: float = side * (HALF_WIDTH + 3.0 + pow(rng.randf(), 1.6) * 100.0)
				var x := center_x(dd) + lx
				var s := rng.randf_range(0.8, 1.7)
				trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(x, height(x, -dd) - 0.2, -dd)))
			if rng.randf() < 0.05 and d > 0.0:
				var x2: float = center_x(d) + side * (HALF_WIDTH + 2.0)
				snowmen.append(Transform3D(Basis(Vector3.UP, -side * 0.6), Vector3(x2, height(x2, -d), -d)))
		d += 4.5


func _near_obstacle(data: Dictionary, p: Vector3) -> bool:
	for o in data.obstacles:
		if Vector2(p.x - o.pos.x, p.z - o.pos.z).length() < o.radius + 2.0:
			return true
	return false


func _place_gifts(rng: RandomNumberGenerator, d0: float, data: Dictionary, parent: Node3D) -> void:
	var d := maxf(d0, 80.0) + rng.randf_range(0.0, 20.0)
	while d < d0 + CHUNK_LEN - 16.0:
		if rng.randf() < 0.75:
			var lx0 := rng.randf_range(-HALF_WIDTH + 4.0, HALF_WIDTH - 4.0)
			var drift := rng.randf_range(-1.2, 1.2)
			for k in 5:
				var dd := d + k * 4.0
				var lx := clampf(lx0 + drift * k, -HALF_WIDTH + 2.0, HALF_WIDTH - 2.0)
				var x := center_x(dd) + lx
				var p := Vector3(x, height(x, -dd) + 0.9, -dd)
				if _ramp_height(dd, lx) <= 0.0 and not _near_obstacle(data, p):
					_add_gift(parent, data, p)
		d += rng.randf_range(35.0, 60.0)


func _add_gift(parent: Node3D, data: Dictionary, p: Vector3) -> void:
	var mi := _add_mesh(parent, _gift_mesh, _gift_mat, p)
	data.gifts.append({"node": mi, "pos": p, "taken": false})


func _add_mesh(parent: Node3D, mesh: Mesh, material: Material, p: Vector3) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = material
	mi.position = p
	parent.add_child(mi)
	return mi


func _add_multimesh(parent: Node3D, mesh: Mesh, xforms: Array[Transform3D], material: Material = null) -> void:
	if xforms.is_empty():
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = mesh
	mm.instance_count = xforms.size()
	for i in xforms.size():
		mm.set_instance_transform(i, xforms[i])
	var mmi := MultiMeshInstance3D.new()
	mmi.multimesh = mm
	mmi.material_override = material if material else MeshUtil.vertex_color_material()
	parent.add_child(mmi)


func _build_shared_meshes() -> void:
	if _theme == "desert":
		_build_desert_meshes()
	elif _theme == "sky":
		_build_sky_meshes()
	elif _theme == "beach":
		_build_beach_meshes()
	elif _theme == "city":
		_build_city_meshes()
	elif _final:
		_final.build_meshes()
	else:
		_build_snow_meshes()
	var red := Color(0.9, 0.1, 0.2)
	var gold := Color(1.0, 0.85, 0.2)
	_gift_mesh = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(0.8, 0.8, 0.8)), MeshUtil.at(Vector3.ZERO), red],
		[MeshUtil.box(Vector3(0.84, 0.84, 0.18)), MeshUtil.at(Vector3.ZERO), gold],
		[MeshUtil.box(Vector3(0.18, 0.84, 0.84)), MeshUtil.at(Vector3.ZERO), gold],
		[MeshUtil.box(Vector3(0.35, 0.18, 0.1)), MeshUtil.at(Vector3(-0.12, 0.48, 0), Basis(Vector3.FORWARD, 0.6)), gold],
		[MeshUtil.box(Vector3(0.35, 0.18, 0.1)), MeshUtil.at(Vector3(0.12, 0.48, 0), Basis(Vector3.FORWARD, -0.6)), gold],
	])
	_flag_mesh = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.06, 0.06, 1.8, 6), MeshUtil.at(Vector3(0, 0.9, 0)), Color(0.95, 0.95, 1.0)],
		[MeshUtil.box(Vector3(0.03, 0.4, 0.6)), MeshUtil.at(Vector3(0, 1.55, 0.3)), Color(1.0, 0.45, 0.05)],
	])


## Desert props: saguaro cacti take the place of trees, sandstone boulders replace snowmen.
func _build_desert_meshes() -> void:
	var green := Color(0.16, 0.55, 0.22)
	var light := Color(0.24, 0.66, 0.28)
	var flower := Color(1.0, 0.35, 0.55)
	_tree_mesh = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.38, 0.42, 4.6, 8), MeshUtil.at(Vector3(0, 2.3, 0)), green],
		[MeshUtil.sphere(0.38, 8), MeshUtil.at(Vector3(0, 4.6, 0)), light],
		# left arm: out, then up
		[MeshUtil.box(Vector3(1.1, 0.5, 0.5)), MeshUtil.at(Vector3(-0.75, 2.0, 0)), green],
		[MeshUtil.cylinder(0.25, 0.27, 1.6, 8), MeshUtil.at(Vector3(-1.2, 2.75, 0)), green],
		[MeshUtil.sphere(0.25, 8), MeshUtil.at(Vector3(-1.2, 3.55, 0)), light],
		# right arm, a bit higher and shorter
		[MeshUtil.box(Vector3(0.9, 0.45, 0.45)), MeshUtil.at(Vector3(0.65, 2.8, 0)), green],
		[MeshUtil.cylinder(0.22, 0.24, 1.1, 8), MeshUtil.at(Vector3(1.0, 3.3, 0)), green],
		[MeshUtil.sphere(0.22, 8), MeshUtil.at(Vector3(1.0, 3.85, 0)), light],
		[MeshUtil.sphere(0.12, 6), MeshUtil.at(Vector3(0, 5.0, 0)), flower],
	])
	var stone := Color(0.78, 0.46, 0.3)
	var dark := Color(0.6, 0.32, 0.22)
	_snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(0.95), MeshUtil.at(Vector3(0, 0.55, 0), Basis.from_scale(Vector3(1.0, 0.75, 0.9))), stone],
		[MeshUtil.sphere(0.6), MeshUtil.at(Vector3(0.55, 0.4, 0.35), Basis.from_scale(Vector3(1.0, 0.7, 1.0))), dark],
		[MeshUtil.sphere(0.5), MeshUtil.at(Vector3(-0.2, 1.15, -0.1)), stone],
	])


func _build_snow_meshes() -> void:
	var trunk := Color(0.45, 0.2, 0.15)
	_tree_mesh = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(0.6, 1.2, 0.6)), MeshUtil.at(Vector3(0, 0.6, 0)), trunk],
		[MeshUtil.box(Vector3(3.2, 1.3, 3.2)), MeshUtil.at(Vector3(0, 1.75, 0)), Color(0.04, 0.72, 0.3)],
		[MeshUtil.box(Vector3(2.4, 1.2, 2.4)), MeshUtil.at(Vector3(0, 2.95, 0), Basis(Vector3.UP, 0.35)), Color(0.07, 0.8, 0.34)],
		[MeshUtil.box(Vector3(1.5, 1.1, 1.5)), MeshUtil.at(Vector3(0, 4.05, 0), Basis(Vector3.UP, 0.7)), Color(0.1, 0.87, 0.4)],
		[MeshUtil.box(Vector3(0.9, 0.35, 0.9)), MeshUtil.at(Vector3(0, 4.75, 0), Basis(Vector3.UP, 0.7)), Color(0.97, 0.98, 1.0)],
	])
	var white := Color(0.96, 0.97, 1.0)
	var black := Color(0.05, 0.05, 0.08)
	_snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(0.55), MeshUtil.at(Vector3(0, 0.5, 0)), white],
		[MeshUtil.sphere(0.4), MeshUtil.at(Vector3(0, 1.25, 0)), white],
		[MeshUtil.sphere(0.28), MeshUtil.at(Vector3(0, 1.82, 0)), white],
		[MeshUtil.cylinder(0.32, 0.32, 0.04), MeshUtil.at(Vector3(0, 2.04, 0)), black],
		[MeshUtil.cylinder(0.2, 0.2, 0.36), MeshUtil.at(Vector3(0, 2.24, 0)), black],
		[MeshUtil.cylinder(0.0, 0.05, 0.3, 6), MeshUtil.at(Vector3(0, 1.8, 0.38), Basis(Vector3.RIGHT, PI * 0.5)), Color(1.0, 0.5, 0.1)],
		[MeshUtil.sphere(0.04, 6), MeshUtil.at(Vector3(-0.1, 1.9, 0.24)), black],
		[MeshUtil.sphere(0.04, 6), MeshUtil.at(Vector3(0.1, 1.9, 0.24)), black],
		[MeshUtil.sphere(0.05, 6), MeshUtil.at(Vector3(0, 1.35, 0.39)), black],
		[MeshUtil.sphere(0.05, 6), MeshUtil.at(Vector3(0, 1.15, 0.38)), black],
	])


# ---------------------------------------------------------------- sky islands theme

var _island_meshes: Array[Mesh] = []
var _island_mat: Material
var _cloud_mesh: Mesh


## Sky Islands props: Bao-style gum trees (white trunks, round green canopies) in place of
## pine trees, mossy boulders in place of snowmen, plus floating islands and clouds.
func _build_sky_meshes() -> void:
	var bark := Color(0.93, 0.9, 0.84)
	var bark_dark := Color(0.7, 0.66, 0.6)
	var leaf := Color(0.18, 0.62, 0.22)
	var leaf_hi := Color(0.32, 0.78, 0.3)
	_tree_mesh = MeshUtil.merge_parts([
		[MeshUtil.cylinder(0.22, 0.34, 3.6, 7), MeshUtil.at(Vector3(0, 1.8, 0)), bark],
		[MeshUtil.cylinder(0.1, 0.16, 1.6, 6), MeshUtil.at(Vector3(0.55, 3.6, 0), Basis(Vector3.FORWARD, -0.6)), bark_dark],
		[MeshUtil.cylinder(0.1, 0.16, 1.5, 6), MeshUtil.at(Vector3(-0.5, 3.8, 0.2), Basis(Vector3.FORWARD, 0.55)), bark_dark],
		[MeshUtil.sphere(1.5, 8), MeshUtil.at(Vector3(0, 4.9, 0), Basis.from_scale(Vector3(1.2, 0.8, 1.2))), leaf],
		[MeshUtil.sphere(1.1, 8), MeshUtil.at(Vector3(1.1, 4.4, 0.3), Basis.from_scale(Vector3(1.1, 0.75, 1.1))), leaf_hi],
		[MeshUtil.sphere(1.0, 8), MeshUtil.at(Vector3(-1.0, 4.6, -0.4), Basis.from_scale(Vector3(1.1, 0.75, 1.1))), leaf_hi],
	])
	var stone := Color(0.66, 0.62, 0.56)
	var stone_dark := Color(0.48, 0.45, 0.42)
	var moss := Color(0.3, 0.7, 0.25)
	_snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(0.95), MeshUtil.at(Vector3(0, 0.6, 0), Basis.from_scale(Vector3(1.0, 0.8, 0.9))), stone],
		[MeshUtil.sphere(0.62), MeshUtil.at(Vector3(0.6, 0.4, 0.3), Basis.from_scale(Vector3(1.0, 0.7, 1.0))), stone_dark],
		[MeshUtil.sphere(0.7), MeshUtil.at(Vector3(-0.05, 1.08, 0), Basis.from_scale(Vector3(1.1, 0.35, 1.0))), moss],
	])
	# floating islands: grassy top, rocky underside tapering to a point, a few gum trees
	var grass := Color(0.26, 0.86, 0.22)
	var lip := Color(0.16, 0.64, 0.18)
	var rock := Color(0.82, 0.64, 0.46)
	var rock_dark := Color(0.6, 0.44, 0.32)
	# a little self-glow so the far islands don't sink into the haze
	_island_mat = MeshUtil.ps1_material(Color(0.26, 0.3, 0.24), 1.0)
	for v in 3:
		var parts := [
			[MeshUtil.cylinder(1.0, 0.98, 0.25, 10), MeshUtil.at(Vector3(0, 0.0, 0)), grass],
			[MeshUtil.cylinder(1.0, 0.92, 0.25, 10), MeshUtil.at(Vector3(0, -0.25, 0)), lip],
			[MeshUtil.cylinder(0.92, 0.45, 0.9, 9), MeshUtil.at(Vector3(0, -0.82, 0)), rock],
			[MeshUtil.cylinder(0.45, 0.04, 1.1 + v * 0.35, 7), MeshUtil.at(Vector3(0.05 * v, -1.8 - v * 0.17, 0)), rock_dark],
			[MeshUtil.cylinder(0.3, 0.02, 0.8, 6), MeshUtil.at(Vector3(0.5, -1.3, 0.2)), rock_dark],
		]
		var tree_spots := [[Vector3(0.3, 0.12, 0.2), 0.16], [Vector3(-0.4, 0.12, -0.15), 0.12], [Vector3(0.1, 0.12, -0.5), 0.1]]
		for t in range(v + 1):
			var ts: Array = tree_spots[t]
			var p: Vector3 = ts[0]
			var s: float = ts[1]
			parts.append([MeshUtil.cylinder(0.25 * s, 0.35 * s, 3.6 * s, 6), MeshUtil.at(p + Vector3(0, 1.8 * s, 0)), Color(0.93, 0.9, 0.84)])
			parts.append([MeshUtil.sphere(1.5 * s, 7), MeshUtil.at(p + Vector3(0, 4.6 * s, 0)), leaf])
		_island_meshes.append(MeshUtil.merge_parts(parts))
	var white := Color(1.0, 1.0, 1.0)
	var shade := Color(0.86, 0.9, 0.98)
	_cloud_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(1.0, 8), MeshUtil.at(Vector3(0, 0, 0), Basis.from_scale(Vector3(1.4, 0.7, 1.0))), white],
		[MeshUtil.sphere(0.8, 8), MeshUtil.at(Vector3(1.2, -0.1, 0.2), Basis.from_scale(Vector3(1.2, 0.65, 1.0))), shade],
		[MeshUtil.sphere(0.75, 8), MeshUtil.at(Vector3(-1.2, -0.05, -0.1), Basis.from_scale(Vector3(1.2, 0.65, 1.0))), shade],
		[MeshUtil.sphere(0.6, 8), MeshUtil.at(Vector3(0.4, 0.45, -0.1)), white],
	])


## Trees only along the grassy shoulder (past it the island drops away), plus the odd boulder.
func _place_sky_scenery(rng: RandomNumberGenerator, c: int, d0: float,
		trees: Array[Transform3D], snowmen: Array[Transform3D]) -> void:
	var d := d0
	while d < d0 + CHUNK_LEN:
		for side in [-1.0, 1.0]:
			if rng.randf() < _scenery_density * 0.7:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var x: float = center_x(dd) + side * (HALF_WIDTH + rng.randf_range(1.2, 3.2))
				var s := rng.randf_range(0.8, 1.3)
				trees.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
					Vector3(x, height(x, -dd) - 0.2, -dd)))
			if rng.randf() < 0.05 and d > 0.0:
				var x2: float = center_x(d) + side * (HALF_WIDTH + 2.0)
				snowmen.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x2, height(x2, -d), -d)))
		d += 4.5


## Floating islands at every distance on both sides, and clouds drifting below the track.
func _add_sky_extras(rng: RandomNumberGenerator, c: int, d0: float, node: Node3D) -> void:
	var by_variant: Array = [[], [], []]
	var clouds: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		# nearby islands, just past the cliffs
		for i in 2:
			if rng.randf() > 0.7:
				continue
			var dd := d0 + rng.randf_range(0.0, CHUNK_LEN)
			var lx: float = side * rng.randf_range(HALF_WIDTH + 24.0, HALF_WIDTH + 75.0)
			var y := base_height(dd) + rng.randf_range(-12.0, 10.0)
			var s := rng.randf_range(6.0, 13.0)
			by_variant[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(center_x(dd) + lx, y, -dd)))
		# big ones further out, at all heights
		for i in 3:
			var dd := d0 + rng.randf_range(0.0, CHUNK_LEN)
			var lx: float = side * rng.randf_range(95.0, 300.0)
			var y := base_height(dd) + rng.randf_range(-55.0, 40.0)
			var s := rng.randf_range(14.0, 32.0)
			by_variant[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(center_x(dd) + lx, y, -dd)))
		# clouds below the island
		for i in 3:
			var dd := d0 + rng.randf_range(0.0, CHUNK_LEN)
			var lx: float = side * rng.randf_range(HALF_WIDTH + 10.0, 260.0)
			var y := base_height(dd) - rng.randf_range(22.0, 70.0)
			var s := rng.randf_range(6.0, 16.0)
			clouds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
				Vector3(center_x(dd) + lx, y, -dd)))
	for v in 3:
		var xf: Array[Transform3D] = []
		xf.assign(by_variant[v])
		_add_multimesh(node, _island_meshes[v], xf, _island_mat)
	_add_multimesh(node, _cloud_mesh, clouds)


# ---------------------------------------------------------------- beach theme

var _palm_mesh: Mesh
var _umbrella_mesh: Mesh
var _arch_mesh: Mesh
var _islet_meshes: Array[Mesh] = []
var _beach_glow_mat: Material


func _palm_parts(base: Vector3, height_m: float, lean: float, yaw: float) -> Array:
	## A curved palm: trunk segments leaning more towards the top, a crown of fronds, coconuts.
	var trunk := Color(0.7, 0.54, 0.34)
	var trunk_dark := Color(0.56, 0.42, 0.26)
	var frond := Color(0.08, 0.5, 0.14)
	var frond_hi := Color(0.18, 0.66, 0.2)
	var parts := []
	var p := base
	var dirv := Vector3(sin(yaw), 0, cos(yaw))
	var segs := 6
	for i in segs:
		var t := float(i) / segs
		var step := Vector3.UP * (height_m / segs) + dirv * lean * (height_m / segs) * t * 1.6
		var mid := p + step * 0.5
		var b := Basis.looking_at(step.normalized(), dirv if absf(step.normalized().y) > 0.99 else Vector3.UP)
		b = b * Basis(Vector3.RIGHT, PI * 0.5)
		parts.append([MeshUtil.cylinder(0.17 - t * 0.05, 0.2 - t * 0.05, step.length() * 1.05, 6), Transform3D(b, mid), trunk if i % 2 == 0 else trunk_dark])
		p += step
	for k in 7:
		var a := k * TAU / 7.0
		var out := Vector3(cos(a), 0, sin(a))
		var fb := Basis.looking_at(out, Vector3.UP) * Basis(Vector3.RIGHT, -0.35)
		parts.append([MeshUtil.box(Vector3(0.5, 0.06, 2.4)), Transform3D(fb, p + out * 1.1 - Vector3(0, 0.25, 0)), frond if k % 2 == 0 else frond_hi])
	for k in 3:
		var a := k * TAU / 3.0 + 0.5
		parts.append([MeshUtil.sphere(0.16, 6), MeshUtil.at(p + Vector3(cos(a) * 0.22, -0.3, sin(a) * 0.22)), Color(0.42, 0.28, 0.14)])
	return parts


func _build_beach_meshes() -> void:
	_palm_mesh = MeshUtil.merge_parts(_palm_parts(Vector3.ZERO, 6.5, 0.35, 0.0))
	# obstacles: an islet of sand with a palm stands in for trees, a buoy for snowmen
	var sand := Color(0.95, 0.86, 0.62)
	var rock := Color(0.62, 0.58, 0.52)
	var parts := [
		[MeshUtil.sphere(1.6, 9), MeshUtil.at(Vector3(0, -0.6, 0), Basis.from_scale(Vector3(1.0, 0.45, 1.0))), sand],
		[MeshUtil.sphere(0.6, 7), MeshUtil.at(Vector3(0.7, 0.0, 0.4)), rock],
	]
	parts.append_array(_palm_parts(Vector3(-0.2, 0.0, 0), 5.0, 0.4, 1.0))
	_tree_mesh = MeshUtil.merge_parts(parts)
	var red := Color(0.95, 0.15, 0.15)
	var white := Color(0.97, 0.97, 0.97)
	_snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(0.7, 9), MeshUtil.at(Vector3(0, 0.25, 0), Basis.from_scale(Vector3(1.0, 0.7, 1.0))), red],
		[MeshUtil.cylinder(0.72, 0.72, 0.22, 10), MeshUtil.at(Vector3(0, 0.45, 0)), white],
		[MeshUtil.cylinder(0.08, 0.1, 1.5, 6), MeshUtil.at(Vector3(0, 1.3, 0)), white],
		[MeshUtil.sphere(0.2, 6), MeshUtil.at(Vector3(0, 2.1, 0)), red],
	])
	# beach umbrella
	var stripe_a := Color(1.0, 0.45, 0.15)
	var stripe_b := Color(1.0, 0.95, 0.85)
	var up := [[MeshUtil.cylinder(0.05, 0.05, 2.4, 6), MeshUtil.at(Vector3(0, 1.2, 0)), white]]
	for k in 8:
		var a := k * TAU / 8.0
		var b := Basis(Vector3.UP, a) * Basis(Vector3.RIGHT, 0.35)
		up.append([MeshUtil.box(Vector3(0.9, 0.05, 1.3)), Transform3D(b, Vector3(sin(a) * 0.6, 2.3, cos(a) * 0.6)), stripe_a if k % 2 == 0 else stripe_b])
	up.append([MeshUtil.box(Vector3(0.9, 0.08, 1.8)), MeshUtil.at(Vector3(0.9, 0.05, 0.4)), Color(0.3, 0.6, 1.0)])   # towel
	_umbrella_mesh = MeshUtil.merge_parts(up)
	# rock arch over the track (like the arches in those early-2000s beach levels)
	var ra := Color(0.72, 0.6, 0.48)
	var rb := Color(0.6, 0.48, 0.38)
	var moss := Color(0.3, 0.62, 0.25)
	var span := HALF_WIDTH + 5.0
	var arch := []
	for side in [-1.0, 1.0]:
		arch.append([MeshUtil.box(Vector3(4.5, 18.0, 5.0)), MeshUtil.at(Vector3(side * span, 5.0, 0)), ra])
		arch.append([MeshUtil.box(Vector3(5.5, 4.0, 6.0)), MeshUtil.at(Vector3(side * span, -2.0, 0.3)), rb])
	var n := 12
	for i in n:
		var t0 := float(i) / n
		var t1 := float(i + 1) / n
		var a0 := PI * t0
		var a1 := PI * t1
		var p0 := Vector3(-cos(a0) * span, 13.0 + sin(a0) * 6.0, 0)
		var p1 := Vector3(-cos(a1) * span, 13.0 + sin(a1) * 6.0, 0)
		var mid := (p0 + p1) * 0.5
		var dir := (p1 - p0).normalized()
		var b := Basis(dir, Vector3(0, 0, 1).cross(dir), Vector3(0, 0, 1))
		arch.append([MeshUtil.box(Vector3((p1 - p0).length() + 0.6, 3.6, 4.6)), Transform3D(b, mid), ra if i % 2 == 0 else rb])
		if i % 3 == 1:
			arch.append([MeshUtil.box(Vector3(2.0, 0.6, 3.0)), Transform3D(b, mid + Vector3(0, 1.9, 0)), moss])
	_arch_mesh = MeshUtil.merge_parts(arch)
	# little tropical islands out at sea: a sand dome with palms, some with a big rock
	var green := Color(0.12, 0.5, 0.14)
	for v in 3:
		var ip := [[MeshUtil.sphere(1.0, 10), MeshUtil.at(Vector3(0, -0.15, 0), Basis.from_scale(Vector3(1.0, 0.22, 1.0))), sand]]
		if v >= 1:
			ip.append([MeshUtil.sphere(0.45, 8), MeshUtil.at(Vector3(0.25, 0.25, 0.1), Basis.from_scale(Vector3(1.0, 1.4, 0.9))), rock])
			ip.append([MeshUtil.sphere(0.36, 8), MeshUtil.at(Vector3(0.25, 0.75, 0.1), Basis.from_scale(Vector3(1.0, 0.5, 0.9))), green])
		if v == 2:
			ip.append([MeshUtil.cylinder(0.3, 0.5, 1.4, 7), MeshUtil.at(Vector3(-0.3, 0.6, -0.2)), rock])
			ip.append([MeshUtil.sphere(0.4, 8), MeshUtil.at(Vector3(-0.3, 1.35, -0.2), Basis.from_scale(Vector3(1.1, 0.5, 1.1))), green])
		for k in v + 2:
			var a := k * 2.1 + v
			for part in _palm_parts(Vector3(cos(a) * 0.45, 0.05, sin(a) * 0.45), 0.6, 0.4, a):
				ip.append(part)
		_islet_meshes.append(MeshUtil.merge_parts(ip))
	_beach_glow_mat = MeshUtil.ps1_material(Color(0.25, 0.28, 0.25), 0.8)
	_cloud_mesh = MeshUtil.merge_parts([
		[MeshUtil.sphere(1.0, 8), MeshUtil.at(Vector3(0, 0, 0), Basis.from_scale(Vector3(1.4, 0.7, 1.0))), Color(1, 1, 1)],
		[MeshUtil.sphere(0.8, 8), MeshUtil.at(Vector3(1.2, -0.1, 0.2), Basis.from_scale(Vector3(1.2, 0.65, 1.0))), Color(0.92, 0.95, 1.0)],
		[MeshUtil.sphere(0.75, 8), MeshUtil.at(Vector3(-1.2, -0.05, -0.1), Basis.from_scale(Vector3(1.2, 0.65, 1.0))), Color(0.92, 0.95, 1.0)],
	])


func _add_beach_extras(rng: RandomNumberGenerator, c: int, d0: float, node: Node3D) -> void:
	var palms: Array[Transform3D] = []
	var umbrellas: Array[Transform3D] = []
	var islets: Array = [[], [], []]
	var clouds: Array[Transform3D] = []
	var d := d0
	while d < d0 + CHUNK_LEN:
		for side in [-1.0, 1.0]:
			# palms: along the sea-side berm, and all over the dunes on the land side
			var chance := 0.35 if side < 0.0 else 0.75
			if rng.randf() < chance:
				var dd := d + rng.randf_range(-2.0, 2.0)
				var e := rng.randf_range(1.5, 5.0) if side < 0.0 else rng.randf_range(2.0, 32.0)
				var x: float = center_x(dd) + side * (HALF_WIDTH + e)
				var s := rng.randf_range(0.8, 1.35)
				palms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), Vector3(x, height(x, -dd) - 0.2, -dd)))
			if side > 0.0 and rng.randf() < 0.08:
				var dd2 := d + rng.randf_range(-2.0, 2.0)
				var x2: float = center_x(dd2) + HALF_WIDTH + rng.randf_range(2.5, 7.0)
				umbrellas.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU), Vector3(x2, height(x2, -dd2), -dd2)))
		d += 4.5
	# islands out at sea (sea side), near and far
	for i in 4:
		var dd := d0 + rng.randf_range(0.0, CHUNK_LEN)
		var far := i >= 2
		var lx := -(HALF_WIDTH + (rng.randf_range(90.0, 320.0) if far else rng.randf_range(30.0, 80.0)))
		var s := rng.randf_range(14.0, 30.0) if far else rng.randf_range(5.0, 11.0)
		islets[rng.randi() % 3].append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s),
			Vector3(center_x(dd) + lx, base_height(dd) + SEA_DEPTH, -dd)))
	# a few clouds over the sea
	for i in 2:
		var dd := d0 + rng.randf_range(0.0, CHUNK_LEN)
		clouds.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * rng.randf_range(8.0, 16.0)),
			Vector3(center_x(dd) - rng.randf_range(60.0, 300.0), base_height(dd) + rng.randf_range(35.0, 70.0), -dd)))
	_add_multimesh(node, _palm_mesh, palms)
	_add_multimesh(node, _umbrella_mesh, umbrellas)
	for v in 3:
		var xf: Array[Transform3D] = []
		xf.assign(islets[v])
		_add_multimesh(node, _islet_meshes[v], xf, _beach_glow_mat)
	_add_multimesh(node, _cloud_mesh, clouds)
	# now and then a rock arch spans the track
	if c >= 1 and rng.randf() < 0.4:
		var ad := d0 + rng.randf_range(20.0, CHUNK_LEN - 20.0)
		if not _near_ramp(ad, 0.0):
			var cx := center_x(ad)
			var arch := MeshInstance3D.new()
			arch.mesh = _arch_mesh
			arch.material_override = MeshUtil.vertex_color_material()
			arch.position = Vector3(cx, base_height(ad), -ad)
			arch.rotation.y = track_yaw(ad)
			node.add_child(arch)


# ---------------------------------------------------------------- neon city theme

var _prop_mat: Material                  # unlit neon material for the obstacles (null = normal)
var _tower_mat: Material
var _tower_meshes: Array[Mesh] = []
var _gantry_mesh: Mesh
var _sign_mesh: Mesh
var _cars: Array[Dictionary] = []


func _neon(c: Color, phase: float) -> Color:
	## Vertex alpha below 1 marks a part as a neon tube for ps1_city.gdshader.
	return Color(c.r, c.g, c.b, clampf(phase, 0.02, 0.9))


func _build_city_meshes() -> void:
	var city_shader: Shader = load("res://shaders/ps1_city.gdshader")
	var prop := ShaderMaterial.new()
	prop.shader = city_shader
	_prop_mat = prop
	var tower := ShaderMaterial.new()
	tower.shader = city_shader
	tower.set_shader_parameter("windows", true)
	_tower_mat = tower

	var pink := Color(1.0, 0.08, 0.62)
	var cyan := Color(0.08, 0.92, 1.0)
	var violet := Color(0.55, 0.2, 1.0)
	var amber := Color(1.0, 0.62, 0.08)
	var steel := Color(0.11, 0.11, 0.2)
	var dark := Color(0.05, 0.05, 0.1)

	# Towers are unit-sized and stretched per instance: base at y = 0, top at y = 1.
	_tower_meshes.append(MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(1, 1, 1)), MeshUtil.at(Vector3(0, 0.5, 0)), Color(0.045, 0.045, 0.09)],
		[MeshUtil.box(Vector3(0.025, 1, 0.025)), MeshUtil.at(Vector3(-0.5, 0.5, 0.5)), _neon(cyan, 0.2)],
		[MeshUtil.box(Vector3(0.025, 1, 0.025)), MeshUtil.at(Vector3(0.5, 0.5, 0.5)), _neon(cyan, 0.2)],
		[MeshUtil.box(Vector3(1.02, 0.012, 1.02)), MeshUtil.at(Vector3(0, 0.97, 0)), _neon(pink, 0.5)],
	]))
	_tower_meshes.append(MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(1, 0.62, 1)), MeshUtil.at(Vector3(0, 0.31, 0)), Color(0.06, 0.04, 0.1)],
		[MeshUtil.box(Vector3(0.72, 0.26, 0.72)), MeshUtil.at(Vector3(0, 0.75, 0)), Color(0.05, 0.05, 0.11)],
		[MeshUtil.box(Vector3(0.44, 0.12, 0.44)), MeshUtil.at(Vector3(0, 0.94, 0)), Color(0.07, 0.05, 0.12)],
		[MeshUtil.box(Vector3(1.02, 0.01, 1.02)), MeshUtil.at(Vector3(0, 0.615, 0)), _neon(violet, 0.35)],
		[MeshUtil.box(Vector3(0.74, 0.01, 0.74)), MeshUtil.at(Vector3(0, 0.875, 0)), _neon(pink, 0.65)],
		[MeshUtil.box(Vector3(0.46, 0.01, 0.46)), MeshUtil.at(Vector3(0, 0.995, 0)), _neon(cyan, 0.8)],
	]))
	_tower_meshes.append(MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(1, 0.9, 0.72)), MeshUtil.at(Vector3(0, 0.45, 0)), Color(0.04, 0.06, 0.11)],
		[MeshUtil.box(Vector3(0.07, 0.86, 0.74)), MeshUtil.at(Vector3(-0.2, 0.47, 0)), _neon(amber, 0.12)],
		[MeshUtil.box(Vector3(0.7, 0.05, 0.5)), MeshUtil.at(Vector3(0, 0.925, 0)), dark],
		[MeshUtil.box(Vector3(0.72, 0.008, 0.52)), MeshUtil.at(Vector3(0, 0.95, 0)), _neon(cyan, 0.45)],
		[MeshUtil.box(Vector3(0.012, 0.1, 0.012)), MeshUtil.at(Vector3(0.2, 1.0, 0)), _neon(pink, 0.7)],
	]))

	# Obstacle: a data pylon, in the trees' slot (radius 1.4, about 5 m tall).
	var pylon := [
		[MeshUtil.cylinder(1.25, 1.4, 0.7, 6), MeshUtil.at(Vector3(0, 0.35, 0)), steel],
		[MeshUtil.cylinder(1.3, 1.3, 0.08, 6), MeshUtil.at(Vector3(0, 0.74, 0)), _neon(pink, 0.3)],
		[MeshUtil.cylinder(0.5, 0.7, 3.7, 6), MeshUtil.at(Vector3(0, 2.6, 0)), dark],
		[MeshUtil.cylinder(0.14, 0.14, 4.1, 6), MeshUtil.at(Vector3(0.45, 2.75, 0)), _neon(cyan, 0.15)],
		[MeshUtil.cylinder(0.14, 0.14, 4.1, 6), MeshUtil.at(Vector3(-0.45, 2.75, 0)), _neon(cyan, 0.15)],
		[MeshUtil.cylinder(0.92, 0.92, 0.1, 8), MeshUtil.at(Vector3(0, 2.1, 0)), _neon(cyan, 0.5)],
		[MeshUtil.cylinder(0.78, 0.78, 0.1, 8), MeshUtil.at(Vector3(0, 3.3, 0)), _neon(pink, 0.6)],
		[MeshUtil.sphere(0.38, 7), MeshUtil.at(Vector3(0, 4.9, 0)), _neon(Color(1, 1, 1), 0.8)],
	]
	_tree_mesh = MeshUtil.merge_parts(pylon)
	# Obstacle: a glowing vending machine, in the snowmen's slot (radius 0.85, 2.4 m tall).
	_snowman_mesh = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(1.5, 2.3, 1.05)), MeshUtil.at(Vector3(0, 1.15, 0)), Color(0.13, 0.05, 0.2)],
		[MeshUtil.box(Vector3(1.22, 1.3, 0.06)), MeshUtil.at(Vector3(0, 1.42, 0.53)), _neon(cyan, 0.25)],
		[MeshUtil.box(Vector3(1.05, 0.05, 0.08)), MeshUtil.at(Vector3(0, 1.72, 0.55)), Color(0.04, 0.05, 0.12)],
		[MeshUtil.box(Vector3(1.05, 0.05, 0.08)), MeshUtil.at(Vector3(0, 1.32, 0.55)), Color(0.04, 0.05, 0.12)],
		[MeshUtil.box(Vector3(1.26, 0.2, 0.08)), MeshUtil.at(Vector3(0, 2.14, 0.53)), _neon(pink, 0.55)],
		[MeshUtil.box(Vector3(0.9, 0.24, 0.06)), MeshUtil.at(Vector3(0, 0.34, 0.53)), Color(0.02, 0.02, 0.05)],
		[MeshUtil.box(Vector3(0.14, 0.14, 0.07)), MeshUtil.at(Vector3(0.48, 0.66, 0.54)), _neon(amber, 0.7)],
	])

	# A steel gantry over the highway, lined with neon.
	var span := HALF_WIDTH + 1.7
	_gantry_mesh = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(1.1, 14.0, 1.1)), MeshUtil.at(Vector3(-span, 5.0, 0)), steel],
		[MeshUtil.box(Vector3(1.1, 14.0, 1.1)), MeshUtil.at(Vector3(span, 5.0, 0)), steel],
		[MeshUtil.box(Vector3(span * 2.0 + 1.1, 1.3, 1.2)), MeshUtil.at(Vector3(0, 11.2, 0)), steel],
		[MeshUtil.box(Vector3(span * 2.0 + 1.1, 0.14, 1.25)), MeshUtil.at(Vector3(0, 10.55, 0)), _neon(cyan, 0.3)],
		[MeshUtil.box(Vector3(span * 2.0 + 1.1, 0.14, 1.25)), MeshUtil.at(Vector3(0, 11.85, 0)), _neon(pink, 0.6)],
		[MeshUtil.box(Vector3(0.14, 10.5, 1.15)), MeshUtil.at(Vector3(-span + 0.56, 5.3, 0)), _neon(pink, 0.6)],
		[MeshUtil.box(Vector3(0.14, 10.5, 1.15)), MeshUtil.at(Vector3(span - 0.56, 5.3, 0)), _neon(pink, 0.6)],
	])

	# Roadside billboard; its words are a Label3D in _add_city_sign.
	_sign_mesh = MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(0.28, 7.0, 0.28)), MeshUtil.at(Vector3(-3.6, 3.5, -0.2)), steel],
		[MeshUtil.box(Vector3(0.28, 7.0, 0.28)), MeshUtil.at(Vector3(3.6, 3.5, -0.2)), steel],
		[MeshUtil.box(Vector3(11.0, 3.4, 0.22)), MeshUtil.at(Vector3(0, 7.8, 0)), Color(0.025, 0.02, 0.06)],
		[MeshUtil.box(Vector3(11.2, 0.12, 0.26)), MeshUtil.at(Vector3(0, 9.55, 0)), _neon(cyan, 0.4)],
		[MeshUtil.box(Vector3(11.2, 0.12, 0.26)), MeshUtil.at(Vector3(0, 6.05, 0)), _neon(cyan, 0.4)],
		[MeshUtil.box(Vector3(0.12, 3.6, 0.26)), MeshUtil.at(Vector3(-5.55, 7.8, 0)), _neon(pink, 0.75)],
		[MeshUtil.box(Vector3(0.12, 3.6, 0.26)), MeshUtil.at(Vector3(5.55, 7.8, 0)), _neon(pink, 0.75)],
	])

	# Flying cars: one small pool that wraps around the rider.
	var car_mesh := MeshUtil.merge_parts([
		[MeshUtil.box(Vector3(2.2, 0.7, 5.0)), MeshUtil.at(Vector3.ZERO), Color(0.09, 0.09, 0.17)],
		[MeshUtil.box(Vector3(1.7, 0.55, 2.3)), MeshUtil.at(Vector3(0, 0.6, 0.3)), Color(0.05, 0.14, 0.24)],
		[MeshUtil.box(Vector3(0.55, 0.2, 0.08)), MeshUtil.at(Vector3(-0.72, 0.05, -2.53)), _neon(Color(1, 1, 0.9), 0.9)],
		[MeshUtil.box(Vector3(0.55, 0.2, 0.08)), MeshUtil.at(Vector3(0.72, 0.05, -2.53)), _neon(Color(1, 1, 0.9), 0.9)],
		[MeshUtil.box(Vector3(2.0, 0.16, 0.08)), MeshUtil.at(Vector3(0, 0.05, 2.53)), _neon(Color(1, 0.05, 0.1), 0.5)],
		[MeshUtil.box(Vector3(1.9, 0.08, 4.5)), MeshUtil.at(Vector3(0, -0.4, 0)), _neon(cyan, 0.2)],
	])
	var rng := RandomNumberGenerator.new()
	rng.seed = SEED + 7
	for i in 16:
		var car := MeshInstance3D.new()
		car.mesh = car_mesh
		car.material_override = _prop_mat
		add_child(car)
		var side := -1.0 if i % 2 == 0 else 1.0
		_cars.append({
			"node": car,
			"lx": side * (HALF_WIDTH + rng.randf_range(7.0, 34.0)),
			"alt": rng.randf_range(9.0, 34.0),
			"dir": 1.0 if rng.randf() < 0.5 else -1.0,
			"speed": rng.randf_range(32.0, 62.0),
			"d": rng.randf_range(-60.0, 480.0),
		})


func _update_traffic(delta: float) -> void:
	for car in _cars:
		var d: float = car.d + car.dir * car.speed * delta
		if d > focus_d + 500.0:
			d -= 590.0
		elif d < focus_d - 90.0:
			d += 590.0
		car.d = d
		var n: MeshInstance3D = car.node
		n.position = Vector3(center_x(d) + car.lx, base_height(d) + car.alt, -d)
		n.rotation.y = track_yaw(d) + (0.0 if car.dir > 0.0 else PI)


func _add_city_extras(rng: RandomNumberGenerator, c: int, d0: float, node: Node3D) -> void:
	var towers: Array = [[], [], []]
	var rows := [9.0, 40.0, 72.0, 112.0, 165.0, 235.0]   # how far each row of towers is from the road
	for side in [-1.0, 1.0]:
		for row in rows.size():
			var dd := d0 + rng.randf_range(0.0, 10.0)
			while dd < d0 + CHUNK_LEN:
				var w := rng.randf_range(14.0, 26.0) + row * 2.0
				var depth := rng.randf_range(14.0, 26.0)
				var tall := rng.randf_range(58.0, 105.0) + row * 16.0
				if rng.randf() < 0.18:
					tall += 60.0
				var mid := dd + depth * 0.5
				var x: float = center_x(mid) + side * (HALF_WIDTH + rows[row] + w * 0.5)
				var b := Basis(Vector3.UP, track_yaw(mid)) * Basis.from_scale(Vector3(w, tall, depth))
				towers[rng.randi() % 3].append(Transform3D(b, Vector3(x, base_height(mid) + CITY_STREET_DEPTH - 3.0, -mid)))
				dd += depth + rng.randf_range(2.0, 8.0)
	for v in 3:
		var xf: Array[Transform3D] = []
		xf.assign(towers[v])
		_add_multimesh(node, _tower_meshes[v], xf, _tower_mat)
	if c < 0:
		return
	for i in 2:
		_add_city_sign(rng, node, d0 + (i + rng.randf()) * CHUNK_LEN * 0.5, -1.0 if rng.randf() < 0.5 else 1.0)
	if c >= 1 and rng.randf() < 0.5:
		var gd := d0 + rng.randf_range(20.0, CHUNK_LEN - 20.0)
		if not _near_ramp(gd, 0.0):
			var cx := center_x(gd)
			var gantry := _add_mesh(node, _gantry_mesh, _prop_mat, Vector3(cx, height(cx, -gd), -gd))
			gantry.rotation.y = track_yaw(gd)


func _add_city_sign(rng: RandomNumberGenerator, node: Node3D, d: float, side: float) -> void:
	var x := center_x(d) + side * (HALF_WIDTH + 3.0)
	var board := _add_mesh(node, _sign_mesh, _prop_mat, Vector3(x, height(x, -d) - 0.1, -d))
	board.rotation.y = track_yaw(d) - side * 0.55   # angled to face the oncoming rider
	var text: String = CITY_SIGNS[rng.randi() % CITY_SIGNS.size()]
	var colors := [Color(1.0, 0.25, 0.75), Color(0.3, 0.95, 1.0), Color(1.0, 0.8, 0.25)]
	var label := Label3D.new()
	label.text = text
	label.font = Screen.pixel_font
	label.font_size = 64
	label.pixel_size = clampf(10.0 / (text.length() * 48.0), 0.012, 0.034)
	label.outline_size = 0
	label.modulate = colors[rng.randi() % colors.size()]
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.position = Vector3(0, 7.8, 0.14)
	board.add_child(label)


## Beach level: the sea carries on far past the edge of the terrain mesh, out to the horizon.
func _far_sea_mesh(parent: Node3D, d0: float) -> void:
	var cols := [-SIDE_EXTENT + 2.0, -400.0, -900.0, -1600.0]
	var steps := 8
	var verts := PackedVector3Array()
	var nrm := PackedVector3Array()
	var col := PackedColorArray()
	for r in steps + 1:
		var d := d0 + CHUNK_LEN * r / steps
		var cx := center_x(d)
		for lx in cols:
			verts.append(Vector3(cx + lx, base_height(d) + SEA_DEPTH - 0.05, -d))
			nrm.append(Vector3.UP)
			col.append(Color(0, 1, 0))
	var idx := PackedInt32Array()
	var n := cols.size()
	for r in steps:
		for j in n - 1:
			var a := r * n + j
			idx.append_array(PackedInt32Array([a, a + n, a + 1, a + 1, a + n, a + n + 1]))
	var arr := []
	arr.resize(Mesh.ARRAY_MAX)
	arr[Mesh.ARRAY_VERTEX] = verts
	arr[Mesh.ARRAY_NORMAL] = nrm
	arr[Mesh.ARRAY_COLOR] = col
	arr[Mesh.ARRAY_INDEX] = idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arr)
	_add_mesh(parent, mesh, _terrain_mat, Vector3.ZERO)
