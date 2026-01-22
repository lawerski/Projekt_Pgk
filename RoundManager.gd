extends Node

# --- SYGNAŁY ---
signal state_change_requested(new_state)
signal round_message(msg)
signal timer_start(duration, type)
signal round_started(question_data)
signal answer_revealed(answer_data)
signal strike_occured(count)
signal round_bank_updated(amount)
signal decision_made(team_name, decision)
signal player_answer_display(text)

enum RoundState { FACEOFF, DECISION, TEAM_PLAY, STEAL }
var current_substate = RoundState.FACEOFF

var playing_team: int = 0
var strikes: int = 0
var round_bank: int = 0
var faceoff_winner_id: int = -1 
var waiting_for_decision: bool = false 

# --- ZMIENNE DO LOGIKI PRZEBIJANIA W POJEDYNKU ---
var faceoff_pending_score: int = -1 	
var faceoff_pending_team_idx: int = -1 

# Zmienne do kontroli odpytywania w grze drużynowej
var current_member_index = 0 
var faceoff_active_player_id: int = -1
var current_round_index: int = 0
var faceoff_p1: int = -1
var faceoff_p2: int = -1
var buzzers_locked: bool = false

# Referencje
var q_manager = null 
var t_manager = null 
var current_question = {} 

# Inicjuje nową rundę, resetuje stan gry i przygotowuje do pojedynku
func start_round(question, round_idx):
	current_round_index = round_idx
	current_question = question
	round_bank = 0
	emit_signal("round_bank_updated", 0)
	strikes = 0
	current_substate = RoundState.FACEOFF
	waiting_for_decision = false
	buzzers_locked = true

	faceoff_pending_score = -1
	faceoff_pending_team_idx = -1
	faceoff_active_player_id = -1

	faceoff_p1 = t_manager.get_faceoff_player(0, round_idx)
	faceoff_p2 = t_manager.get_faceoff_player(1, round_idx)

	emit_signal("round_started", current_question)

	_log_info("POJEDYNEK! Do tablicy: %s (A) vs %s (B). Oczekiwanie na żart..." % [str(faceoff_p1), str(faceoff_p2)])
	
	# WYŚLIJ TREŚĆ PYTANIA DO WSZYSTKICH (w tle, by zaktualizować DOM klienta)
	var question_msg = {
		"type": "question",
		"text": question["question"]
	}
	for client_id in NetworkManager.get_connected_clients():
		NetworkManager.send_to_client(client_id, question_msg)
	
	# Initial Wait Screen
	for client_id in NetworkManager.get_connected_clients():
		NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "wait", "msg": "Prowadzący czyta pytanie..." })
	
	# Delay for Joke (Matches GameUI duration)
	# Increased to 9.0s to sync with "Slower gameplay"
	await get_tree().create_timer(9.0).timeout
	
	# Enable buzzers immediately
	buzzers_locked = false
	_log_info("Buzery aktywne (czytanie pytania)!")

	# Ustawienie ekranów: BUZZER tylko dla walczących, WAIT dla reszty (Pytanie jeszcze nie widoczne na telefonie)
	var p1_str = str(faceoff_p1)
	var p2_str = str(faceoff_p2)

	for client_id in NetworkManager.get_connected_clients():
		var pid = NetworkManager.client_to_player_id.get(client_id, -1)
		var pid_str = str(pid)
		
		# Robust int string compare just in case
		var is_p1 = (str(pid) == str(faceoff_p1))
		var is_p2 = (str(pid) == str(faceoff_p2))
		
		if is_p1 or is_p2:
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "buzzer" })
		else:
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "wait", "msg": "Pojedynek: Gracz %s vs Gracz %s" % [p1_str, p2_str] })

	# Delay for Question Reading (12s) - synchronizacja z GameUI
	# W tym czasie buzzery są już aktywne
	await get_tree().create_timer(12.0).timeout


# Obsługa wciśnięcia buzera (wywoływana z GameManager)
func handle_buzzer(player_id: int):
	print("RoundManager: handle_buzzer(%d) called. State=%s ActivePlayer=%d Locked=%s" % [player_id, str(current_substate), faceoff_active_player_id, str(buzzers_locked)])

	# Allow buzzer even if faceoff_active_player_id is NOT -1 in some edge cases?
	# But strictly speaking, it should only be accepted if NO ONE is currently answering.
	if current_substate != RoundState.FACEOFF:
		return
	
	if faceoff_active_player_id != -1:
		print("IGNOROWANE: Ktoś (%d) już wcisnął buzzer!" % faceoff_active_player_id)
		return
		
	if buzzers_locked:
		print("IGNOROWANE: Buzer wciśnięty przed czasem przez %d" % player_id)
		return

	# Walidacja - czy to właściwy gracz?
	if player_id != faceoff_p1 and player_id != faceoff_p2:
		return

	faceoff_active_player_id = player_id
	var team_idx = t_manager.get_player_team_index(player_id)
	
	_log_info("BUZER! Wcisnął gracz ID: %d (Drużyna %s)" % [player_id, _get_team_name(team_idx)])
	
	# Aktualizacja ekranów: Wygrywający ma Input, rywal wait, reszta dalej wait
	var winner_client_id = NetworkManager.get_client_id(player_id)
	if winner_client_id != "":
		NetworkManager.send_to_client(winner_client_id, { "type": "set_screen", "screen": "input" })
	
	for cid in NetworkManager.get_connected_clients():
		if cid != winner_client_id:
			var msg = "Przeciwnik zgłosił się pierwszy!"
			# Opcjonalnie inny komunikat dla obserwatorów
			NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": msg })


var is_processing_answer: bool = false # Blokada przed spamowaniem

# Główny router inputu, kieruje odpowiedź gracza do odpowiedniej podfunkcji w zależności od stanu rundy
func handle_input(player_id: int, text: String, team_idx: int):
	is_processing_answer = true # Temporarily block others while processing synchronous checks? 
	# Actually, better unlock later after async calls.
	
	if is_processing_answer:
		# WARNING: This logic might be too aggressive if 'is_processing_answer' gets stuck.
		# For now, let's remove this check or ensure it resets correctly in ALL code paths.
		# print("IGNOROWANE (BUSY): Input od %d: '%s' (Trwa sprawdzanie innej odpowiedzi)" % [player_id, text])
		# return
		pass 

	print("INPUT RECEIVED: PID=%d Team=%d Text='%s' State=%s Sub=%s" % [player_id, team_idx, text, "???", str(current_substate)])

	match current_substate:
		RoundState.FACEOFF:
			# Sprawdzenie, czy odpowiada osoba, która wygrała buzer (lub faceoff_winner po nietrafionej odpowiedzi)
			if faceoff_active_player_id != -1 and player_id != faceoff_active_player_id:
				if faceoff_winner_id != -1 and player_id == faceoff_winner_id:
					pass # To jest OK, kontynuacja (przebicie)
				else:
					print("IGNOROWANE: Input od gracza %d w fazie Faceoff (oczekiwany: %d)" % [player_id, faceoff_active_player_id])
					return

			_handle_faceoff_answer(player_id, text, team_idx)
			
		RoundState.DECISION:
			if player_id == faceoff_winner_id:
				_handle_decision(player_id, text)
			else:
				print("IGNOROWANE: Decyzja od %d, a oczekiwana od %d" % [player_id, faceoff_winner_id])
				
		RoundState.TEAM_PLAY:
			if team_idx == playing_team:
				_handle_team_play_answer(player_id, text, team_idx)
			else:
				print("IGNOROWANE: Odpowiada %s (TeamIdx %d), a tura należy do %s (TeamIdx %d)" % [_get_team_name(team_idx), team_idx, _get_team_name(playing_team), playing_team])
				
		RoundState.STEAL:
			if team_idx == playing_team:
				_process_steal_answer(text, team_idx)

# Obsługuje odpowiedź w fazie pojedynku (FACEOFF), sprawdzając czy jest to TOP odpowiedź lub czy ma czekać na przebicie
func _handle_faceoff_answer(player_id, text, team_idx):
	is_processing_answer = true
	if faceoff_pending_score != -1:
		await _handle_faceoff_rebuttal(player_id, text, team_idx)
		is_processing_answer = false
		return

	await _announce_answer_and_wait(text)
	emit_signal("round_message", "Sędzia sprawdza odpowiedź: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	is_processing_answer = false
	
	# Znajdź ID przeciwnika (konkretny rywal w tym pojedynku, a nie losowy)
	var opponent_id = -1
	if player_id == faceoff_p1:
		opponent_id = faceoff_p2
	elif player_id == faceoff_p2:
		opponent_id = faceoff_p1
	else:
		# Fallback gry awaryjnej (jeśli ID się nie zgadza)
		var opponent_team = 1 if team_idx == 0 else 0
		var opponent_members = t_manager.teams.get(opponent_team, [])
		if opponent_members.size() > 0:
			opponent_id = opponent_members[0]

	if result:
		var points = result["points"]
		round_bank += points
		emit_signal("round_bank_updated", round_bank)
		q_manager.reveal_answer(result)
		emit_signal("answer_revealed", result)
		
		var is_top = (current_question["answers"][0]["text"] == result["text"])
		
		if is_top:
			_log_info("[%s] TRAFIENIE! Top odpowiedź '%s' (+%d)!" % [_get_team_name(team_idx), result["text"], points])
			_win_faceoff(player_id, team_idx)
		else:
			faceoff_pending_score = points
			faceoff_pending_team_idx = team_idx
			faceoff_winner_id = -1 # Reset winner ID, as we are waiting for rebuttal
			
			_log_info("[%s] TRAFIENIE! '%s' (+%d). Ale to nie TOP..." % [_get_team_name(team_idx), result["text"], points])
			_log_info("Szansa dla przeciwnika na przebicie wyniku!")
			
			if opponent_id != -1:
				faceoff_active_player_id = opponent_id
				var pid_client = NetworkManager.get_client_id(player_id)
				var oid_client = NetworkManager.get_client_id(opponent_id)
				if pid_client != "": NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "wait", "msg": "Przeciwnik ma szansę na przebicie..." })
				if oid_client != "": NetworkManager.send_to_client(oid_client, { "type": "set_screen", "screen": "input" })
			else:
				# No opponent? Then original player wins immediately
				_win_faceoff(player_id, team_idx)

				
	else:
		_log_info("[%s] PUDŁO w pojedynku! Szansa dla przeciwnika." % _get_team_name(team_idx))
		
		# Czytaj pytanie ponownie dla przeciwnika (bo mogliśmy mu przerwać)
		# NOTE: This assumes GameUI or GameManager listens to 'round_message' or we trigger it explicitly via signal
		emit_signal("round_message", "CZYTANIE_PONOWNE|" + current_question["question"])
		
		faceoff_pending_score = 0
		faceoff_pending_team_idx = team_idx
		faceoff_winner_id = -1
		
		if opponent_id != -1:
			faceoff_active_player_id = opponent_id
			var pid_client = NetworkManager.get_client_id(player_id)
			var oid_client = NetworkManager.get_client_id(opponent_id)
			if pid_client != "": NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "wait", "msg": "Pudło! Przeciwnik ma szansę..." })
			if oid_client != "": NetworkManager.send_to_client(oid_client, { "type": "set_screen", "screen": "input" })

# Obsługuje próbę przebicia w pojedynku przez drugiego gracza, po tym jak pierwszy trafił, ale nie TOP
func _handle_faceoff_rebuttal(player_id, text, team_idx):
	if team_idx == faceoff_pending_team_idx:
		return 
		
	await _announce_answer_and_wait(text)
	emit_signal("round_message", "Sędzia sprawdza przebicie: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	
	if result:
		var points = result["points"]
		round_bank += points
		emit_signal("round_bank_updated", round_bank)
		q_manager.reveal_answer(result)
		emit_signal("answer_revealed", result)
		
		if points > faceoff_pending_score:
			_log_info("[%s] PRZEBICIE! '%s' (+%d) jest lepsze niż %d pkt!" % [_get_team_name(team_idx), result["text"], points, faceoff_pending_score])
			_win_faceoff(player_id, team_idx)
		else:
			_log_info("[%s] '%s' (+%d) to za mało, by przebić %d pkt." % [_get_team_name(team_idx), result["text"], points, faceoff_pending_score])
			# The original player (who set pending score) wins
			
			# Find original player from pending team idx
			var winner_id = faceoff_p1 if faceoff_pending_team_idx == 0 else faceoff_p2
			_win_faceoff(winner_id, faceoff_pending_team_idx)
	else:
		_log_info("[%s] PUDŁO! Wygrywa zespół, który trafił cokolwiek." % _get_team_name(team_idx))
		# The original player wins because rebutter missed
		var winner_id = faceoff_p1 if faceoff_pending_team_idx == 0 else faceoff_p2
		_win_faceoff(winner_id, faceoff_pending_team_idx)


# Kończy pojedynek, ustawia zwycięzcę i przechodzi do fazy DECISION (decyzji o grze)
func _win_faceoff(winner_player_id, winner_team_idx):
	faceoff_winner_id = winner_player_id
	playing_team = winner_team_idx
	
	if q_manager.are_all_revealed_in_question(current_question):
		_log_info("Pojedynek wyczyścił tablicę! Koniec rundy.")
		_finish_round(winner_team_idx)
		return

	waiting_for_decision = true
	current_substate = RoundState.DECISION
	_log_info("[%s] WYGRANY POJEDYNEK! Decyzja (Gracz %d): [G]RAMY czy [O]DDAJEMY?" % [_get_team_name(winner_team_idx), winner_player_id])
	
	var winner_client_id = NetworkManager.get_client_id(winner_player_id)
	if winner_client_id != "":
		NetworkManager.send_to_client(winner_client_id, { "type": "set_screen", "screen": "decision" })
	
	for cid in NetworkManager.get_connected_clients():
		if cid != winner_client_id:
			NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "Przeciwnik podejmuje decyzję..." })

# Obsługuje komendę gracza zwycięskiego w pojedynku (GRAMY lub ODDAJEMY)
func _handle_decision(player_id: int, text: String):
	var command = text.to_upper()
	if command == "GRAMY" or command == "PLAY" or command == "G":
		current_substate = RoundState.TEAM_PLAY
		var team_name = _get_team_name(playing_team)
		_log_info("[%s] Decyzja: GRAMY! Tablica należy do nas." % team_name)
		emit_signal("decision_made", team_name, "GRAJĄ")
		_start_team_play_phase()
	elif command == "ODDAJEMY" or command == "PASS" or command == "O":
		playing_team = 1 if playing_team == 0 else 0
		current_substate = RoundState.TEAM_PLAY
		var team_name = _get_team_name(1 if playing_team==0 else 0) # Team that got passed to (wait, playing_team is already flipped here? Yes)
		# Wait, playing_team is flipped in line above. So playing_team is now the team that IS playing.
		# Original logic: playing_team = 1 if playing_team == 0 else 0
		# So playing_team is the NEW playing team.
		var passing_team_name = _get_team_name(1 if playing_team==0 else 0) # The one who passed
		
		_log_info("[%s] Decyzja: ODDAJEMY! Tablica dla przeciwników (%s)." % [passing_team_name, _get_team_name(playing_team)])
		emit_signal("decision_made", passing_team_name, "ODDAJĄ")
		_start_team_play_phase()


# --- LOGIKA GRY DRUŻYNOWEJ (TEAM PLAY) ---

func _start_team_play_phase():
	current_substate = RoundState.TEAM_PLAY
	
	# Reset faceoff players to send them back to desks (logic handled by UI polling these vars)
	faceoff_p1 = -1
	faceoff_p2 = -1
	
	# LOGIKA ROTACJI:
	# Jeśli gra 1 osoba w drużynie, zawsze ona odpowiada.
	# Jeśli > 1, kolejkujemy (indeks rośnie).
	
	# Startujemy od gracza następnego po tym, który brał udział w pojedynku (round_index)
	# Dzięki modulo w _update_input... obsłuży to zarówno 1 gracza (zawsze index 0) jak i wielu (rotacja).
	current_member_index = current_round_index + 1
	
	_log_info("Start rundy drużynowej. Drużyna %s, index startowy: %d" % [_get_team_name(playing_team), current_member_index])
	_update_input_for_active_team_member()


func _update_input_for_active_team_member():
	var team_members = t_manager.teams.get(playing_team, [])
	if team_members.is_empty(): 
		print("BŁĄD: Pusta drużyna w _update_input_for_active_team_member!")
		return
	
	# Zapewnienie pętli (modulo)
	# Dla 1 gracza: x % 1 = 0 (zawsze ten sam)
	# Dla N graczy: x % N = 0..N-1 (obieg)
	current_member_index = current_member_index % team_members.size()
	
	var active_player_id = team_members[current_member_index]
	var active_client_id = NetworkManager.get_client_id(active_player_id)
	
	_log_info("Tura gracza: %d (Client: %s)" % [active_player_id, active_client_id])
	
	# 1. Wyślij INPUT do aktywnego gracza
	if active_client_id != "":
		# ZAWSZE wysyłamy komendę wejścia (Input), nawet jeśli gracz już ją ma.
		# W backendzie JS resetujemy pole tekstowe po wysłaniu, więc gracz czeka na ponowne 'input' tylko jeśli zmienił się stan,
		# ALE tutaj logika jest taka: on jest na ekranie 'game-answer-input'.
		# Jeśli nic nie zrobimy, pozostanie na tym ekranie. 
		# Jeśli wyślemy mu "wait", a potem znów "input", to ekran mignie.
		
		# Żeby obsłużyć 'zapętlenie' (ta sama osoba odpowiada z rzędu), musimy dać znać frontendowi.
		# Ale frontend i tak czyści input po wysłaniu. Więc jest gotowy do pisania.
		
		# PROBLEM: Jeśli frontend przełączył się na 'wait' (bo np. dostał wait od steal lub innego eventu?), to trzeba przywrócić.
		# Tu wysyłamy input_active.
		NetworkManager.send_to_client(active_client_id, { "type": "set_screen", "screen": "input" })
		
		# Dodatkowy debug
		print("  -> Wysyłam INPUT do klienta: %s (Gracz %d)" % [active_client_id, active_player_id])
	else:
		print("BŁĄD: Nie znaleziono clientId dla aktywnego gracza %d!" % active_player_id)
	
	# 2. Wyślij WAIT do reszty
	for client_id in NetworkManager.get_connected_clients():
		if client_id != active_client_id:
			var pid = NetworkManager.client_to_player_id.get(client_id, -1)
			var team_idx = t_manager.get_player_team_index(pid)
			
			var msg = ""
			if team_idx == playing_team:
				# Kolega z drużyny (widać tylko gdy graczy > 1)
				msg = "Twój kolega odpowiada..."
			else:
				# Przeciwnik
				msg = "Druga drużyna odpowiada..."
				
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "wait", "msg": msg })



func _handle_team_play_answer(player_id, text, team_idx):
	is_processing_answer = true
	# Sprawdzenie czy odpowiada właściwy gracz z kolejki
	var team_members = t_manager.teams.get(playing_team, [])
	var expected_id = team_members[current_member_index]
	
	if player_id != expected_id:
		print("IGNOROWANE: Odpowiada %d, a kolejka gracza %d (Index: %d)" % [player_id, expected_id, current_member_index])
		is_processing_answer = false
		return

	await _announce_answer_and_wait(text)
	emit_signal("round_message", "Sędzia sprawdza: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	is_processing_answer = false
	
	if result:
		# Trafienie, ale sprawdź czy już nie było
		if result["text"] in q_manager.get_revealed_answers(current_question):
			_log_info("Ta odpowiedź już padła!")
			# Nie zmieniaj gracza, niech próbuje innej? Albo uznaj za błąd?
			# W Familiadzie powtórzenie to zazwyczaj strata lub prośba o inną. 
			# Tu uznajemy za stratę kolejki lub prosimy o inną.
			# Zróbmy BŁĄD dla uproszczenia (Strike)
			_handle_strike(team_idx)
		else:
			round_bank += result["points"]
			emit_signal("round_bank_updated", round_bank)
			q_manager.reveal_answer(result)
			emit_signal("answer_revealed", result)
			_log_info("[%s] TRAFIENIE! '%s' (+%d)" % [_get_team_name(team_idx), result["text"], result["points"]])
			
			if q_manager.are_all_revealed_in_question(current_question):
				_finish_round(playing_team)
			else:
				# Następny gracz
				current_member_index += 1
				_update_input_for_active_team_member()
	else:
		_handle_strike(team_idx)

func _handle_strike(team_idx):
	strikes += 1
	emit_signal("strike_occured", strikes)
	_log_info("[%s] BŁĄD nr %d/3" % [_get_team_name(team_idx), strikes])
	
	# Wibracja dla wszystkich w drużynie
	for m_id in t_manager.teams.get(team_idx, []):
		var cid = NetworkManager.get_client_id(m_id)
		if cid != "": NetworkManager.send_to_client(cid, { "type": "vibrate" })

	if strikes >= 3:
		_trigger_steal()
	else:
		current_member_index += 1
		_update_input_for_active_team_member()

# Inicjuje fazę kradzieży (STEAL) po osiągnięciu 3 błędów przez drużynę grającą, oddając tablicę przeciwnikom
func _trigger_steal():
	current_substate = RoundState.STEAL
	playing_team = 1 if playing_team == 0 else 0 
	_log_info("PRZEJĘCIE! Szansa dla %s!" % _get_team_name(playing_team))
	emit_signal("timer_start", 10.0, "answer")
	
	# Wyślij input do wszystkich z drużyny przeciwnej (narada)
	var stealing_members = t_manager.teams.get(playing_team, [])
	for mid in stealing_members:
		var cid = NetworkManager.get_client_id(mid)
		if cid != "": NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "input" })
		
	# Wyślij wait do drużyny która straciła
	var waiting_team = 1 if playing_team == 0 else 0
	for mid in t_manager.teams.get(waiting_team, []):
		var cid = NetworkManager.get_client_id(mid)
		if cid != "": NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "Przeciwnicy naradzają się do przejęcia!" })

# Przetwarza odpowiedź drużyny próbującej kradzieży (STEAL), kończąc rundę sukcesem lub porażką
func _process_steal_answer(text, team_idx):
	await _announce_answer_and_wait(text)
	emit_signal("round_message", "Weryfikacja kradzieży...")
	
	var result = await q_manager.check_answer(text, current_question)
	
	if result:
		round_bank += result["points"]
		emit_signal("round_bank_updated", round_bank)
		# W kradzieży też odkrywamy? Zazwyczaj tak
		q_manager.reveal_answer(result)
		emit_signal("answer_revealed", result)
		
		_log_info("[%s] KRADZIEŻ UDANA! +%d pkt. Wygrywacie rundę!" % [_get_team_name(team_idx), result["points"]])
		_finish_round(team_idx)
	else:
		_handle_strike(team_idx)
		var original_team = 1 if team_idx == 0 else 0
		_log_info("[%s] KRADZIEŻ NIEUDANA! Punkty wracają do %s." % [_get_team_name(team_idx), _get_team_name(original_team)])
		_finish_round(original_team)

# Kończy rundę, dodaje zebrane punkty do wyniku zwycięskiej drużyny i prosi o zmianę stanu gry
func _finish_round(winner_idx):
	t_manager.add_score(winner_idx, round_bank)
	await _reveal_missed_answers()
	emit_signal("state_change_requested", "ROUND_END")


func _reveal_missed_answers():
	if current_question.has("answers"):
		for ans in current_question["answers"]:
			# Sprawdzamy czy odpowiedź została już odkryta
			# WARNING: In production code, q_manager.get_revealed_answers should return a list of texts
			# Here assuming simple logic for revealing misses.
			# if not ans["text"] in q_manager.get_revealed_answers(current_question):
				# emit_signal("answer_revealed", ans)
				# await get_tree().create_timer(1.0).timeout # Małe opóźnienie dla efektu wizualnego
			pass


# Zwraca czytelną nazwę drużyny (DRUŻYNA A/B) na podstawie indeksu
func _get_team_name(idx):
	return "DRUŻYNA A" if idx == 0 else "DRUŻYNA B"

# Wysyła wiadomość do konsoli/UI za pomocą sygnału round_message
func _log_info(msg):
	emit_signal("round_message", msg)

func _announce_answer_and_wait(text: String):
	# Dostęp do TTS z GameManager (RoundManager jest dzieckiem GameManagera)
	var gm = get_parent()
	if gm and "tts_speak" in gm:
		# Używamy tts_speak z GM lub bezpośrednio TTSManager
		# gm.tts_speak("Odpowiedź: " + text, false) <- to by dodało "Pytanie:" itd.
		# Lepiej bezpośrednio
		if gm.tts_manager:
			gm.tts_manager.speak(text, true) # true = głos gracza/lżejszy?
	
	# Oczekiwanie na zakończenie czytania (szacunkowe)
	# ZwiÄ™kszamy opÃ³Åºnienie dla lepszego efektu (user request: za szybko)
	var wait_time = 2.0 + text.length() * 0.15
	await get_tree().create_timer(wait_time).timeout
	
	# Po przeczytaniu: pokaż odpowiedź nad tablicą
	emit_signal("player_answer_display", text)
