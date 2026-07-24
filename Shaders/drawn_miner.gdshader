shader_type canvas_item;

// Retained only for recoloring neutral tool metal when this optional material
// is assigned. The former white silhouette outline is intentionally removed;
// the authored miner textures provide their own black linework.
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
	}
	COLOR = source;
}
