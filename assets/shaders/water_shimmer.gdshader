shader_type canvas_item;

// Gentle shimmer for the sea, applied to the whole water TileMapLayer.
//
// The sheet's four animation frames differ by only 2-4% of their pixels, so
// frame-cycling alone reads as a static sea. This adds movement on top without
// touching the source art.
//
// Two things it deliberately does NOT do:
//  * It never samples outside the tile's own atlas region. A TileMapLayer packs
//    every tile into one texture, so nudging UV in texture space would drag a
//    neighbouring tile's pixels in. The distortion is applied to a SEPARATE
//    noise lookup, and only the COLOUR is modulated — the texture is read at
//    its true UV, so tiles stay seamless at their edges.
//  * It never brightens transparent pixels, so the shoreline's soft alpha edge
//    is left exactly as drawn.
//
// All three wave periods divide into LOOP_SECONDS, so the whole effect repeats
// seamlessly rather than drifting.

// How long one full cycle takes. Slow on purpose — this is a shimmer, not surf.
uniform float loop_seconds : hint_range(2.0, 30.0) = 12.0;
// Peak brightness added at a sparkle. Small: the sea should breathe, not strobe.
uniform float shimmer_strength : hint_range(0.0, 0.5) = 0.085;
// Size of the moving highlight bands, in world pixels.
uniform float band_size : hint_range(4.0, 128.0) = 34.0;
// Slight cool/warm shift so the ripple reads as water rather than a grey flash.
uniform vec3 shimmer_tint = vec3(0.72, 0.90, 1.0);

void fragment() {
	vec4 base = texture(TEXTURE, UV);
	// Fully transparent pixels are the gaps the land shows through. Leave them.
	if (base.a < 0.01) {
		COLOR = base;
	} else {
		float t = TAU * TIME / loop_seconds;
		vec2 p = FRAGCOORD.xy / band_size;

		// Three drifting waves at whole-number rates, so the sum has exactly
		// the period of loop_seconds and cannot pop when it wraps.
		float a = sin(p.x * 0.9 + p.y * 0.45 + t);
		float b = sin(p.x * -0.55 + p.y * 1.10 + t * 2.0);
		float c = sin((p.x + p.y) * 0.35 - t * 3.0);
		float wave = (a + b + c) / 3.0;

		// Bias upward and sharpen, so most of the sea sits calm and only the
		// crests catch the light — a sparkle, not an overall brightening.
		float crest = pow(clamp(wave * 0.5 + 0.5, 0.0, 1.0), 3.0);

		vec3 lit = base.rgb + shimmer_tint * crest * shimmer_strength;
		COLOR = vec4(clamp(lit, vec3(0.0), vec3(1.0)), base.a);
	}
}
