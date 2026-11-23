extends Node
## Autoload "Screen": renders every scene into a 320x240 SubViewport and shows it on a
## CRT TV (curvature, scanlines, 15-bit dithered colour, plastic bezel).
## Change scenes with Screen.go(path) instead of get_tree().change_scene_to_file().

const GAME_RES := Vector2i(320, 240)
const PixelFont := preload("res://scripts/pixel_font.gd")
const ClassicFont := preload("res://scripts/classic_pixel_font.gd")
const MUSIC_DIR := "res://assets/my_music/"   # your own tracks (the old ones are still in assets/music)

## Emitted when the background playlist moves to a new song (display name).
signal track_changed(title: String)
## Emitted when the player switches between keyboard and gamepad (for on-screen prompts).
signal input_device_changed(gamepad: bool)

## True while the last input came from a gamepad.
var using_gamepad := false
## Level picked on the level select (1-based, see levels.gd).
var level := 1
## Rider picked on the rider select (1-based, see riders.gd). Loaded from the save file.
var rider := 1
var run: RefCounted = null   # the roguelike run in progress (run_state.gd)

# Dev cheats, changed only by debug_menu.gd (which exists only when run from the editor).
var debug_invincible := false
var debug_unlock_all := false
var debug_hide_hud := false
var debug_tainted := false   # this run used a cheat, so it won't save a best or unlock a level

## How the picture is presented (saved). The 15-bit dithering and vertex wobble stay in
## every mode; these only change the "old TV" extras.
const SCREEN_MODES := {
	"CLEAN": {"show_bezel": false, "curvature": 0.0, "scanline_strength": 0.0,
		"mask_strength": 0.0, "vignette_strength": 0.0, "glare_strength": 0.0},
	"LIGHT": {"show_bezel": true, "curvature": 0.0, "scanline_strength": 0.12,
		"mask_strength": 0.0, "vignette_strength": 0.0, "glare_strength": 0.0},
	"TV": {"show_bezel": true, "curvature": 0.07, "scanline_strength": 0.35,
		"mask_strength": 0.07, "vignette_strength": 1.0, "glare_strength": 0.035},
}
const SCREEN_MODE_ORDER := ["CLEAN", "LIGHT", "TV"]
var screen_mode := "CLEAN"
var _bezel_nodes: Array[Control] = []
## Controller rumble on/off (saved).
var vibration := true

var viewport: SubViewport
var pixel_font: FontFile
var classic_font: FontFile   # the original upright font: title screen, rider select and pause menu
var current_track := ""
var _music: AudioStreamPlayer
var _tracks: PackedStringArray = []
var _queue: Array = []
var _last := ""
var _level_track := ""   # the song looping for this level, if it has its own
var _crt: ColorRect
var _mat: ShaderMaterial


func _ready() -> void:
	pixel_font = PixelFont.build()
	classic_font = ClassicFont.build()
	ThemeDB.fallback_font = pixel_font
	ThemeDB.fallback_font_size = 8

	viewport = SubViewport.new()
	viewport.size = GAME_RES
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.audio_listener_enable_3d = true
	add_child(viewport)

	_mat = ShaderMaterial.new()
	_mat.shader = load("res://shaders/crt.gdshader")
	_mat.set_shader_parameter("screen_tex", viewport.get_texture())
	_mat.set_shader_parameter("game_res", Vector2(GAME_RES))
	_crt = ColorRect.new()
	_crt.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_crt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_crt.material = _mat
	add_child(_crt)
	_crt.resized.connect(_on_resized)
	_on_resized()
	_build_badge()
	if "--raw-video" in OS.get_cmdline_user_args():
		_use_raw_display()

	_adopt_current_scene.call_deferred()
	_load_fullscreen()
	_setup_audio_buses()

	_music = AudioStreamPlayer.new()
	_music.volume_db = -8.0
	_music.bus = "Music"
	_music.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_music)
	_music.finished.connect(_next_track)
	for f in ResourceLoader.list_directory(MUSIC_DIR):
		if f.get_extension().to_lower() in ["mp3", "ogg", "wav"]:
			_tracks.append(MUSIC_DIR + f)
	if OS.has_feature("editor"):   # never in exported builds
		add_child(load("res://scripts/debug_menu.gd").new())


# ---------------------------------------------------------------- sound effects
# PSX UI / event sounds by Nomagician Music (nomagician.itch.io).
# Each event picks a random take and nudges the pitch so repeats don't sound identical.

const SFX_DIR := "res://assets/sfx/ui/"
const SFX := {
	"gift": ["gift_1.ogg", "gift_2.ogg", "gift_3.ogg"],
	"wipeout": ["wipeout_1.ogg", "wipeout_2.ogg", "wipeout_3.ogg"],
	"run_over": ["run_over.ogg"],
	"new_best": ["new_best.ogg"],
	"milestone": ["milestone_1.ogg", "milestone_2.ogg"],
	"tick": ["tick_1.ogg", "tick_2.ogg"],
	"go": ["go.ogg"],
	"start": ["start.ogg"],
	"confirm": ["confirm.ogg"],
	"back": ["back.ogg"],
	"toggle": ["toggle.ogg"],
	"pause": ["pause.ogg"],
	"unpause": ["unpause.ogg"],
	"move_up": ["move_up.ogg"],
	"move_down": ["move_down.ogg"],
	"adjust": ["adjust.ogg"],
}
const SFX_VOICES := 10

var _sfx_players: Array[AudioStreamPlayer] = []
var _sfx_cache := {}


## Plays a named sound effect (see SFX). Safe to call from any scene.
func sfx(sound: String, volume_db: float = -3.0, pitch_jitter: float = 0.05) -> void:
	var files: Array = SFX.get(sound, [])
	if files.is_empty():
		return
	var path: String = SFX_DIR + files[randi() % files.size()]
	if not _sfx_cache.has(path):
		_sfx_cache[path] = load(path)
	var p := _free_sfx_player()
	p.stream = _sfx_cache[path]
	p.volume_db = volume_db
	p.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	p.play()


func _free_sfx_player() -> AudioStreamPlayer:
	for p in _sfx_players:
		if not p.playing:
			return p
	if _sfx_players.size() < SFX_VOICES:
		var p := AudioStreamPlayer.new()
		p.bus = "SFX"
		p.process_mode = Node.PROCESS_MODE_ALWAYS
		add_child(p)
		_sfx_players.append(p)
		return p
	return _sfx_players[0]  # all busy: steal the oldest voice


# ---------------------------------------------------------------- volume

## 0..10 steps, saved to the settings file. 0 mutes.
var music_volume := 8
var sfx_volume := 8


func _setup_audio_buses() -> void:
	for bus_name in ["Music", "SFX"]:
		if AudioServer.get_bus_index(bus_name) == -1:
			AudioServer.add_bus()
			var i := AudioServer.bus_count - 1
			AudioServer.set_bus_name(i, bus_name)
			AudioServer.set_bus_send(i, "Master")
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK:
		music_volume = cfg.get_value("settings", "music_volume", music_volume)
		sfx_volume = cfg.get_value("settings", "sfx_volume", sfx_volume)
		vibration = cfg.get_value("settings", "vibration", vibration)
		screen_mode = cfg.get_value("settings", "screen_mode", screen_mode)
	_apply_screen_mode()
	# Prompts start as keyboard and switch the moment a pad button/stick is actually used
	# (some PCs report unrelated devices as joypads, so "connected" isn't reliable).
	using_gamepad = false
	_apply_volume("Music", music_volume)
	_apply_volume("SFX", sfx_volume)


func set_music_volume(v: int) -> void:
	music_volume = clampi(v, 0, 10)
	_apply_volume("Music", music_volume)
	_save_setting("music_volume", music_volume)


func set_sfx_volume(v: int) -> void:
	sfx_volume = clampi(v, 0, 10)
	_apply_volume("SFX", sfx_volume)
	_save_setting("sfx_volume", sfx_volume)


func _apply_volume(bus_name: String, v: int) -> void:
	var i := AudioServer.get_bus_index(bus_name)
	AudioServer.set_bus_mute(i, v <= 0)
	AudioServer.set_bus_volume_db(i, linear_to_db(maxf(v / 10.0, 0.001)))


func _save_setting(key: String, value: Variant) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("settings", key, value)
	cfg.save(SETTINGS_PATH)


# ---------------------------------------------------------------- fullscreen

const SETTINGS_PATH := "user://super_snowboarding.cfg"


func _input(event: InputEvent) -> void:
	# Track the last device used so prompts can show pad buttons or keys.
	if event is InputEventJoypadButton or (event is InputEventJoypadMotion and absf(event.axis_value) > 0.5):
		_set_gamepad(true)
	elif (event is InputEventKey and event.pressed) or event is InputEventMouseButton:
		_set_gamepad(false)
	if event is InputEventKey and event.pressed and not event.echo and event.physical_keycode == KEY_F11:
		set_fullscreen(not is_fullscreen())
		sfx("toggle")
		get_viewport().set_input_as_handled()


## Switches between CLEAN / LIGHT / TV presentation and remembers it.
func set_screen_mode(mode: String) -> void:
	if not SCREEN_MODES.has(mode):
		return
	screen_mode = mode
	_apply_screen_mode()
	_save_setting("screen_mode", mode)


## Steps to the next/previous screen mode (dir = +1 / -1).
func cycle_screen_mode(dir: int) -> void:
	var i := SCREEN_MODE_ORDER.find(screen_mode)
	set_screen_mode(SCREEN_MODE_ORDER[posmod(i + dir, SCREEN_MODE_ORDER.size())])


func _apply_screen_mode() -> void:
	if not SCREEN_MODES.has(screen_mode):
		screen_mode = "CLEAN"
	var m: Dictionary = SCREEN_MODES[screen_mode]
	for k in m:
		_mat.set_shader_parameter(k, m[k])
	for n in _bezel_nodes:
		n.visible = m.show_bezel


func _set_gamepad(on: bool) -> void:
	if on != using_gamepad:
		using_gamepad = on
		input_device_changed.emit(on)


## Rumbles every connected controller (if vibration is on). weak/strong are 0..1.
func rumble(weak: float, strong: float, duration: float) -> void:
	if not vibration:
		return
	for id in Input.get_connected_joypads():
		Input.start_joy_vibration(id, clampf(weak, 0.0, 1.0), clampf(strong, 0.0, 1.0), duration)


func set_vibration(on: bool) -> void:
	vibration = on
	_save_setting("vibration", on)
	if on:
		rumble(0.5, 0.3, 0.15)   # a little buzz so you can feel it's on


func is_fullscreen() -> bool:
	return DisplayServer.window_get_mode() in [DisplayServer.WINDOW_MODE_FULLSCREEN, DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN]


## Switches fullscreen on/off and remembers the choice for next launch.
func set_fullscreen(on: bool) -> void:
	DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN if on else DisplayServer.WINDOW_MODE_WINDOWED)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)  # keep the saved best time
	cfg.set_value("settings", "fullscreen", on)
	cfg.save(SETTINGS_PATH)


func _load_fullscreen() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) == OK and cfg.get_value("settings", "fullscreen", false):
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)


# ---------------------------------------------------------------- playlist

## Starts (or keeps playing) the shuffled background playlist.
func start_playlist() -> void:
	if not _music.playing and not _tracks.is_empty():
		_next_track()


func stop_playlist() -> void:
	_music.stop()
	_level_track = ""
	current_track = ""


## Music for a level: loops its own song, or uses the shuffled playlist if path is empty.
func play_level_music(path: String) -> void:
	if path == "":
		if _level_track != "":
			stop_playlist()
		start_playlist()
	elif path != _level_track or not _music.playing:
		_level_track = path
		_play_track(path)


func _play_track(path: String) -> void:
	_music.stream = load(path)
	_music.play()
	current_track = _display_name(path)
	track_changed.emit(current_track)


func _next_track() -> void:
	if _level_track != "":
		_play_track(_level_track)
		return
	if _queue.is_empty():
		_queue = Array(_tracks)
		_queue.shuffle()
		# never play the same song twice in a row across reshuffles
		if _queue.size() > 1 and _queue[0] == _last:
			_queue.push_back(_queue.pop_front())
	var path: String = _queue.pop_front()
	_last = path
	_play_track(path)


func _display_name(path: String) -> String:
	var re := RegEx.create_from_string("^\\d+\\.?\\s*")
	return re.sub(path.get_file().get_basename(), "").replace("_", " ").to_upper()


## Recording mode (`-- --raw-video`): show the plain 320x240 picture scaled up with sharp
## pixels — no CRT shader, dithering, bezel or badge. Used for capturing trailers/videos.
func _use_raw_display() -> void:
	for c in get_children():
		if c is CanvasItem:
			c.visible = false
	var raw := TextureRect.new()
	raw.texture = viewport.get_texture()
	raw.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	raw.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	raw.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	raw.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(raw)


func go(path: String) -> void:
	for c in viewport.get_children():
		viewport.remove_child(c)
		c.queue_free()
	viewport.add_child(load(path).instantiate())


func _adopt_current_scene() -> void:
	var s := get_tree().current_scene
	if s != null and s.get_parent() != viewport:
		s.get_parent().remove_child(s)
		viewport.add_child(s)


func _on_resized() -> void:
	_mat.set_shader_parameter("rect_size", _crt.size)


func _build_badge() -> void:
	# Brand plate under the screen and a red power LED, like a real TV.
	var badge := Label.new()
	badge.text = "SUPER SNOWBOARDING"
	var ls := LabelSettings.new()
	ls.font = pixel_font
	ls.font_size = 16
	ls.font_color = Color(0.62, 0.64, 0.7)
	ls.shadow_color = Color(0.03, 0.03, 0.04)
	ls.shadow_offset = Vector2(0, 2)
	badge.label_settings = ls
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	badge.anchor_left = 0.3
	badge.anchor_right = 0.7
	badge.anchor_top = 0.925
	badge.anchor_bottom = 0.985
	badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(badge)
	_bezel_nodes.append(badge)

	var led := Panel.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(1.0, 0.15, 0.1)
	sb.set_corner_radius_all(6)
	sb.shadow_color = Color(1.0, 0.1, 0.05, 0.6)
	sb.shadow_size = 6
	led.add_theme_stylebox_override("panel", sb)
	led.anchor_left = 0.8
	led.anchor_right = 0.8
	led.anchor_top = 0.955
	led.anchor_bottom = 0.955
	led.offset_left = -6
	led.offset_right = 6
	led.offset_top = -6
	led.offset_bottom = 6
	led.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(led)
	_bezel_nodes.append(led)
