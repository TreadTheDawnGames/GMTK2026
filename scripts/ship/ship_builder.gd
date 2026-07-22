class_name ShipBuilder
extends Node2D
## Joins navigation between manually placed ship sections at matching connectors.

@export_range(0.1, 8.0, 0.1) var connection_tolerance := 1.0
@export_range(1.0, 32.0, 1.0) var navigation_link_inset := 12.0

@onready var navigation_links: Node2D = %NavigationLinks


func _ready() -> void:
	NavigationServer2D.map_set_use_async_iterations(
		get_world_2d().navigation_map,
		false
	)
	rebuild_navigation_links()


func rebuild_navigation_links() -> void:
	for child in navigation_links.get_children():
		navigation_links.remove_child(child)
		child.queue_free()

	var sections: Array[ShipSection] = []
	for child in get_children():
		var section := child as ShipSection
		if section != null:
			sections.append(section)
			if not section.placement_changed.is_connected(_on_section_placement_changed):
				section.placement_changed.connect(_on_section_placement_changed)

	for section in sections:
		for direction: ShipSection.Connection in [
			ShipSection.Connection.RIGHT,
			ShipSection.Connection.DOWN,
		]:
			if not section.has_connection(direction):
				continue
			var connected_section := _find_connected_section(section, direction, sections)
			if connected_section == null:
				continue
			var outward := Vector2.RIGHT if direction == ShipSection.Connection.RIGHT else Vector2.DOWN
			var connector_position := section.get_world_connection_position(direction)
			var navigation_link := NavigationLink2D.new()
			navigation_link.name = "%sTo%s" % [section.name, connected_section.name]
			navigation_link.bidirectional = true
			navigation_link.start_position = navigation_links.to_local(
				connector_position - outward * navigation_link_inset
			)
			navigation_link.end_position = navigation_links.to_local(
				connector_position + outward * navigation_link_inset
			)
			navigation_links.add_child(navigation_link)
	NavigationServer2D.map_force_update(get_world_2d().navigation_map)


func _find_connected_section(
	section: ShipSection,
	direction: ShipSection.Connection,
	sections: Array[ShipSection]
) -> ShipSection:
	var opposite_direction := ShipSection.opposite(direction)
	var connector_position := section.get_world_connection_position(direction)
	for candidate in sections:
		if candidate == section or not section.can_connect_to(candidate, direction):
			continue
		if candidate.get_world_connection_position(opposite_direction).distance_to(connector_position) <= connection_tolerance:
			return candidate
	return null


func _on_section_placement_changed(_section: ShipSection) -> void:
	rebuild_navigation_links.call_deferred()
