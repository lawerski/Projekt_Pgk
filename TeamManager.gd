extends Node
class_name TeamManager

signal score_updated(team_idx, new_score)
signal team_name_updated(team_idx, new_name)

var teams: Dictionary = { 0: [], 1: [] }
var team_scores: Dictionary = { 0: 0, 1: 0 }
var captains: Dictionary = { 0: -1, 1: -1 } 
var team_names: Dictionary = { 0: "Drużyna A", 1: "Drużyna B" }

# Zwraca indeks drużyny (0 lub 1) na podstawie ID gracza; jeśli nie znaleziono, zwraca -1
func get_player_team_index(player_id: int) -> int:
	if player_id in teams[0]: return 0
	if player_id in teams[1]: return 1
	return -1 

# Przypisuje gracza o danym ID do określonej drużyny (indeks 0 lub 1), usuwając go wcześniej ze starej drużyny
# Returns TRUE if this player is the first one in the team (Captain candidate)
func set_player_team(player_id: int, team_index):
	team_index = int(team_index)
	if player_id in teams[0]: teams[0].erase(player_id)	
	if player_id in teams[1]: teams[1].erase(player_id)
	
	if teams.has(team_index):
		var is_first = teams[team_index].is_empty()
		teams[team_index].append(player_id)
		return is_first
	return false

# Sets custom team name
func set_team_name(team_idx: int, name: String):
	if name.length() > 0:
		team_names[team_idx] = name
		emit_signal("team_name_updated", team_idx, name)

# Gets team name
func get_team_name(team_idx: int) -> String:
	return team_names.get(team_idx, "Drużyna " + str(team_idx + 1))

# Zwraca ID gracza, który ma podejść do pojedynku w danej drużynie w oparciu o indeks rundy (cykliczna rotacja)
func get_faceoff_player(team_idx: int, round_index: int) -> int:
	var members = teams[team_idx]
	if members.is_empty(): return -1

	var player_idx = round_index % members.size()
	return members[player_idx]

# Ustawia pierwszego gracza z listy w każdej drużynie jako kapitana
func assign_captains():
	if not teams[0].is_empty(): captains[0] = teams[0][0]
	if not teams[1].is_empty(): captains[1] = teams[1][0]

# Zwraca ID kapitana dla danej drużyny
func get_captain_id(team_idx: int) -> int:
	return captains.get(team_idx, -1)

# Dodaje określoną liczbę punktów do wyniku danej drużyny
func add_score(team_idx: int, points: int):
	team_scores[team_idx] += points
	emit_signal("score_updated", team_idx, team_scores[team_idx])

# Sprawdza, czy któraś z drużyn osiągnęła próg 300 punktów i kwalifikuje się do finału
func check_for_finalist() -> int:
	print("[TeamManager] Sprawdzam punkty: A=%d, B=%d (Wymagane: 300)" % [team_scores[0], team_scores[1]])
	if team_scores[0] >= 300: return 0
	if team_scores[1] >= 300: return 1
	return -1 # Zwraca -1, jeśli nikt jeszcze nie wygrał

func reset_state():
	teams = { 0: [], 1: [] }
	team_scores = { 0: 0, 1: 0 }
	captains = { 0: -1, 1: -1 }
	team_names = { 0: "Drużyna A", 1: "Drużyna B" }
	emit_signal("score_updated", 0, 0)
	emit_signal("score_updated", 1, 0)

