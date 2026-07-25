shader_type canvas_item;
render_mode unshaded;

// How it works:
// - strength is the sustained darkness a running combo has earned, and pulse is
//   the short kick one impact adds on top of it. Both come from
//   combo_impact_vignette.gd and are zero while no streak is running.
// - The frame is a banded ellipse measured from screen center, wobbled by the
//   same periodic value noise the dust puffs use so its rings read as inked
//   arcs rather than as a photographic falloff.
// - Band edges are antialiased against their own screen gradient, so the flat
//   steps stay deliberate art instead of gradient banding.
// The invariant is that a fragment costs the same every frame; the owner hides
// the rect entirely rather than running this at zero strength.

// Sustained darkness earned by the current combo, 0..1.
uniform float strength = 0.0;
// Short per-impact kick. Pushes the frame inward and briefly deepens it.
uniform float pulse = 0.0;
// Where the frame starts and where it reaches full darkness, as a share of the
// aspect-corrected half-height. A 16:9 corner sits at about 1.02.
uniform float inner_radius = 0.58;
uniform float outer_radius = 1.06;
// How far one impact drags the frame inward at full pulse.
uniform float pulse_reach = 0.16;
// Extra darkness one impact adds at full pulse.
uniform float pulse_darkness = 0.35;
// Flat rings the frame is quantised into. Terrain dirt uses four for the same
// hard-shading reason.
uniform float band_steps = 4.0;
uniform float viewport_aspect = 1.7777778;
// Deep earth rather than black, so the frame belongs to the terrain palette.
uniform vec4 edge_color : source_color = vec4(0.07, 0.05, 0.05, 1.0);
// How far the ring edges wander around the frame.
uniform float wobble_amount = 0.05;
uniform float wobble_cells = 7.0;

const float TURN = 6.283185307;

// Repeatable pseudo-random value for one wobble cell.
float frame_hash(float cell) {
	return fract(sin(cell * 78.233 + 12.9898) * 43758.5453123);
}

// Smooth 1D value noise around the frame, wrapped so the ring closes cleanly.
float frame_noise(float turns, float cell_count) {
	float scaled = turns * cell_count;
	float cell = floor(scaled);
	float blend = fract(scaled);
	blend = blend * blend * (3.0 - 2.0 * blend);
	return mix(
		frame_hash(mod(cell, cell_count)),
		frame_hash(mod(cell + 1.0, cell_count)),
		blend
	);
}

void fragment() {
	vec2 centered = (UV - vec2(0.5)) * vec2(viewport_aspect, 1.0);
	float radius = length(centered);

	float clamped_pulse = clamp(pulse, 0.0, 1.0);
	float turns = atan(centered.y, centered.x) / TURN + 0.5;
	float wobble = (
		frame_noise(turns, max(floor(wobble_cells), 3.0)) - 0.5
	) * wobble_amount;

	float frame_inner = inner_radius
		- pulse_reach * clamped_pulse
		+ wobble;
	float frame_outer = max(
		outer_radius + wobble,
		frame_inner + 0.02
	);
	float frame = smoothstep(frame_inner, frame_outer, radius);

	// Quantise into flat rings, then restore an antialiased edge on each step so
	// the deliberate banding does not turn into stairsteps across the screen.
	float safe_steps = max(floor(band_steps), 1.0);
	float stepped = floor(frame * safe_steps) / safe_steps;
	float step_local = fract(frame * safe_steps);
	float step_softness = clamp(
		fwidth(frame) * safe_steps,
		0.0001,
		1.0
	);
	stepped += smoothstep(
		1.0 - step_softness,
		1.0,
		step_local
	) / safe_steps;

	float darkness = clamp(
		strength + pulse_darkness * clamped_pulse,
		0.0,
		1.0
	);
	COLOR = vec4(
		edge_color.rgb,
		edge_color.a * clamp(stepped, 0.0, 1.0) * darkness
	);
}
