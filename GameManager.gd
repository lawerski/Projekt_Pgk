extends Node

# --- ZMIENNE ---
var players: Dictionary = {}

# Podłączone moduły (dzieci w drzewie sceny)
@onready var team_manager = $TeamManager
@onready var question_manager = $QuestionManager
@onready var round_manager = $RoundManager
@onready var final_manager = $FinalManager

enum GameState { LOBBY, ROUND_START, ROUND_PLAY, FINAL }
var current_state = GameState.LOBBY
var round_counter = 0

var current_question = {
	"text": "Więcej niż jedno zwierzę to...",
	"answers": { "STADO": 40, "ŁAWICA": 20, "WATAHA": 15 },
	"revealed": []
}
var current_team = "A"
var strikes = 0
var temp_score = 0

# --- ZMIENNE DO BUZZERA ---
var buzzer_winner_id = null
var buzzer_locked = false
var active_team = -1
var pot = 0
var revealed_answers = []
var is_steal_phase = false


func _ready():
	# 1. Konfiguracja referencji
	if round_manager and question_manager and team_manager:
		round_manager.q_manager = question_manager
		round_manager.t_manager = team_manager
	else:
		printerr("[GameManager] BŁĄD: Brakuje węzłów-dzieci (TeamManager, itp.)!")
		return

	# 2. Podłączenie sygnałów LOGICZNYCH
	round_manager.connect("state_change_requested", _on_round_state_change)
	final_manager.connect("final_finished", _on_final_end)

	# 3. Podłączenie sygnałów DEBUGOWYCH
	round_manager.connect("round_message", _on_debug_message)
	round_manager.connect("timer_start", _on_debug_timer)

	# Podłączenie sygnałów DEBUGOWYCH (Finał)
	final_manager.connect("final_update", _on_debug_final_update)
	final_manager.connect("play_sound", _on_debug_sound)

	# --- DODANE: Połączenie z serwerem i obsługa kodu pokoju ---
	if not NetworkManager.is_connected("host_registered", Callable(self, "_on_room_code")):
		NetworkManager.connect("host_registered", Callable(self, "_on_room_code"))
	
	if not NetworkManager.connected:
		NetworkManager.connect_to_relay()
	else:
		print("[GameManager] Już połączono. Pomijam connect_to_relay.")
	
	# Podłączenie sygnałów sieciowych z NetworkManager
	if not NetworkManager.is_connected("player_buzzer", Callable(self, "_on_player_buzzer")):
		NetworkManager.connect("player_buzzer", Callable(self, "_on_player_buzzer"))
	if not NetworkManager.is_connected("player_answer", Callable(self, "_on_player_answer")):
		NetworkManager.connect("player_answer", Callable(self, "_on_player_answer"))
	
	# Podłączenie sygnału wyboru drużyny
	if not NetworkManager.is_connected("team_chosen", Callable(self, "_on_team_chosen")):
		NetworkManager.connect("team_chosen", Callable(self, "_on_team_chosen"))

	# --- SYNCHRONIZACJA Z NETWORK MANAGER ---
	# Ponieważ w Lobby gracze już dołączyli, musimy pobrać ich stan do TeamListenra
	print("[GameManager] Synchronizacja graczy z NetworkManager...")
	print("  Dostępne ID klientów: ", NetworkManager.client_to_player_id.keys())
	print("  Dostępne dane graczy: ", NetworkManager.players_data.keys())
	
	if NetworkManager.client_to_player_id.is_empty():
		print("[GameManager] UWAGA: Brak graczy w NetworkManager! Dodaję graczy testowych jeśli jesteśmy w edytorze.")
		# Opcjonalnie tutaj można wywołać setup_debug_game() jeśli testujemy bez serwera
	
	for cid in NetworkManager.client_to_player_id.keys():
		var pid = NetworkManager.client_to_player_id[cid]
		var team_idx = NetworkManager.client_to_team.get(cid, -1)
		var p_info = NetworkManager.players_data.get(cid, {})
		var nick = p_info.get("nickname", "Gracz %d" % pid)
		
		print("  Synchronizacja: ClientID=%s -> PlayerID=%d, Nick=%s, Team=%d" % [cid, pid, nick, team_idx])
		
		# Rejestracja w lokalnym słowniku
		players[pid] = nick
		
		# Sprawdzamy i naprawiamy przypisanie do drużyny
		var needs_update = false
		var old_team = team_idx
		
		if team_idx == -1:
			team_idx = pid % 2 # Automatyczne przypisanie (0 lub 1)
			needs_update = true
			print("    -> Brak drużyny. Auto-przypisanie do: ", team_idx)
		
		# Upewnijmy się, że NetworkManager ma spójne dane
		if needs_update:
			NetworkManager.client_to_team[cid] = team_idx
			
			# Usuń ze starej listy (np. -1)
			if NetworkManager.team_to_clients.has(old_team):
				NetworkManager.team_to_clients[old_team].erase(cid)
				
			# Dodaj do nowej listy
			if not NetworkManager.team_to_clients.has(team_idx):
				NetworkManager.team_to_clients[team_idx] = []
			if not NetworkManager.team_to_clients[team_idx].has(cid):
				NetworkManager.team_to_clients[team_idx].append(cid)
			
			# Powiadom UI (jeśli już nasłuchuje)
			NetworkManager.emit_signal("team_chosen", cid, team_idx)
		
		# Jeszcze raz sprawdźmy czy jest w team_to_clients (dla pewności, nawet jak miał team)
		if NetworkManager.team_to_clients.has(team_idx) and not NetworkManager.team_to_clients[team_idx].has(cid):
			NetworkManager.team_to_clients[team_idx].append(cid)
			
		team_manager.set_player_team(pid, team_idx)
	
	team_manager.assign_captains()
	print("Stan TeamManager po synchronizacji:")
	print("  Team 0: ", team_manager.teams[0])
	print("  Team 1: ", team_manager.teams[1])

	# Automatyczny start gry po załadowaniu sceny
	print("[GameManager] Rozpoczynanie gry za 1 sekundę...")
	await get_tree().create_timer(1.0).timeout
	start_next_round()

func _on_room_code(code):
	print("KOD POKOJU (GameManager): ", code)

func setup_debug_game():
	print("--- TRYB DEBUG: Dodawanie wirtualnych graczy ---")
	players[1] = "Ania"
	players[2] = "Bartek"
	players[3] = "Celina"
	players[4] = "Darek"
	
	team_manager.teams[0] = [1, 3] # Drużyna A
	team_manager.teams[1] = [2, 4] # Drużyna B
	team_manager.assign_captains()
	
	print("Gracze dodani. Wciśnij SPACJĘ (klikając w okno gry), aby rozpocząć.")

# --- GŁÓWNA PĘTLA ---

func start_next_round():
	# is_steal_phase = false # USUNIĘTE - zarządza tym RoundManager
	print("\n--- [GAME MANAGER] Rozpoczynanie nowej sekwencji ---")
	
	# 1. Sprawdź czy ktoś wchodzi do finału
	var finalist = team_manager.check_for_finalist()
	
	if finalist != -1:
		print("!!! MAMY FINALISTĘ (Drużyna %d). Uruchamiam procedurę finałową..." % finalist)
		start_finale(finalist)
		return

	# 2. Jeśli nie ma finału, graj dalej
	print("DEBUG: Brak rozstrzygnięcia. Gramy kolejną rundę.")
	
	current_state = GameState.ROUND_START
	round_counter += 1
	
	var q = question_manager.get_random_question()
	if q.is_empty():
		print("BŁĄD KRYTYCZNY: Brak pytań do nowej rundy!")
		return
	
	current_state = GameState.ROUND_PLAY
	round_manager.start_round(q, round_counter - 1)
	
	print("PYTANIE: %s" % q["question"])
	
	# (Wysyłanie ekranów buzzer jest teraz w RoundManager.start_round)


func start_finale(team_idx):
	current_state = GameState.FINAL
	print("WIELKI FINAŁ! Drużyna: " + str(team_idx))
	
	# Pobierz 5 pytań (jeśli brakuje unikalnych, dobierze użyte)
	var final_qs = question_manager.get_questions_exclude_used(5)
	final_manager.setup_final(final_qs)


# --- OBSŁUGA INPUTU ---

func process_player_input(player_id: int, text: String):
	# Sprawdzamy w jakiej drużynie jest gracz
	var team_idx = team_manager.get_player_team_index(player_id)
	
	match current_state:
		GameState.ROUND_PLAY:
			round_manager.handle_input(player_id, text, team_idx)
			
		GameState.FINAL:
			# W finale przekazujemy input do final_manager
			if text == "SKIP":
				final_manager.handle_input("", true)
			else:
				final_manager.handle_input(text, false)

func _input(event):
	if not event is InputEventKey or not event.pressed:
		return

	# USUNIĘTO OBSŁUGĘ SPACJI DO STARTU RUNDY
	
	# Menu wyjścia (ESC)
	if event.keycode == KEY_ESCAPE:
		_show_exit_confirmation()
		return

	var text_input = ""
	var player_id = -1 # ID gracza, który "niby" nacisnął przycisk
	
	match event.keycode:
		# --- STANDARDOWE RUNDY (A, B, C) ---
		# Player 1: Q, A, Z
		KEY_Q: player_id = 1; text_input = "autokar"
		KEY_A: player_id = 1; text_input = "auto"
		KEY_Z: player_id = 1; text_input = "C"

		# Player 2: O, K, M
		KEY_O: player_id = 2; text_input = "auto"
		KEY_K: player_id = 2; text_input = "Bicykl"
		KEY_M: player_id = 2; text_input = "C"

		# --- DECYZJE ---
		# Player 1: D = GRAMY, F = ODDAJEMY
		KEY_D: player_id = 1; text_input = "GRAMY"
		KEY_F: player_id = 1; text_input = "ODDAJEMY"

		# Player 2: H = GRAMY, J = ODDAJEMY
		KEY_H: player_id = 2; text_input = "GRAMY"
		KEY_J: player_id = 2; text_input = "ODDAJEMY"

	if text_input != "":
		# print("DEBUG INPUT: Gracz %d wysyła '%s'" % [player_id, text_input])
		process_player_input(player_id, text_input)


# --- FUNKCJE ODBIERAJĄCE SYGNAŁY (CALLBACKI) ---

func _on_round_state_change(new_state_name):
	if new_state_name == "ROUND_END":
		print(">>> [RUNDA]: Koniec rundy! Wyniki zaktualizowane.")
		# Automatyczny start kolejnej sekwencji po 3 sekundach
		await get_tree().create_timer(3.0).timeout
		start_next_round()

func _perform_game_reset():
	# Zapisz listę klientów PRZED wyczyszczeniem struktur danych!
	var connected_clients = NetworkManager.get_connected_clients()

	# Resetuj stan graczy - usuń przypisania do drużyn w NetworkManager
	NetworkManager.client_to_team.clear()
	NetworkManager.team_to_clients = { 0: [], 1: [] }
	
	# Resetuj stan gry i drużyn
	team_manager.reset_state()
	current_state = GameState.LOBBY
	round_counter = 0
	strikes = 0
	temp_score = 0
	
	# Resetuj klientów
	for cid in connected_clients:
		NetworkManager.send_to_client(cid, { "type": "join_accepted", "is_vip": false })

func _on_final_end(score, won):
	if won:
		print(">>> [KONIEC GRY]: WYGRANA! Zdobyto 200 pkt w finale!")
	else:
		print(">>> [KONIEC GRY]: Przegrana. Wynik finału: " + str(score))
	
	# Automatyczny powrót do lobby
	print("[GAME] Powrót do Lobby za 10 sekund...")
	NetworkManager.send_to_all({"type": "set_screen", "screen": "end", "won": won, "score": score})
	await get_tree().create_timer(10.0).timeout
	
	_perform_game_reset()
	
	# Zmiana sceny DOPIERO PO WYSŁANIU KOMUNIKATÓW
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Lobby.tscn")
	
func _show_exit_confirmation():
	# Sprawdź czy dialog już istnieje
	if get_node_or_null("ExitDialog"):
		return
		
	var dialog = ConfirmationDialog.new()
	dialog.name = "ExitDialog"
	dialog.title = "Wyjście"
	dialog.dialog_text = "Czy na pewno chcesz wrócić do menu głównego?\nGra zostanie przerwana."
	dialog.get_ok_button().text = "Tak"
	dialog.get_cancel_button().text = "Anuluj"
	dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_PRIMARY_SCREEN
	
	add_child(dialog)
	dialog.confirmed.connect(_on_exit_confirmed)
	dialog.canceled.connect(func(): dialog.queue_free())
	dialog.popup()

func _on_exit_confirmed():
	# Usuń dialog
	if get_node_or_null("ExitDialog"):
		get_node("ExitDialog").queue_free()
		
	print(">>> [GAME] Wymuszone wyjście do lobby.")
	_perform_game_reset()
	await get_tree().create_timer(0.5).timeout
	get_tree().change_scene_to_file("res://Lobby.tscn")

# --- FUNKCJE DEBUGUJĄCE (WYPISYWANIE W KONSOLI) ---

func _on_debug_message(msg):
	print("\n>>> [GRA]: " + msg)

func _on_debug_timer(duration, type):
	print(">>> [ZEGAR]: Start odliczania (%s s) - %s" % [str(duration), type])

func _on_debug_final_update(question_text, time, current_score):
	# Wyświetla stan finału w konsoli (zamiast na ekranie)
	print(">>> [FINAŁ]: Pyt: '%s' | Czas: %.1f | Wynik: %d" % [question_text, time, current_score])

func _on_debug_sound(sound_name):
	if sound_name == "repeat":
		print("!!! [AUDIO]: DŹWIĘK BŁĘDU (BYŁO!) !!!")
	else:
		print(">>> [AUDIO]: " + sound_name)


# --- LOGIKA SIECIOWA ---

func _on_player_connected(client_id, player_info):
	var player_id = NetworkManager.client_to_player_id.get(client_id, -1)
	if player_id == -1:
		return
	players[player_id] = player_info.get("name", "Gracz " + str(player_id))

	# Nowa logika: wybór drużyny przez gracza
	var team_idx = -1
	if player_info.has("team") and str(player_info.team).is_valid_int():
		team_idx = int(player_info.team)
	
	# Jeśli team_idx to 0 lub 1, przypisz od razu. Jeśli -1, czekaj na wybór.
	if team_idx == 0 or team_idx == 1:
		team_manager.set_player_team(player_id, team_idx)
		team_manager.assign_captains()
		print("Dodano gracza %s (ID %d) do drużyny %s" % [players[player_id], player_id, "A" if team_idx==0 else "B"])
	else:
		print("Gracz %s (ID %d) dołączył do lobby (oczekiwanie na wybór drużyny)" % [players[player_id], player_id])

func _on_team_chosen(client_id, team_idx):
	var player_id = NetworkManager.client_to_player_id.get(client_id, -1)
	if player_id == -1:
		return

	# Ustaw drużynę gracza w menedżerze drużyn
	team_manager.set_player_team(player_id, team_idx)
	team_manager.assign_captains()

	var team_name = "Nieznana"
	if team_idx == 0:
		team_name = "A"
	elif team_idx == 1:
		team_name = "B"
 


# --- ODBIÓR BUZZERA ---
func _on_player_buzzer(client_id):
	var player_id = NetworkManager.client_to_player_id.get(client_id, -1)
	if player_id != -1:
		round_manager.handle_buzzer(player_id)


# --- ODBIÓR ODPOWIEDZI BUZZER I GRY DRUŻYNOWEJ ---
func _on_player_answer(client_id, answer):
	var player_id = NetworkManager.client_to_player_id.get(client_id, -1)
	if player_id == -1: return

	# Przekaż odpowiedź do managera rundy
	process_player_input(player_id, answer)
 
