shader_type canvas_item;

#include "res://Shaders/sunset_prop_light.gdshaderinc"

// How it works:
// - The bus is one drawn sprite, so each wheel is located by an authored UV
//   centre and radius rather than being its own node.
// - The bus is also a prop standing in front of a setting sun, so it is relit
//   through the shared sunset include before any of the wheel work happens. It
//   carries both here because a CanvasItem only gets one material.
// - Inside a wheel, a ring of glints is fixed to the tyre; subtracting
//   wheel_spin_phase rotates them, so the wheel reads as turning.
// - A glint only lights where it faces the sun, so highlights flare across the
//   top of the tyre and die at the bottom. That contrast is what sells rotation.
// - A rim band keeps the shine on the tyre's curved shoulder, not the hub.
// - A darkness gate keeps the highlight on black rubber, so the blue body and
//   the pale hub never pick it up even where a wheel circle overlaps them.
// - ArrivalIntroSequence drives wheel_spin_phase from real travel distance, so
//   a parked bus sits perfectly still and a fast one spins fast.
// - Loop-free and constant per fragment, for GL Compatibility and the web.

// Wheel placement in texture UV. x is corrected by texture_aspect so a wheel on
// a wide texture still reads as a circle.
uniform vec2 wheel_one_uv = vec2(0.391, 0.568);
uniform vec2 wheel_two_uv = vec2(0.684, 0.568);
// Radius in UV-Y units. The script reads this back to convert travel into spin.
uniform float wheel_radius_uv = 0.0312;
uniform float texture_aspect = 1.3333;

// Radians. Advanced by the owning sequence as the bus actually moves.
uniform float wheel_spin_phase = 0.0;

uniform vec4 sun_shine_color : source_color = vec4(1.0, 0.94, 0.78, 1.0);
uniform float shine_strength = 0.9;
uniform int glint_count = 3;
uniform float glint_sharpness = 5.0;

// Fraction of the radius that catches light: the tyre shoulder, not the middle.
uniform float rim_inner = 0.42;
uniform float rim_outer = 1.0;
// Higher values pull the highlight tighter to the top of the wheel.
uniform float sun_up_bias = 1.6;

// Returns how strongly one wheel's rotating glint lights this fragment.
float wheel_shine(vec2 uv, vec2 center) {
	vec2 delta = uv - center;
	// UV x is compressed on a wide texture; undo that so the wheel is round.
	delta.x *= texture_aspect;
	float radius = max(wheel_radius_uv, 0.0001);
	float distance_ratio = length(delta) / radius;
	if (distance_ratio > rim_outer + 0.18) {
		return 0.0;
	}

	// Ring band across the tyre's shoulder.
	float band = smoothstep(
		rim_inner,
		(rim_inner + rim_outer) * 0.5,
		distance_ratio
	) * (
		1.0 - smoothstep(rim_outer, rim_outer + 0.18, distance_ratio)
	);

	// The glints belong to the tyre, so subtracting the phase spins them with it.
	float angle = atan(delta.y, delta.x) - wheel_spin_phase;
	float glint = pow(
		max(cos(angle * float(glint_count)), 0.0),
		glint_sharpness
	);

	// UV y grows downward, so -y is the side facing the sun overhead.
	float facing_sun = pow(
		clamp(-delta.y / radius, 0.0, 1.0),
		sun_up_bias
	);

	return band * glint * facing_sun;
}

void fragment() {
	vec4 source = texture(TEXTURE, UV);
	if (source.a > 0.01) {
		// The rubber test below has to run on the drawn art, not on the relit
		// bus, or the twilight fill darkens the whole body into "rubber" and the
		// glints spread off the wheels onto the panels.
		float darkness = 1.0 - dot(
			source.rgb,
			vec3(0.299, 0.587, 0.114)
		);

		float sunward_coverage = texture(
			TEXTURE,
			UV + normalize(sun_direction + vec2(0.0001)) * rim_texels
				* TEXTURE_PIXEL_SIZE
		).a;
		source.rgb = apply_sunset_prop_light(
			source.rgb,
			build_sunset_rim_mask(source.a, sunward_coverage),
			UV.y
		);

		float shine = wheel_shine(UV, wheel_one_uv)
			+ wheel_shine(UV, wheel_two_uv);
		// Only black rubber takes the highlight.
		shine *= smoothstep(0.55, 0.85, darkness);
		source.rgb += sun_shine_color.rgb
			* clamp(shine, 0.0, 1.0)
			* shine_strength;
	}
	COLOR = source;
}
