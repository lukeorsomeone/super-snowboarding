extends RefCounted
## The game's own font: heavy 5x7 letters, built at runtime and slanted like a 90s sports game.
## Lowercase letters reuse the uppercase glyphs.
## Use font sizes that are multiples of 8 (8, 16, 24, 32...) for crisp integer scaling.

const W := 5
const H := 8          # 7 glyph rows + 1 blank row of spacing
const SLANT := 2      # how many pixels the top row leans right of the bottom row
const CELL := Vector2i(W + SLANT + 1, 9)
const COLS := 16
const UPRIGHT := ["#", "="]   # volume bar pieces stay square

const GLYPHS := {
	" ": "..... ..... ..... ..... ..... ..... .....",
	"A": ".###. ##.## ##.## ##### ##.## ##.## ##.##",
	"B": "####. ##.## ##.## ####. ##.## ##.## ####.",
	"C": ".#### ##... ##... ##... ##... ##... .####",
	"D": "####. ##.## ##.## ##.## ##.## ##.## ####.",
	"E": "##### ##... ##... ####. ##... ##... #####",
	"F": "##### ##... ##... ####. ##... ##... ##...",
	"G": ".#### ##... ##... ##.## ##.## ##.## .####",
	"H": "##.## ##.## ##.## ##### ##.## ##.## ##.##",
	"I": "####. .##.. .##.. .##.. .##.. .##.. ####.",
	"J": "..### ...## ...## ...## ##.## ##.## .###.",
	"K": "##.## ##.## ####. ###.. ####. ##.## ##.##",
	"L": "##... ##... ##... ##... ##... ##... #####",
	"M": "##.## ##### ##### #.#.# ##.## ##.## ##.##",
	"N": "##.## ###.# ##### ##### #.### ##.## ##.##",
	"O": ".###. ##.## ##.## ##.## ##.## ##.## .###.",
	"P": "####. ##.## ##.## ####. ##... ##... ##...",
	"Q": ".###. ##.## ##.## ##.## ##### ##.#. .##.#",
	"R": "####. ##.## ##.## ####. ###.. ##.## ##.##",
	"S": ".#### ##... ##... .###. ...## ...## ####.",
	"T": "##### .##.. .##.. .##.. .##.. .##.. .##..",
	"U": "##.## ##.## ##.## ##.## ##.## ##.## .###.",
	"V": "##.## ##.## ##.## ##.## ##.## .###. ..#..",
	"W": "##.## ##.## ##.## #.#.# ##### ##### .#.#.",
	"X": "##.## ##.## .###. .###. .###. ##.## ##.##",
	"Y": "##.## ##.## ##.## .###. .##.. .##.. .##..",
	"Z": "##### ...## ..##. .##.. ##... ##... #####",
	"0": ".###. ##.## ##.## ##.## ##.## ##.## .###.",
	"1": ".##.. ###.. .##.. .##.. .##.. .##.. ####.",
	"2": ".###. ##.## ...## ..##. .##.. ##... #####",
	"3": "####. ...## ...## .###. ...## ...## ####.",
	"4": "...## ..### .#.## #..## ##### ...## ...##",
	"5": "##### ##... ####. ...## ...## ##.## .###.",
	"6": ".###. ##... ##... ####. ##.## ##.## .###.",
	"7": "##### ...## ...## ..##. ..##. .##.. .##..",
	"8": ".###. ##.## ##.## .###. ##.## ##.## .###.",
	"9": ".###. ##.## ##.## .#### ...## ...## .###.",
	"!": ".##.. .##.. .##.. .##.. .##.. ..... .##..",
	"?": ".###. ##.## ...## ..##. .##.. ..... .##..",
	":": "..... .##.. .##.. ..... .##.. .##.. .....",
	".": "..... ..... ..... ..... ..... .##.. .##..",
	",": "..... ..... ..... ..... .##.. ..#.. .#...",
	"'": ".##.. .##.. ..... ..... ..... ..... .....",
	"/": "...## ...## ..##. ..##. .##.. ##... ##...",
	"+": "..... ..#.. ..#.. ##### ..#.. ..#.. .....",
	"-": "..... ..... ..... ##### ##### ..... .....",
	"(": "...#. ..##. .##.. .##.. .##.. ..##. ...#.",
	")": ".#... .##.. ..##. ..##. ..##. .##.. .#...",
	"%": "##..# ##.## ...#. ..#.. .#... ##.## #..##",
	"&": ".##.. ##.#. ###.. .##.. ##.## ##.#. .##.#",
	">": "##... .##.. ..##. ...## ..##. .##.. ##...",
	"<": "...## ..##. .##.. ##... .##.. ..##. ...##",
	"[": ".###. .##.. .##.. .##.. .##.. .##.. .###.",
	"]": ".###. ..##. ..##. ..##. ..##. ..##. .###.",
	"#": ".###. .###. .###. .###. .###. .###. .###.",   # volume bar block
	"=": "..... ..... ..... .#.#. ..... ..... .....",   # empty volume bar slot
}


static func build() -> FontFile:
	var keys: Array = GLYPHS.keys()
	var rows := int(ceil(keys.size() / float(COLS)))
	var img := Image.create(COLS * CELL.x, rows * CELL.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))

	var font := FontFile.new()
	font.antialiasing = TextServer.FONT_ANTIALIASING_NONE
	font.generate_mipmaps = false
	font.allow_system_fallback = false
	font.fixed_size = H
	font.fixed_size_scale_mode = TextServer.FIXED_SIZE_SCALE_INTEGER_ONLY

	var size := Vector2i(H, 0)
	for i in keys.size():
		var ch: String = keys[i]
		var cx := (i % COLS) * CELL.x
		var cy := int(i / float(COLS)) * CELL.y
		var lines: PackedStringArray = (GLYPHS[ch] as String).split(" ")
		for y in lines.size():
			# rows lean right the higher they are
			var lean := 0 if UPRIGHT.has(ch) else int((lines.size() - 1 - y) * SLANT / float(lines.size() - 1) + 0.5)
			for x in W:
				if lines[y][x] == "#":
					img.set_pixel(cx + x + lean, cy + y, Color.WHITE)
		var codes := [ch.unicode_at(0)]
		if ch.to_lower() != ch:
			codes.append(ch.to_lower().unicode_at(0))
		for code in codes:
			font.set_glyph_advance(0, H, code, Vector2(W + 1, 0))   # same spacing as before, so layouts hold
			font.set_glyph_offset(0, size, code, Vector2(0, -H / 2.0))
			font.set_glyph_size(0, size, code, Vector2(W + SLANT, H))
			font.set_glyph_uv_rect(0, size, code, Rect2(cx, cy, W + SLANT, H))
			font.set_glyph_texture_idx(0, size, code, 0)
	font.set_texture_image(0, size, 0, img)
	font.set_cache_ascent(0, H, H / 2.0)
	font.set_cache_descent(0, H, H / 2.0)
	return font
