## Constants for replication. Yay

const META_SYNC_PROPERTIES := &"_mp_p"
const META_SYNC_PROPERTIES_SEND := &"_mp_s"
const META_SYNC_PROPERTIES_RECV := &"_mp_r"

enum PeerFilter {
	CLIENTS = 1,
	OWNER = 2,
	SERVER = 4
}

const PeerFilterBitfieldToName := {
	0: "Nobody",
	1: "All Clients",
	2: "Owner Only",
	4: "Server Only",
	6: "Owner + Server",
	5: "Everybody",
}

const DEFAULT_SEND_FILTER := 4
const DEFAULT_RECV_FILTER := 1

static func editor_filter_to_real_filter(editor: int) -> int:
	return PeerFilterBitfieldToName.keys()[editor]

static func real_filter_to_editor_filter(real: int) -> int:
	return PeerFilterBitfieldToName.keys().find(real)
