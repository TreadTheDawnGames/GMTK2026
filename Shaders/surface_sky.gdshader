shader_type canvas_item;

// How it works:
// - One fullscreen rect paints everything behind terrain and characters.
// - Above surface_screen_y it draws a vertical daylight gradient plus the sun.
// - Below that line it collapses to the flat underground void color.
// - The sun is a soft disc with a wide radial halo, both clipped at the horizon.
// - It is authored setting: the disc straddles the ground line, so only its
//   upper sliver and its halo clear the horizon and the light reads as low.
// - Depth is built in three receding passes over that gradient: streaked cloud
//   bands high up, a bright haze cushion on the horizon, then two ridge lines
//   standing on it. Each pass is hazed further toward the horizon color than
//   the one in front of it, which is what turns a flat gradient into distance.
// - surface_screen_y is pushed by SurfacePresentation, so digging scrolls the
//   whole backdrop away together and no pass can drift off the ground line.
// - No loops and no texture samples, for GL Compatibility and the web export.

// Sky band. horizon_color meets the ground, zenith_color sits at the top edge.
uniform vec4 sky_zenith_color : source_color = vec4(0.16, 0.13, 0.31, 1.0);
uniform vec4 sky_horizon_color : source_color = vec4(0.95, 0.45, 0.24, 1.0);

// Everything below the surface line. Matches the former flat background color
// so descending past the intro looks identical to the shipped mining scene.
uniform vec4 underground_color : source_color = vec4(0.075, 0.095, 0.13, 1.0);

uniform vec4 sun_color : source_color = vec4(1.0, 0.74, 0.40, 1.0);
uniform vec4 sun_halo_color : source_color = vec4(1.0, 0.47, 0.22, 1.0);

// Viewport pixels. SurfacePresentation owns this value so the sky and the warm
// wash always place the sun at the same point.
uniform vec2 sun_screen_position = vec2(676.0, 284.0);
uniform float sun_radius = 34.0;
uniform float sun_edge_softness = 4.0;
uniform float sun_halo_radius = 360.0;
uniform float sun_halo_strength = 0.8;

// Pixels of gradient between zenith_color and horizon_color at the ground line.
uniform float horizon_band_pixels = 235.0;

// Bright cushion of scattered light sitting directly on the ground line. It is
// much tighter than horizon_band_pixels, and it is what the ridges are
// silhouetted against, so a ridge reads as standing in air rather than as a
// shape cut out of the gradient.
uniform vec4 horizon_glow_color : source_color = vec4(1.0, 0.72, 0.36, 1.0);
uniform float horizon_glow_pixels = 54.0;
uniform float horizon_glow_strength = 0.55;

// Distant land. Two ridge lines, each a sum of three sines, so the horizon
// carries silhouettes without a texture, a loop, or a second draw. Far is
// drawn first and hazed hardest; near stands in front of it and reads solid.
// Both are pure background: nothing is ever mined out of them.
uniform bool ridges_enabled = true;
uniform vec4 ridge_far_color : source_color = vec4(0.47, 0.26, 0.30, 1.0);
uniform vec4 ridge_near_color : source_color = vec4(0.25, 0.14, 0.21, 1.0);
// Peak height above the ground line, in viewport pixels.
uniform float ridge_far_height_px = 52.0;
uniform float ridge_near_height_px = 27.0;
// Width of one full undulation. The two are deliberately not multiples of each
// other, so the crests never line up and the pair keeps reading as two ranges.
uniform float ridge_far_period_px = 690.0;
uniform float ridge_near_period_px = 415.0;
uniform float ridge_far_offset_px = 0.0;
uniform float ridge_near_offset_px = 240.0;
// How far each ridge gives up its own color to the sky behind it. This, not
// its size, is what places a range at a distance.
uniform float ridge_far_haze = 0.62;
uniform float ridge_near_haze = 0.24;
// Warm light spilling over each crest from the sun behind it.
uniform float ridge_rim_pixels = 3.0;
uniform float ridge_rim_strength = 0.85;

// Streaked cloud bands. Two octaves of value noise stretched hard along x, so
// the result is drawn-out streaks rather than blobs, then lit from the sun.
uniform bool clouds_enabled = true;
uniform vec4 cloud_shade_color : source_color = vec4(0.35, 0.21, 0.34, 1.0);
uniform vec4 cloud_light_color : source_color = vec4(1.0, 0.70, 0.42, 1.0);
uniform vec2 cloud_world_size = vec2(760.0, 68.0);
// Coverage 0 is clear sky, 1 is overcast. The gaps are what make bands read as
// separate clouds instead of one filter over the whole sky.
uniform float cloud_coverage = 0.42;
uniform float cloud_softness = 0.30;
uniform float cloud_strength = 0.62;
// Clouds fade out this far above the ground line, so they never crowd the
// ridges or fight the horizon glow.
uniform float cloud_horizon_fade_px = 130.0;
// Distance from the sun over which a cloud stops taking its light.
uniform float cloud_light_reach_px = 460.0;

uniform float surface_screen_y = 260.0;
uniform vec2 viewport_size = vec2(1152.0, 648.0);

// Local copy of the value-noise pair the terrain shader uses. It stays local on
// purpose: the terrain version is on the per-hit hot path and is not worth
// coupling to a background effect that runs once per fullscreen pass.
float sky_hash(vec2 point) {
	vec3 point_hash = fract(vec3(point.xyx) * 0.1031);
	point_hash += dot(point_hash, point_hash.yzx + 33.33);
	return fract((point_hash.x + point_hash.y) * point_hash.z);
}

float sky_noise(vec2 point) {
	vec2 cell = floor(point);
	vec2 blend_weight = fract(point);
	blend_weight = blend_weight * blend_weight * (
		vec2(3.0) - 2.0 * blend_weight
	);
	float top_noise = mix(
		sky_hash(cell),
		sky_hash(cell + vec2(1.0, 0.0)),
		blend_weight.x
	);
	float bottom_noise = mix(
		sky_hash(cell + vec2(0.0, 1.0)),
		sky_hash(cell + vec2(1.0, 1.0)),
		blend_weight.x
	);
	return mix(top_noise, bottom_noise, blend_weight.y);
}

// Height of one ridge crest above the ground line at this column. Three sines
// at unrelated periods give a profile that never repeats inside a screen width.
float ridge_height(float pixel_x, float period_px, float offset_px) {
	float phase = (pixel_x + offset_px) / max(period_px, 1.0) * 6.2831853;
	float profile = (
		sin(phase) * 0.55
		+ sin(phase * 2.30 + 1.70) * 0.28
		+ sin(phase * 0.43 - 0.90) * 0.17
	);
	// Bias the range into 0..1 with the crests kept clear of the ground line,
	// so a trough is still land rather than a gap the sky shows through.
	return clamp(profile * 0.5 + 0.52, 0.12, 1.0);
}

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

	// Clouds go on before the sun disc and before the horizon cushion: they are
	// the furthest thing in the sky, so the disc still burns through them and
	// the haze on the ground line still passes in front of them.
	if (clouds_enabled) {
		vec2 cloud_uv = pixel / max(cloud_world_size, vec2(1.0));
		float cloud_field = mix(
			sky_noise(cloud_uv),
			sky_noise(cloud_uv * 2.30 + vec2(11.7, 4.3)),
			0.38
		);
		float threshold = 1.0 - clamp(cloud_coverage, 0.0, 1.0);
		float cloud = smoothstep(
			threshold,
			threshold + max(cloud_softness, 0.01),
			cloud_field
		);

		// Thin them out toward the ground line and toward the top edge, so the
		// band sits in the middle of the sky where a real cloud deck reads.
		cloud *= smoothstep(
			surface_screen_y,
			surface_screen_y - max(cloud_horizon_fade_px, 1.0),
			pixel.y
		);

		// A cloud near the sun takes its light on the underside; one far away
		// keeps the cold shade color. That split is the whole depth cue.
		float sun_reach = 1.0 - clamp(
			sun_distance / max(cloud_light_reach_px, 1.0),
			0.0,
			1.0
		);
		vec3 cloud_color = mix(
			cloud_shade_color.rgb,
			cloud_light_color.rgb,
			pow(sun_reach, 1.6)
		);
		sky_color = mix(
			sky_color,
			cloud_color,
			cloud * clamp(cloud_strength, 0.0, 1.0)
		);
	}

	sky_color = mix(sky_color, sun_color.rgb, sun_disc);

	// Scattered light banked on the ground line, in front of the clouds and
	// behind the land. Additive so it brightens the gradient it sits on rather
	// than replacing it.
	float horizon_glow = 1.0 - smoothstep(
		0.0,
		max(horizon_glow_pixels, 1.0),
		max(surface_screen_y - pixel.y, 0.0)
	);
	sky_color += horizon_glow_color.rgb
		* horizon_glow
		* horizon_glow_strength
		* (1.0 - sun_disc);

	// Land, far range first. Each range is filled with its own color hazed
	// toward the sky it stands in, then given a warm lit edge along its crest.
	if (ridges_enabled) {
		float far_top = surface_screen_y - ridge_height(
			pixel.x,
			ridge_far_period_px,
			ridge_far_offset_px
		) * ridge_far_height_px;
		float near_top = surface_screen_y - ridge_height(
			pixel.x,
			ridge_near_period_px,
			ridge_near_offset_px
		) * ridge_near_height_px;

		vec3 far_body = mix(
			ridge_far_color.rgb,
			sky_color,
			clamp(ridge_far_haze, 0.0, 1.0)
		);
		vec3 near_body = mix(
			ridge_near_color.rgb,
			sky_color,
			clamp(ridge_near_haze, 0.0, 1.0)
		);

		// A one-pixel crossfade is all the antialiasing a horizontal edge needs.
		float far_fill = smoothstep(far_top - 1.0, far_top + 1.0, pixel.y);
		float near_fill = smoothstep(near_top - 1.0, near_top + 1.0, pixel.y);

		// The lit edge is the band of land within ridge_rim_pixels of its own
		// crest: solid here, open just above. Same test as the terrain bevel.
		float rim_reach = max(ridge_rim_pixels, 0.5);
		float far_rim = far_fill * (
			1.0 - smoothstep(0.0, rim_reach, pixel.y - far_top)
		);
		float near_rim = near_fill * (
			1.0 - smoothstep(0.0, rim_reach, pixel.y - near_top)
		);

		sky_color = mix(sky_color, far_body, far_fill);
		sky_color += horizon_glow_color.rgb
			* far_rim
			* ridge_rim_strength
			* (1.0 - clamp(ridge_far_haze, 0.0, 1.0));
		sky_color = mix(sky_color, near_body, near_fill);
		sky_color += horizon_glow_color.rgb * near_rim * ridge_rim_strength;
	}

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
