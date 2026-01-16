extends Node
func get_connected_clients() -> Array:
	# Zwraca listę client_id aktualnie połączonych klientów
	var ids = []
	for t in team_to_clients.keys():
		for client_id in team_to_clients[t]:
			ids.append(client_id)
	return ids


signal player_joined(client_id, team)
signal team_chosen(client_id, team)
signal player_buzzer(client_id)
signal player_answer(client_id, answer)
signal team_name_received(client_id, name)
signal cmd_start_round()
signal host_registered(room_code)

var current_address: String = "ws://188.68.247.138:8910"
var room_code: String = "???"
var ws := WebSocketPeer.new()
var connected := false
var client_to_team := {} # client_id: "A" lub "B"
var team_to_clients := { 0: [], 1: [] }
var client_to_player_id := {}
var players_data := {} # client_id: { "nickname": ..., "avatar": ... }

func _ready():
	print("NetworkManager is ready.")
	set_process(true)

func connect_to_relay(address: String = ""):
	var target_addr = address if address != "" else current_address
	print("[NetworkManager] Łączenie z adresem: ", target_addr)
	ws = WebSocketPeer.new()
	ws.inbound_buffer_size = 5000000 # 5 MB
	ws.outbound_buffer_size = 5000000 # 5 MB
	var err = ws.connect_to_url(target_addr)
	if err != OK:
		print("[NetworkManager] BŁĄD połączenia: ", err)
	connected = false

func _process(_delta):
	ws.poll()
	var state = ws.get_ready_state()
	if state == WebSocketPeer.STATE_OPEN and not connected:
		ws.put_packet(JSON.stringify({ "type": "register_host" }).to_utf8_buffer())
		connected = true
	elif state == WebSocketPeer.STATE_OPEN:
		while ws.get_available_packet_count() > 0:
			var pkt = ws.get_packet().get_string_from_utf8()
			var data = JSON.parse_string(pkt)
			if typeof(data) != TYPE_DICTIONARY:
				continue
			match data.get("type", ""):
				"host_registered":
					print("[NetworkManager] Zarejestrowano pokój: ", data.room)
					room_code = str(data.room)
					emit_signal("host_registered", data.room)
				"join_request":
					var client_id = data.clientId
					var team = int(data.player_info.team)
					# --- POPRAWKA ---
					# Jeśli player_id nie jest podane, parsujemy clientId jako int, usuwając prefiks "C"
					var player_id = 0
					if data.player_info.has("player_id"):
						player_id = data.player_info.player_id
					else:
						# "C123" -> 123
						var id_str = client_id.replace("C", "")
						player_id = id_str.to_int()

					# --- NORMALIZACJA DANYCH (KLUCZY) ---
					# Serwer wysyła "name" i "avatar_base64", my używamy "nickname" i "avatar"
					var p_info = data.player_info
					var normalized = {
						"nickname": p_info.get("name", "Gracz"),
						"avatar": p_info.get("avatar_base64", ""), # Serwer zmienia klucz na avatar_base64
						"team": team,
						"player_id": player_id
					}
					
					# Jeśli jakimś cudem serwer wysyła stare klucze, to zachowajmy kompatybilność:
					if normalized["nickname"] == "Gracz" and p_info.has("nickname"):
						normalized["nickname"] = p_info["nickname"]
					if normalized["avatar"] == "" and p_info.has("avatar"):
						normalized["avatar"] = p_info["avatar"]

					players_data[client_id] = normalized
					client_to_team[client_id] = team
					client_to_player_id[client_id] = player_id
					if not team_to_clients.has(team):
						team_to_clients[team] = []
					if not team_to_clients[team].has(client_id):
						team_to_clients[team].append(client_id)
					emit_signal("player_joined", client_id, team)
				"choose_team":
					var client_id = data.clientId
					var team = int(data.team)
					
					# Update internal state
					client_to_team[client_id] = team
					
					# Update team_to_clients mapping
					# Remove from all teams first to be safe
					for t in team_to_clients.keys():
						if team_to_clients[t].has(client_id):
							team_to_clients[t].erase(client_id)
					
					# Add to new team
					if not team_to_clients.has(team):
						team_to_clients[team] = []
					team_to_clients[team].append(client_id)
					
					# Update players_data entry if exists
					if players_data.has(client_id):
						players_data[client_id]["team"] = team
					
					emit_signal("team_chosen", client_id, team)
				"player_buzzer":
					emit_signal("player_buzzer", data.clientId)
				"player_answer":
					emit_signal("player_answer", data.clientId, data.answer)
				"team_name":
					emit_signal("team_name_received", data.clientId, data.name)
				"cmd_start_round":
					emit_signal("cmd_start_round")
				_: pass

func send_input_active(team_idx):
	team_idx = int(team_idx)
	for t in team_to_clients.keys():
		for client_id in team_to_clients[t]:
			var t_int = int(t)
			if t_int == team_idx:
				send_to_client(client_id, { "type": "input_active" })
			else:
				send_to_client(client_id, { "type": "input_inactive" })

func send_to_client(client_id: String, json_data: Dictionary):
	if ws.get_ready_state() == WebSocketPeer.STATE_OPEN:
		var pkt = { "targetId": client_id, "data": json_data }
		ws.put_packet(JSON.stringify(pkt).to_utf8_buffer())

func get_client_id(player_id: int) -> String:
	for cid in client_to_player_id.keys():
		if client_to_player_id[cid] == player_id:
			return cid
	return ""

func send_to_all(json_data: Dictionary):
	for cid in get_connected_clients():
		send_to_client(cid, json_data)
