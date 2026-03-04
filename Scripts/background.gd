extends Sprite2D

func _ready():
	z_index = 0
	modulate = Color(1.0, 1.0, 1.0, 0.024)  # Very subtle
	texture = create_dirt_texture()

func create_dirt_texture() -> NoiseTexture2D:
	var noise_tex = NoiseTexture2D.new()
	var noise = FastNoiseLite.new()
	noise.noise_type = FastNoiseLite.TYPE_CELLULAR
	noise.frequency = 0.05
	noise_tex.noise = noise
	noise_tex.width = 1920
	noise_tex.height = 1080
	return noise_tex
