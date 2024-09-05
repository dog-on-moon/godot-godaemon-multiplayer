extends ServiceBase
class_name VisitationSetupService
## Sets up the Visitation demo.

const ZONE_SWAPPER = preload("res://demos/visitation/zone_swapper.tscn")
const VISITATION_ZONE = preload("res://demos/visitation/visitation_zone.tscn")

@onready var zone_service: ZoneService = mp.get_service(ZoneService)

func _ready() -> void:
	if mp.is_server():
		var swapper: Node = ZONE_SWAPPER.instantiate()
		var swapper_zone := zone_service.add_zone(swapper)
		
		for i in 3:
			var visitation: Node = VISITATION_ZONE.instantiate()
			var visitation_zone := zone_service.add_zone(visitation)
			swapper.server_zones.append(visitation_zone)
		
		mp.peer_connected.connect(
			func (peer: int):
				zone_service.add_interest(peer, swapper_zone)
		)
