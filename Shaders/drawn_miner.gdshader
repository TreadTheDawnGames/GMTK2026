shader_type canvas_item;

uniform vec4 outline_color : source_color = vec4(0.96, 0.94, 0.86, 1.0);
uniform float outline_width = 3.0;
uniform vec4 tool_tint : source_color = vec4(1.0);

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a > 0.01) {
		float maximum_channel = max(source.r, max(source.g, source.b));
		float minimum_channel = min(source.r, min(source.g, source.b));
		float brightness = dot(source.rgb, vec3(0.299, 0.587, 0.114));
		bool is_tool_metal = (
			maximum_channel - minimum_channel < 0.04
			&& brightness > 0.2
			&& brightness < 0.7
		);
		if (is_tool_metal) {
			source.rgb *= tool_tint.rgb;
		}
		COLOR = source;
	} else {
		vec2 offset = TEXTURE_PIXEL_SIZE * outline_width;
		float nearby_alpha = 0.0;
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(offset.x, 0.0)).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(offset.x, 0.0)).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(0.0, offset.y)).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - vec2(0.0, offset.y)).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + offset).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV - offset).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(offset.x, -offset.y)).a);
		nearby_alpha = max(nearby_alpha, texture(TEXTURE, UV + vec2(-offset.x, offset.y)).a);
		COLOR = vec4(
			outline_color.rgb,
			outline_color.a * nearby_alpha
		);
	}
}
