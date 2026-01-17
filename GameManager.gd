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

# TTS Manager Reference
@onready var tts_manager = null # Will load dynamically

func _ready():
	# --- DODANE TTS ---
	# Dynamicznie dodaj TTSManager jako dziecko
	var tts_script = load("res://TTSManager.gd")
	if tts_script:
		tts_manager = tts_script.new()
		add_child(tts_manager)
		print("TTSManager zainicjalizowany.")
	else:
		printerr("Nie znaleziono skryptu TTSManager.gd!")

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
	
	# Podłączenie TTS do round_message
	round_manager.connect("round_message", _on_tts_round_message)

	# Podłączenie sygnałów DEBUGOWYCH (Finał)
	final_manager.connect("final_update", _on_debug_final_update)
	final_manager.connect("play_sound", _on_debug_sound)
	
	# Podłączenie TTS do finału
	final_manager.connect("final_update", _on_tts_final_update)

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
	
	# Delay reading question slightly to sync with UI
	await get_tree().create_timer(1.0).timeout
	
	# Czytaj pytanie
	tts_speak("Pytanie: " + q["question"], false)
	
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
	# TTS dla zmiany stanu
	if new_state_name == "ROUND_END":
		tts_speak("Koniec rundy!", false)
		
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
		tts_speak("Gratulacje! Wygraliście 200 punktów!", false)
		print(">>> [KONIEC GRY]: WYGRANA! Zdobyto 200 pkt w finale!")
	else:
		tts_speak("Niestety, to za mało. Wynik: " + str(score), false)
		print(">>> [KONIEC GRY]: Przegrana. Wynik finału: " + str(score))

func _on_player_buzzer(player_id): # REMOVED _timestamp
	print("DEBUG: Otrzymano sygnał BUZZER od gracza: ", player_id)
	match current_state:
		GameState.ROUND_PLAY:
			round_manager.handle_buzzer(player_id)
		_:
			print("IGNOROWANE: Buzer wciśnięty w złym stanie gry: ", current_state)

func _on_player_answer(player_id, text): # REMOVED _timestamp
	print("DEBUG: Otrzymano odpowiedź '%s' od gracza: %d" % [text, player_id])
	process_player_input(player_id, text)

func _on_team_chosen(client_id, team_idx):
	# --- OBSŁUGA WYBORU DRUŻYNY ---
	print("DEBUG: Otrzymano wybór drużyny od klienta: %d, Drużyna: %d" % [client_id, team_idx])
	
	# Znajdź powiązane PlayerID
	var player_id = NetworkManager.client_to_player_id.get(client_id, -1)
	if player_id == -1:
		print("BŁĄD: Nie znaleziono powiązanego gracza dla ClientID: %d" % client_id)
		return
	
	# Zaktualizuj drużynę gracza w TeamManager
	team_manager.set_player_team(player_id, team_idx)
	
	# Powiadom innych graczy o zmianie drużyny (jeśli już są połączeni)
	for cid in NetworkManager.client_to_player_id.keys():
		if cid != client_id:
			NetworkManager.send_to_client(cid, { "type": "player_team_changed", "player_id": player_id, "team_idx": team_idx })
	
	print("Gracz %d dołączył do drużyny %d" % [player_id, team_idx])

# --- FUNKCJE DEBUGUJĄCE (WYPISYWANIE W KONSOLI) ---

func _on_debug_message(msg):
	# Nie czytamy wszystkiego, ale wybrane komunikaty tak
	print("\n>>> [GRA]: " + msg)

func _on_debug_timer(time_left):
	# Opcjonalne: wypisywanie czasu w konsoli (można wyłączyć, żeby nie spamować)
	# print("TIMER: " + str(time_left))
	pass

func _on_debug_final_update(q_text, time_left, score):
	# Debug finału
	pass

func _on_debug_sound(snd_name):
	print("[SOUND] Grałbym dźwięk: " + snd_name)

func _on_tts_round_message(msg):
	# Proste mapowanie ważnych komunikatów na mowę
	if msg.begins_with("Sędzia sprawdza odpowiedź:"):
		var ans = msg.split("'")[1]
		tts_speak("Odpowiedź: " + ans, true)
	elif msg.begins_with("POJEDYNEK!"):
		tts_speak("Pojedynek! Kto pierwszy ten lepszy.", false)
	elif "TRAFIENIE" in msg:
		tts_speak("Dobra odpowiedź!", false)
	elif "PUDŁO" in msg:
		tts_speak("To błędna odpowiedź.", false)
	elif "BŁĄD" in msg:
		tts_speak("Błąd!", false)
	elif "START_TEAM_PLAY_AUTO" in msg:
		tts_speak("Gramy!", false)
	elif "PRZEJĘCIE" in msg:
		tts_speak("Przejęcie! Drużyna przeciwna ma szansę.", false)
	elif "DECYZJA" in msg:
		tts_speak("Decyzja: Gramy czy oddajemy?", false)

func _on_tts_final_update(question_text, time, current_score):
	# Czytanie pytania finałowego? Może być spamowate przy odliczaniu.
	# Lepiej czytać tylko raz, gdy pytanie się zmieni.
	# Zostawmy to na razie proste.
	pass

# Helper
func tts_speak(text, is_player):
	if tts_manager:
		tts_manager.speak(text, is_player)

func _show_exit_confirmation():
	print("ESC pressed - resetting game session...")
	_perform_game_reset()
	# Change scene back to Lobby if we are not already there
	# Or reload the current scene to fully reset
	get_tree().change_scene_to_file("res://Main.tscn")
