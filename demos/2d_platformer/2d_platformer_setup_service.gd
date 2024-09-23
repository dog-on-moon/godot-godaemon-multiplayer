extends ServiceBase
class_name TDPlatformerSetupService
## Sets up the Visitation demo.

const EXT_ZONE = preload("res://demos/2d_platformer/area/ext_zone.tscn")
const PLAYER = preload("res://demos/2d_platformer/player/player.tscn")

@onready var zone_service := Godaemon.zone_service(self)
@onready var replication_service := Godaemon.replication_service(self)

func _ready() -> void:
	if mp.is_server():
		var ext_zone_node: Node2D = EXT_ZONE.instantiate()
		var ext_zone: Zone = zone_service.add_zone(ext_zone_node)
		
		var peer_to_player: Dictionary[int, Node] = {}
		
		mp.peer_connected.connect(
			func (peer: int):
				# Create player node.
				var player := PLAYER.instantiate()
				player.position.x = randi_range(-256, 256)
				player.color = Color.from_hsv(randf(), 1.0, 1.0)
				replication_service.set_node_owner(player, peer)
				ext_zone_node.add_child(player)
				replication_service.set_visibility(player, true)
				
				peer_to_player[peer] = player
				
				# Give peer interest in the zone.
				ext_zone.add_interest(peer)
		)
		mp.peer_disconnected.connect(
			func (peer: int):
				if peer in peer_to_player:
					peer_to_player[peer].queue_free()
					peer_to_player.erase(peer)
		)
