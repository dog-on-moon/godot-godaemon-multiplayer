extends Node
class_name PeerService
## The server can write metadata for connected peers
## and replicate them back to clients.

@onready var mp := MultiplayerNode.fetch(self)

func _ready() -> void:
	pass
