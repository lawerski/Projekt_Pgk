extends Node

@onready var question_manager = $QuestionManager

enum GameState {
	LOBBY,
	ROUND_START,
	PLAYER_INPUT,
	REVEAL,
	ROUND_END
}

var current_state: GameState = GameState.LOBBY
var players: Dictionary = {}
var current_question_data: Dictionary = {}

func _ready() -> void:
	print(" GAME MANAGER START")
	print("Stan początkowy: %s" % current_state)

func change_state(new_state: GameState):
	var old_state_name = GameState.keys()[current_state]
	var new_state_name = GameState.keys()[new_state]
	
	print("[GameManager] Zmiana stanu: %s -> %s" % [old_state_name, new_state_name])
	current_state = new_state
	
	_handle_state_logic()
	
func _handle_state_logic():
	match current_state:
		GameState.LOBBY:
			print("Host oczekuje na połączenia...")
		GameState.ROUND_START:
			print("Start rundy: Pobieranie pytania..")
			if question_manager:
				current_question_data = question_manager.get_random_question()
				if current_question_data:
					print("Pytanie: " + str(current_question_data["question"]))
					change_state(GameState.PLAYER_INPUT)
					#wyslanie pytania do UI feature
		GameState.PLAYER_INPUT:
			print("Oczekiwanie na input od graczy (smartfony).")
		GameState.REVEAL:
			print("Sprawdzanie odpowiedzi i animacja tablicy.")
		GameState.ROUND_END:
			print("Koniec rundy. Aktualizacja wyników.")

func start_game():
	print("Próba rozpoczecia gry...")
	
	if players.size() < 2:
		print("[BŁĄD] Za mało graczy. Wymaganych: 2, Obecnie: %d" % players.size())
		return
	
	change_state(GameState.ROUND_START)
	
func join_fake_player(name: String):
	var new_id = players.size() + 1
	players[new_id] = name
	print("Dołącza gracz: %s. Razem graczy: %d" % [name, players.size()])

var chars = "abcdefghijklmnoprstuvwxyz"
func generate_fake_name(letters, length):
	var word: String
	var n_char = len(letters)
	
	for i in range(length):
		word += chars[randi() % n_char]
	
	return word
	
func _input(event):
	if event.is_action_pressed("ui_accept"):
		start_game()
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_T:
		if current_state == GameState.PLAYER_INPUT:
			var test_input = "katomierz"
			print("testuje input: " + test_input)
			
			var result = question_manager.check_answer(test_input, current_question_data)
			
			if result:
				print("Trafienie! Punkty: " + str(result["points"]))
				# feature - zmiana stanu gry na reveal
			else:
				print("Pudlo")
	
	if event is InputEventKey and event.pressed and event.keycode == KEY_A:
		join_fake_player(generate_fake_name(chars, 4))
