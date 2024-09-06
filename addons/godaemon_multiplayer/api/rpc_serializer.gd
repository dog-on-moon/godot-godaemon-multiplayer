extends RefCounted
## Provides an interface for serializing RPCs.

var mp: MultiplayerRoot

func _init(_mp: MultiplayerRoot) -> void:
	mp = _mp

func cleanup():
	mp = null

func compress_rpc(from_peer: int, to_peer: int, node_path: NodePath, method_idx: int, args: Array) -> PackedByteArray:
	var data := PackedByteArray()
	var comp_data := [to_peer, node_path, method_idx]
	
	if mp.is_server():
		comp_data.insert(0, from_peer)
	if args:
		comp_data.append(args)
	
	return var_to_bytes(comp_data)

func decompress_rpc(data: PackedByteArray) -> Dictionary:
	var decomp_data: Array = bytes_to_var(data)
	
	var has_from_peer := mp.is_client()
	var has_args := (decomp_data.size() == 5) if has_from_peer else (decomp_data.size() == 4)
	
	return {
		'from_peer': decomp_data[0] if has_from_peer else mp.api.remote_sender,
		'to_peer': decomp_data[1 if has_from_peer else 0],
		'node_path': decomp_data[2 if has_from_peer else 1],
		'method_idx': decomp_data[3 if has_from_peer else 2],
		'args': decomp_data[4 if has_from_peer else 3] if has_args else [],
	}
