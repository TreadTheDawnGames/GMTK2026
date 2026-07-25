@tool
class_name CreditEntry
extends Resource

## One inspector-authored inscription embedded in the credits terrain.

@export_range(0, 200, 1) var depth_offset: int = 0
@export var heading: String = ""
@export_multiline var body: String = ""
