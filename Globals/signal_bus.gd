extends Node

signal map_changed

signal spawn_hub_requested

signal spawn_vent_requested

signal car_returned_home

signal building_spawned(entrance_cell: Vector2i, driveway_direction: Vector2i, instance_id: int)

signal pressure_updated(new_value: int, percentage: float)

signal pressure_phase_changed(new_phase: int)

signal fracture_wave

signal fracture_wave_impact

signal disaster_triggered(event_name: String)

signal increase_map_size(map_size: Rect2i)

signal pipes_upgraded(upgrade_level: int)

signal check_fractures

signal open_rocket_menu

signal rocket_segment_purchased(new_phase: int)

signal camera_shake(duration: float, strength: float)

signal zone_unlocked(zone: int)

signal game_over

signal vent_interval_updated

signal trigger_packet_slowdown

signal trigger_vent_burst

signal ui_wake_up

signal notify_player(message: String, type: int)
