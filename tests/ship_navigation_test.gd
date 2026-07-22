extends SceneTree
## Verifies authored ship coverage and real CrewMember navigation across module links.

const LEVEL_SCENE := preload("res://scenes/game_scene/levels/spaceship_level.tscn")
const EXPECTED_SECTION_COUNT := 14
const EXPECTED_TRANSITION_COUNT := 14


func _initialize() -> void:
	var level := LEVEL_SCENE.instantiate()
	root.add_child.call_deferred(level)
	await physics_frame
	await physics_frame
	await physics_frame

	var ship := level.get_node("BaseShip") as ShipBuilder
	var sections: Array[ShipSection] = []
	for descendant in ship.find_children("*", "ShipSection", true, false):
		var section := descendant as ShipSection
		if section != null:
			sections.append(section)
	if sections.size() != EXPECTED_SECTION_COUNT:
		_fail(
			"Expected %d ship sections, found %d." % [
				EXPECTED_SECTION_COUNT,
				sections.size(),
			]
		)
		return

	var transition_count := ship.get_node("NavigationLinks").get_child_count()
	if transition_count != EXPECTED_TRANSITION_COUNT:
		_fail(
			"Expected %d navigation transitions, found %d." % [
				EXPECTED_TRANSITION_COUNT,
				transition_count,
			]
		)
		return

	var navigation_map := ship.get_world_2d().navigation_map
	NavigationServer2D.map_force_update(navigation_map)
	var main_hull := ship.get_node("MainHull") as ShipSection
	var route_origin := main_hull.global_position
	for section in sections:
		var destination := section.global_position
		var path := NavigationServer2D.map_get_path(
			navigation_map,
			route_origin,
			destination,
			true
		)
		if path.is_empty() or not path[path.size() - 1].is_equal_approx(destination):
			_fail("Main hull cannot reach ship section %s." % section.name)
			return

		var navigation_region := section.get_node("NavigationRegion2D") as NavigationRegion2D
		var navigation_polygon := navigation_region.navigation_polygon
		var vertices := navigation_polygon.vertices
		for polygon_index in range(navigation_polygon.get_polygon_count()):
			var polygon := navigation_polygon.get_polygon(polygon_index)
			var local_sample := Vector2.ZERO
			for vertex_index in polygon:
				local_sample += vertices[vertex_index]
			local_sample /= polygon.size()
			var polygon_sample := navigation_region.to_global(local_sample)
			var polygon_path := NavigationServer2D.map_get_path(
				navigation_map,
				route_origin,
				polygon_sample,
				true
			)
			if (
				polygon_path.is_empty()
				or not polygon_path[polygon_path.size() - 1].is_equal_approx(polygon_sample)
			):
				_fail(
					"Navigation polygon %d in %s is not walkable from the main hull." % [
						polygon_index,
						section.name,
					]
				)
				return

	var crew := level.get_node("CrewContainer/CrewOne") as CrewMember
	var second_crew := level.get_node("CrewContainer/CrewTwo") as CrewMember
	for crew_member in [crew, second_crew]:
		crew_member.move_speed = 600.0
		crew_member.navigation_agent.path_desired_distance = 12.0
		crew_member.navigation_agent.target_desired_distance = 8.0
		crew_member.navigation_agent.max_speed = crew_member.move_speed

	var engineering := ship.get_node("EngineeringRoom") as ShipSection
	crew.move_to(engineering.global_position + Vector2.LEFT * 8.0)
	second_crew.move_to(engineering.global_position + Vector2.RIGHT * 8.0)
	var both_arrived := false
	for _frame in range(360):
		await physics_frame
		if (
			crew.global_position.distance_to(engineering.global_position) <= 18.0
			and second_crew.global_position.distance_to(engineering.global_position) <= 18.0
		):
			both_arrived = true
			break
	if not both_arrived:
		_fail(
			"Authored crew spawns could not reach engineering; stopped at %s and %s." % [
				crew.global_position,
				second_crew.global_position,
			]
		)
		return

	for section_name in [
		"PortCrewQuarters",
		"Airlock",
		"CargoRoom",
	]:
		var target_section := ship.get_node(section_name) as ShipSection
		var target := target_section.global_position
		crew.move_to(target)
		var arrived := false
		for _frame in range(360):
			await physics_frame
			if crew.global_position.distance_to(target) <= 10.0:
				arrived = true
				break
		if not arrived:
			_fail(
				"Crew failed to walk to %s; stopped at %s." % [
					section_name,
					crew.global_position,
				]
			)
			return

	print(
		"Ship navigation passed: %d sections, %d transitions, and crew traversal." % [
			sections.size(),
			transition_count,
		]
	)
	quit()


func _fail(message: String) -> void:
	push_error(message)
	quit(1)
