extends Node
class_name TeamManager

# teams = { 0: [id1, id2, id3], 1: [id4, id5, id6] }
var teams: Dictionary = { 0: [], 1: [] }
var team_scores: Dictionary = { 0: 0, 1: 0 }
var captains: Dictionary = { 0: -1, 1: -1 } # ID kapitanów

# --- FUNKCJA, KTÓREJ BRAKOWAŁO (NAPRAWA BŁĘDU) ---
func get_player_team_index(player_id: int) -> int:
	if player_id in teams[0]: return 0
	if player_id in teams[1]: return 1
	return -1 # Gracz nie ma drużyny

# --- POZOSTAŁE FUNKCJE ---

# Przypisanie gracza do drużyny (API dla UI/Sieci)
func set_player_team(player_id: int, team_index: int):
	# Usuń ze starej (jeśli był)
	if player_id in teams[0]: teams[0].erase(player_id)
	if player_id in teams[1]: teams[1].erase(player_id)
	
	# Dodaj do nowej
	if teams.has(team_index):
		teams[team_index].append(player_id)

# Zwraca ID gracza, który ma podejść do pojedynku w danej rundzie
# round_index zaczynamy od 0 (Runda 1 = index 0)
func get_faceoff_player(team_idx: int, round_index: int) -> int:
	var members = teams[team_idx]
	if members.is_empty(): return -1
	# Modulo sprawia, że jeśli rund jest więcej niż graczy, kolejka wraca do pierwszego
	var player_idx = round_index % members.size()
	return members[player_idx]

# Ustawienie pierwszego gracza jako kapitana (domyślne)
func assign_captains():
	if not teams[0].is_empty(): captains[0] = teams[0][0]
	if not teams[1].is_empty(): captains[1] = teams[1][0]

func get_captain_id(team_idx: int) -> int:
	return captains.get(team_idx, -1)

func add_score(team_idx: int, points: int):
	team_scores[team_idx] += points

func check_for_finalist() -> int:
	print("[TeamManager] Sprawdzam punkty: A=%d, B=%d (Wymagane: 300)" % [team_scores[0], team_scores[1]])
	if team_scores[0] >= 300: return 0
	if team_scores[1] >= 300: return 1
	return -1 # Nikt jeszcze nie wygrał
