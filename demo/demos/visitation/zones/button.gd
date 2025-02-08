extends Button

const ICON = preload("res://demos/visitation/zones/icon.tscn")

@onready var initial_text := "Presses: %s"

@export var press_count := 0:
	set(x):
		press_count = x
		if is_node_ready():
			text = initial_text % [press_count]
			if mp.is_server():
				sync.request_sync(self, &"press_count")

@onready var sync := Godaemon.sync_service(self)
@onready var mp := Godaemon.mp(self)

func _ready() -> void:
	press_count = press_count
	if mp.is_server():
		position = (get_parent().size - size) * Vector2(randf(), randf())
	else:
		pressed.connect(_request_pressed.rpc)

@rpc("any_peer")
func _request_pressed():
	press_count += 1
	
	var _icon := ICON.instantiate()
	_icon.global_position = Vector2(get_parent().size.x * randf(), get_parent().size.y * randf())
	_icon.rotation_degrees = randi_range(0, 360)
	Godaemon.replication_service(self).set_visibility(_icon, true)
	get_parent().add_child(_icon)
