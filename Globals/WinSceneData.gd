extends Node

var pipe_tiles     : int    = 0
var peak_pressure  : float  = 0.0
var data_collected : int    = 0
var repair_reserve : int    = 0
var survival_time  : float  = 0.0
var failure_cause  : String = ""

## Call this before transitioning to Win or Lose scene.
## Pass failure_cause = "" for a win, or a cause string for a loss.
func capture(cause: String = "") -> void:
	pipe_tiles     = GameData.road_grid.size()
	peak_pressure  = GameData.current_pressure
	data_collected = GameData.lifetime_data_earned
	repair_reserve = GameData.data_reserve_for_auto_repairs
	failure_cause  = cause
	# survival_time must be set externally via a running timer in the Director
