shader_type canvas_item;

// How it works:
// - Draws the soft ellipse of shadow directly under one actor, on the ground
//   they are standing on.
// - This is the thing that welds a character to a floor. Without it a sprite
//   placed on a walkway is a cut-out in front of it, however well the floor is
//   shaded, because nothing in the image says the two are touching.
// - The quad is drawn centred on the actor's feet; the ellipse is entirely in
//   this shader, so the node carrying it needs no art.
// - Density is highest directly under the contact point and falls off with an
//   eased curve, which is what a soft area light does. A hard-edged blob reads
//   as a sticker on the floor and is worse than nothing.
// - Loop-free for the web export.

uniform vec4 shadow_color : source_color = vec4(0.05, 0.04, 0.05, 1.0);
// Peak darkness directly beneath the actor.
uniform float density : hint_range(0.0, 1.0) = 0.42;
// How quickly the shadow gives out. Higher gathers it tight under the feet.
uniform float falloff : hint_range(0.5, 6.0) = 2.1;
// Squash of the ellipse. Below one is wider than it is deep, which is what a
// shadow on a receding surface looks like from this camera.
uniform float vertical_squash : hint_range(0.05, 1.0) = 0.38;
// Lifts the whole shadow when an actor is off the ground, so a jumping or
// falling character's shadow weakens instead of following them through the air.
uniform float contact_strength : hint_range(0.0, 1.0) = 1.0;


void fragment() {
	// Centred coordinates, with the vertical axis squashed so the falloff is
	// elliptical rather than circular.
	vec2 centered = (UV - vec2(0.5)) * 2.0;
	centered.y /= max(vertical_squash, 0.05);

	float distance_from_contact = length(centered);
	// Eased rather than linear: the darkest part stays small and the edge stays
	// soft, which is what stops it reading as a painted oval.
	float shape = clamp(1.0 - distance_from_contact, 0.0, 1.0);
	float alpha = pow(shape, falloff) * density * contact_strength;

	COLOR = vec4(shadow_color.rgb, alpha);
}
