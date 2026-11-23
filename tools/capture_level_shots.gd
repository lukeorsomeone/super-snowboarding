extends Node3D
## Dev tool: renders a 320x240 screenshot of every playable level for the level select
## cards and saves it to res://assets/levels/level_<n>.png, then quits.
## Run this scene from the editor (or: godot --path . res://tools/capture_level_shots.tscn)
## whenever a level's look changes.

const Levels := preload("res://scripts/levels.gd")
const CourseScript := preload("res://scripts/course.gd")

# [distance downhill, height above the track, look-ahead distance, sideways offset]
const SHOT := [150.0, 7.0, 90.0, -5.0]

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://assets/levels")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	var only := 0   # `-- --only=5` captures just that level
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			only = a.substr(7).to_int()
	for n in range(1, Levels.count() + 1):
		if only > 0 and n != only:
			continue
		var lv := Levels.get_level(n)
		Levels.apply_look(lv, $WorldEnvironment, $Sun)
		var course: Node3D = CourseScript.new()
		add_child(course)
		course.configure(lv)
		course.build()
		var d: float = SHOT[0]
		course.focus_d = d
		course.reset()
		course.focus_d = d
		course._update_chunks(true)
		var x: float = course.center_x(d) + SHOT[3]
		cam.global_position = Vector3(x, course.height(x, -d) + SHOT[1], -d)
		var ahead: float = d + SHOT[2]
		var tx: float = course.center_x(ahead)
		cam.look_at(Vector3(tx, course.height(tx, -ahead) + 1.5, -ahead), Vector3.UP)
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/level_%d.png" % [dir, n]
		Screen.viewport.get_texture().get_image().save_png(path)
		print("CAPTURED ", path)
		course.queue_free()
		await get_tree().process_frame
	get_tree().quit()
