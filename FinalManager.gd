extends Node

signal final_update(question_text, timer, current_score)
signal final_finished(total_score, won_game)
signal play_sound(sound_name)

var questions: Array = []
var p1_answers: Dictionary = {}
var p2_score: int = 0
var current_player_idx: int = 1
var time_left: float = 0.0
var is_active: bool = false
var todo_queue: Array = [] 

# Inicjalizacja finału
func setup_final(selected_questions: Array):
	questions = selected_questions
	p1_answers.clear()
	todo_queue = [0, 1, 2, 3, 4]
	start_player(1)

# Rozpoczęcie tury gracza
func start_player(player_num):
	print("[FinalManager] Start gracza nr: ", player_num)
	current_player_idx = player_num
	is_active = true
	
	if player_num == 2: 
		todo_queue = [0, 1, 2, 3, 4]
	
	time_left = 30.0 if player_num == 1 else 40.0
	print("[FinalManager] Czas start: ", time_left)
	
	# Znajdź ID gracza finałowego z wygranej drużyny
	var winner_team = get_parent().team_manager.check_for_finalist()
	if winner_team == -1: winner_team = 0 # Fallback do A
	
	# Wybieramy gracza nr 1 i nr 2 z tej drużyny
	var members = get_parent().team_manager.teams.get(winner_team, [])
	var active_player_id = -1
	
	if player_num == 1:
		if members.size() > 0: active_player_id = members[0]
	else:
		if members.size() > 1: active_player_id = members[1]
		elif members.size() > 0: active_player_id = members[0] # Fallback jeśli 1 osoba
		
	if active_player_id != -1:
		_send_input_to_finalist(active_player_id)
		
	_send_current_question()

func _send_input_to_finalist(player_id_int):
	var pid_str = str(player_id_int)
	NetworkManager.send_to_client(pid_str, { "type": "set_screen", "screen": "input" })
	
	# Pozostałym wyślij wait
	for cid in NetworkManager.get_connected_clients():
		if str(cid) != pid_str:
			NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "FINAŁ! Odpowiada finalista..." })

# Obsługa czasu gry
func _process(delta):
	if is_active:
		time_left -= delta
		if time_left <= 0:
			finish_player_turn()

# Obsługa odpowiedzi gracza
func handle_input(text: String, is_skip: bool = false):
	if not is_active: 
		return
	
	var q_idx = todo_queue.front()
	
	if is_skip:
		todo_queue.pop_front()
		todo_queue.append(q_idx)
		_send_current_question()
		return

	var current_q_data = questions[q_idx]
	
	if current_player_idx == 2:
		var p1_ans = p1_answers.get(q_idx, "")
		if text.to_lower() == p1_ans.to_lower():
			emit_signal("play_sound", "repeat")
			return 

	var result = get_parent().question_manager.check_answer_final(text, current_q_data)
	var points = result["points"] if result else 0
	
	if current_player_idx == 1:
		p1_answers[q_idx] = text
	
	p2_score += points
	todo_queue.pop_front()
	
	if todo_queue.is_empty():
		finish_player_turn()
	else:
		_send_current_question()

# Zakończenie tury gracza
func finish_player_turn():
	is_active = false
	
	if current_player_idx == 1:
		emit_signal("final_update", "Koniec tury P1. Gracz 2 wchodzi za 3 sekundy...", 0.0, p2_score)
		print("DEBUG: Oczekiwanie na start Gracza 2...")
		await get_tree().create_timer(3.0).timeout
		start_player(2)
	else:
		var won = p2_score >= 200
		emit_signal("final_finished", p2_score, won)

# Wysłanie aktualnego pytania
func _send_current_question():
	var q_idx = todo_queue.front()
	emit_signal("final_update", questions[q_idx]["question"], time_left, p2_score)
