extends CanvasLayer
## Between stages (320x240): choose one of three items, or spend gifts on a reroll.

signal chosen(id: String)

const RunState := preload("res://scripts/run_state.gd")
const CARD := Vector2(98, 112)
const GAP := 5.0
const CARD_Y := 46.0
const INPUT_DELAY := 0.45   # so a key still held from riding can't pick a card by accident
const GOLD := Color(1.0, 0.92, 0.4)
const TEXT := Color(0.85, 0.92, 1.0)
const NAVY := Color(0.04, 0.08, 0.4)

var run: RefCounted
var offers: Array[String] = []
var new_riders: Array[String] = []   # unlocked by clearing this stage
var _sel := 1
var _t := 0.0
var _done := false
var _cards: Array[Dictionary] = []
var _info: Label
var _owned: Label
var _hint: Label


func _ready() -> void:
	layer = 8
	offers = run.roll_offers()
	_sel = mini(1, offers.size() - 1)
	_build()
	_refresh()


func _process(delta: float) -> void:
	_t += delta
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var root: Control = c.root
		var k := clampf((_t - i * 0.07) / 0.3, 0.0, 1.0)
		var hop := absf(sin(_t * 5.0)) * 3.0 if i == _sel else 0.0
		root.position = c.home + Vector2(0, roundf((1.0 - k) * (1.0 - k) * 60.0 - hop))
		root.modulate.a = k
	if _done or _t < INPUT_DELAY:
		return
	if _pressed("ui_left") or _pressed("steer_left"):
		_move(-1)
	elif _pressed("ui_right") or _pressed("steer_right"):
		_move(1)
	elif _pressed("restart"):
		_reroll()
	elif _pressed("confirm") or _pressed("ui_accept"):
		choose(_sel)


func _pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_just_pressed(action)


func _move(dir: int) -> void:
	if offers.size() < 2:
		return
	_sel = posmod(_sel + dir, offers.size())
	Screen.sfx("move_down" if dir > 0 else "move_up", -4.0)
	_refresh()


func _reroll() -> void:
	var cost: int = run.reroll_cost()
	if run.gifts < cost:
		Screen.sfx("back")
		return
	run.gifts -= cost
	run.rerolls += 1
	offers = run.roll_offers()
	_sel = mini(_sel, offers.size() - 1)
	Screen.sfx("adjust", -2.0)
	_refresh()


func choose(i: int) -> void:
	if _done or i < 0 or i >= offers.size():
		return
	_done = true
	Screen.sfx("confirm")
	chosen.emit(offers[i])


func _refresh() -> void:
	for i in _cards.size():
		var c: Dictionary = _cards[i]
		var has_offer := i < offers.size()
		(c.root as Control).visible = has_offer
		if not has_offer:
			continue
		var it: Dictionary = RunState.get_item(offers[i])
		(c.name as Label).text = it.name
		(c.desc as Label).text = it.desc
		(c.frame as ColorRect).color = GOLD if i == _sel else NAVY
		(c.name as Label).label_settings.font_color = GOLD if i == _sel else TEXT
	_info.text = "LIVES %d/%d    GIFTS %d" % [run.lives, run.max_lives, run.gifts]
	var names: Array[String] = []
	for id in run.items:
		names.append(RunState.get_item(id).name)
	_owned.text = "YOUR ITEMS: " + (", ".join(names) if not names.is_empty() else "NONE YET")
	var cost: int = run.reroll_cost()
	if Screen.using_gamepad:
		_hint.text = "STICK SELECT   A TAKE   Y REROLL (%d GIFTS)" % cost
	else:
		_hint.text = "A/D SELECT   ENTER TAKE   R REROLL (%d GIFTS)" % cost


func _label(parent: Control, size: int, color: Color, pos: Vector2, box: Vector2) -> Label:
	var l := Label.new()
	var ls := LabelSettings.new()
	ls.font = Screen.pixel_font
	ls.font_size = size
	ls.font_color = color
	ls.shadow_color = Color(0.0, 0.02, 0.15)
	ls.shadow_size = 0
	ls.shadow_offset = Vector2.ONE * (size / 8.0)
	ls.line_spacing = 2.0
	l.label_settings = ls
	l.position = pos
	l.size = box
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(l)
	return l


func _rect(parent: Control, color: Color, pos: Vector2, box: Vector2) -> ColorRect:
	var r := ColorRect.new()
	r.color = color
	r.position = pos
	r.size = box
	r.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(r)
	return r


func _build() -> void:
	var root := Control.new()
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)
	_rect(root, Color(0.0, 0.02, 0.15, 0.84), Vector2.ZERO, Vector2(320, 240))
	_label(root, 16, GOLD, Vector2(0, 8), Vector2(320, 18)).text = "STAGE %d CLEAR!" % run.stage
	var next: String = preload("res://scripts/levels.gd").get_level(run.stage + 1).name
	_label(root, 8, TEXT, Vector2(0, 30), Vector2(320, 10)).text = "CHOOSE AN ITEM - NEXT: %s" % next

	var left := (320.0 - (CARD.x * 3.0 + GAP * 2.0)) / 2.0
	for i in 3:
		var home := Vector2(left + i * (CARD.x + GAP), CARD_Y)
		var card := Control.new()
		card.position = home
		card.size = CARD
		card.mouse_filter = Control.MOUSE_FILTER_IGNORE
		root.add_child(card)
		var frame := _rect(card, NAVY, Vector2.ZERO, CARD)
		_rect(card, Color(0.03, 0.06, 0.25), Vector2(2, 2), CARD - Vector2(4, 4))
		_rect(card, Color(1.0, 0.45, 0.2), Vector2(8, 33), Vector2(CARD.x - 16, 1))
		var item_name := _label(card, 8, TEXT, Vector2(5, 8), Vector2(CARD.x - 10, 22))
		item_name.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		var desc := _label(card, 8, TEXT, Vector2(6, 42), Vector2(CARD.x - 12, 64))
		_cards.append({"root": card, "home": home, "frame": frame, "name": item_name, "desc": desc})

	_info = _label(root, 8, GOLD, Vector2(0, 165), Vector2(320, 10))
	_owned = _label(root, 8, TEXT, Vector2(8, 179), Vector2(304, 36))
	_hint = _label(root, 8, Color(0.75, 0.92, 1.0), Vector2(0, 226), Vector2(320, 10))
	if not new_riders.is_empty():
		_label(root, 8, Color(1.0, 0.55, 0.6), Vector2(0, 214), Vector2(320, 10)).text = "NEW RIDER UNLOCKED: " + ", ".join(new_riders)
