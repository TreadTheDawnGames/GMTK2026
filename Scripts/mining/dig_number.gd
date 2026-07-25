class_name DigNumber
extends RichTextLabel

## Pops the depth gained from one hit out of the impact point.

@export_category("Combo Appearance")
## Maps combo thresholds to RichText effects, such as wave or rainbow.
@export var combo_effects: Dictionary[int, String] = {
	5: "wave",
	10: "rainbow",
}
@export var minimum_combo_color: Color = Color("f5ead7")
@export var maximum_combo_color: Color = Color("ff6b35")
@export_range(0.0, 1.0, 0.05) var starting_scale: float = 0.4
@export_range(1.0, 2.5, 0.05) var pop_overshoot: float = 1.15

@export_category("Depth Scale")
## Keeps a normal starting hit at the base display size.
@export_range(1, 1_000, 1) var base_depth: int = 6
## Reaches the largest display size at this downward distance.
@export_range(1, 2_000, 1) var full_scale_depth: int = 32
@export_range(0.0, 2.0, 0.05) var maximum_depth_scale_bonus: float = 0.55

@export_category("Motion")
@export_range(0.1, 5.0, 0.1) var lifetime_seconds: float = 1.5
@export_range(0.0, 400.0, 1.0) var launch_lift_px: float = 170.0
@export_range(0.0, 300.0, 1.0) var jump_height_px: float = 64.0
@export_range(0.0, 400.0, 1.0) var horizontal_travel_px: float = 180.0
@export_range(0.0, 30.0, 1.0) var launch_rotation_degrees: float = 8.0
@export_range(0.0, 1.0, 0.05) var fade_portion: float = 0.4
@export_range(0.0, 64.0, 1.0) var ui_clearance_px: float = 16.0

## Retained for deterministic motion-bound checks without sampling tweens.
var _arc_start_position: Vector2
var _arc_end_position: Vector2
var _arc_maximum_bottom_y: float
var _maximum_launch_rect: Rect2
var _player_exclusion_rect: Rect2


## Animates the value from the hammer contact using its captured combo.
func present(
	impact_screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float,
	horizontal_direction: float,
	random_travel_scale: float,
	player_exclusion_rect: Rect2,
	bottom_screen_limit_y: float
) -> void:
	var safe_combo_strength := clampf(combo_strength, 0.0, 1.0)
	var formatted_text := "-%d\nDEPTH" % depth_gained
	var selected_effect_threshold := -1
	var selected_effect_tag := ""
	for threshold: int in combo_effects:
		if (
			combo < threshold
			or threshold <= selected_effect_threshold
		):
			continue
		selected_effect_threshold = threshold
		selected_effect_tag = combo_effects[threshold]
	if not selected_effect_tag.is_empty():
		selected_effect_tag = selected_effect_tag.strip_edges()
		selected_effect_tag = selected_effect_tag.strip_escapes()
		selected_effect_tag = selected_effect_tag.lstrip("[]{}()")
		selected_effect_tag = selected_effect_tag.rstrip("[]{}()")
		if not selected_effect_tag.is_empty():
			# High combos replace lower-tier effects instead of nesting every
			# RichText animation and multiplying per-character update cost.
			formatted_text = (
				"[%s]%s[/%s]"
				% [
					selected_effect_tag,
					formatted_text,
					selected_effect_tag,
				]
			)

	# Combo changes styling and color; actual downward progress changes size.
	text = formatted_text
	var launches_left := horizontal_direction < 0.0
	horizontal_alignment = (
		HORIZONTAL_ALIGNMENT_RIGHT
		if launches_left
		else HORIZONTAL_ALIGNMENT_LEFT
	)
	pivot_offset = Vector2(
		size.x if launches_left else 0.0,
		size.y * 0.5
	)
	scale = Vector2.ONE * starting_scale
	rotation = deg_to_rad(
		-launch_rotation_degrees * horizontal_direction
	)
	modulate = minimum_combo_color.lerp(
		maximum_combo_color,
		safe_combo_strength
	)

	var depth_scale_strength := clampf(
		inverse_lerp(
			float(base_depth),
			float(maxi(full_scale_depth, base_depth + 1)),
			float(depth_gained)
		),
		0.0,
		1.0
	)
	var final_display_scale := (
		1.0
		+ maximum_depth_scale_bonus * depth_scale_strength
	)
	var maximum_visual_scale := final_display_scale * pop_overshoot
	var maximum_scaled_size := size * maximum_visual_scale
	var rotation_cosine := absf(cos(rotation))
	var rotation_sine := absf(sin(rotation))
	var maximum_rotation_intrusion_x := (
		maximum_scaled_size.y * 0.5 * rotation_sine
	)
	var maximum_outward_extent_x := (
		maximum_scaled_size.x * rotation_cosine
		+ maximum_rotation_intrusion_x
	)
	var maximum_vertical_extent := (
		maximum_scaled_size.x * rotation_sine
		+ maximum_scaled_size.y * 0.5 * rotation_cosine
	)
	_player_exclusion_rect = player_exclusion_rect
	# The player-facing label edge is the scale pivot. Small numbers now
	# emerge beside the miner while every larger pop grows away from them.
	var start_pivot_x := (
		player_exclusion_rect.position.x
			- maximum_rotation_intrusion_x
			- 1.0
		if launches_left
		else player_exclusion_rect.end.x
			+ maximum_rotation_intrusion_x
			+ 1.0
	)
	var start_center_y := maxf(
		minf(
			impact_screen_position.y - launch_lift_px,
			player_exclusion_rect.get_center().y - ui_clearance_px
		),
		maximum_vertical_extent + ui_clearance_px
	)
	var start_pivot := Vector2(start_pivot_x, start_center_y)
	position = start_pivot - pivot_offset
	_arc_start_position = position
	var launch_rect_left := (
		start_pivot_x - maximum_outward_extent_x
		if launches_left
		else start_pivot_x - maximum_rotation_intrusion_x
	)
	_maximum_launch_rect = Rect2(
		Vector2(
			launch_rect_left,
			start_center_y - maximum_vertical_extent
		),
		Vector2(
			maximum_outward_extent_x + maximum_rotation_intrusion_x,
			maximum_vertical_extent * 2.0
		)
	)
	var pop_seconds := minf(lifetime_seconds * 0.14, 0.2)
	var settle_seconds := minf(lifetime_seconds * 0.12, 0.16)
	var pop_tween := create_tween()
	pop_tween.set_trans(Tween.TRANS_QUAD)
	pop_tween.set_ease(Tween.EASE_OUT)
	pop_tween.tween_property(
		self,
		"scale",
		Vector2.ONE * final_display_scale * pop_overshoot,
		pop_seconds
	)
	pop_tween.set_trans(Tween.TRANS_QUAD)
	pop_tween.tween_property(
		self,
		"scale",
		Vector2.ONE * final_display_scale,
		settle_seconds
	)

	var randomized_launch_scale := maxf(random_travel_scale, 0.1)
	var destination_pivot_x := (
		start_pivot_x
		+ horizontal_direction
			* horizontal_travel_px
			* randomized_launch_scale
			* lerpf(1.0, 1.25, safe_combo_strength)
	)
	var horizontal_tween := create_tween()
	horizontal_tween.tween_interval(pop_seconds)
	horizontal_tween.set_trans(Tween.TRANS_QUAD)
	horizontal_tween.set_ease(Tween.EASE_OUT)
	horizontal_tween.tween_property(
		self,
		"position:x",
		destination_pivot_x - pivot_offset.x,
		maxf(lifetime_seconds - pop_seconds, 0.01)
	)

	var impact_label_y := position.y
	var jump_height := (
		jump_height_px
		* randomized_launch_scale
		* lerpf(1.0, 1.2, safe_combo_strength)
	)
	var maximum_half_height := pivot_offset.y * maximum_visual_scale
	var safe_end_center_y := (
		bottom_screen_limit_y
		- ui_clearance_px
		- maximum_half_height
	)
	var natural_end_center_y := (
		start_center_y - jump_height * 0.45
	)
	var end_center_y := minf(natural_end_center_y, safe_end_center_y)
	var end_label_y := end_center_y - pivot_offset.y
	_arc_end_position = Vector2(
		destination_pivot_x - pivot_offset.x,
		end_label_y
	)
	_arc_maximum_bottom_y = (
		end_center_y + maximum_half_height
	)
	var rise_seconds := lifetime_seconds * 0.42
	var vertical_tween := create_tween()
	vertical_tween.set_trans(Tween.TRANS_QUAD)
	vertical_tween.set_ease(Tween.EASE_OUT)
	vertical_tween.tween_property(
		self,
		"position:y",
		impact_label_y - jump_height,
		rise_seconds
	)
	vertical_tween.set_ease(Tween.EASE_IN)
	vertical_tween.tween_property(
		self,
		"position:y",
		end_label_y,
		lifetime_seconds - rise_seconds
	)

	var rotation_tween := create_tween()
	rotation_tween.set_trans(Tween.TRANS_QUAD)
	rotation_tween.set_ease(Tween.EASE_OUT)
	rotation_tween.tween_property(
		self,
		"rotation",
		0.0,
		lifetime_seconds * 0.35
	)

	var fade_seconds := lifetime_seconds * fade_portion
	var fade_tween := create_tween()
	fade_tween.tween_interval(
		maxf(lifetime_seconds - fade_seconds, 0.0)
	)
	fade_tween.tween_property(
		self,
		"modulate:a",
		0.0,
		fade_seconds
	)

	await vertical_tween.finished
	queue_free()
