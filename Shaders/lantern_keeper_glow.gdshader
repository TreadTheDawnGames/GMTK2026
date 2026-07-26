shader_type canvas_item;
render_mode unshaded, blend_add;

// How it works:
// - Runs only on a second Sprite2D behind the untouched Keeper artwork.
// - A soft additive halo is anchored on the lantern painted into that texture.
// - The aura shares the actor transform, so walking, facing, bobbing, and fades
//   carry the light without tinting or darkening the character.
// - The invariant is that this shader outputs light only, never source art.

uniform vec2 lantern_uv = vec2(0.440, 0.566);
uniform vec4 glow_color : source_color = vec4(1.0, 0.62, 0.16, 1.0);
uniform float glow_radius : hint_range(0.05, 0.40) = 0.30;
uniform float glow_strength : hint_range(0.0, 1.0) = 0.30;

varying float actor_fade_alpha;


void vertex() {
	// Fragment COLOR includes the source texture's alpha on a Sprite2D, which
	// is zero exactly where the halo must draw. Capture only CanvasItem
	// modulation here so the transparent halo can still follow actor fades.
	actor_fade_alpha = COLOR.a;
}


void fragment() {
	// The source canvas is 4:3. Aspect correction keeps the halo circular in
	// the scaled world sprite instead of stretching it across the character.
	vec2 lantern_delta = (UV - lantern_uv) * vec2(1.333333, 1.0);
	float distance_from_lantern = length(lantern_delta);
	float halo = 1.0 - smoothstep(
		glow_radius * 0.16,
		glow_radius,
		distance_from_lantern
	);
	float pulse = 0.96 + sin(TIME * 2.4) * 0.04;
	COLOR = vec4(
		glow_color.rgb,
		halo * glow_strength * pulse * actor_fade_alpha
	);
}
