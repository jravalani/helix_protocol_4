class_name EntityFactory

# ═════════════════════════════════════════════════════════════════
# Scene preloads — the single source of truth for entity scenes.
# SaveManager delegates all instantiation here so it never needs
# to know which .tscn file belongs to which entity type.
# ═════════════════════════════════════════════════════════════════

const _ROCKET_SCENE    := preload("res://Scenes/rocket.tscn")
const _HUB_SCENE       := preload("res://Scenes/hub3x2.tscn")
const _VENT_SCENE      := preload("res://Scenes/vent.tscn")
const _ROAD_TILE_SCENE := preload("res://Scenes/road_tile.tscn")


## Instantiate a Rocket and add it to [parent]. Returns null on failure.
static func create_rocket(parent: Node) -> Rocket:
	var instance := _ROCKET_SCENE.instantiate() as Rocket
	if not instance:
		push_warning("EntityFactory: Failed to instantiate rocket scene")
		return null
	parent.add_child(instance)
	return instance


## Instantiate a Hub and add it to [parent]. Returns null on failure.
static func create_hub(parent: Node) -> Hub:
	var instance := _HUB_SCENE.instantiate() as Hub
	if not instance:
		push_warning("EntityFactory: Failed to instantiate hub scene")
		return null
	parent.add_child(instance)
	return instance


## Instantiate a Vent and add it to [parent]. Returns null on failure.
static func create_vent(parent: Node) -> Vent:
	var instance := _VENT_SCENE.instantiate() as Vent
	if not instance:
		push_warning("EntityFactory: Failed to instantiate vent scene")
		return null
	parent.add_child(instance)
	return instance


## Instantiate a NewRoadTile at [cell], add it to [parent]. Returns null on failure.
## Handles position and set_cell so callers only need to register + restore data.
static func create_pipe(parent: Node, cell: Vector2i) -> NewRoadTile:
	var instance := _ROAD_TILE_SCENE.instantiate() as NewRoadTile
	if not instance:
		push_warning("EntityFactory: Failed to instantiate road tile scene")
		return null
	instance.position = GameData.get_cell_center(cell)
	instance.set_cell(cell)
	parent.add_child(instance)
	return instance
