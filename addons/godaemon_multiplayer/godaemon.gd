extends Node
## An autoload which provides typed access to various services within the addon.

const Profiler = preload("res://addons/godaemon_multiplayer/api/profiler.gd")
const Repository = preload("res://addons/godaemon_multiplayer/api/repository.gd")
const RpcInterface = preload("res://addons/godaemon_multiplayer/api/rpc.gd")

## The MultiplayerRoot provides access to the connection state of its encapsulated multiplayer tree.
## It also creates all the service nodes within itself.
func mp(node: Node) -> MultiplayerRoot:
	return api(node).mp

## Services implement high-level multiplayer logic for different aspects of your game.
func service(node: Node, service: Script, required := true) -> ServiceBase:
	return mp(node).get_service(service, required)

## The GodaemonMultiplayerAPI establishes a server-authoritative wrapper over SceneMultiplayer.
func api(node: Node) -> GodaemonMultiplayerAPI:
	return node.multiplayer

## The API profiler allows configuring Godot's network profiler.
func profiler(node: Node) -> Profiler:
	return api(node).profiler

## The API repository provides unique IDs for nodes that are shared between all server/clients.
## This can be helpful for serializing node references across RPCs.
func repository(node: Node) -> Repository:
	return api(node).repository

## The API's RPC interface exposes useful RPC configuration, such as filters, channel overrides,
## ratelimiting, and disabling RPC forwarding.
func rpcs(node: Node) -> RpcInterface:
	return api(node).rpc

## The PeerService is a distributed blackboard which the server can use to replicate data to peers.
func peer_service(node: Node) -> PeerService:
	return service(node, PeerService)

## The ReplicationService manages replicated scenes.
## The server can configure scene visibility from the server to clients, along with
## assigning specific scenes "ownership" for a peer (not to be confused with node authority).
func replication_service(node: Node) -> ReplicationService:
	return service(node, ReplicationService)

## The SyncService implements property replication across services for existing replicated scenes.
func sync_service(node: Node) -> SyncService:
	return service(node, SyncService)

## The ZoneService implements a high-level interface on ReplicationService for creating "zones,"
## replicated scenes with separate physic spaces, navigation maps, and visual scenarios.
## Useful for building large, multiplayer overworlds, or for "faking" scene transitions for clients.
func zone_service(node: Node) -> ZoneService:
	return service(node, ZoneService)

## A Zone is a replicated scene created by the ZoneService.
func zone(node: Node) -> Zone:
	return zone_service(node).get_node_zone(node)

#region Custom services

## The UsernameService implements a quick access interface for assigning peers specific usernames.
## They are also supplied with a default username if not specified.
func username_service(node: Node) -> UsernameService:
	return service(node, UsernameService)

## The InventoryService keeps track of peer's inventories, allows peers to request for equipping
## items, storing them, etc., and distributes information related to inventory systems as necessary.
func inventory_service(node: Node) -> InventoryService:
	return service(node, InventoryService)

## Keeps track of player stats from levelling and distributes to other peers as necessary.
func stats_service(node: Node) -> StatsService:
	return service(node, StatsService)

## Generates the overworld and its corresponding regions and rooms.
func dungeon_service(node: Node) -> DungeonService:
	return service(node, DungeonService)

## Contains general use UI utils and instantiates the shared game interface.
func ui_service(node: Node) -> UIService:
	return service(node, UIService)

## Keeps track of player positions on the map and allows the overworld minimap to function.
func map_service(node: Node) -> MapService:
	return service(node, MapService)

## Tracks overworld battles, who's partaking in them, and cleans up battles when completed.
func battle_service(node: Node) -> BattleService:
	return service(node, BattleService)

## Instantiates peers with their player node as well as containg some other global use game utils.
func game_service(node: Node) -> GameService:
	return service(node, GameService)

#endregion
