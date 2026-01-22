extends Node

signal final_update(question_text, timer, current_score)
signal final_state_update(results_data)
signal final_finished(total_score, won_game)
signal play_sound(sound_name)

var questions: Array = []
# results format: [ { "question": "...", "p1_ans": "", "p1_pts": 0, "p2_ans": "", "p2_pts": 0 }, ... ]
var results: Array = []

var current_player_idx: int = 1
var time_left: float = 0.0
var is_active: bool = false
var todo_queue: Array = [] 
var current_q_index_for_ui: int = 0
var current_q_text: String = ""
var waiting_for_2nd_start: bool = false

# Inicjalizacja finału
func setup_final(selected_questions: Array):
	questions = selected_questions
	current_q_text = ""
	waiting_for_2nd_start = false
	results.clear()
	for q in questions:
		results.append({
			"question": q["question"],
			"p1_ans": "", "p1_pts": 0,
			"p2_ans": "", "p2_pts": 0
		})
	
	todo_queue = [0, 1, 2, 3, 4]
	start_player(1)

# Rozpoczęcie tury gracza
func start_player(player_num):
	print("[FinalManager] Start gracza nr: ", player_num)
	current_player_idx = player_num
	is_active = true
	current_q_index_for_ui = 0
	
	if player_num == 2: 
		todo_queue = [0, 1, 2, 3, 4]
	
	time_left = 30.0 if player_num == 1 else 40.0 # P2 usually gets more time
	print("[FinalManager] Czas start: ", time_left)
	
	# Znajdź ID gracza finałowego z wygranej drużyny
	var winner_team = TeamManager.check_for_finalist()
	if winner_team == -1: winner_team = 0 # Fallback do A
	
	# Wybieramy gracza nr 1 i nr 2 z tej drużyny
	var members = TeamManager.teams.get(winner_team, [])
	var active_player_id = -1
	
	if player_num == 1:
		if members.size() > 0: active_player_id = members[0]
	else:
		if members.size() > 1: active_player_id = members[1]
		elif members.size() > 0: active_player_id = members[0] # Fallback jeśli 1 osoba
		
	if active_player_id != -1:
		_send_input_to_finalist(active_player_id)
		
	_send_current_question()
	_emit_state()

func _send_input_to_finalist(player_id_int):
	var pid_client = NetworkManager.get_client_id(player_id_int)
	if pid_client != "":
		NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "input" })
	
	# Pozostałym wyślij wait
	for cid in NetworkManager.get_connected_clients():
		if cid != pid_client:
			var msg = "FINAŁ! Patrz na ekran"
			NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": msg })

# Obsługa czasu gry
func _process(delta):
	if is_active:
		time_left -= delta
		
		# Oblicz sumę punktów na bieżąco
		var current_total = _calculate_total_score()
		
		# Bezpośrednia wywołanie aktualizacji UI (zamiast signal spam, jeśli GameUI ma referencję)
		emit_signal("final_update", current_q_text, max(0.0, time_left), current_total)
		
		if time_left <= 0:
			finish_player_turn()

# Wewnętrzna metoda
func _calculate_total_score() -> int:
	var total = 0
	for r in results:
		total += r["p1_pts"] + r["p2_pts"]
	return total

# Obsługa odpowiedzi gracza
func handle_input(text: String, is_skip: bool = false):
	if not is_active: 
		return
	
	if todo_queue.is_empty(): return

	var q_idx = todo_queue.front()
	
	# Jeśli SKIP - wrzuć na koniec kolejki (tylko w Familiadzie zazwyczaj się "nie odpowiada" i leci dalej, 
	# ale mechanika "SKIP" może też oznaczać "nie wiem" i 0 pkt)
	if is_skip:
		# W klasycznych zasadach: "Dalej" -> traci się szansę na to pytanie w tym przebiegu? 
		# Czy wraca na koniec? Przyjmijmy że to 0 pkt i następne.
		# A może "Pasuje" i wraca na koniec?
		# Zróbmy jak w teleturnieju: "Dalej" -> pytanie wraca na koniec.
		todo_queue.pop_front()
		todo_queue.append(q_idx)
		_send_current_question()
		return

	var current_q_data = questions[q_idx]
	
	# Check for duplicate if loading P2
	if current_player_idx == 2:
		var p1_answ_text = results[q_idx]["p1_ans"]
		if text.to_lower() == p1_answ_text.to_lower():
			emit_signal("play_sound", "repeat")
			# Gracz musi podać inną odpowiedź! Nie zdejmujemy z kolejki.
			return 

	var result = get_parent().question_manager.check_answer_final(text, current_q_data)
	var points = result["points"] if result else 0
	
	# Update internal state
	if current_player_idx == 1:
		results[q_idx]["p1_ans"] = text
		results[q_idx]["p1_pts"] = points
	else:
		results[q_idx]["p2_ans"] = text
		results[q_idx]["p2_pts"] = points
	
	todo_queue.pop_front()
	_emit_state()
	
	if todo_queue.is_empty():
		finish_player_turn()
	else:
		_send_current_question()

# Zakończenie tury gracza
func finish_player_turn():
	is_active = false
	
	var total_score = _calculate_total_score()
	
	if current_player_idx == 1:
		waiting_for_2nd_start = true
		emit_signal("final_update", "Koniec cz. 1. Oczekiwanie na drugiego gracza...", 0.0, total_score)
		
		# Ukryj odpowiedzi na tablicy (wyślij puste dane)
		var masked = []
		for i in range(5):
			masked.append({"question":"", "p1_ans":"", "p1_pts":0, "p2_ans":"", "p2_pts":0})
		emit_signal("final_state_update", masked)
		
		print("DEBUG: Oczekiwanie na start Gracza 2 (Wciśnij spację lub przycisk)...")
	else:
		var won = total_score >= 200
		emit_signal("final_finished", total_score, won)
		_show_end_screen(won, total_score)

func start_second_part_manual():
	if waiting_for_2nd_start:
		waiting_for_2nd_start = false
		# Przywróć widok wyników gracza 1 przed startem gracza 2
		_emit_state()
		start_player(2)

func _show_end_screen(won, score):
	# Send end game packet to clients
	for client_id in NetworkManager.get_connected_clients():
		NetworkManager.send_to_client(client_id, { 
			"type": "set_screen", 
			"screen": "end",
			"won": won,
			"score": score
		})

# Wysłanie aktualnego pytania
func _send_current_question():
	if todo_queue.is_empty(): 
		current_q_text = "Koniec!"
	else:
		var q_idx = todo_queue.front()
		current_q_text = questions[q_idx]["question"]
	
	var total = _calculate_total_score()
	emit_signal("final_update", current_q_text, time_left, total)

func _emit_state():
	emit_signal("final_state_update", results)



