#extends Building
#class_name Workplace
#
#@onready var request_label: Label = $MarginContainer/VBoxContainer/RequestLabel
#
## =============================================================================
## DUMB WORKPLACE - Director Controls Everything
## Workplace just fires requests at intervals dictated by Director's pressure
## =============================================================================
#
#var shipment_timer: Timer
#var shipment_backlog: int = 0
#
## Lifetime stats (for UI/debugging)
#var total_requests_made: int = 0
#var total_deliveries_received: int = 0
#var time_alive: float = 0.0
#
## Director reference (set on spawn)
#var director: Node = null
#
#
#func _ready():
	#cell_type = "WORKPLACE"
	#
	## Only assign random color if director didn't already set one
	#if color_id == -1:
		#assign_random_color()
	#
	#super()
	#
	## Find Director
	#await get_tree().process_frame
	#director = get_node_or_null("/root/Main/Director")
	#
	#if not director:
		#push_warning("Workplace: No Director found! Using fallback intervals")
	#
	#setup_shipment_timer()
	#update_ui()
	#
	#print("Workplace spawned at %s | color_id: %d | Director-controlled" % [entrance_cell, color_id])
#
#
#func _process(delta: float) -> void:
	#time_alive += delta
#
#
## =============================================================================
## COLOR SYSTEM
## =============================================================================
#func assign_random_color() -> void:
	#"""Assign a random color from GameData's active palette"""
	#var color_data = GameData.get_random_color_from_palette()
	#set_building_color(color_data["color"], color_data["id"])
	#print("Workplace assigned color_id: %d" % color_id)
#
#
## =============================================================================
## TIMER SETUP - Interval Controlled by Director
## =============================================================================
#func setup_shipment_timer():
	#shipment_timer = Timer.new()
	#shipment_timer.wait_time = get_request_interval()
	#shipment_timer.timeout.connect(_on_shipment_timer_timeout)
	#add_child(shipment_timer)
	#shipment_timer.start()
#
#
#func get_request_interval() -> float:
	#"""Ask Director for the current request interval based on pressure"""
	#if director and director.has_method("get_workplace_request_interval"):
		#return director.get_workplace_request_interval()
	#else:
		## Fallback if Director not found
		#return 10.0
#
#
#func _on_shipment_timer_timeout():
	## Ask Director how many shipments to request this cycle
	#var burst_size = get_burst_size()
	#
	#for i in range(burst_size):
		#make_request()
	#
	## Update interval for next cycle (Director may have changed pressure)
	#shipment_timer.wait_time = get_request_interval()
	#
	#update_ui()
#
#
#func get_burst_size() -> int:
	#"""Ask Director for burst size based on pressure"""
	#if director and director.has_method("get_workplace_burst_size"):
		#return director.get_workplace_burst_size()
	#else:
		## Fallback
		#return 1
#
#
## =============================================================================
## REQUEST LOGIC
## =============================================================================
#func make_request():
	#shipment_backlog += 1
	#total_requests_made += 1
	#
	#SignalBus.delivery_requested.emit(self)
	#
	#print("Workplace at %s requests shipment (backlog: %d)" % [entrance_cell, shipment_backlog])
#
#
#func fulfill_request():
	#"""Called when a car delivers a shipment"""
	#if shipment_backlog > 0:
		#shipment_backlog -= 1
		#total_deliveries_received += 1
		#GameData.total_global_deliveries += 1
		#GameData.player_score += 10
		#
		#print("Workplace at %s received delivery (backlog: %d, total: %d)" % [
			#entrance_cell, 
			#shipment_backlog,
			#total_deliveries_received
		#])
		#
		#update_ui()
#
#
## =============================================================================
## UI UPDATE
## =============================================================================
#func update_ui():
	#if request_label:
		## Show backlog and current pressure phase
		#var phase_text = ""
		#if director:
			#var phase_names = ["ADAGIO", "ANDANTE", "VIVACE", "FINALE"]
			#var pressure_info = director.get_pressure_info()
			#phase_text = " [%s]" % phase_names[pressure_info["phase"]]
		#
		#request_label.text = "Backlog: %d%s" % [shipment_backlog, phase_text]
