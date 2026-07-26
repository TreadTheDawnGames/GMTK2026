// How it works:
// - A side-on shot has no horizontal surfaces, so ground reads as a wall the
//   miner stands in front of. These masks give one world-space line a top face,
//   a far edge, a lip, and a cut face below, which is what sells 2.5D depth.
// - Every mask is a pure function of how far a pixel sits below that line, so
//   the same stack lights the world surface and any cutscene room floor
//   hundreds of rows down. Nothing here knows which line it is being asked about.
// - rise is the one mask that looks upward instead: a wall standing on a lit
//   floor catches bounce near its foot and loses it with height, and without
//   that band the wall and the floor meet as a hard seam at the exact place the
//   illusion has to hold.
// - Compose them widest-band-first so each shades what the last laid down:
//   shelf, face, lip, contact. apply_ground_plane does that in the right order.
// - Loop-free and sampler-free, for GL Compatibility and the web export. It
//   creates no allocations and changes no terrain cell, depth, or collision.
// The invariant is that every mask is zero above its line except rise, so a
// plane can never light the open air over it.

// Lit top plane, held flat to its far edge and only then turned down. Fading
// from the line itself would read as a gradient painted on a wall rather than
// as a surface seen at a shallow angle.
float ground_plane_shelf_mask(
	float depth_below,
	float shelf_depth,
	float plateau
) {
	float depth = max(shelf_depth, 1.0);
	float edge = depth * clamp(plateau, 0.0, 0.99);
	return step(-1.0, depth_below) * (
		1.0 - smoothstep(edge, depth, depth_below)
	);
}

// The corner itself: darkest just past the shelf's far edge, back to open rock
// over its own depth. This is the band that actually turns the corner; without
// it the light just fades out and the plane has no far edge.
// The far edge has to be the same edge the shelf rolled off at, so this takes
// the plateau too rather than assuming one: they are two halves of one corner
// and drifting them apart puts a lit gap between the plane and its own shadow.
float ground_plane_face_mask(
	float depth_below,
	float shelf_depth,
	float plateau,
	float face_depth
) {
	float depth = max(shelf_depth, 1.0);
	float edge = depth * clamp(plateau, 0.0, 0.99);
	return smoothstep(edge, depth, depth_below) * (
		1.0 - smoothstep(depth, depth + max(face_depth, 1.0), depth_below)
	);
}

// Shared shape for the thin bands printed on the exposed top of the line: the
// packed lip, and the tighter contact shade under whatever sits on it.
float ground_plane_lip_mask(float depth_below, float lip_depth) {
	return step(-1.0, depth_below) * (
		1.0 - smoothstep(0.0, max(lip_depth, 1.0), depth_below)
	);
}

// Bounce a lit floor throws onto rock standing on it, strongest at the foot and
// gone by rise_world_px above. height_above is positive going up, so this is the
// only mask in the file that reads the air side of the line.
float ground_plane_rise_mask(float height_above, float rise_world_px) {
	return step(0.0, height_above) * (
		1.0 - smoothstep(0.0, max(rise_world_px, 1.0), height_above)
	);
}

// Lays the whole stack over one already-sampled rock pixel.
//
// plane_world_y is the line this call is about. Pass the surface for the world
// ground and a room's floor for a cutscene, with the same tunables both times:
// one authored ground look reused, rather than a second look to keep in step.
vec3 apply_ground_plane(
	vec3 rock_color,
	float world_y,
	float plane_world_y,
	float shelf_depth,
	float shelf_plateau,
	vec3 shelf_light_color,
	float shelf_light_strength,
	float face_depth,
	float face_strength,
	float lip_depth,
	vec3 lip_color,
	float lip_strength,
	float contact_depth,
	float contact_strength,
	float rise_world_px,
	vec3 rise_color,
	float rise_strength
) {
	vec3 result = rock_color;
	float depth_below = world_y - plane_world_y;

	// Bounce first, because it belongs to the air side and everything after
	// this is about the solid side. Skipping it when the strength is zero keeps
	// the surface path byte-identical to what it drew before this file existed.
	if (rise_strength > 0.0) {
		float rise = ground_plane_rise_mask(-depth_below, rise_world_px);
		result = mix(
			result,
			rise_color,
			clamp(rise * rise_strength, 0.0, 1.0)
		);
	}

	float shelf = ground_plane_shelf_mask(
		depth_below,
		shelf_depth,
		shelf_plateau
	);
	result = mix(
		result,
		shelf_light_color,
		clamp(shelf * shelf_light_strength, 0.0, 1.0)
	);

	float face = ground_plane_face_mask(
		depth_below,
		shelf_depth,
		shelf_plateau,
		face_depth
	);
	result *= 1.0 - clamp(face * face_strength, 0.0, 0.9);

	float lip = ground_plane_lip_mask(depth_below, lip_depth);
	result = mix(result, lip_color, clamp(lip * lip_strength, 0.0, 1.0));

	// Contact last, so it darkens the finished lip rather than being covered by
	// it. That order is what leaves dark line, bright lip, falling face.
	float contact = ground_plane_lip_mask(depth_below, contact_depth);
	result *= 1.0 - clamp(contact * contact_strength, 0.0, 0.9);
	return result;
}
