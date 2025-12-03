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

# Sprawdzanie poprawności odpowiedzi/wyrazow podobnych

const similarity_threshold = 0.6
const pl_chars = {
	"ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z"
}

func check_answer(player_input: String, current_question: Dictionary) -> Dictionary:
	if current_question.is_empty() or not current_question.has("answers"):
		return {}
	
	var normalized_input = normalize_text(player_input)
	var best_match = null
	var best_score = 0.0
	
	for answer in current_question["answers"]:
		if answer.get("revealed", false):
			continue
		
		var answer_text = answer["text"]
		var normalized_answer = normalize_text(answer_text)
		
		if normalized_input == normalized_answer:
			answer["revealed"] = true
			return answer
			
		var score = calculate_similarity(normalized_input, normalized_answer)
		if score > similarity_threshold and score > best_score:
			best_score = score
			best_match = answer
	
	if best_match:
		best_match["revealed"] = true
		print("[Fuzzy] Znaleziono '%s' jako '%s' (Zgodność: %.2f)" % [player_input, best_match["text"], best_score])
		return best_match
	
	print("[Fuzzy] Nie trafiono: '%s'" % player_input)
	return {}

func normalize_text(text: String) -> String:
	var s = text.strip_edges().to_lower()
	for key in pl_chars:
		s = s.replace(key, pl_chars[key])
	return s

func calculate_similarity(s1: String, s2: String) -> float:
	if s1 == s2: return 1.0
	if s1.length() < 2 or s2.length() < 2: return 0.0
	
	var longer = s1 if s1.length() > s2.length() else s2
	
	var distance = levenshtein_distance(s1, s2)
	return 1.0 - (float(distance) / float(longer.length()))

func levenshtein_distance(s1: String, s2: String) -> int:
	var m = s1.length()
	var n = s2.length()
	
	var d = []
	for i in range(m + 1):
		d.append([])
		for j in range(n + 1):
			d[i].append(0)

	for i in range(m + 1): d[i][0] = i
	for j in range(n + 1): d[0][j] = j

	for i in range(1, m + 1):
		for j in range(1, n + 1):
			var cost = 0 if s1[i - 1] == s2[j - 1] else 1
			d[i][j] = min(
				d[i - 1][j] + 1,      # usunięcie
				d[i][j - 1] + 1,      # wstawienie
				d[i - 1][j - 1] + cost # zamiana
			)
	
	return d[m][n]
