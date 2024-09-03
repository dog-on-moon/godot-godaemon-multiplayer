extends Node
class_name ChatService

@onready var mp := MultiplayerNode.fetch(self)

func _ready() -> void:
	mp.peer_connected.connect(_peer_connected)

func _peer_connected(peer: int):
	var prefix := "Client" if mp.is_client() else "Server"
	print('{%s, %s} peer connected: %s' % [name, prefix, peer])
	if mp.is_client():
		print_msg.rpc_id(1, "Hello server!")
	elif mp.is_server():
		print_msg.rpc_id(peer, "Hello client!")

@rpc("any_peer")
func print_msg(msg: String):
	print('{%s} %s' % [mp.name, msg])
