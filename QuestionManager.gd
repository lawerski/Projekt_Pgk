extends Node

const QUESTIONS_FILE = "res://questions.json"

var all_questions: Array = []
var current_pool: Array = []
var used_question_ids: Array = []

# Konfiguracja czułości (Duże litery to dobra praktyka dla stałych)
const SIMILARITY_THRESHOLD = 0.6 
const PL_CHARS = {
	"ą": "a", "ć": "c", "ę": "e", "ł": "l", "ń": "n", "ó": "o", "ś": "s", "ź": "z", "ż": "z"
}

func _ready():
	load_questions()

func load_questions():
	if not FileAccess.file_exists(QUESTIONS_FILE):
		printerr("[QuestionManager] Błąd: Plik questions.json nie istnieje")
		return
	
	var file = FileAccess.open(QUESTIONS_FILE, FileAccess.READ)
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
	used_question_ids.append(selected_question["id"])
	
	print("[QuestionManager] Wylosowano pytanie ID: %d: %s" % [selected_question.get("id"), selected_question.get("question")])
	
	return selected_question

# --- GŁÓWNA LOGIKA SPRAWDZANIA ODPOWIEDZI ---

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
		
		# 1. Dokładne dopasowanie
		if normalized_input == normalized_answer:
			# answer["revealed"] = true  <-- To teraz robi funkcja reveal_answer
			return answer 
			
		# 2. Fuzzy logic
		var score = calculate_similarity(normalized_input, normalized_answer)
		if score > SIMILARITY_THRESHOLD and score > best_score:
			best_score = score
			best_match = answer
	
	if best_match:
		# best_match["revealed"] = true <-- To teraz robi funkcja reveal_answer
		print("[Fuzzy] Znaleziono '%s' jako '%s' (Zgodność: %.2f)" % [player_input, best_match["text"], best_score])
		return best_match
	
	print("[Fuzzy] Nie trafiono: '%s'" % player_input)
	return {}

# --- BRAKUJĄCE FUNKCJE (TO NAPRAWIA BŁĄD) ---

# Tę funkcję woła RoundManager po poprawnej odpowiedzi
func reveal_answer(answer_dict: Dictionary):
	answer_dict["revealed"] = true

# Tę funkcję woła RoundManager, aby sprawdzić czy kończyć rundę
func are_all_revealed_in_question(question_data: Dictionary) -> bool:
	if not question_data.has("answers"): return false
	for ans in question_data["answers"]:
		if not ans.get("revealed", false):
			return false
	return true

# --- LOGIKA FINAŁU ---

func get_questions_exclude_used(count: int) -> Array:
	var available = []
	
	# 1. Szukamy pytań, które NIE były użyte
	for q in all_questions:
		if not q["id"] in used_question_ids:
			available.append(q)
	
	# 2. ZABEZPIECZENIE: Jeśli pytań jest za mało (np. mały JSON), bierzemy wszystkie jak leci
	if available.size() < count:
		print("[QuestionManager] Uwaga: Za mało unikalnych pytań (%d). Dobieram z użytych." % available.size())
		# Dodajemy brakujące z puli wszystkich (pomijając te co już mamy w available)
		for q in all_questions:
			if not q in available:
				available.append(q)
	
	available.shuffle()
	
	var result = []
	# Pobieramy tyle ile trzeba (lub max ile mamy)
	for i in range(min(count, available.size())):
		var q_copy = available[i].duplicate(true) # Głęboka kopia, żeby nie psuć oryginału
		reset_question_state(q_copy) # WAŻNE: Czyścimy flagi 'revealed'
		result.append(q_copy)
		
		# Oznaczamy jako użyte (jeśli jeszcze nie było)
		if not available[i]["id"] in used_question_ids:
			used_question_ids.append(available[i]["id"])
		
	return result

# DODAJ TĘ FUNKCJĘ POMOCNICZĄ (na dole pliku):
func reset_question_state(question: Dictionary):
	if question.has("answers"):
		for ans in question["answers"]:
			ans["revealed"] = false

func check_answer_final(input_text: String, question_data: Dictionary) -> Dictionary:
	var normalized_input = normalize_text(input_text)
	var best_match = null
	var best_score = 0.0

	for answer in question_data["answers"]:
		var normalized_answer = normalize_text(answer["text"])
		
		# 1. Exact match
		if normalized_input == normalized_answer:
			return answer

		# 2. Fuzzy match
		var score = calculate_similarity(normalized_input, normalized_answer)
		if score > SIMILARITY_THRESHOLD and score > best_score:
			best_score = score
			best_match = answer

	if best_match:
		return best_match
		
	return {}

# --- ALGORYTMY POMOCNICZE ---

func normalize_text(text: String) -> String:
	var s = text.strip_edges().to_lower()
	for key in PL_CHARS:
		s = s.replace(key, PL_CHARS[key])
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
				d[i - 1][j] + 1,
				d[i][j - 1] + 1,
				d[i - 1][j - 1] + cost
			)
	
	return d[m][n]
