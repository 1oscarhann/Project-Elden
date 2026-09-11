extends Node

## Authoring tool. Writes the input map into project.godot.
##
##   godot --headless --path . res://scripts/tools/setup_input.tscn
##
## Run as a SCENE, not with --script: a --script MainLoop never registers the
## autoload globals, so any script referencing GameState or BattleManager fails
## to compile, load() hands back null, and the generated scene silently loses
## it — which is why _require_script() exists.
##
## Done in code so the bindings are reviewable as a diff instead of as a wall
## of Object(InputEventKey, ...) blobs nobody reads.

const ACTIONS := {
	"move_forward": [KEY_W, KEY_UP],
	"move_back": [KEY_S, KEY_DOWN],
	"move_left": [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump": [KEY_SPACE],
	"look_left": [KEY_J],
	"look_right": [KEY_L],
	"look_up": [KEY_I],
	"look_down": [KEY_K],
	"quick_save": [KEY_F5],
	"interact": [KEY_E, KEY_ENTER],
}

const JOY_AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_forward": [JOY_AXIS_LEFT_Y, -1.0],
	"move_back": [JOY_AXIS_LEFT_Y, 1.0],
	"look_left": [JOY_AXIS_RIGHT_X, -1.0],
	"look_right": [JOY_AXIS_RIGHT_X, 1.0],
	"look_up": [JOY_AXIS_RIGHT_Y, -1.0],
	"look_down": [JOY_AXIS_RIGHT_Y, 1.0],
}


func _ready() -> void:
	for action in ACTIONS:
		var events: Array = []
		for keycode in ACTIONS[action]:
			var key := InputEventKey.new()
			key.physical_keycode = keycode
			events.append(key)
		if JOY_AXES.has(action):
			var motion := InputEventJoypadMotion.new()
			motion.axis = JOY_AXES[action][0]
			motion.axis_value = JOY_AXES[action][1]
			events.append(motion)

		ProjectSettings.set_setting(
			"input/%s" % action, {"deadzone": 0.2, "events": events}
		)

	var err: int = ProjectSettings.save()
	print("input map written (%d actions), err=%d" % [ACTIONS.size(), err])
	get_tree().quit()
