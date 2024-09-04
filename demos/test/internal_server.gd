extends Node

@onready var server_root: ServerRoot = $ServerRoot

func _ready() -> void:
	server_root.connection_success.connect(func (): print('Server connection success'))
	server_root.connection_failed.connect(
		func (s: ServerRoot.ConnectionState):
			print('Server connection failed: %s' % ServerRoot.get_connection_state_name(s))
	)
	server_root.attempt_multiple_connects(-1)
