extends Node

# --- SYGNAŁY ---
signal exit_requested
signal game_paused_players
signal game_resumed_players
signal host_message(text, duration) # Nowy sygnał dla GameUI

var is_paused_for_players = false

# --- ZMIENNE ---
var players: Dictionary = {}

# Podłączone moduły (dzieci w drzewie sceny)
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
var input_blocked_until_time = 0 # Timestamp do blokowania inputu podczas TTS

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
	if round_manager and question_manager:
		round_manager.q_manager = question_manager
		round_manager.t_manager = TeamManager
	else:
		printerr("[GameManager] BŁĄD: Brakuje węzłów-dzieci (QuestionManager, itp.)!")
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
	if not final_manager.is_connected("request_host_speak", _on_final_host_speak):
		final_manager.connect("request_host_speak", _on_final_host_speak)

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

	# Podłączenie sygnałów zarządzania graczami
	if not NetworkManager.is_connected("player_left", Callable(self, "_on_player_left")):
		NetworkManager.connect("player_left", Callable(self, "_on_player_left"))
	if not NetworkManager.is_connected("player_joined", Callable(self, "_on_player_joined")):
		NetworkManager.connect("player_joined", Callable(self, "_on_player_joined"))

	# --- SYNCHRONIZACJA Z NETWORK MANAGER ---
	# Ponieważ w Lobby gracze już dołączyli, musimy pobrać ich stan do TeamListenra
	print("[GameManager] Synchronizacja graczy z NetworkManager...")
	print("  Dostępne ID klientów: ", NetworkManager.client_to_player_id.keys())
	print("  Dostępne dane graczy: ", NetworkManager.players_data.keys())
	
	if NetworkManager.client_to_player_id.is_empty():
		print("[GameManager] UWAGA: Brak graczy w NetworkManager! Dodaję graczy testowych jeśli jesteśmy w edytorze.")
		# Opcjonalnie tutaj można wywołać setup_debug_game() jeśli testujemy bez serwera
	
	for cid in NetworkManager.client_to_player_id.keys():
		register_player_internal(cid)
	
	TeamManager.assign_captains()
	print("Stan TeamManager po synchronizacji:")
	print("  Team 0: ", TeamManager.teams[0])
	print("  Team 1: ", TeamManager.teams[1])

	# Automatyczny start gry po załadowaniu sceny
	print("[GameManager] Rozpoczynanie gry za 1 sekundę...")
	await get_tree().create_timer(1.0).timeout
	
	# INTRO SEKWENCJA
	SoundManager.play_sfx("intro")
	emit_signal("host_message", "Witamy w Familiadzie! Przed nami emocjonująca rozgrywka!", 4.0)
	tts_speak("Witamy w Familiadzie! Przed nami emocjonująca rozgrywka!", false)
	
	await get_tree().create_timer(5.0).timeout
	
	start_next_round()

func _on_room_code(code):
	print("KOD POKOJU (GameManager): ", code)

func setup_debug_game():
	print("--- TRYB DEBUG: Dodawanie wirtualnych graczy ---")
	players[1] = "Ania"
	players[2] = "Bartek"
	players[3] = "Celina"
	players[4] = "Darek"
	
	TeamManager.teams[0] = [1, 3] # Drużyna A
	TeamManager.teams[1] = [2, 4] # Drużyna B
	TeamManager.assign_captains()
	
	print("Gracze dodani. Wciśnij SPACJĘ (klikając w okno gry), aby rozpocząć.")

# --- GŁÓWNA PĘTLA ---

func start_next_round():
	# is_steal_phase = false # USUNIĘTE - zarządza tym RoundManager
	print("\n--- [GAME MANAGER] Rozpoczynanie nowej sekwencji ---")
	
	# 1. Sprawdź czy ktoś wchodzi do finału
	var finalist = TeamManager.check_for_finalist()
	
	if finalist != -1:
		print("!!! MAMY FINALISTĘ (Drużyna %d). Uruchamiam procedurę finałową..." % finalist)
		
		# Opóźnienie i celebracja przed finałem
		SoundManager.play_sfx("win")
		tts_speak("Koniec rund punktowanych! Mamy zwycięską drużynę. Zapraszam do finału!", false)
		
		await get_tree().create_timer(7.0).timeout
		
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
	
	# Delay reading question slightly to sync with UI (Slower pace)
	# User request: "cała rozgrywka jest zdesynchronizowana"
	# Instead of arbitrary timers, we will do a sequence here.
	
	# 1. Wait for Intro music/animation
	tts_speak("Runda " + str(round_counter) + ". Proszę o skupienie.", false)
	await get_tree().create_timer(4.0).timeout
	
	# 2. Read Question
	# Calculate reading time and wait
	var q_full_text = "Pytanie brzmi: " + q["question"]
	var read_time = clamp(q_full_text.length() / 10.0, 3.0, 10.0)
	
	if tts_manager:
		tts_manager.speak(q_full_text, false)
		# Specjalny przypadek: czytanie pytania pozwala na przerywanie (buzzer)
		# Więc NIE ustawiamy blokady inputu (allow_interrupt=true)
	
	# Usunięto dymki na prośbę użytkownika
	# await get_tree().create_timer(read_time).timeout
	# emit_signal("host_message", "Pytanie: " + q["question"], 8.0) 

	
	# (Wysyłanie ekranów buzzer jest teraz w RoundManager.start_round)

func register_player_internal(cid):
	var pid = NetworkManager.client_to_player_id[cid]
	var team_idx = NetworkManager.client_to_team.get(cid, -1)
	var p_info = NetworkManager.players_data.get(cid, {})
	var nick = p_info.get("nickname", "Gracz %d" % pid)
	
	print("  Rejestracja/Sync: ClientID=%s -> PlayerID=%d, Nick=%s, Team=%d" % [cid, pid, nick, team_idx])
	
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
		
	TeamManager.set_player_team(pid, team_idx)

func _on_player_joined(client_id, team):
	print(">>> [GRA] Gracz dołączył: ", client_id)
	register_player_internal(client_id)
	
	# Sprawdź czy możemy wznowić grę
	if is_paused_for_players:
		var count = NetworkManager.client_to_player_id.size()
		if count >= 2:
			print(">>> [GRA] Wznowienie gry! Graczy: ", count)
			is_paused_for_players = false
			emit_signal("game_resumed_players")
			tts_speak("Gra wznowiona!", false)

func _on_player_left(client_id):
	print(">>> [GRA] Gracz opuścił grę: ", client_id)
	
	# Sprawdź stan (NetworkManager już usunął wpis)
	var count = NetworkManager.client_to_player_id.size()
	print(">>> [GRA] Pozostało graczy: ", count)
	
	if current_state == GameState.ROUND_PLAY or current_state == GameState.FINAL:
		if count < 2:
			print("!!! ZA MAŁO GRACZY !!! Pauza.")
			if not is_paused_for_players:
				is_paused_for_players = true
				if tts_manager: tts_manager.stop()
				emit_signal("game_paused_players")
				tts_speak("Zbyt mało graczy. Gra wstrzymana.", false)


func start_finale(team_idx):
	current_state = GameState.FINAL
	print("WIELKI FINAŁ! Drużyna: " + str(team_idx))
	
	# Pobierz 5 pytań (jeśli brakuje unikalnych, dobierze użyte)
	var final_qs = question_manager.get_questions_exclude_used(5)
	final_manager.setup_final(final_qs)


# --- OBSŁUGA INPUTU ---

func process_player_input(player_id: int, text: String):
	# Blokada inputu jeśli TTS mówi (chyba że to czytanie pytania)
	if Time.get_ticks_msec() < input_blocked_until_time:
		print("IGNOROWANE (TTS MÓWI): Input gracza ", player_id)
		return

	# Sprawdzamy w jakiej drużynie jest gracz
	var team_idx = TeamManager.get_player_team_index(player_id)
	
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

	# Start drugiej części finału spacją
	if current_state == GameState.FINAL and event.keycode == KEY_SPACE:
		if final_manager.waiting_for_2nd_start:
			final_manager.start_second_part_manual()
			return

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
		# Bardziej rozbudowany komentarz końcowy
		var t_a = TeamManager.team_scores.get(0, 0)
		var t_b = TeamManager.team_scores.get(1, 0)
		var msg = "Koniec rundy! Aktualny wynik: Drużyna A %d, Drużyna B %d." % [t_a, t_b]
		tts_speak(msg, false)
		
	if new_state_name == "ROUND_END":
		print(">>> [RUNDA]: Koniec rundy! Wyniki zaktualizowane.")
		# Automatyczny start kolejnej sekwencji po dłuższym czasie (user request: za szybko)
		# Zwiększone do 12 sekund
		await get_tree().create_timer(12.0).timeout
		start_next_round()

func _perform_game_reset():
	# Zapisz listę klientów PRZED wyczyszczeniem struktur danych!
	var connected_clients = NetworkManager.get_connected_clients()

	# Resetuj stan graczy - usuń przypisania do drużyn w NetworkManager
	NetworkManager.client_to_team.clear()
	NetworkManager.team_to_clients = { 0: [], 1: [] }
	
	# Resetuj stan gry i drużyn
	TeamManager.reset_state()
	current_state = GameState.LOBBY
	round_counter = 0
	strikes = 0
	temp_score = 0
	
	# Resetuj klientów
	for cid in connected_clients:
		NetworkManager.send_to_client(cid, { "type": "join_accepted", "is_vip": false })

func _on_final_end(score, won):
	if won:
		SoundManager.play_sfx("win")
		tts_speak("Gratulacje! Wielka wygrana w finale!", false)
		print(">>> [KONIEC GRY]: WYGRANA! Zdobyto punkty w finale!")
	else:
		SoundManager.play_sfx("wrong") 
		tts_speak("Niestety, to za mało. Wynik: " + str(score), false)
		print(">>> [KONIEC GRY]: Przegrana. Wynik finału: " + str(score))

	# Wait for celebration/sounds then return to Lobby
	await get_tree().create_timer(10.0).timeout
	quit_to_lobby()

func _on_player_buzzer(player_id): # REMOVED _timestamp
	print("DEBUG: Otrzymano sygnał BUZZER od gracza: ", player_id)
	
	# Blokada inputu jeśli TTS mówi
	if Time.get_ticks_msec() < input_blocked_until_time:
		print("IGNOROWANE (TTS MÓWI): Buzzer gracza ", player_id)
		return
	
	SoundManager.play_sfx("reveal")
	
	# Stop TTS immediately on buzzer
	if tts_manager:
		tts_manager.stop()
		# Odblokuj input natychmiast po przerwaniu
		input_blocked_until_time = 0
		
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
	TeamManager.set_player_team(player_id, team_idx)
	
	# Powiadom innych graczy o zmianie drużyny (jeśli już są połączeni)
	for cid in NetworkManager.client_to_player_id.keys():
		if cid != client_id:
			NetworkManager.send_to_client(cid, { "type": "player_team_changed", "player_id": player_id, "team_idx": team_idx })
	
	print("Gracz %d dołączył do drużyny %d" % [player_id, team_idx])

# --- FUNKCJE DEBUGUJĄCE (WYPISYWANIE W KONSOLI) ---

func _on_debug_message(msg):
	# Nie czytamy wszystkiego, ale wybrane komunikaty tak
	print("\n>>> [GRA]: " + msg)

func _on_debug_timer(time_left, type = null):
	# Opcjonalne: wypisywanie czasu w konsoli (można wyłączyć, żeby nie spamować)
	# print("TIMER: " + str(type) + " " + str(time_left))
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
		tts_speak("Pojedynek! Zapraszam przedstawicieli drużyn do tablicy. Kto pierwszy ten lepszy.", false)
		
	elif "TRAFIENIE" in msg:
		var phrases = ["Czy jest to na tablicy?", "Sprawdźmy czy to dobra odpowiedź!", "Czy ankietowani tak powiedzieli?"]
		tts_speak(phrases.pick_random(), false)
		
	elif "PUDŁO" in msg:
		var phrases = ["Niestety nie.", "Brak tej odpowiedzi.", "Ankietowani milczą."]
		tts_speak(phrases.pick_random(), false)
		
	elif "SZANSA_DLA_PRZECIWNIKA" in msg:
		tts_speak("Szansa dla przeciwnika na przebicie!", false)
		
	elif "BŁĄD" in msg: # Strike
		var phrases = ["To pierwsza pomyłka.", "Druga pomyłka, uwaga!", "Trzecia wpadka! Przejęcie!"]
		# RoundManager can be more specific, but for now generic:
		tts_speak("To błędna odpowiedź.", false)
		
	elif "START_TEAM_PLAY_AUTO" in msg:
		tts_speak("Zatem gramy! Proszę o kolejne odpowiedzi.", false)
		
	elif "PRZEJĘCIE" in msg: # Steal phase
		tts_speak("Uwaga! Narada drużyny przeciwnej. Mają szansę na przejęcie punktów.", false)
		
	elif "DECYZJA" in msg:
		tts_speak("Wygrywacie pojedynek! Decydujcie: gramy czy oddajemy?", false)
		
	elif "ODDAJEMY" in msg:
		tts_speak("Oddajemy pytanie. Zobaczymy czy drużyna przeciwna sobie poradzi.", false)
		
	elif msg.begins_with("CZYTANIE_PONOWNE|"):
		var q_text = msg.split("|")[1]
		# Delay slightly to not overlap with PUDŁO sound/tts
		await get_tree().create_timer(1.5).timeout
		tts_speak("Przeczytam jeszcze raz: " + q_text, false)

func _on_tts_final_update(question_text, time, current_score):
	# Czytanie pytania finałowego? Może być spamowate przy odliczaniu.
	pass

func _on_final_host_speak(audio_text, visual_text = null):
	# Oblicz czas trwania (tylko do debugu)
	var duration = clamp(audio_text.length() / 10.0, 3.0, 10.0)
	
	# 1. Najpierw czytamy (TTS) - blokujemy input (false)
	tts_speak(audio_text, false, null, false)
	
	# Usunięto dymki na prośbę użytkownika

# Helper
func tts_speak(text, is_player, visual_override = null, allow_interrupt = false):
	if tts_manager:
		tts_manager.speak(text, is_player)
		
		# Jeśli to host i nie pozwalamy przerywać (allow_interrupt=false), blokujemy input
		if not is_player and not allow_interrupt:
			var char_rate = 12.0 # znaków na sekundę (szacunkowo)
			var duration_sec = clamp(text.length() / char_rate, 2.0, 10.0)
			# Dodajemy mały bufor 0.5s
			input_blocked_until_time = Time.get_ticks_msec() + int((duration_sec + 0.5) * 1000)
			print("TTS BLOCK START (%s): Duration %fs" % [text.left(20), duration_sec])
	
	# Usunięto automatyczne dymki prowadzącego na prośbę użytkownika
	pass

func _show_exit_confirmation():
	emit_signal("exit_requested")

func quit_to_lobby():
	print("ESC confirmed - resetting game session...")
	_perform_game_reset()
	# Return to Lobby scene
	get_tree().change_scene_to_file("res://Lobby.tscn")
