shader_type canvas_item;

uniform sampler2D fill_texture : source_color, repeat_enable;
uniform bool use_fill_texture = false;
uniform vec4 layer_tint : source_color = vec4(1.0);
uniform vec2 world_origin = vec2(0.0);
uniform vec2 chunk_world_size = vec2(1024.0, 512.0);
uniform vec2 fill_texture_world_size = vec2(256.0);

void fragment() {
	float mask_alpha = texture(TEXTURE, UV).a;
	vec4 artwork = vec4(1.0);
	if (use_fill_texture) {
		vec2 safe_texture_size = max(
			fill_texture_world_size,
			vec2(1.0)
		);
		vec2 world_position = world_origin + UV * chunk_world_size;
		artwork = texture(fill_texture, world_position / safe_texture_size);
	}
	COLOR = vec4(
		artwork.rgb * layer_tint.rgb,
		artwork.a * layer_tint.a * mask_alpha
	);
}
