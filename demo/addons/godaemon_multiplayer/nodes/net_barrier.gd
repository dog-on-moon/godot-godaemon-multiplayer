extends Node
class_name NetBarrier
## A NetBarrier is a networking node that requires a handshake from multiple connected
## peers before emitting a signal.

## Replicated signal. Emitted from the server once the barrier has been completed.
signal complete

@onready var mp := Godaemon.mp(self)

## Timeout duration for the server barrier.
## Once the server barrier ends, the complete signal will be emitted this many seconds
## later, if not all peers have responded yet.
@export_range(0.0, 10.0, 0.1, "or_greater") var timeout := 4.0

## All peers that have yet to respond. Only on the server.
var awaiting_peers: Array[int] = []

## Starts the net barrier on the server, awaiting a response from defined peers.
func start(_peers: Array[int] = []):
	if not mp.is_server():
		assert(false)
		return
	
	# Setup peer state.
	awaiting_peers = _peers.duplicate()

var _timeout_ival: Tween:
	set(x):
		if _timeout_ival:
			_timeout_ival.kill()
		_timeout_ival = x

## All clients must call this function for the complete signal to be emitted.
## When called on the server, the complete signal will emit [timeout] seconds later.
func end():
	if mp.is_client():
		_receive_end.rpc()
	else:
		_timeout_ival = create_tween()
		_timeout_ival.tween_interval(timeout)
		_timeout_ival.tween_callback(complete.emit)

@rpc func _receive_end():
	var had_peers := awaiting_peers.size() > 0
	awaiting_peers.erase(mp.remote_peer)
	var has_peers := awaiting_peers.size() > 0
	if had_peers and not has_peers:
		complete.emit()
		_timeout_ival = null
