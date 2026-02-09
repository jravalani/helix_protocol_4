extends Building

class_name Workplace


@onready var request_label: Label = $MarginContainer/VBoxContainer/RequestLabel
# A timer to control how often this workplace requests a delivery
@export var shipment_interval: float = 10.0
var shipment_timer: Timer

var shipment_backlog: int = 0

func _ready():
	# 1. Identify as a building/workplace before parent registration
	cell_type = "WORKPLACE"
	
	# 2. Run the parent's registration logic
	super()
	
	# 3. Setup the Shipment Logic
	setup_shipment_timer()
	
	update_ui()

func setup_shipment_timer():
	shipment_timer = Timer.new()
	add_child(shipment_timer)
	shipment_timer.wait_time = randi_range(6, shipment_interval)
	shipment_timer.timeout.connect(_on_shipment_timeout)
	shipment_timer.start()

func _on_shipment_timeout():
	shipment_backlog += 1
	update_ui()
	print("Workplace at ", entrance_cell, " is requesting a shipment!")
	# Shout to the SignalBus so all Houses can hear the request
	# We pass 'entrance_cell' so houses know where to go
	SignalBus.delivery_requested.emit(self)

func fulfill_request():
	if shipment_backlog > 0:
		shipment_backlog -= 1
		update_ui()

func update_ui() -> void:
	if request_label:
		request_label.text = str(shipment_backlog)
