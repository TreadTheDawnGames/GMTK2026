shader_type canvas_item;

uniform sampler2D art_texture : source_color, repeat_enable;
uniform bool use_art_texture = false;
uniform bool mask_from_alpha = false;
uniform vec4 layer_tint : source_color = vec4(1.0);
uniform vec2 world_origin_px = vec2(0.0);
uniform vec2 chunk_world_size_px = vec2(1024.0, 512.0);
uniform vec2 texture_world_size_px = vec2(512.0);

void fragment() {
	vec4 mask = texture(TEXTURE, UV);
	float mask_alpha = mask_from_alpha ? mask.a : mask.r;
	vec4 artwork = vec4(1.0);
	if (use_art_texture) {
		vec2 safe_texture_size = max(texture_world_size_px, vec2(1.0));
		vec2 world_position = world_origin_px + UV * chunk_world_size_px;
		artwork = texture(art_texture, world_position / safe_texture_size);
	} else if (mask_from_alpha) {
		artwork = vec4(mask.rgb, 1.0);
	}
	COLOR = vec4(
		artwork.rgb * layer_tint.rgb,
		artwork.a * layer_tint.a * mask_alpha
	);
}
