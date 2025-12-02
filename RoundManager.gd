extends Node

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

# Odniesienia (ustawiane przez GameManager)
var q_manager = null
var t_manager = null
var current_question = {}

func start_round(question, round_idx):
	current_question = question
	round_bank = 0
	strikes = 0
	current_substate = RoundState.FACEOFF
	waiting_for_decision = false
	
	# Pobierz graczy do pojedynku
	var p1 = t_manager.get_faceoff_player(0, round_idx)
	var p2 = t_manager.get_faceoff_player(1, round_idx)
	
	emit_signal("round_message", "POJEDYNEK! Do tablicy: %s vs %s" % [str(p1), str(p2)])

func handle_input(player_id: int, text: String, team_idx: int):
	print("DEBUG: RoundManager input: ", text)
	match current_substate:
		RoundState.FACEOFF:
			_handle_faceoff_answer(player_id, text, team_idx)
		RoundState.DECISION:
			_handle_decision(player_id, text)
		RoundState.TEAM_PLAY:
			if team_idx == playing_team:
				_process_game_answer(text)
		RoundState.STEAL:
			# W fazie kradzieży odpowiada tylko kapitan drużyny kradnącej
			# (Dla uproszczenia testu: każdy z tej drużyny)
			if team_idx == playing_team:
				_process_steal_answer(text)

func _handle_faceoff_answer(player_id, text, team_idx):
	var result = q_manager.check_answer(text, current_question)
	
	if result:
		round_bank += result["points"]
		q_manager.reveal_answer(result)
		
		emit_signal("round_message", "TRAFIENIE! '%s' (+%d). Bank: %d" % [result["text"], result["points"], round_bank])
		
		# SPRAWDZENIE CZY TO JUŻ KONIEC (Dla pytań z 1 odpowiedzią)
		if q_manager.are_all_revealed_in_question(current_question):
			print("DEBUG: Pojedynek wyczyścił tablicę! Koniec rundy.")
			_finish_round(team_idx)
			return

		# Czy to najlepsza odpowiedź?
		var is_top = (current_question["answers"][0]["text"] == result["text"])
		
		if is_top:
			emit_signal("round_message", "TOP ODPOWIEDŹ! Decyzja: Grasz (G) czy Oddajesz (O)?")
			faceoff_winner_id = player_id
			playing_team = team_idx
			waiting_for_decision = true
			current_substate = RoundState.DECISION
		else:
			playing_team = team_idx
			current_substate = RoundState.TEAM_PLAY
			emit_signal("round_message", "Dobra odpowiedź! Gra drużyna " + str(team_idx))
	else:
		emit_signal("round_message", "Pudło w pojedynku!")

func _handle_decision(player_id: int, text: String):
	if player_id != faceoff_winner_id: return # Tylko zwycięzca decyduje

	var command = text.to_upper()
	if command == "PLAY" or command == "GRAMY":
		current_substate = RoundState.TEAM_PLAY
		emit_signal("round_message", "Decyzja: GRAMY! Odpowiada Twoja drużyna.")
	elif command == "PASS" or command == "ODDAJEMY":
		playing_team = 1 if playing_team == 0 else 0
		current_substate = RoundState.TEAM_PLAY
		emit_signal("round_message", "Decyzja: ODDAJEMY! Przeciwnicy przejmują tablicę.")

func _process_game_answer(text):
	var result = q_manager.check_answer(text, current_question)
	
	if result:
		round_bank += result["points"]
		q_manager.reveal_answer(result)
		emit_signal("round_message", "DOBRA ODPOWIEDŹ! '%s' (+%d)" % [result["text"], result["points"]])
		
		if q_manager.are_all_revealed_in_question(current_question):
			print("DEBUG: Wszystko odkryte. Koniec rundy.")
			_finish_round(playing_team)
	else:
		strikes += 1
		emit_signal("round_message", "BŁĄD nr " + str(strikes))
		
		if strikes == 2:
			emit_signal("round_message", "NARADA (30s) - Uważajcie!")
			
		if strikes >= 3:
			_trigger_steal() # <--- TUTAJ BYŁ BŁĄD, TERAZ FUNKCJA ISTNIEJE PONIŻEJ

# --- TEJ FUNKCJI BRAKOWAŁO ---
func _trigger_steal():
	current_substate = RoundState.STEAL
	# Zmiana drużyny na przeciwną (tę która kradnie)
	playing_team = 1 if playing_team == 0 else 0
	
	print("DEBUG: Przełączenie na fazę STEAL. Odpowiada drużyna: ", playing_team)
	emit_signal("round_message", "PRZEJĘCIE! Szansa dla Drużyny " + str(playing_team))
# -----------------------------

func _process_steal_answer(text):
	var result = q_manager.check_answer(text, current_question)
	if result:
		round_bank += result["points"]
		emit_signal("round_message", "KRADZIEŻ UDANA! '+%d'" % result["points"])
		# Wygrywa drużyna kradnąca (obecna playing_team)
		_finish_round(playing_team)
	else:
		emit_signal("round_message", "KRADZIEŻ NIEUDANA! Punkty wracają.")
		# Wygrywa drużyna pierwotna (przeciwna do obecnej kradnącej)
		var original_team = 1 if playing_team == 0 else 0
		_finish_round(original_team)

func _finish_round(winner_idx):
	t_manager.add_score(winner_idx, round_bank)
	emit_signal("state_change_requested", "ROUND_END")
