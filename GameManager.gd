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
		NetworkManager.connect_to_relay()
	
	# Podłączenie sygnałów sieciowych z NetworkManager
	if not NetworkManager.is_connected("player_buzzer", Callable(self, "_on_player_buzzer")):
		NetworkManager.connect("player_buzzer", Callable(self, "_on_player_buzzer"))
	if not NetworkManager.is_connected("player_answer", Callable(self, "_on_player_answer")):
		NetworkManager.connect("player_answer", Callable(self, "_on_player_answer"))
	
	# Podłączenie sygnału wyboru drużyny
	if not NetworkManager.is_connected("team_chosen", Callable(self, "_on_team_chosen")):
		NetworkManager.connect("team_chosen", Callable(self, "_on_team_chosen"))

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

	# START GRY / RUNDY
	if event.keycode == KEY_SPACE:
		start_next_round()
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

func _on_final_end(score, won):
	if won:
		print(">>> [KONIEC GRY]: WYGRANA! Zdobyto 200 pkt w finale!")
	else:
		print(">>> [KONIEC GRY]: Przegrana. Wynik finału: " + str(score))

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
 
