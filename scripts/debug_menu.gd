extends CanvasLayer
## Developer menu. Screen only creates this when the game is run from the Godot editor, so it
## doesn't exist in exported builds. Press ` (the key left of 1) or F1, then a number key.
## A run that uses a cheat never saves a best distance or unlocks a level.

const Levels := preload("res://scripts/levels.gd")
const Riders := preload("res://scripts/riders.gd")
const GAME_SCENE := "res://scenes/game.tscn"
const SPEEDS := [1.0, 0.5, 0.25, 2.0]
const WARP := 500.0
const HITBOX_RANGE := 140.0

var _open := false
var _speed_i := 0
var _show_hitboxes := false
var _panel: PanelContainer
var _text: Label
var _badge: Label
var _hitboxes: MeshInstance3D
var _lines: ImmediateMesh
var _line_mat: StandardMaterial3D


func _ready() -> void:
	layer = 120
	process_mode = Node.PROCESS_MODE_ALWAYS
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_panel = PanelContainer.new()
	_panel.position = Vector2(12, 12)
	_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.03, 0.1, 0.88)
	style.border_color = Color(1.0, 0.2, 0.7)
	style.set_border_width_all(2)
	style.set_content_margin_all(10)
	_panel.add_theme_stylebox_override("panel", style)
	root.add_child(_panel)
	_text = _make_label(Color(0.85, 1.0, 1.0))
	_panel.add_child(_text)
	_panel.visible = false

	_badge = _make_label(Color(1.0, 0.35, 0.75))
	_badge.position = Vector2(12, 12)
	root.add_child(_badge)

	_line_mat = StandardMaterial3D.new()
	_line_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_line_mat.no_depth_test = true
	_line_mat.vertex_color_use_as_albedo = true
	_lines = ImmediateMesh.new()
	print("DEBUG MENU ACTIVE")


func _make_label(color: Color) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Screen.pixel_font
	ls.font_size = 16
	ls.font_color = color
	ls.line_spacing = 3.0
	l.label_settings = ls
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return l


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_QUOTELEFT or key.physical_keycode == KEY_F1:
		_open = not _open
		get_viewport().set_input_as_handled()
	elif _open and key.physical_keycode >= KEY_1 and key.physical_keycode <= KEY_8:
		do_action(key.physical_keycode - KEY_0)
		get_viewport().set_input_as_handled()


## Runs menu entry n (1-8).
func do_action(n: int) -> void:
	var g := _game()
	match n:
		1:
			Screen.debug_invincible = not Screen.debug_invincible
			if Screen.debug_invincible:
				Screen.debug_tainted = true
		2:
			if g:
				g.debug_warp(WARP)
		3:
			_ensure_run()
			Screen.run.cheated = true
			Screen.run.stage += 1   # carries on into later laps
			_load_game()
		4:
			Screen.rider = wrapi(Screen.rider + 1, 1, Riders.count() + 1)
			if g:
				_load_game()
		5:
			_speed_i = (_speed_i + 1) % SPEEDS.size()
			Engine.time_scale = SPEEDS[_speed_i]
			if _speed_i != 0:
				Screen.debug_tainted = true
		6:
			_show_hitboxes = not _show_hitboxes
		7:
			Screen.debug_hide_hud = not Screen.debug_hide_hud
			if g:
				g.debug_set_hud(not Screen.debug_hide_hud)
		8:
			_ensure_run()
			var offers: Array[String] = Screen.run.roll_offers()
			if not offers.is_empty():
				Screen.run.cheated = true
				Screen.run.add_item(offers[0])
				if g:
					g.player.apply_run(Screen.run, g.level_def.get("gravity", 1.0))


func _ensure_run() -> void:
	if Screen.run == null:
		Screen.run = preload("res://scripts/run_state.gd").new()


func _load_game() -> void:
	get_tree().paused = false
	Screen.go(GAME_SCENE)


func _game() -> Node:
	if Screen.viewport == null or Screen.viewport.get_child_count() == 0:
		return null
	var n := Screen.viewport.get_child(0)
	return n if n.has_method("debug_warp") and not n.is_queued_for_deletion() else null


func _process(_delta: float) -> void:
	var g := _game()
	_panel.visible = _open
	_badge.visible = not _open and _active_text() != ""
	if _badge.visible:
		_badge.text = "DEBUG: " + _active_text()
	if _open:
		_text.text = _menu_text(g)
	_update_hitboxes(g)


func _active_text() -> String:
	var on: Array[String] = []
	if Screen.debug_invincible:
		on.append("INVINCIBLE")
	if _speed_i != 0:
		on.append("SPEED %.2fX" % SPEEDS[_speed_i])
	if _show_hitboxes:
		on.append("HITBOXES")
	if Screen.debug_hide_hud:
		on.append("NO HUD")
	return "  ".join(on)


func _onoff(v: bool) -> String:
	return "ON" if v else "OFF"


func _menu_text(g: Node) -> String:
	var level_name: String = Levels.get_level(Screen.run.stage if Screen.run else Screen.level).name
	var rider_name: String = Riders.get_rider(Screen.rider).name
	var t := "DEBUG MENU   F1 TO CLOSE\n\n"   # the pixel font has no backtick
	t += "1  INVINCIBLE      %s\n" % _onoff(Screen.debug_invincible)
	t += "2  WARP +%d M\n" % int(WARP)
	t += "3  NEXT STAGE      %s\n" % level_name
	t += "4  NEXT RIDER      %s\n" % rider_name
	t += "5  GAME SPEED      %.2fX\n" % SPEEDS[_speed_i]
	t += "6  HITBOXES        %s\n" % _onoff(_show_hitboxes)
	t += "7  HIDE HUD        %s\n" % _onoff(Screen.debug_hide_hud)
	t += "8  GIVE ITEM       %d OWNED\n\n" % (Screen.run.items.size() if Screen.run else 0)
	t += "FPS %d   DRAWS %d   MEM %d MB\n" % [Engine.get_frames_per_second(),
		Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME),
		int(OS.get_static_memory_usage() / 1048576.0)]
	if g:
		var d: float = -g.player.position.z
		t += "DIST %d M   SPEED %d KM/H\n" % [int(d), int(g.player.speed * 3.6)]
		t += "OFFSET %.1f   CHUNK %d\n" % [g.player.position.x - g.course.center_x(d), int(floor(d / 96.0))]
		t += "OBSTACLES %d   GIFTS %d\n" % [g.course.obstacles.size(), g.course.gifts.size()]
		t += "SAVING %s" % ("OFF" if Screen.debug_tainted else "ON")
	return t


func _update_hitboxes(g: Node) -> void:
	if not _show_hitboxes or g == null:
		if is_instance_valid(_hitboxes):
			_hitboxes.visible = false
		return
	if not is_instance_valid(_hitboxes) or _hitboxes.get_parent() != g:
		_hitboxes = MeshInstance3D.new()
		_hitboxes.mesh = _lines
		_hitboxes.material_override = _line_mat
		g.add_child(_hitboxes)
	_hitboxes.visible = true
	_lines.clear_surfaces()
	_lines.surface_begin(Mesh.PRIMITIVE_LINES)
	var pp: Vector3 = g.player.position
	_lines.surface_set_color(Color(0.2, 1.0, 0.3))
	for axis in [Vector3.RIGHT, Vector3.UP, Vector3.BACK]:
		_lines.surface_add_vertex(pp - axis * 0.6 + Vector3.UP * 0.1)
		_lines.surface_add_vertex(pp + axis * 0.6 + Vector3.UP * 0.1)
	_lines.surface_set_color(Color(1.0, 0.15, 0.2))
	for o in g.course.obstacles:
		var p: Vector3 = o.pos
		if absf(p.z - pp.z) > HITBOX_RANGE:
			continue
		var r: float = o.radius + 0.35   # the real crash radius (see player.gd)
		var h: float = o.height
		for i in 12:
			var a0 := i * TAU / 12.0
			var a1 := (i + 1) * TAU / 12.0
			var v0 := p + Vector3(cos(a0) * r, 0.0, sin(a0) * r)
			var v1 := p + Vector3(cos(a1) * r, 0.0, sin(a1) * r)
			for y in [0.0, h]:
				_lines.surface_add_vertex(v0 + Vector3.UP * y)
				_lines.surface_add_vertex(v1 + Vector3.UP * y)
			if i % 3 == 0:
				_lines.surface_add_vertex(v0)
				_lines.surface_add_vertex(v0 + Vector3.UP * h)
	_lines.surface_end()
