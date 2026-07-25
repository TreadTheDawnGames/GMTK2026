shader_type canvas_item;
render_mode unshaded;

uniform vec2 aperture_center = vec2(0.5);
uniform vec2 aperture_radius = vec2(2.0);
uniform float viewport_aspect = 1.0;
uniform float edge_softness = 0.08;
uniform vec4 blackout_color : source_color = vec4(0.0, 0.0, 0.0, 1.0);

void fragment() {
	vec2 viewport_delta = (UV - aperture_center) * vec2(viewport_aspect, 1.0);
	vec2 safe_radius = max(aperture_radius, vec2(0.0001));
	float ellipse_distance = length(viewport_delta / safe_radius);
	float mask = smoothstep(
		1.0 - edge_softness,
		1.0 + edge_softness,
		ellipse_distance
	);
	COLOR = vec4(blackout_color.rgb, blackout_color.a * mask);
}
