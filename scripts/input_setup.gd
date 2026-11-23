extends RefCounted
## Registers the game's input actions at runtime (keyboard + gamepad),
## so project.godot doesn't need a hand-written input map.
##
## Gamepad layout (Xbox names; PlayStation: A=Cross, B=Circle, Y=Triangle, LB/RB=L1/R1, LT/RT=L2/R2):
##   Left stick / D-pad  steer (and spin in the air)
##   Stick up / RT / RB  tuck          Stick down / LT / LB  brake
##   A                   jump / confirm
##   Y                   restart
##   B                   back
##   Start               pause (and confirm on menus)


static func setup() -> void:
	_add("steer_left", [KEY_A, KEY_LEFT], [JOY_BUTTON_DPAD_LEFT], [[JOY_AXIS_LEFT_X, -1.0]], 0.2)
	_add("steer_right", [KEY_D, KEY_RIGHT], [JOY_BUTTON_DPAD_RIGHT], [[JOY_AXIS_LEFT_X, 1.0]], 0.2)
	_add("tuck", [KEY_W, KEY_UP], [JOY_BUTTON_RIGHT_SHOULDER, JOY_BUTTON_DPAD_UP],
		[[JOY_AXIS_TRIGGER_RIGHT, 1.0], [JOY_AXIS_LEFT_Y, -1.0]], 0.5)
	_add("brake", [KEY_S, KEY_DOWN], [JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_DPAD_DOWN],
		[[JOY_AXIS_TRIGGER_LEFT, 1.0], [JOY_AXIS_LEFT_Y, 1.0]], 0.5)
	_add("jump", [KEY_SPACE], [JOY_BUTTON_A])
	_add("confirm", [KEY_ENTER, KEY_KP_ENTER, KEY_SPACE], [JOY_BUTTON_A, JOY_BUTTON_START])
	_add("restart", [KEY_R], [JOY_BUTTON_Y])
	_add("back", [KEY_ESCAPE], [JOY_BUTTON_B, JOY_BUTTON_BACK])
	_add("pause", [KEY_ESCAPE, KEY_P], [JOY_BUTTON_START])
	if not InputMap.has_action("click"):
		InputMap.add_action("click")
		var mb := InputEventMouseButton.new()
		mb.button_index = MOUSE_BUTTON_LEFT
		InputMap.action_add_event("click", mb)


## axes: list of [axis, direction] pairs, e.g. [[JOY_AXIS_LEFT_X, -1.0]].
static func _add(action: String, keys: Array, buttons: Array, axes: Array = [], deadzone: float = 0.25) -> void:
	if InputMap.has_action(action):
		return
	InputMap.add_action(action, deadzone)
	for k in keys:
		var ev := InputEventKey.new()
		ev.physical_keycode = k
		InputMap.action_add_event(action, ev)
	for b in buttons:
		var jb := InputEventJoypadButton.new()
		jb.button_index = b
		InputMap.action_add_event(action, jb)
	for a in axes:
		var jm := InputEventJoypadMotion.new()
		jm.axis = a[0]
		jm.axis_value = a[1]
		InputMap.action_add_event(action, jm)
