#include <godot_cpp/core/class_db.hpp>

#include "steam_multiplayer_peer.h"

#include <godot_cpp/variant/utility_functions.hpp>

#define STEAM_BUFFER_SIZE 255

SteamMultiplayerPeer::SteamMultiplayerPeer() :
		callback_network_connection_status_changed(this, &SteamMultiplayerPeer::network_connection_status_changed) {
	configs = Ref<SteamPeerConfig>(memnew(SteamPeerConfig()));
}

SteamMultiplayerPeer::~SteamMultiplayerPeer() {
	// if (_is_active()) {
	// 	close();
	// }
	// memdelete(*config);
}

Error SteamMultiplayerPeer::_get_packet(const uint8_t **r_buffer, int32_t *r_buffer_size) {
	ERR_FAIL_COND_V_MSG(incoming_packets.size() == 0, ERR_UNAVAILABLE, "No incoming packets available.");

	//delete next_received_packet;
	next_received_packet = incoming_packets.front()->get();
	incoming_packets.pop_front();

	*r_buffer = (const uint8_t *)(&next_received_packet->data);
	*r_buffer_size = next_received_packet->size;

	return OK;
}

Error SteamMultiplayerPeer::_put_packet(const uint8_t *p_buffer, int32_t p_buffer_size) {
	ERR_FAIL_COND_V_MSG(!_is_active(), ERR_UNCONFIGURED, "The multiplayer instance isn't currently active.");
	ERR_FAIL_COND_V_MSG(connection_status != CONNECTION_CONNECTED, ERR_UNCONFIGURED, "The multiplayer instance isn't currently connected to any server or client.");
	ERR_FAIL_COND_V_MSG(target_peer != 0 && !peerId_to_steamId.has(ABS(target_peer)), ERR_INVALID_PARAMETER, vformat("Invalid target peer: %d", target_peer));
	ERR_FAIL_COND_V(active_mode == MODE_CLIENT && !peerId_to_steamId.has(1), ERR_BUG);
	int transferMode = _get_steam_transfer_flag();

	if (target_peer == 0) {
		Error returnValue = OK;
		for (HashMap<uint64_t, Ref<SteamConnection>>::Iterator E = connections_by_steamId64.begin(); E; ++E) {
			Ref<SteamPacketPeer> packet = Ref<SteamPacketPeer>(memnew(SteamPacketPeer(p_buffer, p_buffer_size, transferMode)));
			Error errorCode = E->value->send(packet);
			if (errorCode != OK) {
				returnValue = errorCode;
			}
		}
		return returnValue;
	} else {
		Ref<SteamPacketPeer> packet = Ref<SteamPacketPeer>(memnew(SteamPacketPeer(p_buffer, p_buffer_size, transferMode)));
		return get_connection_by_peer(target_peer)->send(packet);
	}
}

int32_t SteamMultiplayerPeer::_get_available_packet_count() const {
	int32_t size = incoming_packets.size();
	return size;
}

int32_t SteamMultiplayerPeer::_get_max_packet_size() const {
	return k_cbMaxSteamNetworkingSocketsMessageSizeSend;
}

int32_t SteamMultiplayerPeer::_get_packet_channel() const {
	return 0;
}

MultiplayerPeer::TransferMode SteamMultiplayerPeer::_get_packet_mode() const {
	ERR_FAIL_COND_V_MSG(!_is_active(), TRANSFER_MODE_RELIABLE, "The multiplayer instance isn't currently active.");
	ERR_FAIL_COND_V_MSG(incoming_packets.size() == 0, TRANSFER_MODE_RELIABLE, "No pending packets, cannot get transfer mode.");

	if (incoming_packets.front()->get()->transfer_mode & k_nSteamNetworkingSend_Reliable) {
		return TRANSFER_MODE_RELIABLE;
	} else {
		return TRANSFER_MODE_UNRELIABLE;
	}
}

void SteamMultiplayerPeer::_set_transfer_channel(int32_t p_channel) {
}

int32_t SteamMultiplayerPeer::_get_transfer_channel() const {
	return 0;
}

void SteamMultiplayerPeer::_set_transfer_mode(MultiplayerPeer::TransferMode p_mode) {
	transfer_mode = p_mode;
}

MultiplayerPeer::TransferMode SteamMultiplayerPeer::_get_transfer_mode() const {
	return transfer_mode;
}

void SteamMultiplayerPeer::_set_target_peer(int32_t p_peer) {
	target_peer = p_peer;
}

int32_t SteamMultiplayerPeer::_get_packet_peer() const {
	ERR_FAIL_COND_V_MSG(!_is_active(), 1, "The multiplayer instance isn't currently active.");
	ERR_FAIL_COND_V_MSG(incoming_packets.size() == 0, 1, "No packets to receive.");

	int32_t peer_id = connections_by_steamId64[incoming_packets.front()->get()->sender]->peer_id;
	return peer_id;
}

bool SteamMultiplayerPeer::_is_server() const {
	return unique_id == 1;
}

#define MAX_MESSAGE_COUNT 255
void SteamMultiplayerPeer::_poll() {
	ERR_FAIL_COND_MSG(!_is_active(), "The multiplayer instance isn't currently active.");

	SteamNetworkingMessage_t *messages[MAX_MESSAGE_COUNT];

	for (HashMap<uint64_t, Ref<SteamConnection>>::ConstIterator E = connections_by_steamId64.begin(); E; ++E) {
		int64_t key = E->key;
		Ref<SteamConnection> value = E->value;
		int count = SteamNetworkingSockets()->ReceiveMessagesOnConnection(value->steam_connection, messages, MAX_MESSAGE_COUNT);
		if (count > 0) {
			for (int i = 0; i < count; i++) {
				SteamNetworkingMessage_t *msg = messages[i];
				if (get_peer_id_from_steam64(msg->m_identityPeer.GetSteamID64()) != -1) {
					_process_message(msg);
				} else {
					_process_ping(msg);
				}
				msg->Release();
			}
		}
	}
}

void SteamMultiplayerPeer::_close() {
	if (!_is_active()) {
		return;
	}
	if (connection_status != CONNECTION_CONNECTED) {
		return;
	}

	for (HashMap<uint64_t, Ref<SteamConnection>>::ConstIterator E = connections_by_steamId64.begin(); E; ++E) {
		const Ref<SteamConnection> connection = E->value;
		// TODO On Enet disconnect all peers with
		// peer_disconnect_now(0);
		connection->close();
	}

	if (_is_server()) {
		close_listen_socket();
	}

	if (host_loopback_peer != nullptr) {
		host_loopback_peer->disconnect_peer(unique_id, true);
		host_loopback_peer = nullptr;
	}

	peerId_to_steamId.clear();
	connections_by_steamId64.clear();
	loopback_connections_by_steamId64.clear();
	active_mode = MODE_NONE;
	unique_id = 0;
	connection_status = CONNECTION_DISCONNECTED;
	is_loopback_client = false;
}

void SteamMultiplayerPeer::_disconnect_peer(int32_t p_peer, bool p_force) {
	ERR_FAIL_COND_MSG(!_is_active(), "The multiplayer instance isn't currently active.");
	ERR_FAIL_COND_MSG(!peerId_to_steamId.has(p_peer), "'PeerConnection' not registered for steam_id. Try p_force true if need clear all multiplayer data.");
	Ref<SteamConnection> connection = get_connection_by_peer(p_peer);
	bool result = connection->close();
	if (!result) {
		return;
	}

	connection->flush();
	connections_by_steamId64.erase(connection->steam_id);
	if (loopback_connections_by_steamId64.has(connection->steam_id)) {
		loopback_connections_by_steamId64.erase(connection->steam_id);
	}
	peerId_to_steamId.erase(p_peer);

	emit_signal("peer_disconnected", p_peer);

	if (p_force) {
		//peers.erase(p_peer);
		// if (hosts.has(p_peer)) {
		// 	hosts.erase(p_peer);
		// }
		if (active_mode == MODE_CLIENT) {
			connections_by_steamId64.clear(); // Avoid flushing again.
			loopback_connections_by_steamId64.clear();
			close();
		}
	}
}

int32_t SteamMultiplayerPeer::_get_unique_id() const {
	ERR_FAIL_COND_V_MSG(!_is_active(), 0, "The multiplayer instance isn't currently active.");
	return unique_id;
}

bool SteamMultiplayerPeer::_is_server_relay_supported() const {
	return active_mode == MODE_SERVER || active_mode == MODE_CLIENT;
}

MultiplayerPeer::ConnectionStatus SteamMultiplayerPeer::_get_connection_status() const {
	return connection_status;
}

bool SteamMultiplayerPeer::close_listen_socket() {
	if (SteamNetworkingSockets() == NULL) {
		WARN_PRINT(String("SteamNetworkingSockets is null!"));
		return false;
	}
	if (!SteamNetworkingSockets()->CloseListenSocket(listen_socket)) {
		WARN_PRINT(String("Fail to close listen socket "));
		return false;
	}
	return true;
}

Error SteamMultiplayerPeer::create_host(int n_local_virtual_port) {
	ERR_FAIL_COND_V_MSG(_is_active(), ERR_ALREADY_IN_USE, "The multiplayer instance is already active.");
	ERR_FAIL_COND_V_MSG((n_local_virtual_port <= 0), Error::ERR_CANT_OPEN, "Cannot use port <= 0");
	if (SteamNetworkingSockets() == NULL) {
		return Error::ERR_UNAVAILABLE;
	}
	SteamNetworkingUtils()->InitRelayNetworkAccess();

	const SteamNetworkingConfigValue_t *these_options = configs->get_convert_options();

	listen_socket = SteamNetworkingSockets()->CreateListenSocketP2P(n_local_virtual_port, configs->size(), these_options);

	delete[] these_options;

	if (listen_socket == k_HSteamListenSocket_Invalid) {
		return Error::ERR_CANT_CREATE;
	}
	unique_id = 1;
	active_mode = MODE_SERVER;
	connection_status = ConnectionStatus::CONNECTION_CONNECTED;
	virtual_port = n_local_virtual_port;
	WARN_PRINT("242 CREATED HOST");
	return Error::OK;
}

Error SteamMultiplayerPeer::create_client(uint64_t identity_remote, int n_remote_virtual_port) {
	ERR_FAIL_COND_V_MSG(_is_active(), ERR_ALREADY_IN_USE, "The multiplayer instance is already active.");
	ERR_FAIL_COND_V_MSG((n_remote_virtual_port <= 0), Error::ERR_CANT_OPEN, "Cannot use port <= 0");
	if (SteamNetworkingSockets() == NULL) {
		return Error::ERR_UNAVAILABLE;
	}
	unique_id = generate_unique_id();
	SteamNetworkingUtils()->InitRelayNetworkAccess();
	SteamNetworkingIdentity p_remote_id;
	p_remote_id.SetSteamID64(identity_remote);

	SteamNetworkingConfigValue_t *these_options = configs->get_convert_options();

	connection = SteamNetworkingSockets()->ConnectP2P(p_remote_id, n_remote_virtual_port, configs->size(), these_options);

	delete[] these_options;

	if (connection == k_HSteamNetConnection_Invalid) {
		unique_id = 0;
		return Error::ERR_CANT_CONNECT;
	}

	active_mode = MODE_CLIENT;
	connection_status = ConnectionStatus::CONNECTION_CONNECTING;
	virtual_port = n_remote_virtual_port;
	WARN_PRINT("268 CONNECTING CLIENT");
	return Error::OK;
}

Error SteamMultiplayerPeer::create_loopback_client(SteamMultiplayerPeer *host) {
	ERR_FAIL_COND_V_MSG(_is_active(), ERR_ALREADY_IN_USE, "The multiplayer instance is already active.");
	if (SteamNetworkingSockets() == NULL) {
		return Error::ERR_UNAVAILABLE;
	}
	SteamNetworkingUtils()->InitRelayNetworkAccess();

	host->loopback_idx += 1;
	CSteamID hostId(host->loopback_idx, k_EUniversePublic, k_EAccountTypeIndividual);
	CSteamID clientId(1, k_EUniversePublic, k_EAccountTypeIndividual);
	const uint64_t hostId64 = hostId.ConvertToUint64();
	const uint64_t clientId64 = clientId.ConvertToUint64();

	SteamNetworkingIdentity iHost, iClient;
	iHost.SetSteamID64(hostId64);
	iClient.SetSteamID64(clientId64);

	HSteamNetConnection hHost, hClient;
	if (!SteamNetworkingSockets()->CreateSocketPair(&hHost, &hClient, false, &iHost, &iClient)) {
		return Error::ERR_CANT_CONNECT;
	}

	connection = hClient;
	configs->apply_options(hClient);
	host->configs->apply_options(hHost);
	client_steam_connection = setup_loopback_connection(clientId64, hClient);
	host->setup_loopback_connection(hostId64, hHost);

	active_mode = MODE_CLIENT;
	connection_status = ConnectionStatus::CONNECTION_CONNECTED;
	unique_id = generate_unique_id();
	client_steam_connection->send_peer(unique_id);
	is_loopback_client = true;
	host_loopback_peer = host;
	return Error::OK;
}

bool SteamMultiplayerPeer::get_identity(SteamNetworkingIdentity *p_identity) {
	return SteamNetworkingSockets()->GetIdentity(p_identity);
}

void SteamMultiplayerPeer::_bind_methods() {
	ClassDB::bind_method(D_METHOD("create_host", "n_local_virtual_port"), &SteamMultiplayerPeer::create_host, DEFVAL(nullptr));
	ClassDB::bind_method(D_METHOD("create_client", "identity_remote", "n_local_virtual_port"), &SteamMultiplayerPeer::create_client, DEFVAL(nullptr));
	ClassDB::bind_method(D_METHOD("create_loopback_client", "host"), &SteamMultiplayerPeer::create_loopback_client, DEFVAL(nullptr));
	ClassDB::bind_method(D_METHOD("is_peer_loopback", "peer"), &SteamMultiplayerPeer::is_peer_loopback);
	ClassDB::bind_method(D_METHOD("set_listen_socket", "listen_socket"), &SteamMultiplayerPeer::set_listen_socket);
	ClassDB::bind_method(D_METHOD("get_listen_socket"), &SteamMultiplayerPeer::get_listen_socket);
	ClassDB::bind_method(D_METHOD("get_steam64_from_peer_id", "peer_id"), &SteamMultiplayerPeer::get_steam64_from_peer_id);
	ClassDB::bind_method(D_METHOD("get_peer_id_from_steam64", "steamid"), &SteamMultiplayerPeer::get_peer_id_from_steam64);
	ClassDB::bind_method(D_METHOD("set_no_nagle", "no_nagle"), &SteamMultiplayerPeer::set_no_nagle);
	ClassDB::bind_method(D_METHOD("get_no_nagle"), &SteamMultiplayerPeer::get_no_nagle);
	ClassDB::bind_method(D_METHOD("set_no_delay", "no_delay"), &SteamMultiplayerPeer::set_no_delay);
	ClassDB::bind_method(D_METHOD("get_no_delay"), &SteamMultiplayerPeer::get_no_delay);
	// ClassDB::bind_method(D_METHOD("set_as_relay", "as_relay"), &SteamMultiplayerPeer::set_as_relay);
	// ClassDB::bind_method(D_METHOD("get_as_relay"), &SteamMultiplayerPeer::get_as_relay);
	ClassDB::bind_method(D_METHOD("set_configs", "configs"), &SteamMultiplayerPeer::set_configs);
	ClassDB::bind_method(D_METHOD("get_configs"), &SteamMultiplayerPeer::get_configs);
	ClassDB::bind_method(D_METHOD("set_config", "config", "value"), &SteamMultiplayerPeer::set_config);
	ClassDB::bind_method(D_METHOD("clear_config", "config"), &SteamMultiplayerPeer::clear_config);
	ClassDB::bind_method(D_METHOD("clear_all_configs"), &SteamMultiplayerPeer::clear_all_configs);

	ADD_PROPERTY(PropertyInfo(Variant::INT, "listen_socket"), "set_listen_socket", "get_listen_socket");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "no_nagle"), "set_no_nagle", "get_no_nagle");
	ADD_PROPERTY(PropertyInfo(Variant::BOOL, "no_delay"), "set_no_delay", "get_no_delay");
	// ADD_PROPERTY(PropertyInfo(Variant::BOOL, "as_relay"), "set_as_relay", "get_as_relay");
	ADD_PROPERTY(PropertyInfo(Variant::OBJECT, "configs"), "set_configs", "get_configs");

	// NETWORKING SOCKETS SIGNALS ///////////////
	ADD_SIGNAL(MethodInfo("network_connection_status_changed", PropertyInfo(Variant::INT, "connect_handle"), PropertyInfo(Variant::DICTIONARY, "connection"), PropertyInfo(Variant::INT, "old_state")));
}

const int SteamMultiplayerPeer::_get_steam_transfer_flag() {
	MultiplayerPeer::TransferMode transfer_mode = get_transfer_mode();

	int32_t flags = (k_nSteamNetworkingSend_NoNagle * no_nagle) | (k_nSteamNetworkingSend_NoDelay * no_delay);

	switch (transfer_mode) {
		case TransferMode::TRANSFER_MODE_RELIABLE:
			return k_nSteamNetworkingSend_Reliable | flags;
			break;
		case TransferMode::TRANSFER_MODE_UNRELIABLE:
			return k_nSteamNetworkingSend_Unreliable | flags;
			break;
		case TransferMode::TRANSFER_MODE_UNRELIABLE_ORDERED:
			//Unreliable order not supported here!
			return k_nSteamNetworkingSend_Reliable | flags;
			break;
	}

	ERR_FAIL_V_MSG(-1, "Flags error. Switch fallthrough in _get_steam_transfer_flag");
}

// NETWORKING SOCKETS CALLBACKS /////////////////
//
//! This callback is posted whenever a connection is created, destroyed, or
//! changes state. The m_info field will contain a complete description of the
//! connection at the time the change occurred and the callback was posted. In
//! particular, m_info.m_eState will have the new connection state.
void SteamMultiplayerPeer::network_connection_status_changed(SteamNetConnectionStatusChangedCallback_t *call_data) {
	// Connection handle.
	//WARN_PRINT("----------");
	bool SERVER = _is_server();
	//if (SERVER) WARN_PRINT("(SERVER) CONNECTION CALLBACK START");
	//else WARN_PRINT("(CLIENT) CONNECTION CALLBACK START");
	SteamNetConnectionInfo_t connection_info = call_data->m_info;
	uint64_t connect_handle = call_data->m_hConn;
	uint64_t socket_handle = connection_info.m_hListenSocket;
	uint64_t steam_id = connection_info.m_identityRemote.GetSteamID().ConvertToUint64();

	//WARN_PRINT(String("-- internal --") + String(connection_info.m_szEndDebug));
	bool handled = false;

	if (is_loopback_client) {
		//WARN_PRINT("IGNORING REQUEST (CLIENT IS LOOPBACK)");
	}

	else if ((!SERVER) && (connect_handle != connection)) {
		//WARN_PRINT("IGNORING REQUEST (CONNECTION HANDLE MISMATCH)");
	}

	else if ((SERVER) && ((socket_handle != listen_socket) || (socket_handle == k_HSteamListenSocket_Invalid))) {
		//WARN_PRINT("IGNORING REQUEST (SOCKET INVALID OR MISMATCH)");
	}

	else if (connection_info.m_nUserData == 1) {
		//WARN_PRINT("IGNORING REQUEST (REQUEST ALREADY HANDLED)");
	}
	
	// A new connection has arrived on a listen socket.
	else if (connection_info.m_hListenSocket && call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_None && call_data->m_info.m_eState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connecting) {
		//WARN_PRINT("TYPE: CONNECTION ARRIVED ON LISTEN SOCKET");
		if (SERVER) {
			handled = true;
			EResult res = SteamNetworkingSockets()->AcceptConnection(connect_handle);
			if (res != k_EResultOK) {
				WARN_PRINT(String("FAILURE: ") + _convert_eresult_to_string(res));
				SteamNetworkingSockets()->CloseConnection(connect_handle, k_ESteamNetConnectionEnd_AppException_Generic, "Failed to accept connection", false);
			}
		}
	}

	// A connection we initiated has been accepted by the remote host.
	else if ((call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connecting || call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_FindingRoute) && call_data->m_info.m_eState == k_ESteamNetworkingConnectionState_Connected) {
		//WARN_PRINT("TYPE: CONNECTION ACCEPTED BY REMOTE");
		
		if (SERVER) {
			handled = true;
			add_connection(steam_id, call_data->m_hConn);
		} else if (connection_status != ConnectionStatus::CONNECTION_CONNECTED) {
			// BUG if we are trying to connect to two servers simultaneously,
			// this callback is global so it could route the wrong connections together
			handled = true;
			connection_status = ConnectionStatus::CONNECTION_CONNECTED;
			client_steam_connection = add_connection(steam_id, call_data->m_hConn);
			Error err = client_steam_connection->send_peer(unique_id);
			if (err != Error::OK) WARN_PRINT(String("ERROR WAS NOT OK"));
		}
	}

	// A connection has been actively rejected or closed by the remote host.
	else if ((call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connecting || call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connected) && call_data->m_info.m_eState == k_ESteamNetworkingConnectionState_ClosedByPeer) {
		//WARN_PRINT("TYPE: CONNECTION REJECTED/CLOSED BY REMOTE");

		if (!SERVER) {
			if (connection_status == CONNECTION_CONNECTED) {
				disconnect_peer(1, false);
				handled = true;
			}
			if (_is_active()) close();
		} else if (connections_by_steamId64.has(steam_id)) {
			Ref<SteamConnection> connection = connections_by_steamId64[steam_id];
			uint32_t peer_id = connection->peer_id;
			if (peer_id != -1) {
				disconnect_peer(1, true);
				handled = true;
			}
		}

		if (handled) {
			SteamNetworkingSockets()->CloseConnection(connect_handle, 0, nullptr, false);
		}
	}

	// Connection problem, appears to have been closed by the local host. Probably timeout.
	else if ((call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connecting || call_data->m_eOldState == ESteamNetworkingConnectionState::k_ESteamNetworkingConnectionState_Connected) && call_data->m_info.m_eState == k_ESteamNetworkingConnectionState_ProblemDetectedLocally) {
		//WARN_PRINT("TYPE: CONNECTION REJECTED/CLOSED BY LOCAL");

		if (!SERVER) {
			if (connection_status == CONNECTION_CONNECTED) {
				disconnect_peer(1, true);
				handled = true;
			}
			if (_is_active()) close();
		} else if (connections_by_steamId64.has(steam_id)) {
			Ref<SteamConnection> connection = connections_by_steamId64[steam_id];
			uint32_t peer_id = connection->peer_id;
			if (peer_id != -1) {
				disconnect_peer(peer_id, true);
				handled = true;
			}
		}

		if (handled) {
			SteamNetworkingSockets()->CloseConnection(connect_handle, 0, nullptr, false);
		}
	}

	// Unknown case
	else {
		//WARN_PRINT("TYPE: UNKNOWN, TRUTHFULLY WE PROBABLY DO NOT CARE?");
	}

	if (handled) {
		connection_info.m_nUserData = 1;
		//WARN_PRINT("HANDLED");
	} else {
		//WARN_PRINT("IGNORED");
	}
}

// GODOT MULTIPLAYER PEER UTILS  ///////////////////
Ref<SteamConnection> SteamMultiplayerPeer::get_connection_by_peer(int peer_id) {
	if (peerId_to_steamId.has(peer_id))
		return peerId_to_steamId[peer_id];

	return nullptr;
}

Ref<SteamConnection> SteamMultiplayerPeer::add_connection(const uint64_t steam_id, HSteamNetConnection connection) {
	ERR_FAIL_COND_V_MSG(steam_id == SteamUser()->GetSteamID().ConvertToUint64(), nullptr, "Cannot add self as a new peer.");

	Ref<SteamConnection> connection_data = Ref<SteamConnection>(memnew(SteamConnection(steam_id)));
	connection_data->steam_connection = connection;
	connections_by_steamId64[steam_id] = connection_data;
	return connection_data;
}

Ref<SteamConnection> SteamMultiplayerPeer::setup_loopback_connection(const uint64_t identity, HSteamNetConnection connection) {
	Ref<SteamConnection> connection_data = Ref<SteamConnection>(memnew(SteamConnection(identity)));
	connection_data->steam_connection = connection;
	connections_by_steamId64[identity] = connection_data;
	loopback_connections_by_steamId64[identity] = connection_data;
	return connection_data;
}

void SteamMultiplayerPeer::_process_message(const SteamNetworkingMessage_t *msg) {
	ERR_FAIL_COND_MSG(msg->GetSize() > MAX_STEAM_PACKET_SIZE, "Packet too large to send!");

	Ref<SteamPacketPeer> packet = Ref<SteamPacketPeer>(memnew(SteamPacketPeer));
	packet->sender = msg->m_identityPeer.GetSteamID64();
	packet->size = msg->GetSize();
	packet->transfer_mode = msg->m_nFlags;

	uint8_t *rawData = (uint8_t *)msg->GetData();
	memcpy(packet->data, rawData, packet->size);
	incoming_packets.push_back(packet);
}

void SteamMultiplayerPeer::_process_ping(const SteamNetworkingMessage_t *msg) {
	ERR_FAIL_COND_MSG(sizeof(SteamConnection::SetupPeerPayload) != msg->GetSize(), "Payload is the wrong size for a ping.");

	SteamConnection::SetupPeerPayload *receive = (SteamConnection::SetupPeerPayload *)msg->GetData();
	uint64_t steam_id = msg->m_identityPeer.GetSteamID64();

	Ref<SteamConnection> connection = connections_by_steamId64[steam_id];

	if (receive->peer_id != -1) {
		if (connection->peer_id == -1) {
			set_steam_id_peer(steam_id, receive->peer_id);
		}
		if (_is_server()) {
			Error err = connection->send_peer(unique_id);
			emit_signal("peer_connected", connection->peer_id);
		} else {
			emit_signal("peer_connected", connection->peer_id);
		}
	}
}

uint64_t SteamMultiplayerPeer::get_steam64_from_peer_id(const uint32_t peer_id) const {
	if (peer_id == this->unique_id) {
		return SteamUser()->GetSteamID().ConvertToUint64();
	} else if (peerId_to_steamId.has(peer_id)) {
		return peerId_to_steamId[peer_id]->steam_id;
	} else
		return -1;
}

uint32_t SteamMultiplayerPeer::get_peer_id_from_steam64(const uint64_t steamid) const {
	if (steamid == SteamUser()->GetSteamID().ConvertToUint64()) {
		return this->unique_id;
	} else if (connections_by_steamId64.has(steamid)) {
		return connections_by_steamId64[steamid]->peer_id;
	} else
		return -1;
}

void SteamMultiplayerPeer::set_steam_id_peer(uint64_t steam_id, int peer_id) {
	ERR_FAIL_COND_MSG(steam_id == SteamUser()->GetSteamID().ConvertToUint64(), "Cannot add self as a new peer.");
	ERR_FAIL_COND_MSG(connections_by_steamId64.has(steam_id) == false, "Steam ID missing");

	Ref<SteamConnection> con = connections_by_steamId64[steam_id];
	if (con->peer_id == -1) {
		con->peer_id = peer_id;
		peerId_to_steamId[peer_id] = con;
	} else if (con->peer_id == peer_id) {
		//peer already exists, so nothing happens
	} else {
		WARN_PRINT(String("Steam ID detected with wrong peer ID!"));
	}
}

void SteamMultiplayerPeer::set_listen_socket(const int listen_socket) {
	this->listen_socket = listen_socket;
}

int SteamMultiplayerPeer::get_listen_socket() const {
	return listen_socket;
}

Dictionary SteamMultiplayerPeer::get_peer_map() {
	Dictionary output;
	for (HashMap<uint64_t, Ref<SteamConnection>>::ConstIterator E = connections_by_steamId64.begin(); E; ++E) {
		output[E->value->peer_id] = E->value->steam_id;
	}
	return output;
}

bool SteamMultiplayerPeer::is_peer_loopback(int peer) {
	uint64_t steam_id = get_steam64_from_peer_id(peer);
	return loopback_connections_by_steamId64.has(steam_id);
}

void SteamMultiplayerPeer::set_no_nagle(const bool new_no_nagle) {
	no_nagle = new_no_nagle;
}

bool SteamMultiplayerPeer::get_no_nagle() const {
	return no_nagle;
}

void SteamMultiplayerPeer::set_no_delay(const bool new_no_delay) {
	no_delay = new_no_delay;
}

bool SteamMultiplayerPeer::get_no_delay() const {
	return no_delay;
}

// void SteamMultiplayerPeer::set_as_relay(const bool new_as_relay) {
// 	as_relay = new_as_relay;
// }

// bool SteamMultiplayerPeer::get_as_relay() const {
// 	return as_relay;
// }

void SteamMultiplayerPeer::set_configs(const Ref<SteamPeerConfig> new_config) {
	configs = new_config;
}

Ref<SteamPeerConfig> SteamMultiplayerPeer::get_configs() const {
	return configs;
}

void SteamMultiplayerPeer::set_config(const SteamPeerConfig::SteamNetworkingConfig config, Variant value) {
	configs->set_config(config, value);
}

void SteamMultiplayerPeer::clear_config(const SteamPeerConfig::SteamNetworkingConfig config) {
	configs->clear_config(config);
}

void SteamMultiplayerPeer::clear_all_configs() {
	configs->clear_all_configs();
}

// Long but simple: just return the type of the EResult as a Godot String
String SteamMultiplayerPeer::_convert_eresult_to_string(EResult e) {
	switch (e) {
		case k_EResultNone:
			return String("k_EResultNone");
		case k_EResultOK:
			return String("k_EResultOK");
		case k_EResultFail:
			return String("k_EResultFail");
		case k_EResultNoConnection:
			return String("k_EResultNoConnection");
		case k_EResultInvalidPassword:
			return String("k_EResultInvalidPassword");
		case k_EResultLoggedInElsewhere:
			return String("k_EResultLoggedInElsewhere");
		case k_EResultInvalidProtocolVer:
			return String("k_EResultInvalidProtocolVer");
		case k_EResultInvalidParam:
			return String("k_EResultInvalidParam");
		case k_EResultFileNotFound:
			return String("k_EResultFileNotFound");
		case k_EResultBusy:
			return String("k_EResultBusy");
		case k_EResultInvalidState:
			return String("k_EResultInvalidState");
		case k_EResultInvalidName:
			return String("k_EResultInvalidName");
		case k_EResultInvalidEmail:
			return String("k_EResultInvalidEmail");
		case k_EResultDuplicateName:
			return String("k_EResultDuplicateName");
		case k_EResultAccessDenied:
			return String("k_EResultAccessDenied");
		case k_EResultTimeout:
			return String("k_EResultTimeout");
		case k_EResultBanned:
			return String("k_EResultBanned");
		case k_EResultAccountNotFound:
			return String("k_EResultAccountNotFound");
		case k_EResultInvalidSteamID:
			return String("k_EResultInvalidSteamID");
		case k_EResultServiceUnavailable:
			return String("k_EResultServiceUnavailable");
		case k_EResultNotLoggedOn:
			return String("k_EResultNotLoggedOn");
		case k_EResultPending:
			return String("k_EResultPending");
		case k_EResultEncryptionFailure:
			return String("k_EResultEncryptionFailure");
		case k_EResultInsufficientPrivilege:
			return String("k_EResultInsufficientPrivilege");
		case k_EResultLimitExceeded:
			return String("k_EResultLimitExceeded");
		case k_EResultRevoked:
			return String("k_EResultRevoked");
		case k_EResultExpired:
			return String("k_EResultExpired");
		case k_EResultAlreadyRedeemed:
			return String("k_EResultAlreadyRedeemed");
		case k_EResultDuplicateRequest:
			return String("k_EResultDuplicateRequest");
		case k_EResultAlreadyOwned:
			return String("k_EResultAlreadyOwned");
		case k_EResultIPNotFound:
			return String("k_EResultIPNotFound");
		case k_EResultPersistFailed:
			return String("k_EResultPersistFailed");
		case k_EResultLockingFailed:
			return String("k_EResultLockingFailed");
		case k_EResultLogonSessionReplaced:
			return String("k_EResultLogonSessionReplaced");
		case k_EResultConnectFailed:
			return String("k_EResultConnectFailed");
		case k_EResultHandshakeFailed:
			return String("k_EResultHandshakeFailed");
		case k_EResultIOFailure:
			return String("k_EResultIOFailure");
		case k_EResultRemoteDisconnect:
			return String("k_EResultRemoteDisconnect");
		case k_EResultShoppingCartNotFound:
			return String("k_EResultShoppingCartNotFound");
		case k_EResultBlocked:
			return String("k_EResultBlocked");
		case k_EResultIgnored:
			return String("k_EResultIgnored");
		case k_EResultNoMatch:
			return String("k_EResultNoMatch");
		case k_EResultAccountDisabled:
			return String("k_EResultAccountDisabled");
		case k_EResultServiceReadOnly:
			return String("k_EResultServiceReadOnly");
		case k_EResultAccountNotFeatured:
			return String("k_EResultAccountNotFeatured");
		case k_EResultAdministratorOK:
			return String("k_EResultAdministratorOK");
		case k_EResultContentVersion:
			return String("k_EResultContentVersion");
		case k_EResultTryAnotherCM:
			return String("k_EResultTryAnotherCM");
		case k_EResultPasswordRequiredToKickSession:
			return String("k_EResultPasswordRequiredToKickSession");
		case k_EResultAlreadyLoggedInElsewhere:
			return String("k_EResultAlreadyLoggedInElsewhere");
		case k_EResultSuspended:
			return String("k_EResultSuspended");
		case k_EResultCancelled:
			return String("k_EResultCancelled");
		case k_EResultDataCorruption:
			return String("k_EResultDataCorruption");
		case k_EResultDiskFull:
			return String("k_EResultDiskFull");
		case k_EResultRemoteCallFailed:
			return String("k_EResultRemoteCallFailed");
		case k_EResultPasswordUnset:
			return String("k_EResultPasswordUnset");
		case k_EResultExternalAccountUnlinked:
			return String("k_EResultExternalAccountUnlinked");
		case k_EResultPSNTicketInvalid:
			return String("k_EResultPSNTicketInvalid");
		case k_EResultExternalAccountAlreadyLinked:
			return String("k_EResultExternalAccountAlreadyLinked");
		case k_EResultRemoteFileConflict:
			return String("k_EResultRemoteFileConflict");
		case k_EResultIllegalPassword:
			return String("k_EResultIllegalPassword");
		case k_EResultSameAsPreviousValue:
			return String("k_EResultSameAsPreviousValue");
		case k_EResultAccountLogonDenied:
			return String("k_EResultAccountLogonDenied");
		case k_EResultCannotUseOldPassword:
			return String("k_EResultCannotUseOldPassword");
		case k_EResultInvalidLoginAuthCode:
			return String("k_EResultInvalidLoginAuthCode");
		case k_EResultAccountLogonDeniedNoMail:
			return String("k_EResultAccountLogonDeniedNoMail");
		case k_EResultHardwareNotCapableOfIPT:
			return String("k_EResultHardwareNotCapableOfIPT");
		case k_EResultIPTInitError:
			return String("k_EResultIPTInitError");
		case k_EResultParentalControlRestricted:
			return String("k_EResultParentalControlRestricted");
		case k_EResultFacebookQueryError:
			return String("k_EResultFacebookQueryError");
		case k_EResultExpiredLoginAuthCode:
			return String("k_EResultExpiredLoginAuthCode");
		case k_EResultIPLoginRestrictionFailed:
			return String("k_EResultIPLoginRestrictionFailed");
		case k_EResultAccountLockedDown:
			return String("k_EResultAccountLockedDown");
		case k_EResultAccountLogonDeniedVerifiedEmailRequired:
			return String("k_EResultAccountLogonDeniedVerifiedEmailRequired");
		case k_EResultNoMatchingURL:
			return String("k_EResultNoMatchingURL");
		case k_EResultBadResponse:
			return String("k_EResultBadResponse");
		case k_EResultRequirePasswordReEntry:
			return String("k_EResultRequirePasswordReEntry");
		case k_EResultValueOutOfRange:
			return String("k_EResultValueOutOfRange");
		case k_EResultUnexpectedError:
			return String("k_EResultUnexpectedError");
		case k_EResultDisabled:
			return String("k_EResultDisabled");
		case k_EResultInvalidCEGSubmission:
			return String("k_EResultInvalidCEGSubmission");
		case k_EResultRestrictedDevice:
			return String("k_EResultRestrictedDevice");
		case k_EResultRegionLocked:
			return String("k_EResultRegionLocked");
		case k_EResultRateLimitExceeded:
			return String("k_EResultRateLimitExceeded");
		case k_EResultAccountLoginDeniedNeedTwoFactor:
			return String("k_EResultAccountLoginDeniedNeedTwoFactor");
		case k_EResultItemDeleted:
			return String("k_EResultItemDeleted");
		case k_EResultAccountLoginDeniedThrottle:
			return String("k_EResultAccountLoginDeniedThrottle");
		case k_EResultTwoFactorCodeMismatch:
			return String("k_EResultTwoFactorCodeMismatch");
		case k_EResultTwoFactorActivationCodeMismatch:
			return String("k_EResultTwoFactorActivationCodeMismatch");
		case k_EResultAccountAssociatedToMultiplePartners:
			return String("k_EResultAccountAssociatedToMultiplePartners");
		case k_EResultNotModified:
			return String("k_EResultNotModified");
		case k_EResultNoMobileDevice:
			return String("k_EResultNoMobileDevice");
		case k_EResultTimeNotSynced:
			return String("k_EResultTimeNotSynced");
		case k_EResultSmsCodeFailed:
			return String("k_EResultSmsCodeFailed");
		case k_EResultAccountLimitExceeded:
			return String("k_EResultAccountLimitExceeded");
		case k_EResultAccountActivityLimitExceeded:
			return String("k_EResultAccountActivityLimitExceeded");
		case k_EResultPhoneActivityLimitExceeded:
			return String("k_EResultPhoneActivityLimitExceeded");
		case k_EResultRefundToWallet:
			return String("k_EResultRefundToWallet");
		case k_EResultEmailSendFailure:
			return String("k_EResultEmailSendFailure");
		case k_EResultNotSettled:
			return String("k_EResultNotSettled");
		case k_EResultNeedCaptcha:
			return String("k_EResultNeedCaptcha");
		case k_EResultGSLTDenied:
			return String("k_EResultGSLTDenied");
		case k_EResultGSOwnerDenied:
			return String("k_EResultGSOwnerDenied");
		case k_EResultInvalidItemType:
			return String("k_EResultInvalidItemType");
		case k_EResultIPBanned:
			return String("k_EResultIPBanned");
		case k_EResultGSLTExpired:
			return String("k_EResultGSLTExpired");
		case k_EResultInsufficientFunds:
			return String("k_EResultInsufficientFunds");
		case k_EResultTooManyPending:
			return String("k_EResultTooManyPending");
		case k_EResultNoSiteLicensesFound:
			return String("k_EResultNoSiteLicensesFound");
		case k_EResultWGNetworkSendExceeded:
			return String("k_EResultWGNetworkSendExceeded");
		case k_EResultAccountNotFriends:
			return String("k_EResultAccountNotFriends");
		case k_EResultLimitedUserAccount:
			return String("k_EResultLimitedUserAccount");
		case k_EResultCantRemoveItem:
			return String("k_EResultCantRemoveItem");
		case k_EResultAccountDeleted:
			return String("k_EResultAccountDeleted");
		case k_EResultExistingUserCancelledLicense:
			return String("k_EResultExistingUserCancelledLicense");
		case k_EResultCommunityCooldown:
			return String("k_EResultCommunityCooldown");
		case k_EResultNoLauncherSpecified:
			return String("k_EResultNoLauncherSpecified");
		case k_EResultMustAgreeToSSA:
			return String("k_EResultMustAgreeToSSA");
		case k_EResultLauncherMigrated:
			return String("k_EResultLauncherMigrated");
		case k_EResultSteamRealmMismatch:
			return String("k_EResultSteamRealmMismatch");
		case k_EResultInvalidSignature:
			return String("k_EResultInvalidSignature");
		case k_EResultParseFailure:
			return String("k_EResultParseFailure");
		case k_EResultNoVerifiedPhone:
			return String("k_EResultNoVerifiedPhone");
		case k_EResultInsufficientBattery:
			return String("k_EResultInsufficientBattery");
		case k_EResultChargerRequired:
			return String("k_EResultChargerRequired");
		case k_EResultCachedCredentialInvalid:
			return String("k_EResultCachedCredentialInvalid");
		case K_EResultPhoneNumberIsVOIP:
			return String("K_EResultPhoneNumberIsVOIP");
	}
	return "Unmatched";
}
