extends RefCounted
class_name RateLimiter
## Can be used to ratelimit requests on specific peers.

var mp: MultiplayerRoot
var count: int = 5
var duration: float = 1.0

var ids: Dictionary[int, Array] = {}

func _init(_mp: MultiplayerRoot, _count: int, _duration: float) -> void:
	mp = _mp
	count = _count
	duration = _duration
	mp.peer_disconnected.connect(_on_peer_disconnected)

func _on_peer_disconnected(peer: int):
	ids.erase(peer)

## Checks if this peer's request in the RateLimiter was valid.
func check(peer: int = 0) -> bool:
	# Get the time array for this peer.
	var time_array: Array = ids.get_or_add(peer, [])
	var time := Time.get_ticks_msec() * 0.001
	
	# Clear out old requests.
	while time_array and (time_array[0] + duration) < time:
		time_array.pop_front()
	
	if time_array.size() < count:
		# There is room in the time array, success
		time_array.append(time)
		return true
	else:
		# No room in the time array. We are not Godoted.
		return false
