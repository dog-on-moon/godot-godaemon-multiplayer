extends Camera2D

func _ready() -> void:
	if multiplayer.is_server():
		enabled = true
		make_current()
