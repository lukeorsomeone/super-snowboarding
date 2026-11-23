extends Node3D
## Dev tool: renders a 320x240 portrait of every rider for the rider select cards and
## saves it to res://assets/riders/rider_<n>.png, then quits.
## Run this scene from the editor (or: godot --path . res://tools/capture_rider_shots.tscn)
## after adding or changing a rider.

const Riders := preload("res://scripts/riders.gd")
const MeshUtil := preload("res://scripts/mesh_util.gd")

const CAM_POS := Vector3(0.7, 1.7, 2.6)     # in front of the rider, a little to the side
const LOOK_AT := Vector3(0.0, 1.22, 0.0)

@onready var cam: Camera3D = $Camera


func _ready() -> void:
	var dir := ProjectSettings.globalize_path("res://assets/riders")
	DirAccess.make_dir_recursive_absolute(dir)
	await get_tree().process_frame
	$Sun.rotation_degrees = Vector3(-35.0, 25.0, 0.0)
	cam.global_position = CAM_POS
	cam.look_at(LOOK_AT, Vector3.UP)
	# `-- --only=4,5,6` captures just those riders.
	var only: PackedInt32Array = []
	for a in OS.get_cmdline_user_args():
		if a.begins_with("--only="):
			for s in a.substr(7).split(","):
				only.append(int(s))
	for n in range(1, Riders.count() + 1):
		if not only.is_empty() and not only.has(n):
			continue
		var scene: PackedScene = load(Riders.get_rider(n).model)
		var rider: Node3D = scene.instantiate()
		add_child(rider)
		for mi in rider.find_children("*", "MeshInstance3D", true, false):
			MeshUtil.apply_ps1(mi)
		var anim: AnimationPlayer = rider.find_child("AnimationPlayer", true, false)
		if anim != null and anim.has_animation("ride"):
			anim.play("ride")
			anim.seek(0.4, true)
			anim.speed_scale = 0.0   # hold the riding pose
		for f in 6:
			await get_tree().process_frame
		await RenderingServer.frame_post_draw
		var path := "%s/rider_%d.png" % [dir, n]
		Screen.viewport.get_texture().get_image().save_png(path)
		print("CAPTURED ", path)
		rider.queue_free()
		await get_tree().process_frame
	get_tree().quit()
