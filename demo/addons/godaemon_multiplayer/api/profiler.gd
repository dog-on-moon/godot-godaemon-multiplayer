extends RefCounted
## Provides profiler methods to the GodaemonMultiplayerAPI.

## The peer ID that the profiler is currently monitoring.
## When set to 0, the network profiler shows data from all peers.
var network_profiler_peer := 0

var api: GodaemonMultiplayerAPI

func _init(_api: GodaemonMultiplayerAPI):
	api = _api

func cleanup():
	api = null

## Profiles an RPC.
func rpc(inbound: bool, instance_id: int, size: int):
	if not OS.has_feature('debug'):
		return
	if network_profiler_peer != 0 and api.get_unique_id() != network_profiler_peer:
		return
	if EngineDebugger.is_profiling(&"multiplayer:rpc"):
		EngineDebugger.profiler_add_frame_data(&"multiplayer:rpc",
		["rpc_in" if inbound else "rpc_out", instance_id, size]
	)
