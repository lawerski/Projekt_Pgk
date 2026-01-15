extends Node

# --- SYGNAŁY ---
signal state_change_requested(new_state)
signal round_message(msg)
signal timer_start(duration, type)

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

# Referencje
var q_manager = null 
var t_manager = null 
var current_question = {} 

# Inicjuje nową rundę, resetuje stan gry i przygotowuje do pojedynku
func start_round(question, round_idx):
	current_round_index = round_idx
	current_question = question
	round_bank = 0
	strikes = 0
	current_substate = RoundState.FACEOFF
	waiting_for_decision = false

	faceoff_pending_score = -1
	faceoff_pending_team_idx = -1
	faceoff_active_player_id = -1

	faceoff_p1 = t_manager.get_faceoff_player(0, round_idx)
	faceoff_p2 = t_manager.get_faceoff_player(1, round_idx)

	_log_info("POJEDYNEK! Do tablicy: %s (A) vs %s (B)" % [str(faceoff_p1), str(faceoff_p2)])

	# WYŚLIJ PYTANIE DO WSZYSTKICH GRACZY (do testów)
	var question_msg = {
		"type": "question",
		"text": question["question"]
	}
	for client_id in NetworkManager.get_connected_clients():
		NetworkManager.send_to_client(client_id, question_msg)

	# Ustawienie ekranów: BUZZER tylko dla walczących, WAIT dla reszty
	var p1_str = str(faceoff_p1)
	var p2_str = str(faceoff_p2)

	for client_id in NetworkManager.get_connected_clients():
		var pid = NetworkManager.client_to_player_id.get(client_id, -1)
		var pid_str = str(pid)
		
		if pid_str == p1_str or pid_str == p2_str:
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "buzzer" })
		else:
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "wait", "msg": "Pojedynek: Gracz %s vs Gracz %s" % [p1_str, p2_str] })

# Obsługa wciśnięcia buzera (wywoływana z GameManager)
func handle_buzzer(player_id: int):
	if current_substate != RoundState.FACEOFF or faceoff_active_player_id != -1:
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


# Główny router inputu, kieruje odpowiedź gracza do odpowiedniej podfunkcji w zależności od stanu rundy
func handle_input(player_id: int, text: String, team_idx: int):
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
				
		RoundState.TEAM_PLAY:
			if team_idx == playing_team:
				_handle_team_play_answer(player_id, text, team_idx)
			else:
				print("IGNOROWANE: Odpowiada %s, a tura należy do %s" % [_get_team_name(team_idx), _get_team_name(playing_team)])
				
		RoundState.STEAL:
			if team_idx == playing_team:
				_process_steal_answer(text, team_idx)

# Obsługuje odpowiedź w fazie pojedynku (FACEOFF), sprawdzając czy jest to TOP odpowiedź lub czy ma czekać na przebicie
func _handle_faceoff_answer(player_id, text, team_idx):
	if faceoff_pending_score != -1:
		await _handle_faceoff_rebuttal(player_id, text, team_idx)
		return

	emit_signal("round_message", "Sędzia sprawdza odpowiedź: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	
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
		q_manager.reveal_answer(result)
		
		var is_top = (current_question["answers"][0]["text"] == result["text"])
		
		if is_top:
			_log_info("[%s] TRAFIENIE! Top odpowiedź '%s' (+%d)!" % [_get_team_name(team_idx), result["text"], points])
			_win_faceoff(player_id, team_idx)
		else:
			faceoff_pending_score = points
			faceoff_pending_team_idx = team_idx
			faceoff_winner_id = player_id 
			
			_log_info("[%s] TRAFIENIE! '%s' (+%d). Ale to nie TOP..." % [_get_team_name(team_idx), result["text"], points])
			_log_info("Szansa dla przeciwnika na przebicie wyniku!")
			
			if opponent_id != -1:
				faceoff_active_player_id = opponent_id
				var pid_client = NetworkManager.get_client_id(player_id)
				var oid_client = NetworkManager.get_client_id(opponent_id)
				if pid_client != "": NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "wait", "msg": "Przeciwnik ma szansę na przebicie..." })
				if oid_client != "": NetworkManager.send_to_client(oid_client, { "type": "set_screen", "screen": "input" })
				
	else:
		_log_info("[%s] PUDŁO w pojedynku! Szansa dla przeciwnika." % _get_team_name(team_idx))
		
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
		
	emit_signal("round_message", "Sędzia sprawdza przebicie: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	
	if result:
		var points = result["points"]
		round_bank += points
		q_manager.reveal_answer(result)
		
		if points > faceoff_pending_score:
			_log_info("[%s] PRZEBICIE! '%s' (+%d) jest lepsze niż %d pkt!" % [_get_team_name(team_idx), result["text"], points, faceoff_pending_score])
			_win_faceoff(player_id, team_idx)
		else:
			_log_info("[%s] '%s' (+%d) to za mało, by przebić %d pkt." % [_get_team_name(team_idx), result["text"], points, faceoff_pending_score])
			_win_faceoff(faceoff_winner_id, faceoff_pending_team_idx)
	else:
		_log_info("[%s] PUDŁO! Wygrywa zespół, który trafił cokolwiek." % _get_team_name(team_idx))
		if faceoff_winner_id != -1:
			_win_faceoff(faceoff_winner_id, faceoff_pending_team_idx)
		else:
			_log_info("Obaj spudłowali! Reset buzzera.")
			faceoff_pending_score = -1
			faceoff_pending_team_idx = -1
			faceoff_active_player_id = -1
			
			var p1_str = str(faceoff_p1)
			var p2_str = str(faceoff_p2)

			for cid in NetworkManager.get_connected_clients():
				var pid = NetworkManager.client_to_player_id.get(cid, -1)
				if str(pid) == p1_str or str(pid) == p2_str:
					NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "buzzer" })
				else:
					NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "Pojedynek (PONOWNIE)..." })

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
		_log_info("[%s] Decyzja: GRAMY! Tablica należy do nas." % _get_team_name(playing_team))
		_start_team_play_phase()
	elif command == "ODDAJEMY" or command == "PASS" or command == "O":
		playing_team = 1 if playing_team == 0 else 0
		current_substate = RoundState.TEAM_PLAY
		_log_info("[%s] Decyzja: ODDAJEMY! Tablica dla przeciwników (%s)." % [_get_team_name(1 if playing_team==0 else 0), _get_team_name(playing_team)])
		_start_team_play_phase()


# --- LOGIKA GRY DRUŻYNOWEJ (TEAM PLAY) ---

func _start_team_play_phase():
	current_substate = RoundState.TEAM_PLAY
	# Znajdź początkowego gracza (np. tego co wygrał faceoff, albo pierwszego w drużynie)
	# Dla uproszczenia: jeśli wygraliśmy faceoff, to active player już wstawia się w metodzie handle_input, 
	# ale tutaj resetujemy indeks na 0 lub na konkretnego gracza.
	# Ustawiamy na pierwszego gracza w liście drużyny.
	
	# Startujemy od gracza następnego po tym, który brał udział w pojedynku (round_index)
	# Jeśli drużyna ma np. 5 graczy, a jest runda 0 (faceoff grał P0), to zaczyna P1.
	current_member_index = current_round_index + 1
	_update_input_for_active_team_member()


func _update_input_for_active_team_member():
	var team_members = t_manager.teams.get(playing_team, [])
	if team_members.is_empty(): return
	
	current_member_index = current_member_index % team_members.size()
	var active_player_id = team_members[current_member_index]
	var active_client_id = NetworkManager.get_client_id(active_player_id)
	
	# 1. Wyślij INPUT do aktywnego gracza
	if active_client_id != "":
		NetworkManager.send_to_client(active_client_id, { "type": "set_screen", "screen": "input" })
	
	# 2. Wyślij WAIT do reszty
	for client_id in NetworkManager.get_connected_clients():
		if client_id != active_client_id:
			var is_same_team = t_manager.get_player_team_index(NetworkManager.client_to_player_id.get(client_id, -1)) == playing_team
			var msg = "Twój kolega z drużyny odpowiada..." if is_same_team else "Druga drużyna odpowiada..."
			NetworkManager.send_to_client(client_id, { "type": "set_screen", "screen": "wait", "msg": msg })


func _handle_team_play_answer(player_id, text, team_idx):
	# Sprawdzenie czy odpowiada właściwy gracz z kolejki
	var team_members = t_manager.teams.get(playing_team, [])
	var expected_id = team_members[current_member_index]
	
	if player_id != expected_id:
		print("IGNOROWANE: Odpowiada %d, a kolejka gracza %d" % [player_id, expected_id])
		return

	emit_signal("round_message", "Sędzia sprawdza: '%s'..." % text)
	
	var result = await q_manager.check_answer(text, current_question)
	
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
			q_manager.reveal_answer(result)
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
	emit_signal("round_message", "Weryfikacja kradzieży...")
	
	var result = await q_manager.check_answer(text, current_question)
	
	if result:
		round_bank += result["points"]
		_log_info("[%s] KRADZIEŻ UDANA! +%d pkt. Wygrywacie rundę!" % [_get_team_name(team_idx), result["points"]])
		_finish_round(team_idx)
	else:
		var original_team = 1 if team_idx == 0 else 0
		_log_info("[%s] KRADZIEŻ NIEUDANA! Punkty wracają do %s." % [_get_team_name(team_idx), _get_team_name(original_team)])
		_finish_round(original_team)

# Kończy rundę, dodaje zebrane punkty do wyniku zwycięskiej drużyny i prosi o zmianę stanu gry
func _finish_round(winner_idx):
	t_manager.add_score(winner_idx, round_bank)
	emit_signal("state_change_requested", "ROUND_END")

# Zwraca czytelną nazwę drużyny (DRUŻYNA A/B) na podstawie indeksu
func _get_team_name(idx):
	return "DRUŻYNA A" if idx == 0 else "DRUŻYNA B"

# Wysyła wiadomość do konsoli/UI za pomocą sygnału round_message
func _log_info(msg):
	emit_signal("round_message", msg)
