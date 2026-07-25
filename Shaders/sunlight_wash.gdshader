shader_type canvas_item;
render_mode blend_add;

// How it works:
// - One additive fullscreen rect pools warm daylight around the surface line.
// - Above the line it is a thin haze; below it it fades out over a set depth.
// - Horizontal falloff from the sun keeps the pool under the sun, not global.
// - It draws above terrain and characters, so sunlight touches the cast too.
// - surface_screen_y comes from SurfaceSunlight, so the pool leaves with depth.
// - Like the sky behind it, every pixel value here is a viewport pixel and the
//   top of fragment() converts the rect into the frame first. Both rects have
//   to read the same space or the pool drifts off the sun during the zoom.
// - Additive blending means alpha is strength; it never darkens anything.

uniform vec4 sunlight_color : source_color = vec4(1.0, 0.63, 0.38, 1.0);

// Haze strength in the sky band, then at the ground line directly under the sun.
uniform float sky_haze_strength = 0.1;
uniform float ground_light_strength = 0.24;

// How far underground the light reaches before it is completely gone.
uniform float ground_falloff_pixels = 190.0;

// Horizontal distance from the sun at which the pool has fully fallen off.
uniform float lateral_falloff_pixels = 760.0;
uniform float lateral_falloff_strength = 0.65;

uniform vec2 sun_screen_position = vec2(676.0, 284.0);
uniform float surface_screen_y = 260.0;
uniform vec2 viewport_size = vec2(1152.0, 648.0);
// How large this rect currently draws, in those same viewport pixels.
uniform vec2 backdrop_screen_size = vec2(1152.0, 648.0);

void fragment() {
	// Rect UV to viewport pixels. See surface_sky.gdshader for why.
	vec2 pixel = (UV - vec2(0.5)) * backdrop_screen_size + viewport_size * 0.5;

	// Underground light decays with depth; the sky keeps a flat thin haze.
	float depth_below_surface = max(pixel.y - surface_screen_y, 0.0);
	float ground_light = ground_light_strength * (
		1.0 - smoothstep(
			0.0,
			max(ground_falloff_pixels, 1.0),
			depth_below_surface
		)
	);
	float is_below_ground = smoothstep(
		surface_screen_y - 1.0,
		surface_screen_y + 1.0,
		pixel.y
	);
	float strength = mix(sky_haze_strength, ground_light, is_below_ground);

	// Pool the light beneath the sun instead of flooding the whole frame.
	float lateral_fade = smoothstep(
		0.0,
		max(lateral_falloff_pixels, 1.0),
		abs(pixel.x - sun_screen_position.x)
	);
	strength *= 1.0 - lateral_fade * clamp(lateral_falloff_strength, 0.0, 1.0);

	COLOR = vec4(sunlight_color.rgb, max(strength, 0.0));
}
