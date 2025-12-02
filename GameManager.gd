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
	
	# 3. Podłączenie sygnałów DEBUGOWYCH (To naprawia Twój błąd!)
	round_manager.connect("round_message", _on_debug_message)
	round_manager.connect("timer_start", _on_debug_timer)
	
	# Podłączenie sygnałów DEBUGOWYCH (Finał)
	final_manager.connect("final_update", _on_debug_final_update)
	final_manager.connect("play_sound", _on_debug_sound)
	
	# 4. Start setupu
	setup_debug_game()

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
	print("\n--- [GAME MANAGER] Rozpoczynanie nowej sekwencji ---")
	
	# 1. Sprawdź czy ktoś wchodzi do finału
	# UWAGA: Próg ustawiony nisko (10 pkt) do testów. W pełnej grze zmień na 300!
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
	if not event is InputEventKey or not event.pressed: return

	# START GRY
	if event.keycode == KEY_SPACE:
		start_next_round()
		return

	# INPUT DO TESTU
	var text_input = ""
	var player_id = 1 # Domyślnie Gracz 1
	
	match event.keycode:
		# Odpowiedzi A, B, C (dla uproszczonego JSONa)
		KEY_A: text_input = "A" 
		KEY_B: text_input = "B" 
		KEY_C: text_input = "C" 
		
		# Symulacja wygrania pojedynku (klawisz 1 -> odpowiedź A)
		KEY_1: 
			player_id = 1
			text_input = "A" 
		# Decyzja "Gramy"
		KEY_G: 
			player_id = 1
			text_input = "GRAMY"
		
		# Skip w finale
		KEY_S:
			text_input = "SKIP"

	if text_input != "":
		# print("DEBUG INPUT: Wysyłam '%s'" % text_input)
		process_player_input(player_id, text_input)

# --- FUNKCJE ODBIERAJĄCE SYGNAŁY (CALLBACKI) ---
# To ich brakowało i powodowały błąd!

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
