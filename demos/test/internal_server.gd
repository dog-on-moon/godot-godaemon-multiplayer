extends Node

@onready var server_node: ServerNode = $ServerNode

func _ready() -> void:
	server_node.connection_success.connect(func (): print('Server connection success'))
	server_node.connection_failed.connect(
		func (s: ServerNode.ConnectionState):
			print('Server connection failed: %s' % ServerNode.get_connection_state_name(s))
	)
	server_node.attempt_multiple_connects(-1)
