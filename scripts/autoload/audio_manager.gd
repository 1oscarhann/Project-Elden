extends Node

## Autoload. Music + SFX (SPEC §5). All audio ships as .ogg (SPEC §8).
##
## Two music players so a track can cross-fade into the battle theme and back
## out without a gap — the overworld-to-battle swap is the most audible seam
## in the whole game.

const BUS_MUSIC := &"Music"
const BUS_SFX := &"SFX"
const FADE_SECONDS := 0.8

var _players: Array[AudioStreamPlayer] = []
var _active: int = 0
var _sfx: AudioStreamPlayer
var _current_track: String = ""


func _ready() -> void:
	for i in 2:
		var player := AudioStreamPlayer.new()
		player.bus = BUS_MUSIC if AudioServer.get_bus_index(BUS_MUSIC) != -1 else &"Master"
		add_child(player)
		_players.append(player)

	_sfx = AudioStreamPlayer.new()
	_sfx.bus = BUS_SFX if AudioServer.get_bus_index(BUS_SFX) != -1 else &"Master"
	add_child(_sfx)


func play_music(stream_path: String, fade_seconds: float = FADE_SECONDS) -> void:
	if stream_path == _current_track:
		return
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		push_warning("AudioManager: no stream at %s" % stream_path)
		return

	_current_track = stream_path
	var outgoing: AudioStreamPlayer = _players[_active]
	_active = 1 - _active
	var incoming: AudioStreamPlayer = _players[_active]

	incoming.stream = stream
	incoming.volume_db = -40.0
	incoming.play()

	var tween := create_tween().set_parallel(true)
	tween.tween_property(incoming, "volume_db", 0.0, fade_seconds)
	if outgoing.playing:
		tween.tween_property(outgoing, "volume_db", -40.0, fade_seconds)
		tween.chain().tween_callback(outgoing.stop)


func stop_music(fade_seconds: float = FADE_SECONDS) -> void:
	_current_track = ""
	for player in _players:
		if player.playing:
			var tween := create_tween()
			tween.tween_property(player, "volume_db", -40.0, fade_seconds)
			tween.tween_callback(player.stop)


func play_sfx(stream_path: String) -> void:
	var stream: AudioStream = load(stream_path) as AudioStream
	if stream == null:
		return
	_sfx.stream = stream
	_sfx.play()
