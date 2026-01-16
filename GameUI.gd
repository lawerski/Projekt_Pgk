extends Control

@onready var game_manager = get_node("/root/Main/GameManager")
@onready var round_manager = game_manager.get_node("RoundManager")
@onready var team_manager = game_manager.get_node("TeamManager")

# UI References via unique names or paths
@onready var question_label = $BottomInfo
@onready var answers_vbox = $BoardArea/BoardInner/VBox/AnswerContainer
@onready var score_a_label = $TeamStation_A/Desk/ScorePanel/Label
@onready var score_b_label = $TeamStation_B/Desk/ScorePanel/Label
@onready var name_a_label = $TeamStation_A/Desk/FrontPanel/NameLabel
@onready var name_b_label = $TeamStation_B/Desk/FrontPanel/NameLabel
@onready var round_score_label = $BoardArea/BoardInner/VBox/RoundScore/Score
@onready var team_a_name_label = $TeamStation_A/Desk/FrontPanel/NameLabel
@onready var team_b_name_label = $TeamStation_B/Desk/FrontPanel/NameLabel

@onready var avatars_a_container = $TeamStation_A/Avatars
@onready var avatars_b_container = $TeamStation_B/Avatars
@onready var faceoff_container = $CentralPodium/FaceOffContainer
@onready var host_spot = $HostSpot

@onready var strike_overlay = $StrikeOverlay
@onready var strike_label = $StrikeOverlay/Label
@onready var final_board = $FinalBoard

# Preload scenes
var answer_row_scene = preload("res://AnswerRow.tscn")

var player_stand_scene = preload("res://PlayerStand.tscn")

var host_jokes = [
	"Jak szybko przemieszcza się burza? – Błyskawicznie!",
	"Co mówi ksiądz po ślubie informatyka? – Pobieranie zakończone!",
	"Co robi chirurg w operze? – Operuje.",
	"Co ile miesięcy chemik jeździ na wakacje? – CO2.",
	"Na czym jeździ papier toaletowy? – Na rolkach.",
	"Jak nazywa się ryba szpiega? – Śledź.",
	"Jak nazywa się twarz matematyka? – Oblicze.",
	"Co robi Jezus na rondzie? – Nawraca.",
	"Jak się nazywa latający kot? – Kotlecik.",
	"Co mówi drwal, gdy za dużo wypije? – Ale się narąbałem.",
	"Co robi dziadek na dyskotece? – Tańczy z laską.",
	"Dlaczego długopisy nie chodzą do szkoły? – Bo się wypisały.",
	"Co robi detektyw podczas czytania książki? – Śledzi tekst.",
	"Czego szuka sprinter w samochodzie? – Biegu.",
	"Co robi skejter w toalecie? – Szaleje na desce.",
	"Co robi krowa na budowie? – Muuuruje.",
	"Co robi żołnierz na sprawdzianie? – Strzela.",
	"Co mówi podłoga po umyciu? – Napastowali mnie.",
	"Co robi mały kościotrup na plaży? – Bawi się łopatką.",
	"Co mówi nauczycielka geografii, gdy wybiera kolor butów? – Morze Czerwone.",
	"Jak nazywa się nieudany żart Arka? – SuchArek.",
	"Jak mnoży Jezus na matematyce? – Na krzyż.",
	"Jak piją wódkę konduktorzy? – Po kolei.",
	"Co robi blondynka w kominie? – Puszcza się z dymem.",
	"Jak żegna się szczur z drugim szczurem? – Paszczur.",
	"Co robi terrorysta na imprezie? – Porywa do tańca.",
	"Jaki jest najsłodszy pies na świecie? – Cukier Pudel.",
	"Co robi blondynka na dnie oceanu? – Czeka na walenie.",
	"Co mówi piłkarz, gdy przychodzi do fryzjera? – Gol.",
	"Gdzie konie wyprawiają bal? – Na balkonie.",
	"Czemu pogrzeby są takie smutne, a urodziny takie wesołe? – Na pogrzebach nie ma tortu.",
	"Dlaczego gmach sejmu jest okrągły? – Bo nikt jeszcze nie widział kwadratowego cyrku.",
	"Jaka jest ulubiona przeglądarka świń? – Google Chrum.",
	"Co robi sprzątaczka na scenie? – Wymiata.",
	"Dlaczego kulturysta chodzi z pudełkiem? – Żeby mógł pakować.",
	"Jak nazywamy działające radio? – Radioaktywne.",
	"Jakie jest ulubione ciasto owiec? – Makowiec.",
	"Jaka roślina boi się najbardziej? – Cykoria.",
	"Jak najłatwiej zabić strusia? – Przestraszyć go na betonie."
]

func _ready():
	print("GameUI Ready")
	
	_setup_host()

	# Connect Signals
	round_manager.connect("round_started", _on_round_started)
	round_manager.connect("answer_revealed", _on_answer_revealed)
	round_manager.connect("strike_occured", _on_strike)
	round_manager.connect("round_bank_updated", _on_bank_updated)
	round_manager.connect("decision_made", _on_decision_made)
	
	team_manager.connect("score_updated", _on_team_score_updated)
	if team_manager.has_signal("team_name_updated"):
		team_manager.connect("team_name_updated", _on_team_name_updated)
	
	# Connect Network listener for avatars
	NetworkManager.connect("player_joined", _on_player_joined)
	NetworkManager.connect("team_chosen", _on_team_updated)
	
	# Listen for player answers to show bubbles
	if not NetworkManager.is_connected("player_answer", Callable(self, "_on_player_answer_spoke")):
		NetworkManager.connect("player_answer", Callable(self, "_on_player_answer_spoke"))
	
	# Connect FinalManager updates
	var fm = game_manager.get_node("FinalManager")
	if fm:
		fm.connect("final_update", _on_final_update)
		fm.connect("final_finished", _on_final_finished)
		# NOTE: We must add this signal to FinalManager or just use final_update generically
		if fm.has_signal("final_state_update"):
			fm.connect("final_state_update", _on_final_state_update)
	
	# Initial population of avatars (for players who joined in Lobby)
	_update_avatars()

	# Initial team name update
	_update_team_labels()

func _update_team_labels():
	if team_manager:
		if team_a_name_label: team_a_name_label.text = team_manager.get_team_name(0)
		if team_b_name_label: team_b_name_label.text = team_manager.get_team_name(1)

func _on_team_name_updated(team_idx, new_name):
	print("GameUI: Team name updated: ", team_idx, " -> ", new_name)
	_update_team_labels()

func _setup_host():
	var host_stand = player_stand_scene.instantiate()
	host_spot.add_child(host_stand)
	# Use a default texture or load something specific
	host_stand.set_player_data("Prowadzący", preload("res://icon.svg")) 
	host_stand.client_id = -999 # Special ID for host
	
	# Say intro
	get_tree().create_timer(1.0).timeout.connect(func():
		_host_speak("Witam w Familiadzie! Zaczynamy grę!", 3.0)
	)

func _host_speak(text, duration: float = 4.0):
	if host_spot.get_child_count() > 0:
		var host = host_spot.get_child(0)
		if host.has_method("show_bubble"):
			host.show_bubble(text, duration)

func _on_round_started(question_data):
	print("UI: Round Started: ", question_data["question"])
	
	# 1. Reset Board UI immediately
	question_label.text = "..."
	round_score_label.text = "0"
	if strike_overlay:
		strike_overlay.visible = false
	
	# Clear old answers
	if answers_vbox:
		for child in answers_vbox.get_children():
			child.queue_free()
	
	# Create new blank rows immediately (so players see the slots)
	var answers_count = question_data["answers"].size()
	for i in range(answers_count):
		var row = answer_row_scene.instantiate()
		answers_vbox.add_child(row)
		row.set_index(i + 1)
	
	# Host joke
	if host_jokes.size() > 0:
		var joke = host_jokes.pick_random()
		# Joke lasts ~6-7s
		_host_speak(joke, 7.0)
	
	# Update positions for faceoff
	_update_stand_positions()
	
	# Wait for joke to finish (7s)
	await get_tree().create_timer(7.0).timeout
	
	# Host reads the question - INCREASED DURATION
	_host_speak("Pytanie: " + question_data["question"], 12.0)
	
	# Wait for reading (12s)
	await get_tree().create_timer(12.0).timeout
	
	# Show on board
	question_label.text = question_data["question"]
	_host_speak("Kto pierwszy ten lepszy!", 3.0) # To zniknie po 3s, ale Label zostanie

func _on_answer_revealed(answer_data):
	print("[GameUI] _on_answer_revealed received: ", answer_data)
	var text = answer_data["text"]
	var points = answer_data["points"]
	
	# Find which index this answers corresponds to in the original list
	# compare by reference if possible, or by text
	var q = round_manager.current_question
	var index = -1
	
	_host_speak(["Dobrze!", "Brawo!", "Jest na tablicy!", "Tak jest!"].pick_random())

	if q.has("answers"):
		for i in range(q["answers"].size()):
			# Try reference match first
			if q["answers"][i] == answer_data:
				index = i
				break
			# Fallback to text match
			if q["answers"][i]["text"] == text:
				index = i
				break
	
	print("[GameUI] Matched answer to index: ", index)
	
	if index != -1:
		var rows = answers_vbox.get_children()
		if index < rows.size():
			print("[GameUI] Revealing row ", index)
			rows[index].reveal(text, points)
		else:
			print("[GameUI] ERROR: Row index out of bounds! Rows: ", rows.size())
	else:
		print("[GameUI] ERROR: Could not find answer in current_question!")


func _on_bank_updated(amount):
	round_score_label.text = str(amount)

func _on_team_score_updated(team_idx, new_score):
	if team_idx == 0:
		score_a_label.text = str(new_score)
	else:
		score_b_label.text = str(new_score)

func _on_decision_made(team_name, decision):
	var msg = "Drużyna %s decyduje: %s!" % [team_name, decision]
	_host_speak(msg)
	
	# Wait a short moment then return players to desks
	await get_tree().create_timer(2.0).timeout
	_update_stand_positions()

func _on_strike(count):
	strike_label.text = "X".repeat(count)
	strike_overlay.visible = true
	
	_host_speak(["Niestety nie...", "Pudło!", "Nie ma takiej odpowiedzi."].pick_random())

	# Play sound here if AudioStreamPlayer available
	await get_tree().create_timer(1.5).timeout
	strike_overlay.visible = false

# --- Final Round Handlers ---

# --- Final Round Handlers ---

func _on_final_update(q_text, time_left, current_score):
	# Show final board if not visible
	if !final_board.visible:
		final_board.visible = true
		final_board.setup_rows(5)
	
	final_board.update_info(q_text, time_left, current_score)

func _on_final_state_update(results_data):
	final_board.update_rows_data(results_data)

func _on_final_finished(total, won):
	if won:
		final_board.show_message("WYGRANA! %d pkt" % total)
		final_board.score_label.add_theme_color_override("font_color", Color.GREEN)
	else:
		final_board.show_message("KONIEC! %d pkt" % total)

# --- Avatars Logic ---

func _on_player_joined(client_id, team):
	_update_avatars()

func _on_team_updated(client_id, team):
	_update_avatars()

func _update_avatars():
	# Clear existing
	for child in avatars_a_container.get_children(): child.queue_free()
	for child in avatars_b_container.get_children(): child.queue_free()
	
	# Rebuild from NetworkManager data
	var team0_ids = NetworkManager.team_to_clients.get(0, [])
	var team1_ids = NetworkManager.team_to_clients.get(1, [])
	
	print("[GameUI] Updating avatars. Team A: ", team0_ids.size(), " players. Team B: ", team1_ids.size(), " players.")
	
	# Team A (0)
	for cid in team0_ids:
		_create_player_stand(cid, avatars_a_container)
		
	# Team B (1)
	for cid in team1_ids:
		_create_player_stand(cid, avatars_b_container)
	
	# Reposition if round is active
	call_deferred("_update_stand_positions")

func _update_stand_positions():
	# Retrieve current faceoff players
	var p1 = round_manager.faceoff_p1
	var p2 = round_manager.faceoff_p2
	
	print("[GameUI] Updating positions. Faceoff: ", p1, " vs ", p2)
	
	# Iterate all stands we know of
	var all_stands = []
	for c in avatars_a_container.get_children(): all_stands.append(c)
	for c in avatars_b_container.get_children(): all_stands.append(c)
	for c in faceoff_container.get_children(): all_stands.append(c)
	
	for stand in all_stands:
		if not ("client_id" in stand): continue
		
		# Robust ID handling
		var stand_cid = stand.client_id
		var stand_pid = -1
		
		# Determine Player ID (int) from stand's client_id (String/Int)
		if typeof(stand_cid) == TYPE_STRING:
			stand_pid = int(NetworkManager.client_to_player_id.get(stand_cid, -1))
		elif typeof(stand_cid) == TYPE_INT or typeof(stand_cid) == TYPE_FLOAT:
			stand_pid = int(stand_cid)
			
		var p1_int = int(p1)
		var p2_int = int(p2)
		
		var target_parent = null
		
		# Check if this player is in faceoff (Compare PIDs)
		if stand_pid != -1 and (stand_pid == p1_int or stand_pid == p2_int):
			target_parent = faceoff_container
		else:
			# Not in faceoff - Check Team
			var team = -1
			if typeof(stand_cid) == TYPE_STRING:
				# Use client ID to look up team
				team = int(NetworkManager.client_to_team.get(stand_cid, -1))
			elif typeof(stand_cid) == TYPE_INT:
				# Maybe we can look up via player_id if needed, but client_id is preferred key
				pass
				
			if team == 0:
				target_parent = avatars_a_container
			elif team == 1:
				target_parent = avatars_b_container
		
		# If parent is different, reparent
		if target_parent and stand.get_parent() != target_parent:
			stand.reparent(target_parent)

func _create_player_stand(client_id, container):
	var data = NetworkManager.players_data.get(client_id, {})
	var nick = data.get("nickname", "Gracz")
	var avatar_b64 = data.get("avatar", "")
	
	var stand = player_stand_scene.instantiate()
	container.add_child(stand)
	stand.client_id = client_id
	
	var texture = null
	if avatar_b64 != "":
		texture = base64_to_texture(avatar_b64)
	
	stand.set_player_data(nick, texture)

func _on_player_answer_spoke(client_id, answer_text):
	# Find the stand and show bubble
	var stand = _find_stand_by_id(client_id)
	if stand:
		stand.show_bubble(answer_text)

func _find_stand_by_id(client_id) -> Node:
	for child in avatars_a_container.get_children():
		if "client_id" in child and child.client_id == client_id:
			return child
	for child in avatars_b_container.get_children():
		if "client_id" in child and child.client_id == client_id:
			return child
	for child in faceoff_container.get_children():
		if "client_id" in child and child.client_id == client_id:
			return child
	return null

# Helper to decode base64
func base64_to_texture(base64_string: String) -> ImageTexture:
	if "base64," in base64_string:
		var parts = base64_string.split("base64,")
		if parts.size() > 1:
			base64_string = parts[1]
	
	var image = Image.new()
	var err = image.load_png_from_buffer(Marshalls.base64_to_raw(base64_string))
	if err != OK: 
		# If loading failed, return null (GameUI or PlayerStand can handle defaults)
		return null
	return ImageTexture.create_from_image(image)
