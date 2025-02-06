extends Camera2D

func _ready() -> void:
	if Godaemon.mp(self).is_server():
		enabled = true
		make_current()
