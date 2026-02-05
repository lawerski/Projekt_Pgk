extends Node

signal final_update(question_text, timer, current_score)
signal final_state_update(results_data)
signal final_finished(total_score, won_game)
signal play_sound(sound_name)
signal request_host_speak(audio_text, visual_text)

var questions: Array = []
# results format: [ { "question": "...", "p1_ans": "", "p1_pts": 0, "p2_ans": "", "p2_pts": 0 }, ... ]
var results: Array = []

enum State { IDLE, P1_PLAYING, P1_REVEAL, WAIT_P2, P2_PLAYING, P2_REVEAL, FINISHED }
var current_state = State.IDLE
var reveal_index = -1
var points_reveal_index = -1

# --- BRAKUJĄCE ZMIENNE ---
var current_q_text: String = ""
var waiting_for_2nd_start: bool = false
var todo_queue: Array = []
var current_player_idx: int = 0
var is_active: bool = false
var current_q_index_for_ui: int = 0
var time_left: float = 0.0


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
	is_active = true # Timer active
	current_q_index_for_ui = 0
	reveal_index = -1 # Reset reveal
	
	if player_num == 1:
		current_state = State.P1_PLAYING
		time_left = 30.0
	else:
		current_state = State.P2_PLAYING
		todo_queue = [0, 1, 2, 3, 4]
		time_left = 40.0 # P2 gets more time
	
	print("[FinalManager] Czas start: ", time_left)
	
	# Znajdź ID gracza finałowego z wygranej drużyny
	var winner_team = TeamManager.check_for_finalist()
	if winner_team == -1: winner_team = 0 
	
	var members = TeamManager.teams.get(winner_team, [])
	var active_player_id = -1
	
	if player_num == 1:
		if members.size() > 0: active_player_id = members[0]
	else:
		if members.size() > 1: active_player_id = members[1]
		elif members.size() > 0: active_player_id = members[0] # Fallback
		
	if active_player_id != -1:
		_send_input_to_finalist(active_player_id)
		
	_send_current_question()
	_emit_state() # Will send masked results

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
		if time_left > 0:
			time_left -= delta
			# W trakcie gry nie aktualizujemy wyniku na żywo (suma punktów), bo jest ukryty
			# Ale UI potrzebuje czasu
			emit_signal("final_update", current_q_text, max(0.0, time_left), _calculate_revealed_score()) # Use revealed score
		
		if time_left <= 0:
			finish_player_turn()

# Wewnętrzna metoda - tylko odkryte punkty
func _calculate_revealed_score() -> int:
	var total = 0
	for i in range(results.size()):
		var r = results[i]
		
		# P1 Score Logic
		var p1_pts_vis = false
		if current_state == State.P1_REVEAL:
			if i <= points_reveal_index: p1_pts_vis = true
		elif current_state >= State.WAIT_P2: p1_pts_vis = true
			
		# P2 Score Logic
		var p2_pts_vis = false
		if current_state == State.P2_REVEAL:
			if i <= points_reveal_index: p2_pts_vis = true
		elif current_state == State.FINISHED: p2_pts_vis = true
		
		if p1_pts_vis: total += r["p1_pts"]
		if p2_pts_vis: total += r["p2_pts"]
		
	return total

func _calculate_total_real_score() -> int:
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
		_send_current_question_delayed()
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
	_emit_state() # Will send updated MASKED state (so board remains hidden)
	
	if todo_queue.is_empty():
		finish_player_turn()
	else:
		_send_current_question_delayed()

func _send_current_question_delayed():
	# Update UI immediately so Board shows new question (or empty if pending)
	# But clear Phone Input first to prevent spamming
	var player_id_int = 0
	if current_player_idx == 1: 
		player_id_int = TeamManager.teams[TeamManager.check_for_finalist() if TeamManager.check_for_finalist()!=-1 else 0][0]
	else:
		var ft = TeamManager.check_for_finalist()
		if ft == -1: ft = 0
		var members = TeamManager.teams.get(ft, [])
		if members.size() > 1: player_id_int = members[1]

	var pid_client = NetworkManager.get_client_id(player_id_int)
	if pid_client != "":
		NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "wait", "msg": "..." })

	# Cooldown on website (User request)
	await get_tree().create_timer(1.0).timeout
	
	_send_current_question()
	
	# Unlock Input
	if pid_client != "":
		NetworkManager.send_to_client(pid_client, { "type": "set_screen", "screen": "input" })

# Zakończenie tury gracza
func finish_player_turn():
	is_active = false # Stop timer, start reveal phase
	
	# Clear phones (User report: "widać pytanie na stronie" -> Web clients still show input)
	for cid in NetworkManager.get_connected_clients():
		NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "Sprawdzanie wyników..." })

	# Transition based on current player
	if current_player_idx == 1:
		current_state = State.P1_REVEAL
		reveal_index = -1
		points_reveal_index = -1
		emit_signal("final_update", "Sprawdzamy odpowiedzi...", 0.0, _calculate_revealed_score())
		_start_reveal_sequence()
	else:
		current_state = State.P2_REVEAL
		reveal_index = -1
		points_reveal_index = -1
		emit_signal("final_update", "Sprawdzamy odpowiedzi (Gracz 2)...", 0.0, _calculate_revealed_score())
		_start_reveal_sequence()

func _start_reveal_sequence():
	# Clear the big question text from UI (User request: "usuń teraz pytania na stronie")
	emit_signal("final_update", "", 0.0, _calculate_revealed_score())

	# PHASE 1: Reveal ALL Texts (With Host Speech)
	for i in range(5):
		var q_txt = questions[i]["question"]
		var ans_txt = ""
		if current_state == State.P1_REVEAL: ans_txt = results[i]["p1_ans"]
		else: ans_txt = results[i]["p2_ans"]
		
		# 1. Host reads Question + Answer FIRST (Bubble shows up here)
		var speech_text = "Pytanie: " + q_txt + ". Odpowiedź: " + ans_txt
		var visual_text = ans_txt # Only show Answer in bubble (User request: "tekst nie mieści się", "niech nie wyświetla pytania")
		if visual_text == "": visual_text = "..."
		
		emit_signal("request_host_speak", speech_text, visual_text)
		
		# 2. Add delay so speech happens BEFORE text reveal
		await get_tree().create_timer(4.0).timeout
		
		# 3. NOW Show the text on board
		reveal_index = i
		_emit_state()
		
		# Extra pause to read the screen AND Cooldown (User report: "dalej nie ma cooldown")
		# Increased from 1.0s to 5.0s to allow Host to breathe and audience to digest.
		await get_tree().create_timer(5.0).timeout

	# Pause between text and points
	emit_signal("request_host_speak", "Sprawdźmy ile to punktów!", "Punkty?")
	await get_tree().create_timer(3.0).timeout

	# PHASE 2: Reveal ALL Points
	for i in range(5):
		# Host build-up bubble first? No, for points it's usually automatic ding/buzz.
		
		# Reveal the points
		points_reveal_index = i
		_emit_state()
		
		# Play sounds depending on points

		var pts = 0
		if current_state == State.P1_REVEAL: pts = results[i]["p1_pts"]
		else: pts = results[i]["p2_pts"]
		
		if pts > 0:
			emit_signal("play_sound", "ding") 
		else:
			emit_signal("play_sound", "wrong")
			
		# Update UI Total SCORE visually
		emit_signal("final_update", "", 0.0, _calculate_revealed_score())
		
		await get_tree().create_timer(2.5).timeout
		
	# End of reveal
	await get_tree().create_timer(1.0).timeout
	
	if current_state == State.P1_REVEAL:
		# Check if we have a second player in the winning team
		var winner_team = TeamManager.check_for_finalist()
		if winner_team == -1: winner_team = 0
		var members = TeamManager.teams.get(winner_team, [])
		
		# Only proceed to P2 if there ARE 2+ members
		# AND if the score is less than 200 (if P1 got 200 alone, they win immediately)
		if members.size() > 1 and _calculate_revealed_score() < 200:
			current_state = State.WAIT_P2
			waiting_for_2nd_start = true
			emit_signal("final_update", "Oczekiwanie na drugiego gracza...", 0.0, _calculate_revealed_score())
			print("DEBUG: Oczekiwanie na start Gracza 2...")
			
			# SEND WAIT SCREEN TO ALL TO BE SURE
			for cid in NetworkManager.get_connected_clients():
				NetworkManager.send_to_client(cid, { "type": "set_screen", "screen": "wait", "msg": "Zmiana gracza..." })

		else:
			print("DEBUG: Tylko 1 gracz w finale LUB 200pkt zdobyte. Kończenie gry.")
			current_state = State.FINISHED
			var total = _calculate_revealed_score()
			# Solo mode threshold: 100 points
			var won = total >= (200 if members.size() > 1 else 100)
			# Fallback: if P1 got 200+ pts in 2-player team, they also win.
			if members.size() > 1 and total >= 200: won = true

			emit_signal("final_finished", total, won)
			_show_end_screen(won, total)
			
	elif current_state == State.P2_REVEAL:
		current_state = State.FINISHED
		var total = _calculate_revealed_score()
		var won = total >= 200
		emit_signal("final_finished", total, won)
		_show_end_screen(won, total)

func start_second_part_manual():
	if current_state == State.WAIT_P2:
		waiting_for_2nd_start = false
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
		
		# W finale też usuwamy pytanie ze strony (User request)
		for cid in NetworkManager.get_connected_clients():
			NetworkManager.send_to_client(cid, { "type": "question", "text": "Patrz na ekran TV" })
	
	var total = _calculate_revealed_score()
	emit_signal("final_update", current_q_text, time_left, total)

func _emit_state():
	# Create MASKED Results based on state
	var masked_results = []
	for i in range(results.size()):
		var original = results[i]
		var item = { "question": original["question"], "p1_ans": "", "p1_pts": 0, "p2_ans": "", "p2_pts": 0 }
		
		# --- P1 VISIBILITY ---
		var show_p1_text = false
		var show_p1_pts = false
		
		if current_state == State.P1_REVEAL: 
			if i <= reveal_index: show_p1_text = true
			if i <= points_reveal_index: show_p1_pts = true
		elif current_state >= State.WAIT_P2:
			show_p1_text = true
			show_p1_pts = true
			
		if show_p1_text: item["p1_ans"] = original["p1_ans"]
		elif current_state == State.P1_PLAYING and original["p1_ans"] != "": item["p1_ans"] = "---"

		if show_p1_pts: item["p1_pts"] = original["p1_pts"]
		
		# --- P2 VISIBILITY ---
		var show_p2_text = false
		var show_p2_pts = false
		
		if current_state == State.P2_REVEAL:
			if i <= reveal_index: show_p2_text = true
			if i <= points_reveal_index: show_p2_pts = true
		elif current_state == State.FINISHED:
			show_p2_text = true
			show_p2_pts = true
			
		if show_p2_text: item["p2_ans"] = original["p2_ans"]
		elif current_state == State.P2_PLAYING and original["p2_ans"] != "": item["p2_ans"] = "---"

		if show_p2_pts: item["p2_pts"] = original["p2_pts"]
		
		masked_results.append(item)

	emit_signal("final_state_update", masked_results)



