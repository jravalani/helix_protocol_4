extends Building

class_name Workplace

# A timer to control how often this workplace requests a delivery
@export var shipment_interval: float = 10.0
var shipment_timer: Timer

func _ready():
	# 1. Identify as a building/workplace before parent registration
	cell_type = GameData.CELL_BUILDING
	
	# 2. Run the parent's registration logic
	super()
	
	# 3. Setup the Shipment Logic
	setup_shipment_timer()

func setup_shipment_timer():
	shipment_timer = Timer.new()
	add_child(shipment_timer)
	shipment_timer.wait_time = shipment_interval # Requests a car every 10 seconds
	shipment_timer.timeout.connect(_on_shipment_timeout)
	shipment_timer.start()

func _on_shipment_timeout():
	print("Workplace at ", entrance_cell, " is requesting a shipment!")
	# Shout to the SignalBus so all Houses can hear the request
	# We pass 'entrance_cell' so houses know where to go
	SignalBus.delivery_requested.emit(entrance_cell)
