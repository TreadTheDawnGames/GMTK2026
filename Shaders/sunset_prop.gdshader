shader_type canvas_item;

#include "res://Shaders/sunset_prop_light.gdshaderinc"

// How it works:
// - The thin wrapper around sunset_prop_light for any drawn prop that needs
//   nothing else: the bus stop, and the grass bands standing behind it.
// - It owns the two texture taps the include cannot do for itself, then hands
//   the result over. Every tunable lives in the include.
// - The bus uses the same include from bus_wheel_shine.gdshader instead, because
//   a CanvasItem gets one material and its wheels need the other half.

void fragment() {
	vec4 art = texture(TEXTURE, UV);
	// One tap toward the sun. Outside the sprite this reads transparent, which
	// is exactly the "open on the sun side" the contour test wants.
	float sunward_coverage = texture(
		TEXTURE,
		UV + normalize(sun_direction + vec2(0.0001)) * rim_texels
			* TEXTURE_PIXEL_SIZE
	).a;
	COLOR = vec4(
		apply_sunset_prop_light(
			art.rgb,
			build_sunset_rim_mask(art.a, sunward_coverage),
			UV.y
		),
		art.a
	);
}
