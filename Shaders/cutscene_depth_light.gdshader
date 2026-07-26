shader_type canvas_item;

// How it works:
// - Lights any cutscene sprite from one authored screen-space direction.
// - Alpha differences around each pixel approximate a paper-cut normal.
// - A warm lower bounce and cool upper shade seat the art on lit ground.
// - depth_amount adds haze and desaturation to actors in receding floor ranks.
// - The source texture and its alpha stay authoritative; this adds no outline.
// - There are no loops, branches over collections, or screen-texture reads.
// The invariant is that depth changes lighting only, never sprite registration.

uniform vec2 light_direction = vec2(-0.72, -0.38);
uniform vec4 light_color : source_color = vec4(1.0, 0.83, 0.58, 1.0);
uniform vec4 shade_color : source_color = vec4(0.18, 0.20, 0.30, 1.0);
uniform vec4 ground_bounce_color : source_color = vec4(0.78, 0.43, 0.22, 1.0);
uniform vec4 depth_haze_color : source_color = vec4(0.20, 0.22, 0.29, 1.0);
uniform float edge_light_strength : hint_range(0.0, 1.5) = 0.62;
uniform float shade_strength : hint_range(0.0, 1.0) = 0.24;
uniform float ground_bounce_strength : hint_range(0.0, 1.0) = 0.20;
uniform float ground_bounce_height : hint_range(0.05, 1.0) = 0.34;
uniform float depth_amount : hint_range(0.0, 1.0) = 0.0;
uniform float depth_haze_strength : hint_range(0.0, 1.0) = 0.34;
uniform float depth_desaturation : hint_range(0.0, 1.0) = 0.26;


void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float alpha_left = texture(TEXTURE, UV - vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a;
	float alpha_right = texture(TEXTURE, UV + vec2(TEXTURE_PIXEL_SIZE.x, 0.0)).a;
	float alpha_up = texture(TEXTURE, UV - vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a;
	float alpha_down = texture(TEXTURE, UV + vec2(0.0, TEXTURE_PIXEL_SIZE.y)).a;
	vec2 alpha_normal = normalize(
		vec2(alpha_left - alpha_right, alpha_up - alpha_down) + vec2(0.0001)
	);
	vec2 resolved_light = normalize(light_direction + vec2(0.0001));
	float lit_edge = max(dot(alpha_normal, -resolved_light), 0.0);
	float shaded_edge = max(dot(alpha_normal, resolved_light), 0.0);

	vec3 lit_rgb = mix(
		source.rgb,
		light_color.rgb,
		lit_edge * edge_light_strength * source.a
	);
	lit_rgb = mix(
		lit_rgb,
		shade_color.rgb,
		shaded_edge * shade_strength * source.a
	);

	float bounce_band = smoothstep(
		1.0 - ground_bounce_height,
		1.0,
		UV.y
	);
	lit_rgb = mix(
		lit_rgb,
		ground_bounce_color.rgb,
		bounce_band * ground_bounce_strength * source.a
	);

	float luma = dot(lit_rgb, vec3(0.299, 0.587, 0.114));
	lit_rgb = mix(
		lit_rgb,
		vec3(luma),
		depth_amount * depth_desaturation
	);
	lit_rgb = mix(
		lit_rgb,
		depth_haze_color.rgb,
		depth_amount * depth_haze_strength * source.a
	);
	COLOR = vec4(lit_rgb, source.a);
}
