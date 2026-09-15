shader_type canvas_item;

// Darkens and desaturates whatever is already on screen, for the opening.
//
// The brief asks for "world visible but darkened/desaturated, not black", and
// desaturation cannot be done by modulating a colour over the top — modulate
// only multiplies, so it can tint and darken but never pull the saturation
// out. That needs to READ the screen, which is what hint_screen_texture does.
//
// The rect is drawn over everything with `amount` tweened 0 -> 1, so at 0 it
// is provably a no-op and the effect can be measured by diffing two frames.

uniform sampler2D screen_tex : hint_screen_texture, filter_nearest;

// 0 = untouched world, 1 = full effect. Tweened by intro.gd.
uniform float amount : hint_range(0.0, 1.0) = 1.0;
// How much colour is drained at full effect. Not 1.0 — a fully grey island
// reads as a broken shader rather than as a memory.
uniform float desaturate : hint_range(0.0, 1.0) = 0.72;
// How far the brightness drops at full effect.
uniform float darken : hint_range(0.0, 1.0) = 0.55;
// Cold tint pushed into the drained colour, so the beach reads as dusk rather
// than as a black-and-white photograph.
uniform vec3 cool = vec3(0.72, 0.80, 1.0);

void fragment() {
	vec3 src = texture(screen_tex, SCREEN_UV).rgb;
	// Rec. 709 luma: the human-weighted grey, not a flat channel average.
	float luma = dot(src, vec3(0.2126, 0.7152, 0.0722));
	vec3 drained = mix(src, vec3(luma), desaturate) * (1.0 - darken) * cool;
	COLOR = vec4(mix(src, drained, amount), 1.0);
}
