extends Node3D
## Dev tool: renders scenic 320x240 shots of the valley for the title screen background.
## Run:  godot --path . res://tools/capture_title_bg.tscn -- --out=<folder>
## Saves shot_<n>.png for each camera spot in SHOTS, then quits.

# [distance downhill, height above the track, look-ahead distance, sideways offset]
const SHOTS := [
	[-30.0, 14.0, 160.0, 0.0],
	[140.0, 10.0, 180.0, -6.0],
	[420.0, 18.0, 220.0, 8.0],
	[60.0, 4.0, 120.0, 10.0],
]

@onready var course: Node3D = $Course
@onready var cam: Camera3D = $Camera


func _ready() -> void:
	$Sun.rotation_degrees = Vector3(-48.0, 30.0, 0.0)
	course.build()
	course.reset()
	var out := OS.get_user_data_dir()
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--out="):
			out = a.substr(6)
	await get_tree().process_frame
	for i in SHOTS.size():
		var s: Array = SHOTS[i]
		var d: float = s[0]
		course.focus_d = maxf(d, 0.0)
		course.reset()                     # make sure chunks around this spot exist
		course.focus_d = maxf(d, 0.0)
		course._update_chunks(true)
		var x: float = course.center_x(d) + s[3]
		var pos := Vector3(x, course.height(x, -d) + s[1], -d)
		var ahead: float = d + s[2]
		var tx: float = course.center_x(ahead)
		var target := Vector3(tx, course.height(tx, -ahead) + 2.0, -ahead)
		cam.global_position = pos
		cam.look_at(target, Vector3.UP)
		for f in 4:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		Screen.viewport.get_texture().get_image().save_png("%s/shot_%d.png" % [out, i])
	get_tree().quit()
