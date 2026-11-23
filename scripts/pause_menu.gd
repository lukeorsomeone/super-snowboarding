extends CanvasLayer
## Pause menu (320x240). Esc pauses during a run; Up/Down to pick, Left/Right to adjust,
## Enter to choose, Esc again to resume. Art: FREE PSX UI by rohhsa (rohhsa.itch.io).

signal restart_requested
signal quit_requested

const ITEMS := ["RESUME", "NEW RUN", "MUSIC", "SFX", "SCREEN", "FULLSCREEN", "VIBRATION", "QUIT TO TITLE"]
const ROW_Y := 76
const ROW_STEP := 12

var _sel := 0
var _opened_frame := -1
var _names: Array[Label] = []
var _values: Array[Label] = []
var _hint1: Label
var _hint2: Label


func _ready() -> void:
	layer = 10
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func is_open() -> bool:
	return visible


func open() -> void:
	visible = true
	_sel = 0
	_opened_frame = Engine.get_process_frames()
	get_tree().paused = true
	Screen.sfx("pause", -2.0, 0.0)
	_refresh()


func close() -> void:
	visible = false
	get_tree().paused = false


func _process(_delta: float) -> void:
	if not visible or Engine.get_process_frames() == _opened_frame:
		return  # ignore the key press that opened the menu
	if _pressed("back") or _pressed("pause"):
		Screen.sfx("unpause", -2.0, 0.0)
		close()
		return
	if _pressed("ui_up") or _pressed("tuck"):
		_sel = posmod(_sel - 1, ITEMS.size())
		Screen.sfx("move_up", -4.0)
		_refresh()
	elif _pressed("ui_down") or _pressed("brake"):
		_sel = posmod(_sel + 1, ITEMS.size())
		Screen.sfx("move_down", -4.0)
		_refresh()
	elif _pressed("ui_left") or _pressed("steer_left"):
		_adjust(-1)
	elif _pressed("ui_right") or _pressed("steer_right"):
		_adjust(1)
	elif _pressed("confirm") or _pressed("ui_accept"):
		_choose()


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _adjust(dir: int) -> void:
	match ITEMS[_sel]:
		"MUSIC":
			Screen.set_music_volume(Screen.music_volume + dir)
		"SFX":
			Screen.set_sfx_volume(Screen.sfx_volume + dir)
		"SCREEN":
			Screen.cycle_screen_mode(dir)
		"FULLSCREEN":
			Screen.set_fullscreen(not Screen.is_fullscreen())
		"VIBRATION":
			Screen.set_vibration(not Screen.vibration)
		_:
			return
	Screen.sfx("adjust", -3.0)
	_refresh()


func _choose() -> void:
	match ITEMS[_sel]:
		"RESUME":
			Screen.sfx("unpause", -2.0, 0.0)
			close()
		"NEW RUN":
			Screen.sfx("confirm")
			close()
			restart_requested.emit()
		"SCREEN", "FULLSCREEN", "VIBRATION":
			_adjust(1)
		"QUIT TO TITLE":
			Screen.sfx("back")
			close()
			quit_requested.emit()
		_:
			_adjust(1)  # Enter on a volume row nudges it up


func _bar(v: int) -> String:
	return "#".repeat(v) + "=".repeat(10 - v)


func _refresh() -> void:
	for i in ITEMS.size():
		var selected := i == _sel
		_names[i].text = (">> " if selected else "   ") + ITEMS[i]
		_names[i].label_settings.font_color = Color(0.55, 0.95, 1.0) if selected else Color(0.85, 0.88, 0.95)
		_values[i].label_settings.font_color = _names[i].label_settings.font_color
		match ITEMS[i]:
			"MUSIC": _values[i].text = _bar(Screen.music_volume)
			"SFX": _values[i].text = _bar(Screen.sfx_volume)
			"SCREEN": _values[i].text = "<" + Screen.screen_mode + ">"
			"FULLSCREEN": _values[i].text = "[ON]" if Screen.is_fullscreen() else "[OFF]"
			"VIBRATION": _values[i].text = "[ON]" if Screen.vibration else "[OFF]"
			_: _values[i].text = ""
	if Screen.using_gamepad:
		_hint1.text = "UP/DOWN SELECT   LEFT/RIGHT ADJUST"
		_hint2.text = "A CHOOSE   B/START RESUME"
	else:
		_hint1.text = "UP/DOWN SELECT   LEFT/RIGHT ADJUST"
		_hint2.text = "ENTER CHOOSE   ESC RESUME"


func _label(parent: Control, text: String, pos: Vector2, size: Vector2, align: int) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Screen.classic_font
	ls.font_size = 8
	ls.shadow_color = Color(0.0, 0.02, 0.1)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2.ONE
	l.label_settings = ls
	l.text = text
	l.position = pos
	l.size = size
	l.horizontal_alignment = align
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.02, 0.12, 0.6)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(dim)

	var title := TextureRect.new()
	title.texture = load("res://assets/ui/pause_title.png")
	title.position = Vector2((320 - 111) / 2.0, 42)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(title)

	var panel := TextureRect.new()
	panel.texture = load("res://assets/ui/panel.png")
	panel.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	panel.stretch_mode = TextureRect.STRETCH_SCALE
	panel.position = Vector2(48, 66)
	panel.size = Vector2(224, 112)
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)

	for i in ITEMS.size():
		var y := ROW_Y + i * ROW_STEP
		_names.append(_label(root, ITEMS[i], Vector2(60, y), Vector2(120, 10), HORIZONTAL_ALIGNMENT_LEFT))
		_values.append(_label(root, "", Vector2(160, y), Vector2(100, 10), HORIZONTAL_ALIGNMENT_RIGHT))

	_hint1 = _label(root, "", Vector2(0, 184), Vector2(320, 10), HORIZONTAL_ALIGNMENT_CENTER)
	_hint2 = _label(root, "", Vector2(0, 196), Vector2(320, 10), HORIZONTAL_ALIGNMENT_CENTER)
