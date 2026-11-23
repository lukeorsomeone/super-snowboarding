extends Node
## Dev tool: starts Sky Islands (level 3) with a rider and saves screenshots to
## res://assets/levels/dev_sky_*.png. Safe to delete.

const RIDER := 1


func _ready() -> void:
	await get_tree().process_frame
	# step out of the game screen first, because Screen.go() frees whatever is in it
	var tree := get_tree()
	get_parent().remove_child(self)
	tree.root.add_child(self)
	Screen.level = 3
	Screen.rider = RIDER
	Screen.go("res://scenes/game.tscn")
	for i in 5:
		await get_tree().create_timer(4.0).timeout
		await RenderingServer.frame_post_draw
		Screen.viewport.get_texture().get_image().save_png(ProjectSettings.globalize_path("res://assets/levels/dev_sky_%d.png" % i))
	get_tree().quit()
