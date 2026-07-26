extends ProgressBar
class_name NotchedProgressBar

@export var ticks : Array[int]
@export var tick_sprite : Texture2D
var active_ticks : Dictionary[int, TextureRect]
signal reached_tick(tick_value : int)

func _ready():
	max_value = ceil(size.x / (get_theme_stylebox("background") as StyleBoxTexture).texture.get_width())
	value_changed.connect(_on_value_changed)
	draw_ticks()

func set_ticks(set_to : Array[int]):
	ticks = set_to
	draw_ticks()
	
func add_tick(new_tick : int):
	ticks.append(new_tick)
	draw_ticks()
	
func add_ticks(new_ticks : Array[int]):
	for i in new_ticks:
		ticks.append(i)
	draw_ticks()
	
func remove_tick(tick : int):
	ticks.erase(tick)
	draw_ticks()
	
func draw_ticks():
	for child in get_children():
		child.queue_free()
	for tick in ticks:
		var sprite : TextureRect = TextureRect.new()
		sprite.pivot_offset_ratio = Vector2(0.5,0.5)
		sprite.texture = tick_sprite
		sprite.position.x = size.x * float(float(tick)/max_value) - (tick_sprite.get_width()*0.5)
		add_child(sprite)
		active_ticks.get_or_add(tick, sprite)
		pass

func _on_value_changed(new_value : float):
	var val : int = int(new_value)
	if ticks.has(val):
		if active_ticks.keys().has(new_value):
			var t : Tween = create_tween()
			t.tween_property(active_ticks[val], "scale", Vector2(1.5,1.5), 0.1)
			t.tween_property(active_ticks[val], "scale", Vector2.ONE, 0.1)
		reached_tick.emit(new_value)
		pass

func set_maximum(new_max : int):
	max_value = new_max
	size.x = (get_theme_stylebox("background") as StyleBoxTexture).texture.get_width() * max_value
