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
signal cmd_start_round()
signal host_registered(room_code)

var ws := WebSocketPeer.new()
var connected := false
var client_to_team := {} # client_id: "A" lub "B"
var team_to_clients := { 0: [], 1: [] }
var client_to_player_id := {}

func _ready():
	print("NetworkManager is ready.")
	set_process(true)

func connect_to_relay(address: String = "ws://188.68.247.138:8910"):
	print("[NetworkManager] Łączenie z adresem: ", address)
	ws = WebSocketPeer.new()
	var err = ws.connect_to_url(address)
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
					emit_signal("host_registered", data.room)
				"join_request":
					var client_id = data.clientId
					var team = int(data.player_info.team) # <-- ZAMIANA NA int
					var player_id = data.player_info.player_id if data.player_info.has("player_id") else client_id.to_int()
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
					emit_signal("team_chosen", client_id, team)
				"player_buzzer":
					emit_signal("player_buzzer", data.clientId)
				"player_answer":
					emit_signal("player_answer", data.clientId, data.answer)
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
