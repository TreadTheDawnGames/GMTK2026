extends RichTextLabel
class_name DigNumber
const DIG_NUMBER = preload("uid://faai1irb202y")


@export var value_effects : Dictionary[int, String] = {10:"wave", 20:"rainbow"}
@export var lifetime : float = 1.5

static func create(at_global_position : Vector2, value : int, tree : SceneTree):
	print("value: ", value)
	var dig_number : DigNumber = DIG_NUMBER.instantiate()
	dig_number.global_position = at_global_position
	var string_value : String = str(-value)
	for _value : int in dig_number.value_effects.keys():
		if value >= _value:
			string_value = wrap_string_bbcode(string_value, dig_number.value_effects[_value])
	dig_number.text = string_value
	tree.root.add_child(dig_number)
	await tree.create_timer(dig_number.lifetime).timeout
	dig_number.queue_free()
	pass

#func _ready():
	#var tween : Tween = create_tween()
	#tween.tween_property(self, "position", Vector2(500, randi()*get_viewport_rect().size.x), 0.5)

static func wrap_string_bbcode(string : String, bbcode_tag : String) -> String:
	bbcode_tag = bbcode_tag.strip_edges()
	bbcode_tag = bbcode_tag.strip_escapes()
	bbcode_tag = bbcode_tag.lstrip("[]{}()")
	bbcode_tag = bbcode_tag.rstrip("[]{}()")
	
	return ("[%s]" % bbcode_tag) + string + ("[/%s]" % bbcode_tag)
	
