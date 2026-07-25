shader_type canvas_item;

// How it works:
// - One fullscreen rect paints everything behind terrain and characters.
// - Above surface_screen_y it draws a vertical daylight gradient plus the sun.
// - Below that line it collapses to the flat underground void color.
// - The sun is a soft disc with a wide radial halo, both clipped at the horizon.
// - It is authored setting: the disc straddles the ground line, so only its
//   upper sliver and its halo clear the horizon and the light reads as low.
// - surface_screen_y is pushed by SurfaceSunlight, so digging scrolls day away.
// - No loops and no texture samples, for GL Compatibility and the web export.

// Sky band. horizon_color meets the ground, zenith_color sits at the top edge.
uniform vec4 sky_zenith_color : source_color = vec4(0.16, 0.13, 0.31, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.95, 0.45, 0.24, 1.0);

// Everything below the surface line. Matches the former flat background color
// so descending past the intro looks identical to the shipped mining scene.
uniform vec4 underground_color : source_color = vec4(0.075, 0.095, 0.13, 1.0);

uniform vec4 sun_color : source_color = vec4(1.0, 0.74, 0.40, 1.0);
uniform vec4 sun_halo_color : source_color = vec4(1.0, 0.47, 0.22, 1.0);

// Viewport pixels. SurfaceSunlight owns this value so the sky and the warm
// wash always place the sun at the same point.
uniform vec2 sun_screen_position = vec2(676.0, 284.0);
uniform float sun_radius = 34.0;
uniform float sun_edge_softness = 4.0;
uniform float sun_halo_radius = 360.0;
uniform float sun_halo_strength = 0.8;

// Pixels of gradient between zenith_color and horizon_color at the ground line.
uniform float horizon_band_pixels = 235.0;

uniform float surface_screen_y = 260.0;
uniform vec2 viewport_size = vec2(1152.0, 648.0);

void fragment() {
	vec2 pixel = UV * viewport_size;

	// Warm the sky as it approaches the ground so the horizon carries the light.
	float horizon_blend = smoothstep(
		surface_screen_y - max(horizon_band_pixels, 1.0),
		surface_screen_y,
		pixel.y
	);
	vec3 sky_color = mix(
		sky_zenith_color.rgb,
		sky_horizon_color.rgb,
		horizon_blend
	);

	// One distance drives both the disc and its halo.
	float sun_distance = length(pixel - sun_screen_position);
	float sun_disc = 1.0 - smoothstep(
		sun_radius,
		sun_radius + max(sun_edge_softness, 0.01),
		sun_distance
	);
	float halo_falloff = 1.0 - clamp(
		sun_distance / max(sun_halo_radius, 1.0),
		0.0,
		1.0
	);
	float sun_halo = pow(halo_falloff, 3.0) * sun_halo_strength;

	sky_color += sun_halo_color.rgb * sun_halo;
	sky_color = mix(sky_color, sun_color.rgb, sun_disc);

	// A two-pixel crossfade lets the sun set behind the ground without aliasing.
	float is_above_ground = 1.0 - smoothstep(
		surface_screen_y - 1.0,
		surface_screen_y + 1.0,
		pixel.y
	);
	COLOR = vec4(
		mix(underground_color.rgb, sky_color, is_above_ground),
		1.0
	);
}
