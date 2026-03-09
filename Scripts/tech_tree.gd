extends Control

@onready var purchase_button: Button = $Panel/VBoxContainer/PurchaseSegmentButton
# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	SignalBus.open_rocket_menu.connect(_on_open_rocket_menu)
	SignalBus.rocket_segment_purchased.connect(_on_rocket_segment_purchased)

func _on_open_rocket_menu() -> void:
	#for testing i have added it here to redirect it to home screen, can remove afer tetsing and using it where neededd
	SceneTransition.transition_to("res://scenes/main.tscn")
	#uncomment below code once scene transiiton removed
	#self.show()
	
	# Check if all segments are built
	if GameData.current_rocket_phase >= 5:
		purchase_button.text = "Launch Rocket!"
		purchase_button.disabled = false  # Or true if already launched
	else:
		var next = GameData.current_rocket_phase + 1
		purchase_button.text = "Purchase " + GameData.ROCKET_UPGRADES[next]["name"]
		purchase_button.disabled = false


func _on_purchase_segment_button_pressed() -> void:
	if ResourceManager.upgrade_rocket_phase():
		# do all the animations and other stuff from here.
		print("Rocket upgraded to: ", GameData.current_rocket_phase)
	else:
		# denial animation or sound or anything
		print("Nope, can't upgrade to next phase.")

func _on_close_button_pressed() -> void:

	self.hide()

func _on_rocket_segment_purchased(to_phase: int) -> void:
	match to_phase:
		1:
			print("Upgraded to phase 1")
			self.hide()
		2:
			print("Upgraded to phase 2")
			self.hide()
		3:
			print("Upgraded to phase 3")
			self.hide()
		4:
			print("Upgraded to phase 4")
			self.hide()
		5:
			print("Upgraded to phase 5")
			self.hide()
			print("Initiating Launch Sequence.")
			print("You Win.")
