extends Node

signal final_update(question_text, timer, current_score)
signal final_finished(total_score, won_game)
signal play_sound(sound_name) # "ding", "buzzer", "repeat"

var questions: Array = []       # 5 wylosowanych pytań
var p1_answers: Dictionary = {} # index_pytania -> odpowiedz_tekst
var p2_score: int = 0
var current_player_idx: int = 1 # 1 lub 2
var time_left: float = 0.0
var is_active: bool = false

# Kolejka pytań: Przechowujemy indeksy pytań, na które jeszcze nie odpowiedziano
var todo_queue: Array = [] 

func setup_final(selected_questions: Array):
	questions = selected_questions
	p1_answers.clear()
	todo_queue = [0, 1, 2, 3, 4] # Indeksy pytań
	start_player(1)

func start_player(player_num):
	print("[FinalManager] Start gracza nr: ", player_num) # log
	current_player_idx = player_num
	is_active = true
	
	if player_num == 2: todo_queue = [0, 1, 2, 3, 4]
	
	time_left = 30.0 if player_num == 1 else 40.0
	print("[FinalManager] Czas start: ", time_left) # log
	
	_send_current_question()

func _process(delta):
	if is_active:
		time_left -= delta
		if time_left <= 0:
			finish_player_turn()

func handle_input(text: String, is_skip: bool = false):
	if not is_active: return
	
	var q_idx = todo_queue.front() # Pobierz aktualne pytanie
	
	if is_skip:
		# Przesuń pytanie na koniec kolejki
		todo_queue.pop_front()
		todo_queue.append(q_idx)
		_send_current_question()
		return

	var current_q_data = questions[q_idx]
	
	# GRACZ 2: Sprawdzenie powtórzeń
	if current_player_idx == 2:
		var p1_ans = p1_answers.get(q_idx, "")
		# Sprawdź czy text jest identyczny (lub bardzo podobny) do tego co powiedział P1
		if text.to_lower() == p1_ans.to_lower():
			emit_signal("play_sound", "repeat") # Dźwięk "BYŁO!"
			# Gracz musi podać inną odpowiedź, nie zmieniamy pytania
			return 

	# Sprawdzenie odpowiedzi (Fuzzy Logic z QuestionManager)
	var result = get_parent().question_manager.check_answer_final(text, current_q_data)
	var points = result["points"] if result else 0
	
	# Zapisz wynik
	if current_player_idx == 1:
		p1_answers[q_idx] = text # Zapisujemy co powiedział, żeby P2 nie powtórzył
	
	p2_score += points
	
	# Usuń pytanie z kolejki (bo odpowiedziano)
	todo_queue.pop_front()
	
	if todo_queue.is_empty():
		finish_player_turn()
	else:
		_send_current_question()

func finish_player_turn():
	is_active = false
	
	if current_player_idx == 1:
		# Komunikat o przerwie
		emit_signal("final_update", "Koniec tury P1. Gracz 2 wchodzi za 3 sekundy...", 0.0, p2_score)
		print("DEBUG: Oczekiwanie na start Gracza 2...")
		
		# --- NAPRAWA: Automatyczny start Gracza 2 ---
		await get_tree().create_timer(3.0).timeout
		start_player(2)
		# --------------------------------------------
		
	else:
		# Koniec gry (Gracz 2 skończył)
		var won = p2_score >= 200 # Próg wygranej (dla testu możesz zmienić na mniej)
		emit_signal("final_finished", p2_score, won)

func _send_current_question():
	var q_idx = todo_queue.front()
	emit_signal("final_update", questions[q_idx]["question"], time_left, p2_score)
