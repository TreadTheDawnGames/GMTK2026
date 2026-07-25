class_name BreakthroughTargetHighlight
extends Node

## How it works:
## - Input: LayerBreakthroughController.arming_changed plus Caspian's timing bar.
## - Output: gold live targets with an explicit next-hit cutscene label.
## - Owned state: whether the cutscene warning is currently applied.
## - The bar creates, reuses, and re-shows its own targets, so an armed warning
##   is re-asserted each frame rather than written once and lost on the next set.
## - The invariant is that disarming always restores the authored target color.

const CUTSCENE_LABEL_PATH: NodePath = ^"CutsceneWarning"

@export_category("References")
@export var timing_window: TimingWindowTask

@export_category("Appearance")
## Must match the green authored on Scenes/targets/target_base.tscn. This adapter
## repaints rather than remembers, so every target shares one resting color.
@export var authored_target_color: Color = Color(0.0, 0.56078434, 0.0, 1.0)
@export var armed_target_color: Color = Color(1.0, 0.78, 0.16, 1.0)
@export_multiline var armed_target_text: String = "NEXT HIT:\nCUTSCENE"
@export var armed_text_color: Color = Color(1.0, 0.92, 0.58, 1.0)

var _is_armed: bool = false


func _ready() -> void:
	set_process(false)


## Latches the warning so the exact triggering target explains itself.
func _on_breakthrough_arming_changed(is_armed: bool) -> void:
	if is_armed == _is_armed:
		return
	_is_armed = is_armed
	set_process(is_armed)
	_apply_target_appearance()


## Re-asserts the warning because the bar may reroll its target set at any time.
func _process(_delta: float) -> void:
	_apply_target_appearance()


func _apply_target_appearance() -> void:
	if not is_instance_valid(timing_window):
		return
	var mining_window := timing_window.mining_window
	if not is_instance_valid(mining_window):
		return
	for target: TimingTarget in mining_window.targets:
		if not is_instance_valid(target):
			continue
		target.self_modulate = (
			armed_target_color if _is_armed else authored_target_color
		)
		var warning_label := (
			target.get_node_or_null(CUTSCENE_LABEL_PATH) as Label
		)
		# One label per bounded live target; it is freed with its target.
		if warning_label == null and _is_armed:
			warning_label = Label.new()
			warning_label.name = CUTSCENE_LABEL_PATH.get_name(0)
			warning_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			warning_label.z_index = 10
			warning_label.position = Vector2(-48.0, -48.0)
			warning_label.size = Vector2(96.0, 42.0)
			warning_label.text = armed_target_text
			warning_label.horizontal_alignment = (
				HORIZONTAL_ALIGNMENT_CENTER
			)
			warning_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			warning_label.add_theme_font_size_override("font_size", 12)
			warning_label.add_theme_constant_override("outline_size", 4)
			warning_label.add_theme_color_override(
				"font_color",
				armed_text_color
			)
			warning_label.add_theme_color_override(
				"font_outline_color",
				Color(0.12, 0.07, 0.03, 1.0)
			)
			target.add_child(warning_label)
		if warning_label != null:
			warning_label.visible = _is_armed
