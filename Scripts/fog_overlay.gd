extends ColorRect

func _ready():
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	
	# Create noise texture with proper settings
	var noise_tex = NoiseTexture2D.new()
	var noise = FastNoiseLite.new()
	
	# Settings from the instructions
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX  # Smooth clouds
	noise.frequency = 0.02  # Adjust for cloud size
	noise.fractal_octaves = 3
	noise.seed = 12345
	
	# Texture settings
	noise_tex.noise = noise
	noise_tex.width = 320  # 16:9 ratio (320x180 or 160x90)
	noise_tex.height = 180
	noise_tex.seamless = true
	noise_tex.seamless_blend_skirt = 1.0
	noise_tex.normalize = false  # Important!
	
	# Apply shader
	var mat = ShaderMaterial.new()
	mat.shader = preload("res://shaders/fog.gdshader")
	mat.set_shader_parameter("noise_texture", noise_tex)
	mat.set_shader_parameter("smoke_color", Vector3(0.5, 0.45, 0.4))  # Wasteland brown
	mat.set_shader_parameter("density", 0.25)  # Adjust visibility
	mat.set_shader_parameter("distortion_speed", 0.1)  # Slow drift
	
	material = mat
