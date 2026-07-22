class_name ShipBuilder
extends Node2D
## Joins navigation between manually placed ship sections at matching connectors.

## Maximum world-space gap between connector markers that should snap together.
@export_range(0.1, 16.0, 0.1) var connection_tolerance := 4.0
## Maximum facing error allowed between two opposing, possibly rotated connectors.
@export_range(0.0, 45.0, 1.0) var connector_angle_tolerance := 15.0
## Moves link endpoints inside each polygon so Godot attaches them reliably.
@export_range(1.0, 32.0, 1.0) var navigation_link_inset := 12.0

@onready var navigation_links: Node2D = %NavigationLinks


func _ready() -> void:
	NavigationServer2D.map_set_use_async_iterations(
		get_world_2d().navigation_map,
		false
	)
	rebuild_navigation_links()


func rebuild_navigation_links() -> void:
	# Links are runtime-derived so designers only need to position section scenes.
	for child in navigation_links.get_children():
		navigation_links.remove_child(child)
		child.queue_free()

	var sections := _get_sections()
	for section in sections:
		if not section.placement_changed.is_connected(_on_section_placement_changed):
			section.placement_changed.connect(_on_section_placement_changed)

	var directions: Array[ShipSection.Connection] = [
		ShipSection.Connection.UP,
		ShipSection.Connection.RIGHT,
		ShipSection.Connection.DOWN,
		ShipSection.Connection.LEFT,
	]
	# Compare every active marker in world space. This keeps nested, rotated, and
	# scaled sections working without orientation-specific builder code.
	var minimum_opposition := cos(deg_to_rad(connector_angle_tolerance))
	for first_index in range(sections.size()):
		var first_section := sections[first_index]
		for second_index in range(first_index + 1, sections.size()):
			var second_section := sections[second_index]
			for first_direction in directions:
				if not first_section.has_connection(first_direction):
					continue
				var first_position := first_section.get_world_connection_position(first_direction)
				var first_outward := first_section.get_world_connection_direction(first_direction)
				for second_direction in directions:
					if not second_section.has_connection(second_direction):
						continue
					var second_position := second_section.get_world_connection_position(second_direction)
					if first_position.distance_to(second_position) > connection_tolerance:
						continue
					var second_outward := second_section.get_world_connection_direction(second_direction)
					if first_outward.dot(second_outward) > -minimum_opposition:
						continue
					var navigation_link := NavigationLink2D.new()
					navigation_link.name = "%sTo%s" % [first_section.name, second_section.name]
					navigation_link.bidirectional = true
					navigation_link.start_position = navigation_links.to_local(
						first_position - first_outward * navigation_link_inset
					)
					navigation_link.end_position = navigation_links.to_local(
						second_position - second_outward * navigation_link_inset
					)
					navigation_links.add_child(navigation_link)
	NavigationServer2D.map_force_update(get_world_2d().navigation_map)


func get_ship_bounds() -> Rect2:
	# Convert every artwork corner back into builder space. Using global
	# transforms here is required for nested or rotated section instances.
	var bounds := Rect2()
	var has_bounds := false
	for section in _get_sections():
		var section_bounds := section.get_visual_bounds()
		if not section_bounds.has_area():
			continue
		var section_to_builder := global_transform.affine_inverse() * section.global_transform
		for corner: Vector2 in [
			section_bounds.position,
			Vector2(section_bounds.end.x, section_bounds.position.y),
			section_bounds.end,
			Vector2(section_bounds.position.x, section_bounds.end.y),
		]:
			var point: Vector2 = section_to_builder * corner
			if not has_bounds:
				bounds = Rect2(point, Vector2.ZERO)
				has_bounds = true
			else:
				bounds = bounds.expand(point)
	return bounds


func _get_sections() -> Array[ShipSection]:
	var sections: Array[ShipSection] = []
	for descendant in find_children("*", "ShipSection", true, false):
		var section := descendant as ShipSection
		if section != null:
			sections.append(section)
	return sections


func _on_section_placement_changed(_section: ShipSection) -> void:
	rebuild_navigation_links.call_deferred()
