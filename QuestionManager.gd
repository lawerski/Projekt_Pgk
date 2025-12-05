extends Node

const QUESTIONS_FILE = "res://questions.json"

var all_questions: Array = []
var current_pool: Array = []
var used_question_ids: Array = []

const SIMILARITY_THRESHOLD = 0.65 
const PL_CHARS = {"ą":"a", "ć":"c", "ę":"e", "ł":"l", "ń":"n", "ó":"o", "ś":"s", "ź":"z", "ż":"z"}

# Zamienia tekst na małe litery, usuwa białe znaki z brzegów i zamienia polskie znaki na zwykłe
func normalize_text(text: String) -> String:
	var s = text.strip_edges().to_lower()
	for key in PL_CHARS:
		s = s.replace(key, PL_CHARS[key])
	return s

# Oblicza procentowe podobieństwo (0.0-1.0) dwóch ciągów znaków na podstawie ich odległości Levenshteina
func calculate_similarity(s1: String, s2: String) -> float:
	if s1 == s2: return 1.0
	if s1.length() < 2 or s2.length() < 2: return 0.0
	var longer = s1 if s1.length() > s2.length() else s2
	var distance = levenshtein_distance(s1, s2)
	return 1.0 - (float(distance) / float(longer.length()))

# Oblicza minimalną liczbę operacji edycji (wstawienie, usunięcie, zamiana) potrzebnych do przekształcenia jednego ciągu w drugi
func levenshtein_distance(s1: String, s2: String) -> int:
	var m = s1.length()
	var n = s2.length()
	var d = []
	for i in range(m + 1):
		d.append([])
		for j in range(n + 1): d[i].append(0)
	for i in range(m + 1): d[i][0] = i
	for j in range(n + 1): d[0][j] = j
	for i in range(1, m + 1):
		for j in range(1, n + 1):
			var cost = 0 if s1[i - 1] == s2[j - 1] else 1
			d[i][j] = min(d[i - 1][j] + 1, d[i][j - 1] + 1, d[i - 1][j - 1] + cost)
	return d[m][n]

# Oznacza konkretną odpowiedź w strukturze danych jako odgadniętą (revealed)
func reveal_answer(answer_dict: Dictionary):
	answer_dict["revealed"] = true

# Sprawdza, czy wszystkie odpowiedzi w danym pytaniu zostały już odgadnięte
func are_all_revealed_in_question(question_data: Dictionary) -> bool:
	if not question_data.has("answers"): return false
	for ans in question_data["answers"]:
		if not ans.get("revealed", false):
			return false
	return true

# Resetuje flagę odgadnięcia dla wszystkich odpowiedzi w pytaniu (używane przy recyklingu pytań)
func reset_question_state(question: Dictionary):
	if question.has("answers"):
		for ans in question["answers"]:
			ans["revealed"] = false

# Funkcja startowa silnika Godot, inicjalizuje menedżera i wczytuje pytania przy starcie
func _ready():
	print("[QuestionManager] Inicjalizacja (Tryb Lokalny - Synonimy)...")
	load_questions()

# Wczytuje dane z pliku JSON, parsuje je i zapisuje do tablicy pytań
func load_questions():
	if not FileAccess.file_exists(QUESTIONS_FILE):
		printerr("[QuestionManager] BŁĄD: Brak pliku questions.json!")
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
			print("[QuestionManager] Wczytano %d pytań." % all_questions.size())
		else:
			printerr("[QuestionManager] Błąd: JSON musi być tablicą!")
	else:
		printerr("[QuestionManager] Błąd JSON: ", json.get_error_message())

# Pobiera losowe pytanie z puli, jeżeli pytania się wyczerpią to resetuje liste użytych pytań
func get_random_question() -> Dictionary:
	if current_pool.is_empty():
		current_pool = all_questions.duplicate()
		if current_pool.is_empty(): return {}
	
	var idx = randi() % current_pool.size()
	var q = current_pool.pop_at(idx)
	used_question_ids.append(q["id"])
	
	print("[QuestionManager] Pytanie ID %d: %s" % [q.get("id"), q.get("question")])
	return q

# Asynchronicznie sprawdza poprawność odpowiedzi gracza (dokładnie i rozmycie), uwzględniając synonimy i sztuczne opóźnienie
func check_answer(player_input: String, current_question: Dictionary) -> Dictionary:
	await get_tree().create_timer(1.5).timeout

	if current_question.is_empty() or not current_question.has("answers"):
		return {}
	
	var normalized_input = normalize_text(player_input)
	var found_answer = null
	var match_info = ""
	
	for answer in current_question["answers"]:
		if answer.get("revealed", false):
			continue
		
		var allowed_words = [answer["text"]]
		if answer.has("synonyms"):
			allowed_words.append_array(answer["synonyms"])
			
		for word in allowed_words:
			var normalized_word = normalize_text(word)
			
			if normalized_input == normalized_word:
				found_answer = answer
				match_info = "Dokładne: " + word
				break
			
			var score = calculate_similarity(normalized_input, normalized_word)
			if score > SIMILARITY_THRESHOLD:
				found_answer = answer
				match_info = "Fuzzy (%.2f): %s" % [score, word]
				break
		
		if found_answer:
			break
	
	if found_answer:
		print("[Check] ZALICZONO [%s] -> %s" % [match_info, found_answer["text"]])
		return found_answer
	
	print("[Check] PUDŁO: '%s'" % player_input)
	return {}

# Przygotowuje pulę unikalnych pytań dla rundy finałowej, unikając powtórzeń z gry głównej jeśli to możliwe
func get_questions_exclude_used(count: int) -> Array:
	var av = []
	for q in all_questions:
		if not q["id"] in used_question_ids: av.append(q)
	
	if av.size() < count:
		for q in all_questions: if not q in av: av.append(q)
	
	av.shuffle()
	
	var result = []
	for i in range(min(count, av.size())):
		var q_copy = av[i].duplicate(true)
		reset_question_state(q_copy)
		result.append(q_copy)
		used_question_ids.append(av[i]["id"])
		
	return result

# Synchronicznie sprawdza odpowiedź w rundzie finałowej, używając tej samej logiki dopasowania co w grze głównej
func check_answer_final(input_text: String, question_data: Dictionary) -> Dictionary:
	var normalized_input = normalize_text(input_text)
	
	for answer in question_data["answers"]:
		var allowed_words = [answer["text"]]
		if answer.has("synonyms"): allowed_words.append_array(answer["synonyms"])
		
		for word in allowed_words:
			var nw = normalize_text(word)
			if normalized_input == nw: return answer
			if calculate_similarity(normalized_input, nw) > SIMILARITY_THRESHOLD: return answer
			
	return {}
