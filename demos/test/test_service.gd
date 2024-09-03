extends Node
class_name TestService

@onready var mp := MultiplayerNode.fetch(self)
@onready var peer_service: PeerService = mp.get_service(PeerService)

func _ready() -> void:
	mp.peer_connected.connect(_peer_connected)
	peer_service.updated.connect(_peer_service_updated)

func _peer_connected(peer: int):
	if mp.is_server():
		var idx := 1
		while peer_service.find_peers(&"username", &"Player%s" % idx):
			idx += 1
		peer_service.add_data(peer, &"username", &"Player%s" % idx)

func _peer_service_updated():
	if mp.is_client():
		print('new fields: %s' % [peer_service.peer_data])
