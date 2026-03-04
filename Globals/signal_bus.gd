extends Node

signal map_changed

signal car_returned_home

signal building_spawned(building_type: String, position: Vector2i, color_id: int)

signal pressure_updated(new_value: int, percentage: float)

signal pressure_changed(new_phase: int)

signal disaster_triggered(event_name: String)

signal increase_map_size(map_size: Rect2i)

signal pipes_upgraded(upgrade_level: int)

signal check_fractures

signal open_rocket_menu

signal rocket_segment_purchased(new_phase: int)
