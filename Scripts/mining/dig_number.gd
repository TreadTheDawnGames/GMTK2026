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
@export_range(0.0, 1.0, 0.05) var starting_scale: float = 0.15
@export_range(1.0, 2.5, 0.05) var pop_overshoot: float = 1.3

@export_category("Depth Scale")
## Keeps a normal starting hit at the base display size.
@export_range(1, 1_000, 1) var base_depth: int = 6
## Reaches the largest display size at this downward distance.
@export_range(1, 2_000, 1) var full_scale_depth: int = 32
@export_range(0.0, 2.0, 0.05) var maximum_depth_scale_bonus: float = 0.8

@export_category("Motion")
@export_range(0.1, 5.0, 0.1) var lifetime_seconds: float = 1.5
@export_range(0.0, 300.0, 1.0) var jump_height_px: float = 92.0
@export_range(0.0, 300.0, 1.0) var horizontal_travel_px: float = 110.0
@export_range(0.0, 30.0, 1.0) var launch_rotation_degrees: float = 8.0
@export_range(0.0, 1.0, 0.05) var fade_portion: float = 0.4


## Animates the value from the hammer contact using its captured combo.
func present(
	impact_screen_position: Vector2,
	depth_gained: int,
	combo: int,
	combo_strength: float,
	horizontal_direction: float,
	random_travel_scale: float
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
	pivot_offset = size * 0.5
	position = impact_screen_position - pivot_offset
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
	var pop_seconds := minf(lifetime_seconds * 0.14, 0.2)
	var settle_seconds := minf(lifetime_seconds * 0.12, 0.16)
	var pop_tween := create_tween()
	pop_tween.set_trans(Tween.TRANS_BACK)
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
	var horizontal_tween := create_tween()
	horizontal_tween.set_trans(Tween.TRANS_QUAD)
	horizontal_tween.set_ease(Tween.EASE_OUT)
	horizontal_tween.tween_property(
		self,
		"position:x",
		position.x
			+ horizontal_direction
			* horizontal_travel_px
			* randomized_launch_scale
			* lerpf(1.0, 1.25, safe_combo_strength),
		lifetime_seconds
	)

	var impact_label_y := position.y
	var jump_height := (
		jump_height_px
		* randomized_launch_scale
		* lerpf(1.0, 1.2, safe_combo_strength)
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
		impact_label_y - jump_height * 0.45,
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
