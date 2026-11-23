extends RefCounted
## Rider definitions. Add a new rider by adding an entry to RIDERS (its model needs the
## same rig and animations as Bao: ride, tuck, brake, air, crash) and running
## ("beach_model" is the swimwear + surfboard version used on surfing levels)
##
## res://tools/capture_rider_shots.tscn to make its portrait.

const SAVE_PATH := "user://super_snowboarding.cfg"
## Slots on the rider select screen; ones past RIDERS.size() say COMING SOON.
const SLOTS := 6
const THUMB_PATH := "res://assets/riders/rider_%d.png"

## Bao is free. "stage" = unlocks on reaching that stage, "wins" = unlocks on beating the game.
const RIDERS := [
	{"name": "BAO", "species": "SUGAR GLIDER", "model": "res://assets/models/sugar_glider.glb", "beach_model": "res://assets/models/sugar_glider_beach.glb"},
	{"name": "PIAO", "species": "RED PANDA", "model": "res://assets/models/red_panda.glb", "beach_model": "res://assets/models/red_panda_beach.glb", "stage": 2},
	{"name": "XIA", "species": "BUSHBABY", "model": "res://assets/models/galago.glb", "beach_model": "res://assets/models/galago_beach.glb", "stage": 4},
	{"name": "JING", "species": "HEDGEHOG", "model": "res://assets/models/hedgehog.glb", "beach_model": "res://assets/models/hedgehog_beach.glb", "stage": 6},
	{"name": "IGNATIUS", "species": "CHINCHILLA", "model": "res://assets/models/chinchilla.glb", "beach_model": "res://assets/models/chinchilla_beach.glb", "stage": 8},
	{"name": "BARNEY", "species": "WEST HIGHLAND TERRIER", "model": "res://assets/models/westie.glb", "beach_model": "res://assets/models/westie_beach.glb", "wins": 1},
]


static func count() -> int:
	return RIDERS.size()


## Rider n (1-based).
static func get_rider(n: int) -> Dictionary:
	return RIDERS[clampi(n - 1, 0, RIDERS.size() - 1)]


## The rider picked last time (saved), or Bao.
static func load_choice() -> int:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) != OK:
		return 1
	var n := clampi(cfg.get_value("settings", "rider", 1), 1, RIDERS.size())
	var met := goal_met(get_rider(n), cfg.get_value("roguelike", "best_stage", 0), cfg.get_value("roguelike", "wins", 0))
	return n if met else 1


static func save_choice(n: int) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	cfg.set_value("settings", "rider", n)
	cfg.save(SAVE_PATH)


static func goal_met(rd: Dictionary, best_stage: int, wins: int) -> bool:
	if rd.has("wins"):
		return wins >= rd.wins
	return best_stage >= rd.get("stage", 0)


static func is_unlocked(n: int) -> bool:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return goal_met(get_rider(n), cfg.get_value("roguelike", "best_stage", 0), cfg.get_value("roguelike", "wins", 0))


static func goal_text(n: int) -> String:
	var rd := get_rider(n)
	if rd.has("wins"):
		return "BEAT THE MOON TO UNLOCK"
	return "REACH STAGE %d TO UNLOCK" % rd.get("stage", 0)


## Names of riders that progress from (old_best, old_wins) to (best, wins) unlocks.
static func newly_unlocked(old_best: int, old_wins: int, best: int, wins: int) -> Array[String]:
	var out: Array[String] = []
	for rd in RIDERS:
		if goal_met(rd, best, wins) and not goal_met(rd, old_best, old_wins):
			out.append(rd.name)
	return out


## Portrait for rider n, or null if it hasn't been captured yet.
static func load_thumb(n: int) -> Texture2D:
	var path := THUMB_PATH % n
	if ResourceLoader.exists(path):
		return load(path)
	var file := ProjectSettings.globalize_path(path)
	if not FileAccess.file_exists(file):
		return null
	var img := Image.load_from_file(file)
	if img == null or img.is_empty():
		return null
	return ImageTexture.create_from_image(img)


## Model path for rider n on a level: the swimwear + surfboard model on surfing levels.
static func model_for(n: int, surf: bool) -> String:
	var rd := get_rider(n)
	if surf and rd.has("beach_model") and ResourceLoader.exists(rd.beach_model):
		return rd.beach_model   # (falls back to the normal model until Godot has imported it)
	return rd.model
