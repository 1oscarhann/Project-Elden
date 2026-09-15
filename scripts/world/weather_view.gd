extends Node2D

## Everything you can SEE of the weather: falling particles and a flat haze.
##
## Parented under the Camera2D, exactly like the fireflies and the drifting
## leaves from Phase 10 — that keeps the emitter over the view wherever the
## player walks, instead of trying to cover a 96x96 island with particles.
##
## It reads WeatherData and nothing else. It does not know when the weather
## changes or why; it listens for the signal and fades. Adding a weather type
## needs no change here at all.
##
## ⚠️ CPUParticles2D, not GPU: the project is on the GL Compatibility renderer
## and targets web, consistent with Phases 4, 5, 9 and 10.

## Fade in/out of the particle sheet, in seconds.
@export var fade_seconds := 2.5
## Rain is drawn ACROSS the view rather than exactly at it, so drops enter from
## past the top edge and leave past the bottom instead of popping into being.
@export var emit_extents := Vector2(210, 130)

## ⚠️ The haze is a WORLD-SPACE ColorRect under the camera, deliberately not a
## Control on a CanvasLayer. A Control only gets the viewport rect when it is a
## root control, and a CanvasLayer for it would have to sit above the HUD
## (layer 0) and below the hotbar (layer 2) — fogging the stat bars. Sized
## generously instead so it covers the view at any zoom the game ever uses,
## including the intro's 1.55.

@onready var _fall: CPUParticles2D = $Fall
@onready var _haze: ColorRect = $Haze

var _tween: Tween


func _ready() -> void:
	# ⚠️ A CPUParticles2D with no texture draws a ONE PIXEL point, which is
	# invisible under the night tint — the same trap the fireflies fell into.
	# Rain gets a real streak texture, sized per weather below.
	_fall.texture = _streak_texture()
	_fall.self_modulate.a = 0.0
	_haze.color.a = 0.0
	Weather.weather_changed.connect(_on_weather_changed)
	# Indoors the sky is a ceiling. Same signal the warmth and fire sides use,
	# so the roof is one fact the whole system agrees on.
	Weather.shelter_changed.connect(_on_shelter_changed)
	if Weather.current != null:
		_apply(Weather.current, true)


## A soft vertical streak, built rather than shipped as a PNG: it is four
## pixels of gradient and an asset file for that would be silly.
func _streak_texture() -> Texture2D:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 1.0])
	gradient.colors = PackedColorArray([
		Color(1, 1, 1, 0.0), Color(1, 1, 1, 1.0), Color(1, 1, 1, 0.0)])
	var tex := GradientTexture2D.new()
	tex.gradient = gradient
	tex.fill = GradientTexture2D.FILL_LINEAR
	tex.fill_from = Vector2(0.5, 0.0)
	tex.fill_to = Vector2(0.5, 1.0)
	tex.width = 2
	tex.height = 8
	return tex


func _on_weather_changed(data: WeatherData) -> void:
	_apply(data, false)


func _on_shelter_changed(_sheltered: bool) -> void:
	# Re-applied rather than just hidden, so walking back out into a downpour
	# fades the rain in again instead of snapping it on.
	if Weather.current != null:
		_apply(Weather.current, false)


func _apply(data: WeatherData, instant: bool) -> void:
	# Everything except the two fade targets is set immediately: an emitter
	# whose velocity is mid-tween would rain sideways for a second.
	_fall.emission_rect_extents = emit_extents
	_fall.lifetime = maxf(data.particle_lifetime, 0.05)
	_fall.color = data.particle_colour
	_fall.scale_amount_min = data.particle_size.y / 8.0
	_fall.scale_amount_max = data.particle_size.y / 8.0
	var speed := data.particle_velocity.length()
	_fall.direction = data.particle_velocity.normalized() if speed > 0.0 else Vector2.DOWN
	_fall.initial_velocity_min = speed * 0.9
	_fall.initial_velocity_max = speed * 1.1
	# Lean the streak into the direction it is falling, or slanted rain is
	# drawn as vertical drops moving diagonally, which reads as snow.
	_fall.angle_min = rad_to_deg(data.particle_velocity.angle()) - 90.0
	_fall.angle_max = _fall.angle_min
	_haze.color = Color(data.haze_colour.r, data.haze_colour.g, data.haze_colour.b,
		_haze.color.a)

	if data.particle_amount > 0:
		# ⚠️ `amount` REALLOCATES the particle system and pops every live
		# particle, and `amount_ratio` is a GPUParticles2D property that does
		# not exist here. Set the count only when it actually differs, and fade
		# with self_modulate.a — which is free and continuous.
		if _fall.amount != data.particle_amount:
			_fall.amount = data.particle_amount
		_fall.emitting = true

	# A roof stops both. Note this reads Weather rather than caching a flag:
	# the shelter count is the single source of truth for "am I under cover".
	var indoors := Weather.is_sheltered()
	var want_fall := 1.0 if data.falls() and not indoors else 0.0
	var want_haze := 0.0 if indoors else data.haze
	if instant:
		_fall.self_modulate.a = want_fall
		_haze.color.a = want_haze
		_fall.emitting = want_fall > 0.0
		return
	if _tween != null and _tween.is_running():
		_tween.kill()
	_tween = create_tween().set_parallel(true)
	_tween.tween_property(_fall, "self_modulate:a", want_fall, fade_seconds)
	_tween.tween_property(_haze, "color:a", want_haze, fade_seconds)
	# Stop emitting only once it has faded out, or the last drops vanish
	# mid-air. Left running for weather that does fall.
	if want_fall <= 0.0:
		_tween.chain().tween_callback(func(): _fall.emitting = false)
