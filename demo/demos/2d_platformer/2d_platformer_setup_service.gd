extends ServiceBase
class_name TDPlatformerSetupService
## Sets up the 2D platformer demo.

const EXT_ZONE = preload("res://demos/2d_platformer/area/ext_zone.tscn")
const PLAYER = preload("res://demos/2d_platformer/player/player.tscn")

@onready var zone_service := Godaemon.zone_service(self)
@onready var replication_service := Godaemon.replication_service(self)

func _ready() -> void:
	# Services are added underneath a ServerRoot after establishing an
	# ENet server, and underneath a ClientRoot after they connect to
	# a ServerRoot.
	if mp.is_server():
		# Instantiate a world scene, and setup a Zone for it.
		var game_scene: Node2D = EXT_ZONE.instantiate()
		var game_zone: Zone = zone_service.add_zone(game_scene)
		
		# Only the server needs to create scenes for the player.
		var peer_to_player: Dictionary[int, Node] = {}
		mp.peer_connected.connect(
			func (peer: int):
				# When a peer connects to us, we give them a player scene.
				var player := PLAYER.instantiate()
				
				# Set initial properties of the player.
				player.position.x = randi_range(-256, 256)
				player.color = Color.from_hsv(randf(), 1.0, 1.0)
				replication_service.set_node_owner(player, peer)
				peer_to_player[peer] = player
				
				# Add them to the zone scene.
				game_scene.add_child(player)
				
				# Set the player scene's global visibility to true,
				# which will replicate it and its properties to all peers.
				replication_service.set_visibility(player, true)
				
				# Give the connected peer 'interest' to the game zone,
				# giving them a view of the game world.
				game_zone.add_interest(peer)
		)
		mp.peer_disconnected.connect(
			func (peer: int):
				# When a peer disconnects, remove their player scene on the server.
				# This will automatically replicate their destruction to clients.
				if peer in peer_to_player:
					peer_to_player[peer].queue_free()
					peer_to_player.erase(peer)
		)
