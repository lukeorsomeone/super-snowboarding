extends RefCounted
## Level definitions and unlocks.
## Each level after the first unlocks once you ride UNLOCK_DISTANCE metres in a single run on
## the level before it. Unlocks and best distances are kept in the save file.

const SAVE_PATH := "user://super_snowboarding.cfg"
const UNLOCK_DISTANCE := 5000.0   # metres in one run
## Slots shown on the level select screen; ones past LEVELS.size() say COMING SOON.
const SLOTS := 8
## Thumbnail screenshots, made with res://tools/capture_level_shots.tscn.
const THUMB_PATH := "res://assets/levels/level_%d.png"

const LEVELS := [
	{
		"name": "WINTER VALLEY",
		# course shape
		"seed": 20251225, "noise_seed": 7, "mtn_seed": 11,
		"slope": 0.24,             # steepness (higher = faster)
		"half_width": 20.0,        # half the width of the fenced track
		"curve_amp": 1.0,          # how far the track swings side to side
		"curve_freq": 1.0,         # how often it turns
		"ramp_chance": 0.6,        # chance of a kicker in each 96 m chunk
		"ramp_h": 2.6,             # kicker height
		"obstacle_base": 0.35,     # obstacle density at the start...
		"obstacle_ramp": 0.3,      # ...plus up to this much more further down
		"gate_color": Color(0.1, 0.45, 1.0),
		# look
		"sky_top": Color(0, 0.04, 0.8),
		"sky_horizon": Color(0.4, 0.55, 1),
		"ground_bottom": Color(0.15, 0.2, 0.5),
		"fog": Color(0.55, 0.65, 1),
		"sun_color": Color(1, 1, 1),
		"sun_energy": 0.85,
		"sun_rot": Vector3(-48.0, 30.0, 0.0),
	},
	{
		"name": "DESERT DUNES",
		"theme": "desert",         # cacti + boulders, sand-coloured ground, no snowfall
		"seed": 777123, "noise_seed": 21, "mtn_seed": 33,
		"slope": 0.29,
		"half_width": 16.0,
		"curve_amp": 1.25,
		"curve_freq": 1.4,
		"ramp_chance": 0.75,
		"ramp_h": 3.2,
		"obstacle_base": 0.42,
		"obstacle_ramp": 0.3,
		"scenery_density": 0.35,   # fewer cacti off the track than trees in the valley
		"gate_color": Color(0.85, 0.3, 0.1),
		# ground: the snow textures are greyed out, then tinted with these
		"desaturate": 1.0,
		"offpiste_tint": Color(1.05, 0.78, 0.48),   # dune sand
		"track_tint": Color(0.95, 0.68, 0.4),      # packed sand on the track
		"rock_tint": Color(1.25, 0.62, 0.4),        # red sandstone
		"ramp_tint": Color(1.0, 0.8, 0.55),
		# look
		"sky_top": Color(0.12, 0.42, 0.95),
		"sky_horizon": Color(1.0, 0.86, 0.62),
		"ground_bottom": Color(0.55, 0.35, 0.2),
		"fog": Color(1.0, 0.85, 0.62),
		"ambient": Color(1.0, 0.84, 0.62),   # warm bounce light off the sand
		"sun_color": Color(1.0, 0.9, 0.72),
		"sun_energy": 0.8,
		"sun_rot": Vector3(-50.0, 40.0, 0.0),
	},
	{
		"name": "SKY ISLANDS",
		"theme": "sky",            # a grassy floating island: cliffs drop away past the fences,
		                           # gum trees + mossy boulders, more islands floating all around
		"seed": 4242001, "noise_seed": 55, "mtn_seed": 66,
		"slope": 0.27,
		"half_width": 17.0,
		"curve_amp": 1.15,
		"curve_freq": 1.2,
		"ramp_chance": 0.8,
		"ramp_h": 3.0,
		"obstacle_base": 0.38,
		"obstacle_ramp": 0.3,
		"scenery_density": 0.5,
		"gate_color": Color(0.55, 0.2, 0.9),
		# ground: textures from Bao: Legend of the Dragonfruit
		# deep meadow off the track, a freshly mown striped lawn down the run, sandy jumps
		"offpiste_tex": "res://assets/textures/sky/sky_meadow.png",
		"track_tex": "res://assets/textures/sky/sky_lawn.png",
		"rock_tex": "res://assets/textures/sky/sky_stone.png",
		"ramp_tex": "res://assets/textures/sky/sky_sand.png",
		"tile_size": 8.0,
		"rock_tile_size": 6.0,
		"offpiste_tint": Color(1.0, 1.0, 1.0),
		"track_tint": Color(1.0, 1.0, 1.0),
		"ramp_tint": Color(1.0, 0.8, 0.55),
		"ramp_tex_tint": Color(1.0, 1.0, 1.0),
		# look: bright open sky above and below
		"sky_top": Color(0.1, 0.36, 0.95),
		"sky_horizon": Color(0.7, 0.88, 1.0),
		"ground_bottom": Color(0.45, 0.68, 1.0),
		"fog": Color(0.66, 0.82, 1.0),
		"fog_scale": 0.3,                          # thinner haze so the far islands show
		"ambient": Color(0.6, 0.66, 0.74),
		"sun_color": Color(1.0, 0.96, 0.88),
		"sun_energy": 0.8,
		"sun_rot": Vector3(-55.0, -30.0, 0.0),
	},
	{
		"name": "CORAL COVE",
		"theme": "beach",          # surf down a turquoise river to the sea: beaches, palms,
		                           # rock arches, tropical islands. Riders swap to swimwear + surfboards.
		"surf": true,
		"music": "res://assets/level_music/sunburned.wav",   # loops instead of the shuffled playlist
		"seed": 8086001, "noise_seed": 77, "mtn_seed": 88,
		"slope": 0.26,
		"half_width": 18.0,
		"curve_amp": 1.1,
		"curve_freq": 1.15,
		"ramp_chance": 0.85,       # kickers are breaking waves
		"ramp_h": 3.0,
		"obstacle_base": 0.36,     # sandy islets with palms + buoys
		"obstacle_ramp": 0.3,
		"gate_color": Color(1.0, 0.55, 0.1),
		# colours from Emerald Coast: royal-blue sea, lush grass, pale sand, dark cliffs
		"offpiste_tex": "res://assets/textures/sky/sky_grass.png",
		"shore_tex": "res://assets/textures/beach/beach_sand.png",
		"track_tex": "res://assets/textures/beach/beach_water_royal.png",
		"rock_tex": "res://assets/textures/beach/beach_rock.png",
		"offpiste_tint": Color(0.72, 0.88, 0.62),
		"shore_tint": Color(1.02, 1.0, 0.94),
		"tile_size": 4.0,
		"rock_tile_size": 5.0,
		"track_tint": Color(1.0, 1.0, 1.0),
		"rock_tint": Color(0.5, 0.48, 0.5),        # dark grey cliffs
		"ramp_tint": Color(1.9, 1.85, 1.75),       # white foam on the wave crests
		"track_scroll": Vector2(0.0, -0.35),       # the water flows downhill
		"track_wobble": 0.04,
		# look: hot tropical sun, turquoise sea under a deep blue sky
		"sky_top": Color(0.03, 0.1, 0.72),
		"sky_horizon": Color(0.5, 0.7, 1.0),
		"ground_bottom": Color(0.05, 0.22, 0.75),
		"fog": Color(0.5, 0.68, 1.0),
		"fog_scale": 0.35,
		"ambient": Color(0.66, 0.72, 0.78),
		"sun_color": Color(1.0, 0.96, 0.86),
		"sun_energy": 0.9,
		"sun_rot": Vector3(-60.0, 20.0, 0.0),
	},
	{
		"name": "NEON DISTRICT",
		"theme": "city",           # a snowy elevated highway at night through a canyon of skyscrapers:
		                           # neon signs, gantries, flying traffic, vending machines + data pylons
		"snowfall": true,
		"music": "res://assets/level_music/city_lights.wav",   # loops instead of the shuffled playlist
		"seed": 9090451, "noise_seed": 91, "mtn_seed": 92,
		"slope": 0.3,
		"half_width": 15.5,
		"curve_amp": 1.35,
		"curve_freq": 1.5,
		"ramp_chance": 0.8,
		"ramp_h": 3.3,
		"obstacle_base": 0.44,
		"obstacle_ramp": 0.3,
		"gate_color": Color(1.0, 0.08, 0.62),
		"offpiste_tex": "res://assets/textures/city/city_rooftop.png",
		"track_tex": "res://assets/textures/city/city_road.png",
		"rock_tex": "res://assets/textures/city/city_wall.png",
		"tile_size": 8.0,
		"rock_tile_size": 6.0,
		"offpiste_tint": Color(1.2, 1.15, 1.45),
		"track_tint": Color(1.3, 1.3, 1.45),
		"rock_tint": Color(1.3, 1.2, 1.6),
		"ramp_tint": Color(2.6, 0.8, 2.3),         # hot pink kickers
		# look: deep night sky with a magenta glow coming up off the city
		"sky_top": Color(0.01, 0.01, 0.07),
		"sky_horizon": Color(0.42, 0.06, 0.5),
		"ground_bottom": Color(0.03, 0.01, 0.08),
		"fog": Color(0.24, 0.05, 0.36),
		"fog_scale": 0.55,
		"ambient": Color(0.55, 0.48, 0.78),
		"sun_color": Color(0.62, 0.78, 1.0),
		"sun_energy": 0.65,
		"sun_rot": Vector3(-55.0, -25.0, 0.0),
	},
	{
		"name": "MEGA MALL",
		"theme": "mall",           # boarding through a three-storey shopping centre under a glass roof:
		                           # shop fronts, escalators, potted palms + runaway trolleys
		"seed": 5150606, "noise_seed": 101, "mtn_seed": 102,
		"slope": 0.28,
		"half_width": 14.5,
		"curve_amp": 0.85,
		"curve_freq": 1.3,
		"ramp_chance": 0.7,
		"ramp_h": 2.8,
		"obstacle_base": 0.48,
		"obstacle_ramp": 0.3,
		"bumpiness": 0.2,          # a polished floor
		"gate_color": Color(0.95, 0.2, 0.35),
		"offpiste_tex": "res://assets/textures/mall/mall_walkway.png",
		"track_tex": "res://assets/textures/mall/mall_floor.png",
		"rock_tex": "res://assets/textures/mall/mall_stone.png",
		"tile_size": 5.0,
		"rock_tile_size": 5.0,
		"ramp_tint": Color(0.75, 0.95, 1.2),
		"sky_top": Color(0.76, 0.9, 1.0),
		"sky_horizon": Color(0.95, 0.9, 0.78),
		"ground_bottom": Color(0.7, 0.62, 0.55),
		"fog": Color(0.96, 0.9, 0.78),
		"fog_scale": 0.3,
		"ambient": Color(0.82, 0.8, 0.76),
		"sun_color": Color(1.0, 0.97, 0.9),
		"sun_energy": 0.45,
		"sun_rot": Vector3(-78.0, 15.0, 0.0),
	},
	{
		"name": "MOUNT CINDER",
		"theme": "volcano",        # a road of cooled lava with lava rivers on both sides,
		                           # obsidian spires and an erupting peak dead ahead
		"seed": 6660013, "noise_seed": 111, "mtn_seed": 112,
		"slope": 0.32,
		"half_width": 14.0,
		"curve_amp": 1.45,
		"curve_freq": 1.6,
		"ramp_chance": 0.85,
		"ramp_h": 3.5,
		"obstacle_base": 0.5,
		"obstacle_ramp": 0.3,
		"gate_color": Color(1.0, 0.36, 0.04),
		"offpiste_tex": "res://assets/textures/volcano/volcano_ash.png",
		"track_tex": "res://assets/textures/volcano/volcano_basalt.png",
		"rock_tex": "res://assets/textures/volcano/volcano_rock.png",
		"tile_size": 8.0,
		"rock_tile_size": 7.0,
		"track_tint": Color(1.25, 1.15, 1.15),
		"ramp_tint": Color(2.6, 1.0, 0.45),        # glowing kickers
		"sky_top": Color(0.06, 0.02, 0.05),
		"sky_horizon": Color(0.72, 0.17, 0.06),
		"ground_bottom": Color(0.1, 0.03, 0.03),
		"fog": Color(0.46, 0.12, 0.07),
		"fog_scale": 0.65,
		"ambient": Color(0.75, 0.42, 0.34),
		"sun_color": Color(1.0, 0.52, 0.28),
		"sun_energy": 0.8,
		"sun_rot": Vector3(-35.0, 15.0, 0.0),
	},
	{
		"name": "THE MOON",
		"theme": "moon",           # the finale: craters, landers, a moon base and Earth in a black sky
		"gravity": 0.4,            # jumps last about two and a half times as long
		"stars": true,
		"seed": 1969072, "noise_seed": 121, "mtn_seed": 122,
		"slope": 0.31,
		"half_width": 17.0,
		"curve_amp": 1.3,
		"curve_freq": 1.25,
		"ramp_chance": 0.95,
		"ramp_h": 3.6,
		"obstacle_base": 0.52,
		"obstacle_ramp": 0.3,
		"gate_color": Color(0.3, 0.75, 1.0),
		"offpiste_tex": "res://assets/textures/moon/moon_dust.png",
		"track_tex": "res://assets/textures/moon/moon_track.png",
		"rock_tex": "res://assets/textures/moon/moon_rock.png",
		"tile_size": 8.0,
		"rock_tile_size": 6.0,
		"ramp_tint": Color(1.05, 1.15, 1.45),
		"sky_top": Color(0.0, 0.0, 0.01),
		"sky_horizon": Color(0.01, 0.01, 0.03),
		"ground_bottom": Color(0.0, 0.0, 0.01),
		"fog": Color(0.02, 0.02, 0.05),
		"fog_scale": 0.12,
		"ambient": Color(0.34, 0.35, 0.42),
		"sun_color": Color(1.0, 1.0, 0.98),
		"sun_energy": 1.05,
		"sun_rot": Vector3(-32.0, 62.0, 0.0),
	},
]


static func count() -> int:
	return LEVELS.size()


## Level n (1-based).
static func get_level(n: int) -> Dictionary:
	return LEVELS[clampi(n - 1, 0, LEVELS.size() - 1)]


static func is_unlocked(n: int) -> bool:
	if n <= 1:
		return true
	if n > LEVELS.size():
		return false
	if Screen.debug_unlock_all:
		return true
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return false
	return cfg.get_value("levels", "unlocked_%d" % n, false)


static func unlock(n: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)   # keep settings and best distances
	cfg.set_value("levels", "unlocked_%d" % n, true)
	cfg.save(SAVE_PATH)


## Save-file key for a level's best distance (level 1 keeps its original key).
static func best_key(n: int) -> String:
	return "best_distance" if n <= 1 else "best_distance_%d" % n


static func load_best(n: int) -> float:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 0.0
	return cfg.get_value("endless", best_key(n), 0.0)


static func save_best(n: int, dist: float) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("endless", best_key(n), dist)
	cfg.save(SAVE_PATH)


## Thumbnail for level n, or null if it hasn't been captured yet.
static func load_thumb(n: int) -> Texture2D:
	var path := THUMB_PATH % n
	if ResourceLoader.exists(path):
		return load(path)
	# Freshly captured and not imported by the editor yet: read the PNG directly.
	var file := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(file):
		return null
	var img := Image.load_from_file(file)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## A black sky map scattered with single-pixel stars.
static func _star_map() -> Texture2D:
	var img := Image.create(1024, 512, false, Image.FORMAT_RGB8)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1969
	for i in 1500:
		var v := rng.randf_range(0.3, 1.0)
		var tint := Color(v, v, v * rng.randf_range(0.9, 1.15))
		img.set_pixel(rng.randi() % 1024, rng.randi() % 512, tint)
	return ImageTexture.create_from_image(img)


## Sky, fog and sun colours for a level.
static func apply_look(level: Dictionary, we: WorldEnvironment, sun: DirectionalLight3D) -> void:
	var env: Environment = we.environment.duplicate(true)
	var sky_mat: ProceduralSkyMaterial = env.sky.sky_material
	sky_mat.sky_top_color = level.sky_top
	sky_mat.sky_horizon_color = level.sky_horizon
	sky_mat.ground_horizon_color = level.sky_horizon
	sky_mat.ground_bottom_color = level.ground_bottom
	env.fog_light_color = level.fog
	if level.has("fog_scale"):
		env.fog_density *= level.fog_scale
	if level.has("ambient"):
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = level.ambient
	if level.get("stars", false):
		sky_mat.sky_cover = _star_map()
		sky_mat.sky_cover_modulate = Color(1, 1, 1)
	we.environment = env
	sun.rotation_degrees = level.sun_rot
	sun.light_color = level.sun_color
	sun.light_energy = level.sun_energy
