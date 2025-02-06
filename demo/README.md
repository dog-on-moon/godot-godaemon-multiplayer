![screen-shot](https://github.com/dog-on-moon/godot-godaemon-multiplayer/blob/main/readme/banner.png)

# Godaemon Multiplayer

**Godaemon** (the *Good Daemon*) is a server-authoritative multiplayer API for Godot 4.4. Inspired by [Astron](https://github.com/Astron/Astron), Godaemon provides an immediate framework for developing any kind of multiplayer game, especially for larger projects.

This is my third attempt at developing a multiplayer framework in Godot. This plugin is created based on what I felt was lacking from Godot in regards to efficient multiplayer development, and I hope it will serve your purposes too.

## Features

Godaemon is built directly on top of Godot's built-in API to provide common multiplayer systems to heavily reduce your boilerplate, streamlining multiplayer development. In Godaemon, you can continue using RPCs the exact same way, but other systems have been introduced to make your life less dependent on them.

### Sandboxing

Godaemon provides two new nodes: the **ClientRoot** and the **ServerRoot**. The ServerRoot contains the entire view of the current multiplayer state, which is partially replicated to connected ClientRoots. Entire multiplayer connections are contained within these multiplayer subtrees, completely abstracting the setup of ENet connections. (In my experience, this decoupling of the "player host" from the "server logic" also makes multiplayer development less frustrating, especially in larger projects.)

With proper sandboxing, you can test multiple clients within a single process, implement a custom view for your server state, or run multiple connected backend Godot servers (such as special account or database servers, which your game server can connect to). **Note that the same Client and Server can access and modify the same static variable and autoload state -- use Services instead to implement high-level multiplayer functionality.**

![screen-shot](https://github.com/dog-on-moon/godot-godaemon-multiplayer/blob/main/readme/sandboxing.png)

![screen-shot](https://github.com/dog-on-moon/godot-godaemon-multiplayer/blob/main/readme/multitest.png)

### Server Authoritative

For increased network security, all client RPCs within Godaemon are processed through the server first. While this tradeoff puts more networking burden on the server, it also gives the developer the tools to properly monitor and block suspicious RPCs from clients, a necessity for large multiplayer games.

This setup also allows for a **scene visibility** pattern for development. The server has the complete view of the multiplayer scene tree, and can selectively make parts of it visible to connected clients. This pattern is remarkably consistent, stable, and simple, you never need to use MultiplayerSynchronizer or MultiplayerSpawner ever again.

```gdscript
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
				# which will replicate it and defined properties to all peers.
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
```

### Replication Editor

To fully replace the MultiplayerSynchronizer, a new Replication editor is present for all scenes. Scenes can be marked as a "Replicated Scene," which is required for the server to be able to replicate its scene view to clients. Any property in the scene can be set for replication, which will automatically replicate and synchronize those properties for clients. You can even tune the filtering on the property send/receive, allowing selective clients to be able to update or receive updates on set fields.

![screen-shot](https://github.com/dog-on-moon/godot-godaemon-multiplayer/blob/main/readme/replication.png)

### Replicated Node IDs

For increased security and performance, nodes do not RPC via shared NodePaths. Instead, nodes can only RPC if their stored node ID is equivalent between server and client processes. Node ID replication is automatically handled by the internal ReplicationService, so this is not something you will have to worry about very often. However, this ID repository is exposed for developers, allowing for an easy way to exchange node references through RPCs.

```gdscript
func request_node(node: Node):
    var node_id := Godaemon.repository(self).get_id(node)
    rpc_request_node.rpc(node_id)

@rpc("any_peer")
func rpc_request_node(node_id: int):
    var node := Godaemon.repository(self).get_node(node_id)
```

### Services

Services are similar to autoloads, except that they are created underneath a ClientRoot/ServerRoot and exist only for the duration of the ENet connection. They can used as singletons for implementing high-level multiplayer functionality, such as chat RPCs, voice chat, usernames, and more. The developer is expected to implement at least one service for setting up their game.

Godaemon comes with four "default services," which are optional and can be disabled:
1. **ReplicationService**, which implements replicated scene visibility on servers to clients.
2. **SyncService**, which replicates property changes on replicated scenes between servers and clients.
3. **PeerService**, a global "blackboard" of peer state which the server can write to.
4. **ZoneService**, a utility for creating replicated scenes under SubViewports, separating physics/navigation/visual worlds.

## Versus SceneMultiplayer

By default, Godot uses SceneMultiplayer for its multiplayer implementation. There are certain tradeoffs between using SceneMultiplayer and GodaemonMultiplayer for your project.

Advantages of SceneMultiplayer:
- Less networking overhead.
- Ideal for smaller lobby games, where **all peers share the same game view.**
- Easier to port existing Godot projects to multiplayer.

Advantages of GodaemonMultiplayer:
- More robust security, solving [vulnerabilities present in SceneMultiplayer](https://github.com/godotengine/godot/issues/96698).
- Server-sided visibility heavily streamlines multiplayer development, allowing you to focus on actual game development instead of network boilerplate.
- You can actually use it to make an MMO. (But I currently have performance concerns with its implementation in GDScript, a GDExtension reimplementation would be optimal.)

## Documentation

Currently, there is no in-depth documentation -- this addon is still evolving and I'm developing it alongside my own multiplayer projects. The Godot project comes with a couple of simple demos.

## Installation

This repository contains the plugin and some simple demos. Copy the contents of the `addons` folder into the `addons` folder in your own Godot project. Be sure to enable the plugin from Project Settings.

As of writing, this plugin depends on functionality introduced in Godot 4.4 dev3 (more specifically [this PR](https://github.com/godotengine/godot/pull/96024)).
