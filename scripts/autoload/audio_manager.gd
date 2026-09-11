extends Node

## Autoload. Music + SFX (SPEC §5).
##
## All audio ships as .ogg (SPEC §8). Note this system has no slot in the
## build order yet — see docs/REVIEW.md.

func play_music(_track: StringName, _fade_seconds: float = 1.0) -> void:
	push_error("AudioManager.play_music() not implemented")


func play_sfx(_sound: StringName) -> void:
	push_error("AudioManager.play_sfx() not implemented")
