## WinSceneData.gd
## Add as Autoload: Project > Project Settings > Autoload > name it "WinSceneData"
##
## Before transitioning to WinScene, set these values:
##   WinSceneData.pipe_tiles     = current_pipe_count
##   WinSceneData.peak_pressure  = highest_pressure_reached
##   WinSceneData.data_collected = total_data
##   WinSceneData.repair_reserve = remaining_reserve
##   SceneTransition.transition_to("res://Scenes/WinScene.tscn", SceneTransition.Type.BEAM)

extends Node

var pipe_tiles     : int    = 0
var peak_pressure  : float  = 0.0
var data_collected : int    = 0
var repair_reserve : int    = 0
var survival_time  : float  = 0.0   # seconds — used by LoseScene
var failure_cause  : String = ""    # optional override for lose screen
