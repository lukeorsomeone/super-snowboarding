extends RefCounted
## One roguelike run: ride all 8 levels in order on one set of lives, picking an item after
## each stage. Screen.run holds the current run so it survives scene changes.
## Finishing unlock goals adds new items to the pool for future runs (saved).

const Riders := preload("res://scripts/riders.gd")
const SAVE_PATH := "user://super_snowboarding.cfg"
const STAGES := 8
const START_LIVES := 3
const REROLL_BASE := 10         # gifts for the first reroll
const REROLL_STEP := 5          # each reroll in a run costs this much more
const ADRENALINE_STEP := 5000   # trick points per extra life with ADRENALINE

## Items with a "goal" start locked until the goal is met in a run.
const ITEMS := [
	{"id": "wax", "name": "WAXED BASE", "desc": "10% HIGHER TOP SPEED"},
	{"id": "bindings", "name": "STICKY BINDINGS", "desc": "STEER 20% FASTER"},
	{"id": "boots", "name": "SPRING BOOTS", "desc": "JUMP 30% HIGHER"},
	{"id": "cocoa", "name": "HOT COCOA", "desc": "+1 MAX LIFE AND HEAL 1"},
	{"id": "magnet", "name": "GIFT MAGNET", "desc": "GRAB GIFTS FROM FAR AWAY"},
	{"id": "socks", "name": "LUCKY SOCKS", "desc": "IGNORE YOUR FIRST CRASH EACH STAGE"},
	{"id": "slim", "name": "SLIM FIT", "desc": "OBSTACLES HIT YOU 25% LESS"},
	{"id": "spin", "name": "SPIN CYCLE", "desc": "SPIN 25% FASTER, MORE SPIN POINTS"},
	{"id": "flip", "name": "FLIP JUICE", "desc": "FLIP 20% FASTER"},
	{"id": "soft", "name": "SOFT LANDING", "desc": "SLOPPY LANDINGS DON'T CRASH"},
	{"id": "tutor", "name": "TRICK TUTOR", "desc": "TRICKS SCORE 50% MORE"},
	{"id": "piggy", "name": "PIGGY BANK", "desc": "GIFTS SCORE DOUBLE"},
	{"id": "feather", "name": "FEATHER SCARF", "desc": "20% LESS GRAVITY IN THE AIR",
		"goal": "REACH STAGE 3"},
	{"id": "wind", "name": "SECOND WIND", "desc": "TWICE THE SAFE TIME AFTER A CRASH",
		"goal": "REACH STAGE 5"},
	{"id": "ghost", "name": "GHOST WAX", "desc": "PHASE THROUGH AN OBSTACLE EVERY 12 SEC",
		"goal": "PLAY 5 RUNS"},
	{"id": "glass", "name": "GLASS BOARD", "desc": "DOUBLE ALL SCORE BUT ONLY 1 LIFE",
		"goal": "CLEAR A STAGE WITHOUT CRASHING"},
	{"id": "rocket", "name": "ROCKET BOARD", "desc": "LANDING A TRICK GIVES A SPEED BOOST",
		"goal": "LAND A DOUBLE FLIP"},
	{"id": "adrenaline", "name": "ADRENALINE", "desc": "+1 LIFE EVERY 5000 TRICK POINTS",
		"goal": "SCORE 10000 TRICK POINTS IN A RUN"},
	{"id": "santa", "name": "SANTA'S SACK", "desc": "+1 LIFE EVERY 25 GIFTS",
		"goal": "COLLECT 100 GIFTS IN A RUN"},
	{"id": "phoenix", "name": "PHOENIX FEATHER", "desc": "SURVIVE YOUR LAST CRASH ONCE",
		"goal": "BEAT THE MOON"},
]

var stage := 1
var lives := START_LIVES
var max_lives := START_LIVES
var score := 0                  # banked from finished stages
var gifts := 0                  # spendable on rerolls
var gifts_total := 0
var trick_points := 0
var next_adrenaline := ADRENALINE_STEP
var best_flips := 0
var clean_stage := false        # cleared at least one stage with no crash
var rerolls := 0
var phoenix_used := false
var cheated := false            # used the debug menu: nothing from this run is saved
var finished := false
var items: Array[String] = []
var _rng := RandomNumberGenerator.new()


func _init() -> void:
	_rng.randomize()


static func get_item(id: String) -> Dictionary:
	for it in ITEMS:
		if it.id == id:
			return it
	return {}


func has(id: String) -> bool:
	return items.has(id)


## Metres to the finish line of a stage: gets longer as the run goes on.
func stage_length(n: int = stage) -> float:
	return 1200.0 + 200.0 * (n - 1)


func add_item(id: String) -> void:
	if items.has(id):
		return
	items.append(id)
	if id == "cocoa":
		max_lives += 1
		heal()
	elif id == "glass":
		max_lives = 1
		lives = 1


func heal() -> bool:
	if lives >= max_lives:
		return false
	lives += 1
	return true


func trick_multiplier() -> float:
	return (1.5 if has("tutor") else 1.0) * (2.0 if has("glass") else 1.0)


func gift_value() -> int:
	return 50 * (2 if has("piggy") else 1) * (2 if has("glass") else 1)


func reroll_cost() -> int:
	return REROLL_BASE + rerolls * REROLL_STEP


## Up to three different items this run doesn't have yet, from the unlocked pool.
func roll_offers() -> Array[String]:
	var pool: Array[String] = []
	var unlocked := unlocked_ids()
	for id in unlocked:
		if items.has(id):
			continue
		if id == "cocoa" and has("glass"):
			continue   # extra lives would undo the Glass Board's catch
		pool.append(id)
	for i in range(pool.size() - 1, 0, -1):
		var j := _rng.randi_range(0, i)
		var t := pool[i]
		pool[i] = pool[j]
		pool[j] = t
	return pool.slice(0, 3)


static func unlocked_ids() -> Array[String]:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var out: Array[String] = []
	for it in ITEMS:
		if not it.has("goal") or cfg.get_value("roguelike", "item_" + it.id, false):
			out.append(it.id)
	return out


static func load_best_stage() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg.get_value("roguelike", "best_stage", 0)


static func load_wins() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	return cfg.get_value("roguelike", "wins", 0)


## Saves reaching stage n straight away, so riders unlock mid-run. Returns their names.
func reach_stage(n: int) -> Array[String]:
	if cheated:
		return []
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	var old_best: int = cfg.get_value("roguelike", "best_stage", 0)
	if n <= old_best:
		return []
	cfg.set_value("roguelike", "best_stage", n)
	cfg.save(SAVE_PATH)
	var wins: int = cfg.get_value("roguelike", "wins", 0)
	return Riders.newly_unlocked(old_best, wins, n, wins)


## Records the finished run once. Returns {new_best, best_score, unlocked: [item names], riders: [names]}.
func finish(won: bool, total: int) -> Dictionary:
	var result := {"new_best": false, "best_score": 0, "unlocked": [], "riders": []}
	var cfg := ConfigFile.new()
	cfg.load(SAVE_PATH)
	result.best_score = cfg.get_value("roguelike", "best_score", 0)
	if finished or cheated:
		finished = true
		return result
	finished = true
	var old_best: int = cfg.get_value("roguelike", "best_stage", 0)
	var old_wins: int = cfg.get_value("roguelike", "wins", 0)
	var runs: int = cfg.get_value("roguelike", "runs", 0) + 1
	var wins: int = cfg.get_value("roguelike", "wins", 0) + (1 if won else 0)
	cfg.set_value("roguelike", "runs", runs)
	cfg.set_value("roguelike", "wins", wins)
	var best_stage := maxi(old_best, stage)
	cfg.set_value("roguelike", "best_stage", best_stage)
	result.riders = Riders.newly_unlocked(old_best, old_wins, best_stage, wins)
	if total > result.best_score:
		result.new_best = true
		result.best_score = total
		cfg.set_value("roguelike", "best_score", total)
	var met := {
		"feather": stage >= 3,
		"wind": stage >= 5,
		"ghost": runs >= 5,
		"glass": clean_stage,
		"rocket": best_flips >= 2,
		"adrenaline": trick_points >= 10000,
		"santa": gifts_total >= 100,
		"phoenix": wins >= 1,
	}
	for id in met:
		if met[id] and not cfg.get_value("roguelike", "item_" + id, false):
			cfg.set_value("roguelike", "item_" + id, true)
			result.unlocked.append(get_item(id).name)
	cfg.save(SAVE_PATH)
	return result
