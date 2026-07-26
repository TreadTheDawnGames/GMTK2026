shader_type canvas_item;

// How it works:
// - The storefront keeps its authored texture and alpha.
// - A stage-owned uniform enables a warm pulse inside the serving window.
// - A soft portrait glow makes the painted-in speaker the brightest point.
// - The invariant is that zero strength reproduces the source art exactly.

uniform float coco_speaking : hint_range(0.0, 1.0) = 0.0;
uniform vec4 speaking_color : source_color = vec4(1.0, 0.72, 0.24, 1.0);


void fragment() {
	vec4 source = texture(TEXTURE, UV) * COLOR;
	float window_x = smoothstep(0.47, 0.51, UV.x)
		* (1.0 - smoothstep(0.89, 0.93, UV.x));
	float window_y = smoothstep(0.63, 0.67, UV.y)
		* (1.0 - smoothstep(0.85, 0.89, UV.y));
	float window_mask = window_x * window_y;

	vec2 portrait_offset = (UV - vec2(0.615, 0.775)) / vec2(0.16, 0.14);
	float portrait_glow = 1.0 - smoothstep(
		0.25,
		1.0,
		length(portrait_offset)
	);
	float pulse = 0.72 + sin(TIME * 7.0) * 0.28;
	float highlight = coco_speaking * pulse * source.a;

	source.rgb = mix(
		source.rgb,
		source.rgb + speaking_color.rgb * 0.34,
		window_mask * highlight
	);
	source.rgb += speaking_color.rgb * portrait_glow * highlight * 0.24;
	COLOR = source;
}
