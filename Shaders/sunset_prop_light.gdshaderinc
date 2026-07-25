// How it works:
// - Every drawn prop at the stop was painted in flat daylight, so dropped into
//   a sunset it reads as a sticker. This relights one already-sampled pixel to
//   belong to the shot instead.
// - Four passes, back to front: haze mixes the whole prop toward the horizon
//   color to place it at a distance, shade pushes it into cool twilight because
//   the sun is behind it, bounce warms its lower edge off the lit ground, and a
//   rim burns the contour that actually faces the sun.
// - The rim mask is supplied by the caller, because Godot will not let a user
//   function take the built-in TEXTURE sampler. Sample alpha one step along
//   sun_direction: solid here and open there means this pixel is on the lit
//   contour. build_sunset_rim_mask turns that pair into the mask.
// - sun_direction is authored to match SurfacePresentation.sun_screen_position.
//   The sun is effectively at infinity for props this size, so one direction per
//   prop is correct and needs no runtime publishing.
// - Loop-free, one extra texture tap, for GL Compatibility and the web export.

// Unit vector from the prop toward the sun, in texture space. Y grows downward,
// so the authored setting is a hair below level: the sun is on the horizon.
uniform vec2 sun_direction = vec2(0.96, 0.28);

// Cool fill standing in for the sky the prop is actually lit by once the sun is
// behind it. Strength 0 leaves the daylight art untouched.
uniform vec4 shade_color : source_color = vec4(0.30, 0.29, 0.46, 1.0);
uniform float shade_strength : hint_range(0.0, 1.0) = 0.5;
// How much of the art's own hue survives the shade. Backlit props go nearly
// monochrome, which is what stops a blue bus reading as a daylight blue bus.
uniform float shade_desaturation : hint_range(0.0, 1.0) = 0.45;

// Warm light spilling around the sun-facing contour.
uniform vec4 rim_color : source_color = vec4(1.0, 0.80, 0.46, 1.0);
uniform float rim_strength : hint_range(0.0, 3.0) = 1.1;
// Contour thickness, in texels of this prop's own texture.
uniform float rim_texels : hint_range(0.0, 24.0) = 4.0;

// Warm light coming back up off the lit ground, over the bottom of the prop.
uniform vec4 bounce_color : source_color = vec4(1.0, 0.55, 0.28, 1.0);
uniform float bounce_strength : hint_range(0.0, 1.0) = 0.22;
// Fraction of the prop's height the bounce reaches up from its base.
uniform float bounce_height : hint_range(0.0, 1.0) = 0.34;

// Atmosphere between the camera and the prop. This is what separates a far band
// from a near one when both are the same artwork.
uniform vec4 haze_color : source_color = vec4(1.0, 0.55, 0.30, 1.0);
uniform float haze_strength : hint_range(0.0, 1.0) = 0.0;

// Turns a pair of alpha taps into the lit contour. coverage is this pixel's own
// alpha; sunward_coverage is alpha one rim step toward the sun. The contour is
// where the prop is solid and its sunward neighbour is not.
float build_sunset_rim_mask(float coverage, float sunward_coverage) {
	return clamp(coverage - sunward_coverage, 0.0, 1.0);
}

// Relights one drawn pixel. uv_y is the pixel's height inside the sprite, where
// 0 is its top edge and 1 its base, and drives the ground bounce only.
vec3 apply_sunset_prop_light(vec3 art_color, float rim_mask, float uv_y) {
	// Distance first: haze sits between the camera and everything else here.
	vec3 lit_color = mix(
		art_color,
		haze_color.rgb,
		clamp(haze_strength, 0.0, 1.0)
	);

	// Drain the daylight hue, then fill with sky. Doing it in this order keeps
	// a dark prop dark instead of washing it toward the fill color.
	float art_value = dot(lit_color, vec3(0.299, 0.587, 0.114));
	lit_color = mix(
		lit_color,
		vec3(art_value),
		clamp(shade_desaturation, 0.0, 1.0)
	);
	lit_color = mix(
		lit_color,
		lit_color * shade_color.rgb * 2.0,
		clamp(shade_strength, 0.0, 1.0)
	);

	// Ground bounce, strongest at the base and gone by bounce_height.
	float bounce = smoothstep(
		1.0 - clamp(bounce_height, 0.01, 1.0),
		1.0,
		clamp(uv_y, 0.0, 1.0)
	);
	lit_color += bounce_color.rgb * bounce * clamp(bounce_strength, 0.0, 1.0);

	// Rim last, so nothing above dulls the one part of the prop the sun reaches.
	return lit_color + rim_color.rgb * rim_mask * max(rim_strength, 0.0);
}
