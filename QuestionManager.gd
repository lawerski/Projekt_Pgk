extends Node

const questions_file = "res://questions.json"

var all_questions: Array = []
var current_pool: Array = []

func _ready():
	load_questions()

func load_questions():
	if not FileAccess.file_exists(questions_file):
		printerr("[QuestionManager] Błąd: Plik questions.json nie istnieje")
		return
	
	var file = FileAccess.open(questions_file, FileAccess.READ)
	var content = file.get_as_text()
	
	var json = JSON.new()
	var error = json.parse(content)
	
	if error == OK:
		var data = json.data
		if typeof(data) == TYPE_ARRAY:
			
			all_questions = data
			current_pool = all_questions.duplicate()
			
			print("[QuestionManager] Pomyślnie wczytano %d pytań." % all_questions.size())
		else:
			printerr("[QuestionManager] Błąd: JSON musi być tablicą")
	else:
		printerr("[QuestionManager] Błąd podczas parsowania JSON na linii ", json.get_error_line())

func get_random_question() -> Dictionary:
	if current_pool.is_empty():
		print("[QuestionManager] Wyczerpano wszystkie pytania! Resetowanie puli")
		
		current_pool = all_questions.duplicate()
		
		if current_pool.is_empty():
			return {}
	
	var random_index = randi() % current_pool.size()
	
	var selected_question = current_pool.pop_at(random_index)
	
	print("[QuestionManager] Wylosowano pytanie ID: %d: %s" % [selected_question.get("id"), selected_question.get("question")])
	
	return selected_question
	
