extends ServiceBase
class_name TDPlatformerSetupService
## Sets up the 2D platformer demo.

const EXT_ZONE = preload("res://demos/2d_platformer/area/ext_zone.tscn")
const PLAYER = preload("res://demos/2d_platformer/player/player.tscn")

@onready var zone_service := Godaemon.zone_service(self)
@onready var replication_service := Godaemon.replication_service(self)
@onready var database_service := Godaemon.database_service(self)

var game_scene: Node2D
var game_zone: Zone

# A mapping from peer to player. Only on the server.
var peer_to_player: Dictionary[int, Node] = {}

func _ready() -> void:
	# Services are added underneath a ServerRoot after establishing an
	# ENet server, and underneath a ClientRoot after they connect to
	# a ServerRoot.
	if mp.is_server():
		database_service.db = TextDB.new()
		
		# Instantiate a world scene, and setup a Zone for it.
		game_scene = EXT_ZONE.instantiate()
		game_zone = zone_service.add_zone(game_scene)
		
		mp.peer_disconnected.connect(
			func (peer: int):
				# When a peer disconnects, remove their player scene on the server.
				# This will automatically replicate their destruction to clients.
				if peer in peer_to_player:
					peer_to_player[peer].queue_free()
					peer_to_player.erase(peer)
		)
	else:
		# In a more favorable network topology, the player ID would be derived
		# from a proper username/password login setup.
		#
		# In this case, we are going to derive it from metadata that
		# multiplayer_test_frame.gd sets.
		var player_id: int = mp.get_meta(&"client_index", 0)
		request_player.rpc(player_id)

@rpc func request_player(player_id: int):
	if mp.remote_peer in peer_to_player: return
	
	# When a peer connects to us, we give them a player scene.
	var player := PLAYER.instantiate()
	
	# Set initial properties of the player.
	var peer := mp.remote_peer
	player.position.x = randi_range(-256, 256)
	player.color = Color.from_hsv(randf(), 1.0, 1.0)
	await database_service.track_object(player, "player", str(player_id))
	replication_service.set_node_owner(player, peer)
	peer_to_player[peer] = player
	
	# Set the player scene's global visibility to true,
	# which will replicate it and its properties to all peers.
	# This MUST be called before the node enters the tree.
	replication_service.set_visibility(player, true)
	
	# Add them to the zone scene.
	game_scene.add_child(player)
	
	# Give the connected peer 'interest' to the game zone,
	# giving them a view of the game world.
	game_zone.add_interest(peer)
