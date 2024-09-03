extends Node
class_name PeerService
## The server can write metadata for connected peers
## and replicate them back to clients.

var mp := MultiplayerNode.fetch(self)
var _client_request_full_ratelimiter := RateLimiter.new(mp, 1, 1.0)

func _ready() -> void:
	mp.peer_connected.connect()
