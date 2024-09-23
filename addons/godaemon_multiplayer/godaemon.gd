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
