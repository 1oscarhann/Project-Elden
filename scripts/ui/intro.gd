extends CanvasLayer

## The opening: letterbox bars, a typewriter line box over a dimmed island, and
## one camera shot.
##
## Plays ONCE per save. The flag lives on GameState (and therefore in the save
## file), because this node is instanced fresh with every scene load and has
## nowhere of its own to remember anything. See `GameState.intro_shown` and
## `SaveManager.new_game`, which is the only place it is ever cleared.
##
## ⚠️ The camera shot is NOT owned by this file. It calls play() on an
## AnimationPlayer sitting on the Camera2D and waits; it does not know what is
## animated, for how long, or how many tracks there are. That is deliberate —
## the placeholder is one slow zoom, and replacing it with a hand-keyframed
## multi-shot sequence is an edit to `resources/animations/intro_camera.tres`
## and nothing else.

## The lines, in order. Text only — pacing is below, so rewriting the opening
## never means touching the typewriter.
@export var lines: PackedStringArray = [
	"Your plane went down over open water.",
	"You swam until your feet found sand.",
	"This island... you don't know where it is, or if anyone knows you're here.",
]

@export_group("Pacing")
## Characters per second. Slow enough to read along with, fast enough that
## nobody reaches for the skip on the first line.
@export var chars_per_second := 26.0
## Held after a line finishes typing before the arrow starts blinking, so a
## fast reader's keypress does not eat the line they just triggered.
@export var settle_seconds := 0.35
@export var bar_seconds := 0.6
@export var fade_out_seconds := 0.8
## How tall the black bars grow, as a share of the screen height each.
@export_range(0.0, 0.3) var bar_height_ratio := 0.14

@export_group("Camera")
## Name of the animation to play on the camera's AnimationPlayer. Kept as a
## string so swapping in a different shot needs no code change.
@export var camera_animation := "intro"
## Node name of the AnimationPlayer under the camera.
@export var camera_player_name := "IntroAnim"
## Restored when the shot ends, whatever zoom the animation happened to stop on.
## Exported rather than read off the camera at the start, because the animation
## may well have its first keyframe at frame zero and overwrite it first.
@export var play_zoom := Vector2(2, 2)

## The in-game overlays the opening lifts out of the way. HUD and hotbar both
## join it in their own _ready, so this never holds a path to either — and a
## later overlay joins the group rather than being added to a list here.
const HUD_GROUP := "game_hud"

signal finished

@onready var _root: Control = $Root
@onready var _dim: ColorRect = $Root/Dim
@onready var _top: ColorRect = $Root/BarTop
@onready var _bottom: ColorRect = $Root/BarBottom
@onready var _box: PanelContainer = $Root/Box
@onready var _line: Label = $Root/Box/Pad/Line
@onready var _arrow: Label = $Root/Box/Arrow
@onready var _skip: Label = $Root/Skip

var _index := 0
## How much of the current line has been typed, in characters. Fractional so
## the speed is delta-based rather than tied to a timer's tick.
var _typed := 0.0
var _settling := 0.0
var _running := false
var _camera: PlayerCamera


func _ready() -> void:
	# ⚠️ BEFORE anything pauses the tree. A node only told to ignore the pause
	# afterwards never runs again to be told.
	process_mode = Node.PROCESS_MODE_ALWAYS
	_root.visible = false
	if GameState.intro_shown:
		# Nothing to do and nothing to show: get out of the way entirely rather
		# than sitting in the tree swallowing input.
		queue_free()
		return
	# One frame, so the world has built and the camera has snapped to the
	# player. Dimming an unbuilt island would dim the clear colour.
	await get_tree().process_frame
	_begin()


func _begin() -> void:
	_running = true
	_index = 0
	_typed = 0.0
	_settling = 0.0
	_line.text = ""
	_arrow.visible = false
	_root.visible = true
	_top.custom_minimum_size = Vector2.ZERO
	_bottom.custom_minimum_size = Vector2.ZERO

	_start_camera()
	_show_hud(false)
	get_tree().paused = true

	var height: float = _root.size.y * bar_height_ratio
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_top, "offset_bottom", height, bar_seconds)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_bottom, "offset_top", -height, bar_seconds)\
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.tween_property(_dim.material, "shader_parameter/amount", 1.0, bar_seconds)
	_box.modulate.a = 0.0
	_skip.modulate.a = 0.0
	tween.tween_property(_box, "modulate:a", 1.0, bar_seconds)
	tween.tween_property(_skip, "modulate:a", 1.0, bar_seconds)


## Hands the camera to the animation. The camera's own follow is suspended
## rather than fought with — see PlayerCamera.cinematic.
func _start_camera() -> void:
	var cameras := get_tree().get_nodes_in_group(PlayerCamera.GROUP)
	if cameras.is_empty():
		return
	_camera = cameras[0] as PlayerCamera
	# ALWAYS, and set before the pause below, or the shot freezes on frame one.
	_camera.process_mode = Node.PROCESS_MODE_ALWAYS
	_camera.cinematic = true
	_camera.snap_to_target()
	var anim := _camera.get_node_or_null(camera_player_name) as AnimationPlayer
	if anim == null or not anim.has_animation(camera_animation):
		push_warning("Intro: no '%s' animation on the camera" % camera_animation)
		return
	anim.process_mode = Node.PROCESS_MODE_ALWAYS
	anim.play(camera_animation)


func _process(delta: float) -> void:
	if not _running:
		return
	_blink()
	if _index >= lines.size():
		return
	var length := float(lines[_index].length())
	if _typed >= length:
		_settling = minf(_settling + delta, settle_seconds)
		return
	_typed = minf(_typed + chars_per_second * delta, length)
	_line.text = lines[_index].substr(0, int(_typed))


## The arrow only blinks once the line is finished AND settled, so it means
## "there is more" rather than "I am busy".
## Wall-clock rather than accumulated delta, so the blink is the same speed on
## any machine — and headless runs _process uncapped, which would make an
## accumulated one strobe.
func _blink() -> void:
	var ready_for_input := _line_complete() and _settling >= settle_seconds
	_arrow.visible = ready_for_input
	if not ready_for_input:
		return
	_arrow.modulate.a = 0.35 + 0.65 * (0.5 + 0.5 * sin(Time.get_ticks_msec() * 0.006))


func _line_complete() -> bool:
	return _index < lines.size() and _typed >= float(lines[_index].length())


func _unhandled_input(event: InputEvent) -> void:
	if not _running:
		return
	if not (event is InputEventKey or event is InputEventMouseButton
			or event is InputEventScreenTouch or event is InputEventJoypadButton):
		return
	if not event.is_pressed() or event.is_echo():
		return
	get_viewport().set_input_as_handled()
	advance()


## One press finishes a half-typed line; the next moves on. Never both at once,
## or a fast reader skips a line they never saw.
func advance() -> void:
	if not _running:
		return
	Audio.play("ui")
	if not _line_complete():
		_typed = float(lines[_index].length())
		_line.text = lines[_index]
		_settling = settle_seconds
		return
	_index += 1
	_typed = 0.0
	_settling = 0.0
	_arrow.visible = false
	if _index >= lines.size():
		_end()
		return
	_line.text = ""


func _end() -> void:
	_running = false
	# ⚠️ Set BEFORE the tween finishes, not after. If anything goes wrong past
	# this point the player still has their camera and their game back.
	GameState.intro_shown = true
	_release_camera()
	_show_hud(true)
	get_tree().paused = false
	var tween := create_tween().set_parallel(true)
	tween.tween_property(_root, "modulate:a", 0.0, fade_out_seconds)
	tween.tween_property(_dim.material, "shader_parameter/amount", 0.0, fade_out_seconds)
	tween.chain().tween_callback(func():
		finished.emit()
		queue_free())


func _release_camera() -> void:
	if _camera == null or not is_instance_valid(_camera):
		return
	var anim := _camera.get_node_or_null(camera_player_name) as AnimationPlayer
	if anim != null and anim.is_playing():
		# Stopped rather than let to run out: the intro's length is however long
		# the player took to read, and the shot should not outlive it.
		anim.stop()
	# Whatever zoom the animation left behind, put the play zoom back.
	_camera.zoom = play_zoom
	_camera.cinematic = false
	# Back to inheriting, or the camera keeps running through the pause menu.
	_camera.process_mode = Node.PROCESS_MODE_INHERIT
	_camera.snap_to_target()
	_camera = null


## A cutscene shows the world, not the bag and the stat bars. Hidden rather
## than dimmed: dimmed, the keybind hints were still perfectly legible through
## the shader and read as clutter over the opening.
func _show_hud(shown: bool) -> void:
	for node in get_tree().get_nodes_in_group(HUD_GROUP):
		if node is CanvasLayer or node is CanvasItem:
			node.visible = shown


func _exit_tree() -> void:
	# A quit or a load mid-intro must not leave the tree paused, the HUD hidden
	# or the camera stuck in a cutscene it will never come out of.
	if _running:
		_release_camera()
		_show_hud(true)
		get_tree().paused = false
