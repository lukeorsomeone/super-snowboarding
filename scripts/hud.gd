extends Control
## The in-game HUD (320x240), drawn in one pass: rider + lives + gifts top left, stage progress
## top centre, score + time top right, speed gauge bottom left, owned items bottom right,
## and a bouncing trick callout just under the top bar.

const Riders := preload("res://scripts/riders.gd")
const RunState := preload("res://scripts/run_state.gd")

const PLATE := Color(0.03, 0.06, 0.25, 0.82)
const EDGE := Color(0.32, 0.5, 0.95)
const SHADOW := Color(0.0, 0.02, 0.15)
const GOLD := Color(1.0, 0.92, 0.4)
const CYAN := Color(0.6, 0.95, 1.0)
const TEXT := Color(0.88, 0.94, 1.0)
const DIM := Color(0.52, 0.62, 0.85)
const OFF := Color(0.12, 0.17, 0.42)
const RED := Color(1.0, 0.3, 0.38)

const SPEED_SEGMENTS := 12
const FLASH_TIME := 0.7
const TRACK_TIME := 3.5

const HEART := [".##.##.", "#######", "#######", ".#####.", "..###..", "...#...", "......."]
const GIFT := ["..#.#..", "#######", "#..#..#", "#######", "#..#..#", "#..#..#", "#######"]
const FLAG := ["#.#.#..", ".#.#.#.", "#.#.#..", ".#.#.#.", "#......", "#......", "#......"]
const NOTE := ["...####", "...#..#", "...#..#", "...#..#", ".###.##", "####.##", ".##...."]

## Item icons: [colour, 7x7 picture].
const ICONS := {
	"wax": [Color(0.45, 0.85, 1.0), ["......#", ".....##", "....##.", "...##..", "..##...", ".##....", "#......"]],
	"bindings": [Color(0.8, 0.82, 0.9), ["#######", "#.....#", "#.###.#", "#.#.#.#", "#.###.#", "#.....#", "#######"]],
	"boots": [Color(0.6, 1.0, 0.45), ["..###..", ".#...#.", "..###..", ".#...#.", "..###..", ".#...#.", "#######"]],
	"cocoa": [Color(0.85, 0.55, 0.3), [".#.#...", "..#.#..", ".......", "#####..", "#####.#", "######.", ".###..."]],
	"magnet": [Color(1.0, 0.35, 0.35), ["##...##", "##...##", "##...##", "##...##", "##...##", ".#####.", "..###.."]],
	"socks": [Color(0.4, 1.0, 0.55), [".###...", ".###...", ".###...", ".###...", ".#####.", ".######", "..####."]],
	"slim": [Color(1.0, 0.75, 0.85), ["...#...", "..###..", "...#...", "...#...", "...#...", "..#.#..", "..#.#.."]],
	"spin": [Color(0.5, 0.75, 1.0), ["..###.#", ".#...##", "#...###", "#......", "#.....#", ".#...#.", "..###.."]],
	"flip": [Color(1.0, 0.65, 0.25), ["...#...", "..###..", ".#.#.#.", "...#...", "...#...", "...#...", "..###.."]],
	"soft": [Color(0.92, 0.95, 1.0), [".......", "..##...", ".####.#", "#######", "#######", ".#####.", "......."]],
	"tutor": [GOLD, ["...#...", "...#...", "#######", ".#####.", "..###..", ".##.##.", "#.....#"]],
	"piggy": [Color(1.0, 0.8, 0.25), ["..###..", ".#####.", "##.#.##", "##.#.##", "##.#.##", ".#####.", "..###.."]],
	"feather": [Color(0.75, 0.6, 1.0), [".....##", "....###", "...###.", "..###..", ".###...", ".#.....", "#......"]],
	"wind": [Color(0.65, 0.95, 0.9), ["..##...", "....#..", "#####..", ".......", "######.", "......#", ".....#."]],
	"ghost": [Color(0.85, 0.9, 1.0), [".#####.", "#######", "#.#.#.#", "#######", "#######", "#######", "#.#.#.#"]],
	"glass": [Color(0.55, 0.95, 1.0), ["..###..", ".#####.", "#######", ".#####.", "..###..", "...#...", "......."]],
	"rocket": [Color(1.0, 0.5, 0.3), ["...#...", "..###..", "..###..", "..###..", ".#####.", "#.###.#", "..#.#.."]],
	"adrenaline": [Color(1.0, 0.95, 0.25), ["....##.", "...##..", "..####.", ".####..", "...##..", "..##...", "..#...."]],
	"santa": [Color(0.95, 0.25, 0.3), ["...#...", "..###..", ".#####.", "#######", "#######", "#######", ".#####."]],
	"phoenix": [Color(1.0, 0.45, 0.15), ["...#...", "..##...", "..###.#", ".#####.", "#######", "#######", ".#####."]],
}

var run: RefCounted
var _font: Font
var _portrait: Texture2D
var _score := 0
var _shown_score := 0.0
var _time := "0:00.00"
var _speed_k := 0.0
var _kmh := 0
var _metres := 0
var _progress := 0.0
var _last_lives := -1
var _lost_heart := -1
var _heart_t := 0.0
var _clock := 0.0
var _gift_t := 0.0
var _gift_text := ""
var _pop_text := ""
var _pop_age := 0.0
var _pop_left := 0.0
var _track := ""
var _track_left := 0.0
var _flashes := {}   # item id -> seconds left


func setup(r: RefCounted) -> void:
	run = r
	_shown_score = r.score
	_last_lives = r.lives
	_portrait = Riders.load_thumb(Screen.rider)


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_font = Screen.pixel_font


func refresh(delta: float, score: int, time_text: String, speed: float, max_speed: float,
		distance: float, length: float) -> void:
	_clock += delta
	_score = score
	_shown_score = move_toward(_shown_score, score, maxf(absf(score - _shown_score) * 10.0, 60.0) * delta)
	_time = time_text
	_kmh = int(speed * 3.6)
	_speed_k = lerpf(_speed_k, clampf(speed / max_speed, 0.0, 1.0), 1.0 - exp(-12.0 * delta))
	_metres = mini(int(distance), int(length))
	_progress = clampf(distance / length, 0.0, 1.0)
	if run.lives < _last_lives:
		_lost_heart = run.lives
		_heart_t = FLASH_TIME
	_last_lives = run.lives
	_heart_t = maxf(_heart_t - delta, 0.0)
	_gift_t = maxf(_gift_t - delta, 0.0)
	_pop_left = maxf(_pop_left - delta, 0.0)
	_pop_age += delta
	if is_visible_in_tree():   # so the song title waits for the intro to finish
		_track_left = maxf(_track_left - delta, 0.0)
	for id in _flashes.keys():
		_flashes[id] -= delta
		if _flashes[id] <= 0.0:
			_flashes.erase(id)
	queue_redraw()


func pop(text: String, seconds: float) -> void:
	_pop_text = text
	_pop_left = seconds
	_pop_age = 0.0


func gift_pop(value: int) -> void:
	_gift_text = "+%d" % value
	_gift_t = 0.6


func show_track(title: String) -> void:
	_track = title.substr(0, 34)
	_track_left = TRACK_TIME


## Makes an owned item's icon flash when it does something.
func flash(id: String) -> void:
	_flashes[id] = FLASH_TIME


func flash_name(item_name: String) -> void:
	for it in RunState.ITEMS:
		if it.name == item_name:
			flash(it.id)


# ---------------------------------------------------------------- drawing

func _draw() -> void:
	if run == null:
		return
	_draw_rider()
	_draw_progress()
	_draw_score()
	_draw_speed()
	_draw_items()
	_draw_track()
	_draw_pop()


func _plate(r: Rect2, alpha := 1.0) -> void:
	draw_rect(r, Color(PLATE, PLATE.a * alpha))
	var edge := Color(EDGE, alpha)
	draw_rect(Rect2(r.position, Vector2(r.size.x, 1)), edge)
	draw_rect(Rect2(r.position + Vector2(0, r.size.y - 1), Vector2(r.size.x, 1)), Color(EDGE.darkened(0.4), alpha))
	draw_rect(Rect2(r.position, Vector2(1, r.size.y)), edge)
	draw_rect(Rect2(r.position + Vector2(r.size.x - 1, 0), Vector2(1, r.size.y)), Color(EDGE.darkened(0.4), alpha))


func _text(x: float, y: float, s: String, color: Color, size := 8) -> void:
	var at := Vector2(roundf(x), roundf(y) + _font.get_ascent(size))
	draw_string(_font, at + Vector2.ONE * (size / 8), s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(SHADOW, color.a))
	draw_string(_font, at, s, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _text_right(right: float, y: float, s: String, color: Color) -> void:
	_text(right - _font.get_string_size(s, HORIZONTAL_ALIGNMENT_LEFT, -1, 8).x, y, s, color)


func _icon(pic: Array, at: Vector2, color: Color) -> void:
	for y in pic.size():
		var row: String = pic[y]
		for x in row.length():
			if row[x] == "#":
				draw_rect(Rect2(at + Vector2(x, y), Vector2.ONE), color)


func _draw_rider() -> void:
	_plate(Rect2(4, 4, 92, 30))
	var frame := Rect2(7, 7, 24, 24)
	draw_rect(frame, GOLD)
	var inner := frame.grow(-1)
	if _portrait:
		var ts := _portrait.get_size()
		var side := ts.y * 0.72
		var src := Rect2((ts.x - side) * 0.5, (ts.y - side) * 0.42, side, side)
		draw_texture_rect_region(_portrait, inner, src)
	else:
		draw_rect(inner, OFF)

	for i in run.max_lives:
		var at := Vector2(35 + i * 9, 8)
		var color := RED if i < run.lives else OFF
		if i == _lost_heart and _heart_t > 0.0:   # the heart you just lost shakes and flashes
			at.x += roundf(sin(_heart_t * 50.0) * 2.0)
			color = Color.WHITE if fmod(_heart_t, 0.16) > 0.08 else RED
		elif run.lives == 1 and i == 0 and fmod(_clock, 0.7) > 0.35:   # last life pulses
			color = Color(1.0, 0.65, 0.7)
		_icon(HEART, at, color)

	_icon(GIFT, Vector2(35, 21), Color(1.0, 0.75, 0.35))
	_text(45, 21, str(run.gifts), TEXT)
	if _gift_t > 0.0:
		_text(68, 21 - roundf((0.6 - _gift_t) * 6.0), _gift_text, Color(GOLD, clampf(_gift_t * 4.0, 0.0, 1.0)))


func _draw_progress() -> void:
	_plate(Rect2(100, 4, 120, 30))
	var bar := Rect2(106, 11, 98, 4)
	draw_rect(bar, OFF)
	draw_rect(Rect2(bar.position, Vector2(roundf(bar.size.x * _progress), bar.size.y)), CYAN)
	var x := roundf(bar.position.x + bar.size.x * _progress)
	draw_rect(Rect2(x - 2, 8, 5, 10), SHADOW)
	draw_rect(Rect2(x - 1, 9, 3, 8), GOLD)
	_icon(FLAG, Vector2(207, 8), Color.WHITE)

	for i in RunState.STAGES:
		var n: int = i + 1
		var color := OFF
		if n < run.stage:
			color = CYAN
		elif n == run.stage:
			color = GOLD
		draw_rect(Rect2(106 + i * 7, 23, 5, 5), color)
	_text_right(215, 21, "%d M" % _metres, TEXT)


func _draw_score() -> void:
	_plate(Rect2(224, 4, 92, 30))
	_text(229, 8, "SCORE", DIM)
	_text_right(312, 8, str(int(_shown_score)), GOLD)
	_text(229, 21, "TIME", DIM)
	_text_right(312, 21, _time, TEXT)


func _draw_speed() -> void:
	_plate(Rect2(4, 216, 128, 20))
	var lit := int(round(_speed_k * SPEED_SEGMENTS))
	for i in SPEED_SEGMENTS:
		var h := 5.0 + i * 0.75
		var k := i / float(SPEED_SEGMENTS - 1)
		var color := CYAN.lerp(GOLD, k * 2.0) if k < 0.5 else GOLD.lerp(RED, (k - 0.5) * 2.0)
		draw_rect(Rect2(9 + i * 5, 232 - roundf(h), 4, roundf(h)), color if i < lit else OFF)
	_text_right(127, 222, "%d KM/H" % _kmh, GOLD if _speed_k > 0.85 else TEXT)


func _draw_items() -> void:
	var n: int = run.items.size()
	if n == 0:
		return
	var w := n * 12 + 3
	var left := 316.0 - w
	_plate(Rect2(left, 220, w, 16))
	for i in n:
		var id: String = run.items[i]
		var tile := Rect2(left + 2 + i * 12, 223, 11, 10)
		var flashing: bool = _flashes.has(id) and fmod(_flashes[id], 0.16) > 0.08
		draw_rect(tile, Color.WHITE if flashing else Color(0.07, 0.11, 0.34))
		if ICONS.has(id):
			var color: Color = ICONS[id][0]
			_icon(ICONS[id][1], tile.position + Vector2(2, 1), PLATE if flashing else color)


func _draw_track() -> void:
	if _track_left <= 0.0 or _track == "":
		return
	var w := _track.length() * 6.0 + 20.0
	var slide := minf(minf(TRACK_TIME - _track_left, _track_left) / 0.25, 1.0)
	var x := roundf(lerpf(322.0, 316.0 - w, slide * (2.0 - slide)))
	_plate(Rect2(x, 201, w, 15))
	_icon(NOTE, Vector2(x + 5, 205), GOLD)
	_text(x + 15, 205, _track, TEXT)


func _draw_pop() -> void:
	if _pop_left <= 0.0 or _pop_text == "":
		return
	var alpha := clampf(_pop_left * 4.0, 0.0, 1.0)
	var size := 16
	var w := _font.get_string_size(_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	if w > 280.0:   # very long trick names drop to the small font
		size = 8
		w = _font.get_string_size(_pop_text, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x
	var bounce := 1.0 + 0.3 * exp(-9.0 * _pop_age) * cos(_pop_age * 18.0)
	draw_set_transform(Vector2(160, 49), 0.0, Vector2.ONE * bounce)   # above the rider, never over them
	var h := size + 8.0
	_plate(Rect2(-w * 0.5 - 7.0, -h * 0.5, w + 14.0, h), alpha)
	_text(-w * 0.5, -size * 0.5, _pop_text, Color(GOLD, alpha), size)
	draw_set_transform(Vector2.ZERO)
