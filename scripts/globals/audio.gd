extends Node

## Plays everything the game makes noise with.
##
## Autoload. Two responsibilities: a small pool of players for one-shot effects,
## and a pair of crossfading loops for music and ambience.
##
## Callers never hold an AudioStream — they call Audio.play("chop") with a key.
## That keeps the "which file is the chop sound" question in exactly one place,
## and means a caller in the world never has to preload anything.

const DIR := "res://assets/audio/"
## Simultaneous one-shots. Beyond this the oldest is stolen, which is normal
## for SFX and far better than spawning players without limit.
const VOICES := 8
## Crossfade for the day/night ambience swap, in seconds. Long on purpose —
## dusk should slide into crickets, not cut to them.
const AMBIENCE_FADE := 3.0
const SILENT_DB := -60.0

## Effect key -> file stem. Adding a sound is a line here and a .res file.
const SFX := {
	"step": "sfx_step",
	"chop": "sfx_chop",
	"pickup": "sfx_pickup",
	"craft": "sfx_craft",
	"place": "sfx_place",
	"ui": "sfx_ui",
	"eat": "sfx_eat",
}

var _voices: Array[AudioStreamPlayer] = []
var _next_voice := 0
var _music: AudioStreamPlayer
## Two ambience players so one can fade up while the other fades down.
var _ambience: Array[AudioStreamPlayer] = []
var _active_ambience := 0
var _current_ambience := ""
var _streams: Dictionary = {}
var _fade: Tween


func _ready() -> void:
	for i in VOICES:
		_voices.append(_make_player("SFX"))
	_music = _make_player("Music")
	for i in 2:
		var player := _make_player("Music")
		player.volume_db = SILENT_DB
		_ambience.append(player)

	# Ambience follows the clock rather than being driven from the world, so it
	# is correct the moment the game starts and stays correct through a load.
	DayNight.phase_changed.connect(_on_phase_changed)
	# Pickups are a global fact, so the blip lives here rather than being
	# re-wired into every drop site.
	Inventory.item_gained.connect(_on_item_gained)
	# Same reasoning for crafting: it is a global event, so the flourish is
	# wired once here rather than in the craft menu AND in every API caller.
	Crafting.crafted.connect(_on_crafted)


## Starts the theme and the ambience. Called by the game scene, not by _ready,
## so the main menu can choose to sit in silence.
func start_world_audio() -> void:
	play_music("music_theme")
	_on_phase_changed(DayNight.phase)


func stop_world_audio() -> void:
	_music.stop()
	for player in _ambience:
		player.stop()
	_current_ambience = ""


## One-shot by key. `pitch_jitter` de-machine-guns repeated sounds — footsteps
## especially, which would otherwise be audibly identical every stride.
func play(key: String, pitch_jitter := 0.08, volume_db := 0.0) -> void:
	if not SFX.has(key):
		push_error("Audio: no sound registered for '%s'" % key)
		return
	var stream := _stream(SFX[key])
	if stream == null:
		return
	var player := _voices[_next_voice]
	_next_voice = (_next_voice + 1) % VOICES
	player.stream = stream
	player.pitch_scale = 1.0 + randf_range(-pitch_jitter, pitch_jitter)
	player.volume_db = volume_db
	player.play()


func play_music(stem: String) -> void:
	var stream := _stream(stem)
	if stream == null or (_music.playing and _music.stream == stream):
		return
	_music.stream = stream
	_music.volume_db = 0.0
	_music.play()


## Swaps the looping background bed, crossfading rather than cutting.
func play_ambience(stem: String) -> void:
	if stem == _current_ambience:
		return
	var stream := _stream(stem)
	if stream == null:
		return
	_current_ambience = stem
	var incoming: AudioStreamPlayer = _ambience[1 - _active_ambience]
	var outgoing: AudioStreamPlayer = _ambience[_active_ambience]
	_active_ambience = 1 - _active_ambience

	incoming.stream = stream
	incoming.volume_db = SILENT_DB
	incoming.play()
	if _fade != null and _fade.is_running():
		_fade.kill()
	_fade = create_tween().set_parallel(true)
	_fade.tween_property(incoming, "volume_db", 0.0, AMBIENCE_FADE)
	_fade.tween_property(outgoing, "volume_db", SILENT_DB, AMBIENCE_FADE)
	# Chained rather than parallel so it stops only once it is actually silent.
	_fade.chain().tween_callback(outgoing.stop)


func _make_player(bus: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.bus = bus
	# Menus and the pause screen stop the tree; audio should keep going.
	player.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(player)
	return player


## Loads and caches a stream. A missing file warns once rather than every time
## the sound is asked for.
func _stream(stem: String) -> AudioStream:
	if _streams.has(stem):
		return _streams[stem]
	var path := DIR + stem + ".res"
	var stream: AudioStream = null
	if ResourceLoader.exists(path):
		stream = load(path) as AudioStream
	else:
		push_warning("Audio: %s is missing — run tools/build_audio.gd" % path)
	_streams[stem] = stream
	return stream


func _on_phase_changed(phase: DayNight.Phase) -> void:
	# Dusk already counts as night: the crickets should be in before it is dark,
	# which is also when warmth starts draining.
	var night := phase == DayNight.Phase.NIGHT or phase == DayNight.Phase.DUSK
	play_ambience("amb_night" if night else "amb_day")


func _on_item_gained(_id: String, _count: int) -> void:
	play("pickup")


func _on_crafted(_recipe: RecipeData) -> void:
	play("craft")
