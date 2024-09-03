extends Node
class_name ChatService

@onready var mp := MultiplayerNode.fetch(self)

func _ready() -> void:
	mp.peer_connected.connect(_peer_connected)

func _peer_connected(peer: int):
	var prefix := "Client" if mp.is_client() else "Server"
	print('[%s] Hello, %s!' % [prefix, peer])
