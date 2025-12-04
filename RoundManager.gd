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

# Referencje
var q_manager = null 
var t_manager = null 
var current_question = {} 

# Inicjuje nową rundę, resetuje stan gry i przygotowuje do pojedynku
func start_round(question, round_idx):
	current_question = question
	round_bank = 0
	strikes = 0
	current_substate = RoundState.FACEOFF
	waiting_for_decision = false
	
	faceoff_pending_score = -1
	faceoff_pending_team_idx = -1
	
	var p1 = t_manager.get_faceoff_player(0, round_idx)
	var p2 = t_manager.get_faceoff_player(1, round_idx)
	
	_log_info("POJEDYNEK! Do tablicy: %s (A) vs %s (B)" % [str(p1), str(p2)])

# Główny router inputu, kieruje odpowiedź gracza do odpowiedniej podfunkcji w zależności od stanu rundy
func handle_input(player_id: int, text: String, team_idx: int):
	match current_substate:
		RoundState.FACEOFF:
			_handle_faceoff_answer(player_id, text, team_idx)
			
		RoundState.DECISION:
			if player_id == faceoff_winner_id:
				_handle_decision(player_id, text)
				
		RoundState.TEAM_PLAY:
			if team_idx == playing_team:
				_process_game_answer(text, team_idx)
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
	else:
		_log_info("[%s] PUDŁO w pojedynku! Szansa dla przeciwnika." % _get_team_name(team_idx))

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
		_win_faceoff(faceoff_winner_id, faceoff_pending_team_idx)

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

# Obsługuje komendę gracza zwycięskiego w pojedynku (GRAMY lub ODDAJEMY)
func _handle_decision(player_id: int, text: String):
	var command = text.to_upper()
	if command == "GRAMY" or command == "PLAY":
		current_substate = RoundState.TEAM_PLAY
		_log_info("[%s] Decyzja: GRAMY! Tablica należy do nas." % _get_team_name(playing_team))
	elif command == "ODDAJEMY" or command == "PASS":
		playing_team = 1 if playing_team == 0 else 0
		current_substate = RoundState.TEAM_PLAY
		_log_info("[%s] Decyzja: ODDAJEMY! Tablica dla przeciwników (%s)." % [_get_team_name(1 if playing_team==0 else 0), _get_team_name(playing_team)])

# Przetwarza odpowiedź drużyny grającej w fazie TEAM_PLAY, nalicza punkty lub błędy
func _process_game_answer(text, team_idx):
	emit_signal("round_message", "Sędzia sprawdza...")
	
	var result = await q_manager.check_answer(text, current_question)
	
	if result:
		round_bank += result["points"]
		q_manager.reveal_answer(result)
		_log_info("[%s] DOBRA ODPOWIEDŹ! '%s' (+%d)" % [_get_team_name(team_idx), result["text"], result["points"]])
		
		if q_manager.are_all_revealed_in_question(current_question):
			_finish_round(playing_team)
	else:
		strikes += 1
		_log_info("[%s] BŁĄD nr %d" % [_get_team_name(team_idx), strikes])
		
		if strikes == 2:
			var opponent = 1 if playing_team == 0 else 0
			_log_info("UWAGA: Narada dla %s (Opponent)" % _get_team_name(opponent))
			emit_signal("timer_start", 15.0, "consultation")
			
		if strikes >= 3:
			_trigger_steal()

# Inicjuje fazę kradzieży (STEAL) po osiągnięciu 3 błędów przez drużynę grającą, oddając tablicę przeciwnikom
func _trigger_steal():
	current_substate = RoundState.STEAL
	playing_team = 1 if playing_team == 0 else 0 
	_log_info("PRZEJĘCIE! Szansa dla %s!" % _get_team_name(playing_team))
	emit_signal("timer_start", 10.0, "answer")

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
