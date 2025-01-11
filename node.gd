@tool
extends Node

signal freak
signal friday

func hello():
	pass

@rpc
func test(a: int, b: bool = false):
	pass

@rpc
func Moondoog():
	pass

func _process(delta: float) -> void:
	var s: Script = get_script()
	# print(s.get_rpc_config())
	#print(s.get_script_method_list())
