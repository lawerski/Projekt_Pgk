extends Control

@onready var game_manager = get_node("/root/Main/GameManager")
@onready var round_manager = game_manager.get_node("RoundManager")

# UI References via unique names or paths
@onready var question_label = $BottomInfo
@onready var answers_vbox = $BoardArea/BoardInner/VBox/AnswerContainer
@onready var score_a_label = $TeamStation_A/Desk/ScorePanel/Label
@onready var score_b_label = $TeamStation_B/Desk/ScorePanel/Label
@onready var name_a_label = $TeamStation_A/Desk/FrontPanel/NameLabel
@onready var name_b_label = $TeamStation_B/Desk/FrontPanel/NameLabel
@onready var round_score_label = $BoardArea/BoardInner/VBox/RoundScore/Score
@onready var team_a_name_label = $TeamStation_A/Desk/FrontPanel/NameLabel
@onready var team_b_name_label = $TeamStation_B/Desk/FrontPanel/NameLabel

@onready var avatars_a_container = $TeamStation_A/Avatars
@onready var avatars_b_container = $TeamStation_B/Avatars
@onready var faceoff_container = $CentralPodium/FaceOffContainer
@onready var host_spot = $HostSpot

@onready var strike_overlay = $StrikeOverlay
@onready var strike_label = $StrikeOverlay/Label
@onready var final_board = $FinalBoard
@onready var game_camera = $GameCamera

# Preload scenes
var answer_row_scene = preload("res://AnswerRow.tscn")

var player_stand_scene = preload("res://PlayerStand.tscn")
var exit_dialog: ConfirmationDialog
var temp_answer_label: Label

var host_jokes = [
	"Jak szybko przemieszcza się burza? – Błyskawicznie!",
	"Co mówi ksiądz po ślubie informatyka? – Pobieranie zakończone!",
	"Co robi chirurg w operze? – Operuje.",
	"Co ile miesięcy chemik jeździ na wakacje? – CO2.",
	"Na czym jeździ papier toaletowy? – Na rolkach.",
	"Jak nazywa się ryba szpiega? – Śledź.",
	"Jak nazywa się twarz matematyka? – Oblicze.",
	"Co robi Jezus na rondzie? – Nawraca.",
	"Jak się nazywa latający kot? – Kotlecik.",
	"Co mówi drwal, gdy za dużo wypije? – Ale się narąbałem.",
	"Co robi dziadek na dyskotece? – Tańczy z laską.",
	"Dlaczego długopisy nie chodzą do szkoły? – Bo się wypisały.",
	"Co robi detektyw podczas czytania książki? – Śledzi tekst.",
	"Czego szuka sprinter w samochodzie? – Biegu.",
	"Co robi skejter w toalecie? – Szaleje na desce.",
	"Co robi krowa na budowie? – Muuuruje.",
	"Co robi żołnierz na sprawdzianie? – Strzela.",
	"Co mówi podłoga po umyciu? – Napastowali mnie.",
	"Co robi mały kościotrup na plaży? – Bawi się łopatką.",
	"Co mówi nauczycielka geografii, gdy wybiera kolor butów? – Morze Czerwone.",
	"Jak nazywa się nieudany żart Arka? – SuchArek.",
	"Jak mnoży Jezus na matematyce? – Na krzyż.",
	"Jak piją wódkę konduktorzy? – Po kolei.",
	"Co robi blondynka w kominie? – Puszcza się z dymem.",
	"Jak żegna się szczur z drugim szczurem? – Paszczur.",
	"Co robi terrorysta na imprezie? – Porywa do tańca.",
	"Jaki jest najsłodszy pies na świecie? – Cukier Pudel.",
	"Co robi blondynka na dnie oceanu? – Czeka na walenie.",
	"Co mówi piłkarz, gdy przychodzi do fryzjera? – Gol.",
	"Gdzie konie wyprawiają bal? – Na balkonie.",
	"Czemu pogrzeby są takie smutne, a urodziny takie wesołe? – Na pogrzebach nie ma tortu.",
	"Dlaczego gmach sejmu jest okrągły? – Bo nikt jeszcze nie widział kwadratowego cyrku.",
	"Jaka jest ulubiona przeglądarka świń? – Google Chrum.",
	"Co robi sprzątaczka na scenie? – Wymiata.",
	"Dlaczego kulturysta chodzi z pudełkiem? – Żeby mógł pakować.",
	"Jak nazywamy działające radio? – Radioaktywne.",
	"Jakie jest ulubione ciasto owiec? – Makowiec.",
	"Jaka roślina boi się najbardziej? – Cykoria.",
	"Jak najłatwiej zabić strusia? – Przestraszyć go na betonie."
]

var current_question_text: String = ""

func _ready():
	print("GameUI Ready")
	
	_setup_host()
	_setup_exit_dialog()
	_setup_pause_screen()
	_setup_visuals()

	# Setup Temp Answer Label
	temp_answer_label = Label.new()
	temp_answer_label.name = "TempAnswerLabel"
	temp_answer_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	temp_answer_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	temp_answer_label.anchors_preset = Control.PRESET_CENTER
	temp_answer_label.anchor_left = 0.5
	temp_answer_label.anchor_right = 0.5
	temp_answer_label.anchor_top = 0.5
	temp_answer_label.anchor_bottom = 0.5
	# Position above board
	temp_answer_label.position = Vector2(0, -500) # Simple offset might not work with anchors if not set correctly
	# Using offsets relative to anchors
	temp_answer_label.offset_left = -400
	temp_answer_label.offset_right = 400
	temp_answer_label.offset_top = -550
	temp_answer_label.offset_bottom = -470
	temp_answer_label.add_theme_font_size_override("font_size", 56)
	temp_answer_label.add_theme_color_override("font_color", Color(1, 1, 0)) # Yellow
	temp_answer_label.add_theme_constant_override("outline_size", 12)
	temp_answer_label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	temp_answer_label.text = ""
	add_child(temp_answer_label)

	if game_manager.has_signal("exit_requested"):
		game_manager.connect("exit_requested", _on_exit_requested)
	
	if game_manager.has_signal("game_paused_players"):
		game_manager.connect("game_paused_players", _on_game_paused)
	if game_manager.has_signal("game_resumed_players"):
		game_manager.connect("game_resumed_players", _on_game_resumed)
	if game_manager.has_signal("host_message"):
		game_manager.connect("host_message", _on_host_message)

	# Connect Signals
	round_manager.connect("round_started", _on_round_started)
	round_manager.connect("answer_revealed", _on_answer_revealed)
	round_manager.connect("strike_occured", _on_strike)
	round_manager.connect("round_bank_updated", _on_bank_updated)
	round_manager.connect("decision_made", _on_decision_made)
	round_manager.connect("round_message", _on_round_message_ui)
	if round_manager.has_signal("player_answer_display"):
		round_manager.connect("player_answer_display", _on_player_answer_display)
	
	TeamManager.connect("score_updated", _on_team_score_updated)
	if TeamManager.has_signal("team_name_updated"):
		TeamManager.connect("team_name_updated", _on_team_name_updated)
	
	# Connect Network listener for avatars
	NetworkManager.connect("player_joined", _on_player_joined)
	NetworkManager.connect("team_chosen", _on_team_updated)
	
	# Listen for player answers to show bubbles
	if not NetworkManager.is_connected("player_answer", Callable(self, "_on_player_answer_spoke")):
		NetworkManager.connect("player_answer", Callable(self, "_on_player_answer_spoke"))
	
	# Connect FinalManager updates
	var fm = game_manager.get_node("FinalManager")
	if fm:
		fm.connect("final_update", _on_final_update)
		fm.connect("final_finished", _on_final_finished)
		# NOTE: We must add this signal to FinalManager or just use final_update generically
		if fm.has_signal("final_state_update"):
			fm.connect("final_state_update", _on_final_state_update)
	
	# Initial population of avatars (for players who joined in Lobby)
	_update_avatars()

	# Initial team name update
	_update_team_labels()
	
	# Initial camera pos (Full board center is roughly 960, 540)
	set_camera_focus("BOARD")

func _update_team_labels():
	if team_a_name_label: team_a_name_label.text = TeamManager.get_team_name(0)
	if team_b_name_label: team_b_name_label.text = TeamManager.get_team_name(1)

# --- CAMERA SYSTEM ---
func set_camera_focus(target_name: String):
	if !game_camera: return
	
	var target_pos = Vector2(960, 540) # Default Center
	var zoom_level = Vector2(1, 1) # Default Zoom
	
	match target_name:
		"BOARD":
			target_pos = Vector2(960, 540)
			zoom_level = Vector2(1, 1)
		"FACEOFF":
			# Zoom on central podium (bottom center)
			target_pos = Vector2(960, 780) 
			zoom_level = Vector2(1.8, 1.8)
		"TEAM_A":
			# Zoom on Team A (Bottom Left)
			target_pos = Vector2(330, 720)
			zoom_level = Vector2(1.5, 1.5)
		"TEAM_B":
			# Zoom on Team B (Bottom Right)
			target_pos = Vector2(1590, 720)
			zoom_level = Vector2(1.5, 1.5)
		"HOST":
			# Zoom on Host (Bottom Center-ish)
			target_pos = Vector2(960, 810)
			zoom_level = Vector2(2.0, 2.0)
	
	var tween = create_tween()
	tween.set_parallel(true)
	tween.tween_property(game_camera, "position", target_pos, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(game_camera, "zoom", zoom_level, 1.5).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

var pause_overlay: ColorRect

func _setup_pause_screen():
	pause_overlay = ColorRect.new()
	pause_overlay.color = Color(0, 0, 0, 0.8)
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.visible = false
	
	var label = Label.new()
	label.text = "Oczekiwanie na graczy...\n(Minimum 2 osoby wymagane)"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	label.add_theme_font_size_override("font_size", 48)
	
	pause_overlay.add_child(label)
	add_child(pause_overlay)

func _on_game_paused():
	# Show interrupt screen
	if pause_overlay:
		pause_overlay.visible = true
		pause_overlay.move_to_front()

func _on_game_resumed():
	if pause_overlay:
		pause_overlay.visible = false

func _on_team_name_updated(team_idx, new_name):
	print("GameUI: Team name updated: ", team_idx, " -> ", new_name)
	_update_team_labels()

func _setup_host():
	var host_stand = player_stand_scene.instantiate()
	host_spot.add_child(host_stand)
	# Use a default texture or load something specific
	host_stand.set_player_data("Prowadzący", preload("res://icon.svg")) 
	host_stand.client_id = -999 # Special ID for host

func _on_host_message(text, duration):
	_host_speak(text, duration)

func _host_speak(text, duration: float = 4.0):
	if host_spot.get_child_count() > 0:
		var host = host_spot.get_child(0)
		if host.has_method("show_bubble"):
			host.show_bubble(text, duration)

func _on_round_started(question_data):
	print("UI: Round Started: ", question_data["question"])
	current_question_text = question_data["question"]
	
	# 1. Reset Board UI immediately
	question_label.text = "..."
	round_score_label.text = "0"
	if strike_overlay:
		strike_overlay.visible = false
	
	# Clear old answers
	if answers_vbox:
		for child in answers_vbox.get_children():
			child.queue_free()
	
	# Create new blank rows immediately (so players see the slots)
	var answers_count = question_data["answers"].size()
	for i in range(answers_count):
		var row = answer_row_scene.instantiate()
		answers_vbox.add_child(row)
		row.set_index(i + 1)
	
	# Host joke
	if host_jokes.size() > 0:
		set_camera_focus("HOST") # Zoom on host for joke
		var joke = host_jokes.pick_random()
		# Joke lasts ~8-9s
		_host_speak(joke, 9.0)
		# Read joke via TTS
		if game_manager and game_manager.has_method("tts_speak"):
			# Slight delay to ensure mode switch logic inside TTSManager (if any) is ready
			game_manager.tts_speak(joke, false) # false = Host voice

	# Update positions for faceoff
	_update_stand_positions()
	
	# Wait for joke to finish (9s)
	await get_tree().create_timer(9.0).timeout
	
	set_camera_focus("FACEOFF") # Zoom on faceoff/podium
	
	# Play Intro/Tension sound
	SoundManager.play_sfx("intro") 
	
	# Host reads the question - GENERIC MESSAGE to avoid spoilers
	_host_speak("Posłuchajcie pytania...", 14.0)
	
	# Wait for reading (14s)
	await get_tree().create_timer(14.0).timeout
	
	# Show on board ONLY if checking answers is done (handled by signals elsewhere now)
	# question_label.text = question_data["question"]
	_host_speak("Kto pierwszy ten lepszy!", 3.0) # To zniknie po 3s, ale Label zostanie

func _on_answer_revealed(answer_data):
	if temp_answer_label:
		temp_answer_label.text = ""

	# REVEAL QUESTION ON BOARD (Safe to show now)
	if current_question_text != "":
		question_label.text = current_question_text

	print("[GameUI] _on_answer_revealed received: ", answer_data)
	
	# Play Sound
	SoundManager.play_sfx("correct")
	
	var text = answer_data["text"]
	var points = answer_data["points"]
	
	# Find which index this answers corresponds to in the original list
	# compare by reference if possible, or by text
	var q = round_manager.current_question
	var index = -1
	
	_host_speak(["Dobrze!", "Brawo!", "Jest na tablicy!", "Tak jest!"].pick_random())

	if q.has("answers"):
		for i in range(q["answers"].size()):
			# Try reference match first
			if q["answers"][i] == answer_data:
				index = i
				break
			# Fallback to text match
			if q["answers"][i]["text"] == text:
				index = i
				break
	
	print("[GameUI] Matched answer to index: ", index)
	
	if index != -1:
		var rows = answers_vbox.get_children()
		if index < rows.size():
			print("[GameUI] Revealing row ", index)
			rows[index].reveal(text, points)
			# Zoom out to see board clearly when answer revealed
			set_camera_focus("BOARD")
			
			# Mini-conffeti for TOP answer (often index 0)
			if index == 0:
				trigger_confetti() # Reward for top answer!
		else:
			print("[GameUI] ERROR: Row index out of bounds! Rows: ", rows.size())
	else:
		print("[GameUI] ERROR: Could not find answer in current_question!")


func _on_round_message_ui(msg):
	if msg is String and msg.begins_with("CZYTANIE_PONOWNE|"):
		if current_question_text != "":
			question_label.text = current_question_text

func _on_bank_updated(amount):
	round_score_label.text = str(amount)

func _on_team_score_updated(team_idx, new_score):
	if team_idx == 0:
		score_a_label.text = str(new_score)
		if new_score > 0: set_camera_focus("TEAM_A")
	else:
		score_b_label.text = str(new_score)
		if new_score > 0: set_camera_focus("TEAM_B")
	
	# Return to board after short delay
	get_tree().create_timer(2.0).timeout.connect(func(): set_camera_focus("BOARD"))

func _on_decision_made(team_name, decision):
	var msg = "Drużyna %s decyduje: %s!" % [team_name, decision]
	_host_speak(msg)
	
	if decision == "GRAMY":
		if team_name == TeamManager.get_team_name(0):
			set_camera_focus("TEAM_A")
		else:
			set_camera_focus("TEAM_B")
	
	# Wait a short moment then return players to desks
	await get_tree().create_timer(2.0).timeout
	_update_stand_positions()

func _on_player_answer_display(text):
	if temp_answer_label:
		temp_answer_label.text = text
		temp_answer_label.add_theme_color_override("font_color", Color(1, 1, 0)) # Reset to Yellow
	
	# Zoom on the answering team? Or Faceoff?
	# RoundManager knows who is answering, but here we just get text.
	# But generally if player speaks, it's nice to see them.
	# We'll leave it for now or implement "active speaker zoom" via TeamManager lookups if needed.

func _on_strike(count):
	strike_label.text = "X".repeat(count)
	strike_overlay.visible = true
	
	# Play Sound
	SoundManager.play_sfx("wrong")
	
	trigger_camera_shake(15.0) # <--- JUICE: CAMERA SHAKE ON ERROR
	
	# Visualize error on the answer label too
	if temp_answer_label:
		temp_answer_label.add_theme_color_override("font_color", Color(1, 0, 0)) # Red
	
	_host_speak(["Niestety nie...", "Pudło!", "Nie ma takiej odpowiedzi."].pick_random())

	# Play sound here if AudioStreamPlayer available
	# WydÅ‚uÅ¼amy wyÅ›wietlanie 'X' (user request: za szybko)
	await get_tree().create_timer(3.0).timeout
	strike_overlay.visible = false
	if temp_answer_label:
		temp_answer_label.text = "" # Clear after strike animation
		temp_answer_label.add_theme_color_override("font_color", Color(1, 1, 0)) # Reset to Yellow
func _setup_visuals():
	# 1. WorldEnvironment (Glow/Bloom)
	var world_env = WorldEnvironment.new()
	var env = Environment.new()
	env.background_mode = Environment.BG_CANVAS
	env.glow_enabled = true
	# --- FIX: Zmniejszamy intensywnoÅ›Ä‡ glow, bo byÅ‚o "za jasno" ---
	env.set("glow_levels/1", 0.0)
	env.set("glow_levels/2", 0.0)
	env.set("glow_levels/3", 0.6) # Tylko Å›rednie detale
	env.set("glow_levels/5", 0.2)
	env.glow_intensity = 0.5   # Zmniejszono z 1.0
	env.glow_strength = 0.85   # Zmniejszono z 0.95
	env.glow_bloom = 0.0       # Bloom czÄ™sto przepala biel
	env.glow_blend_mode = Environment.GLOW_BLEND_MODE_SOFTLIGHT # Åagodniejsze mieszanie niÅ¼ SCREEN
	env.glow_hdr_threshold = 0.9 # WyÅ¼szy prÃ³g, Å¼eby Å›wieciÅ‚y tylko bardzo jasne rzeczy
	world_env.environment = env
	add_child(world_env)
	
	# 2. Styl Tablicy (Board)
	# Szukamy BoardInner lub Panelu tła
	if has_node("BoardArea/BoardInner"):
		var board = get_node("BoardArea/BoardInner")
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.01, 0.02, 0.15, 0.95) # Jeszcze ciemniejszy granat dla kontrastu
		style.border_width_bottom = 8
		style.border_width_left = 8
		style.border_width_right = 8
		style.border_width_top = 8
		style.border_color = Color(0.8, 0.6, 0.1, 1.0) # Złota ramka
		style.corner_radius_bottom_left = 15
		style.corner_radius_bottom_right = 15
		style.corner_radius_top_left = 15
		style.corner_radius_top_right = 15
		style.shadow_color = Color(0,0,0, 0.8)
		style.shadow_size = 50
		board.add_theme_stylebox_override("panel", style)

	# 3. Label Settings (Cienie pod tekstem)
	_apply_text_shadows(self)

func _apply_text_shadows(node):
	for child in node.get_children():
		if child is Label:
			_style_label(child)
		_apply_text_shadows(child)

func _style_label(lbl: Label):
	# Doda cień i outline
	if not lbl.label_settings:
		var settings = LabelSettings.new()
		settings.font_size = lbl.get_theme_font_size("font_size")
		if settings.font_size <= 0: settings.font_size = 24 # Fallback
		
		# Kolor bazowy (zachowaj istniejący jeśli nadpisany, inaczej biały)
		if lbl.has_theme_color_override("font_color"):
			settings.font_color = lbl.get_theme_color("font_color")
		else:
			settings.font_color = Color.WHITE
			
		settings.outline_size = 4
		settings.outline_color = Color.BLACK
		settings.shadow_size = 8
		settings.shadow_color = Color(0,0,0,0.6)
		settings.shadow_offset = Vector2(2, 2)
		lbl.label_settings = settings
	else:
		# Tylko update
		lbl.label_settings.shadow_size = 8
		lbl.label_settings.shadow_color = Color(0,0,0,0.6)
# --- Final Round Handlers ---

# --- Final Round Handlers ---

func _on_final_update(q_text, time_left, current_score):
	# Show final board if not visible
	if !final_board.visible:
		final_board.visible = true
		final_board.setup_rows(5)
	
	final_board.update_info(q_text, time_left, current_score)

func _on_final_state_update(results_data):
	final_board.update_rows_data(results_data)

func _on_final_finished(total, won):
	if won:
		final_board.show_message("WYGRANA! %d pkt" % total)
		final_board.score_label.add_theme_color_override("font_color", Color.GREEN)
		trigger_confetti() # <--- JUICE
	else:
		final_board.show_message("KONIEC! %d pkt" % total)

# --- JUICE MECHANICS (Camera Shake & Confetti) ---
var shake_strength: float = 0.0
var confetti_scene = preload("res://Confetti.tscn")

func _process(delta):
	# Camera Shake decay
	if shake_strength > 0:
		if game_camera:
			game_camera.offset = Vector2(randf_range(-shake_strength, shake_strength), randf_range(-shake_strength, shake_strength))
		
		shake_strength = move_toward(shake_strength, 0, delta * 30.0) # Decay
	else:
		if game_camera and game_camera.offset != Vector2.ZERO:
			game_camera.offset = Vector2.ZERO

func trigger_camera_shake(strength: float = 15.0):
	shake_strength = strength

func trigger_confetti():
	var confetti = confetti_scene.instantiate()
	add_child(confetti)
	confetti.position = Vector2(960, 0) # Top center
	confetti.emitting = true
	# Auto remove after lifetime
	await get_tree().create_timer(5.0).timeout
	confetti.queue_free()

# --- Avatars Logic ---

func _on_player_joined(client_id, team):
	_update_avatars()

func _on_team_updated(client_id, team):
	_update_avatars()

func _update_avatars():
	# Clear existing
	for child in avatars_a_container.get_children(): child.queue_free()
	for child in avatars_b_container.get_children(): child.queue_free()
	
	# Rebuild from NetworkManager data
	var team0_ids = NetworkManager.team_to_clients.get(0, [])
	var team1_ids = NetworkManager.team_to_clients.get(1, [])
	
	print("[GameUI] Updating avatars. Team A: ", team0_ids.size(), " players. Team B: ", team1_ids.size(), " players.")
	
	# Team A (0)
	for i in range(team0_ids.size()):
		var cid = team0_ids[i]
		var stand = _create_player_stand(cid, avatars_a_container)
		if stand: stand.set_visual_index(i)
		
	# Team B (1)
	for i in range(team1_ids.size()):
		var cid = team1_ids[i]
		var stand = _create_player_stand(cid, avatars_b_container)
		if stand: stand.set_visual_index(i)
	
	# Reposition if round is active
	call_deferred("_update_stand_positions")

func _update_stand_positions():
	# Retrieve current faceoff players
	var p1 = round_manager.faceoff_p1
	var p2 = round_manager.faceoff_p2
	
	print("[GameUI] Updating positions. Faceoff: ", p1, " vs ", p2)
	
	# Iterate all stands we know of
	var all_stands = []
	for c in avatars_a_container.get_children(): all_stands.append(c)
	for c in avatars_b_container.get_children(): all_stands.append(c)
	for c in faceoff_container.get_children(): all_stands.append(c)
	
	for stand in all_stands:
		if not ("client_id" in stand): continue
		
		# Robust ID handling
		var stand_cid = stand.client_id
		var stand_pid = -1
		
		# Determine Player ID (int) from stand's client_id (String/Int)
		if typeof(stand_cid) == TYPE_STRING:
			stand_pid = int(NetworkManager.client_to_player_id.get(stand_cid, -1))
		elif typeof(stand_cid) == TYPE_INT or typeof(stand_cid) == TYPE_FLOAT:
			stand_pid = int(stand_cid)
			
		var p1_int = int(p1)
		var p2_int = int(p2)
		
		var target_parent = null
		
		# Check if this player is in faceoff (Compare PIDs)
		if stand_pid != -1 and (stand_pid == p1_int or stand_pid == p2_int):
			target_parent = faceoff_container
		else:
			# Not in faceoff - Check Team
			var team = -1
			if typeof(stand_cid) == TYPE_STRING:
				# Use client ID to look up team
				team = int(NetworkManager.client_to_team.get(stand_cid, -1))
			elif typeof(stand_cid) == TYPE_INT:
				# Maybe we can look up via player_id if needed, but client_id is preferred key
				pass
				
			if team == 0:
				target_parent = avatars_a_container
			elif team == 1:
				target_parent = avatars_b_container
		
		# If parent is different, reparent
		if target_parent and stand.get_parent() != target_parent:
			stand.reparent(target_parent)

func _create_player_stand(client_id, container):
	var data = NetworkManager.players_data.get(client_id, {})
	var nick = data.get("nickname", "Gracz")
	var avatar_b64 = data.get("avatar", "")
	
	var stand = player_stand_scene.instantiate()
	container.add_child(stand)
	stand.client_id = client_id
	
	var texture = null
	if avatar_b64 != "":
		texture = base64_to_texture(avatar_b64)
	
	stand.set_player_data(nick, texture)
	return stand

func _on_player_answer_spoke(player_id, answer_text):
	# The signal transmits player_id (int), but stands are indexed by client_id (String)
	var client_id = NetworkManager.get_client_id(player_id)
	
	# Find the stand and show bubble
	var stand = _find_stand_by_id(client_id)
	if stand:
		stand.show_bubble(answer_text)

func _find_stand_by_id(client_id) -> Node:
	var cid_str = str(client_id)
	for child in avatars_a_container.get_children():
		if "client_id" in child and str(child.client_id) == cid_str:
			return child
	for child in avatars_b_container.get_children():
		if "client_id" in child and str(child.client_id) == cid_str:
			return child
	for child in faceoff_container.get_children():
		if "client_id" in child and str(child.client_id) == cid_str:
			return child
	return null

# Helper to decode base64
func base64_to_texture(base64_string: String) -> ImageTexture:
	if "base64," in base64_string:
		var parts = base64_string.split("base64,")
		if parts.size() > 1:
			base64_string = parts[1]
	
	var image = Image.new()
	var err = image.load_png_from_buffer(Marshalls.base64_to_raw(base64_string))
	if err != OK: 
		# If loading failed, return null (GameUI or PlayerStand can handle defaults)
		return null
	return ImageTexture.create_from_image(image)

func _setup_exit_dialog():
	exit_dialog = ConfirmationDialog.new()
	exit_dialog.title = "Wyjście"
	exit_dialog.dialog_text = "Czy na pewno chcesz wyjść do Lobby?\nGra zostanie przerwana."
	exit_dialog.ok_button_text = "Tak"
	exit_dialog.cancel_button_text = "Nie"
	exit_dialog.initial_position = Window.WINDOW_INITIAL_POSITION_CENTER_MAIN_WINDOW_SCREEN
	exit_dialog.confirmed.connect(_on_exit_confirmed)
	add_child(exit_dialog)

func _on_exit_requested():
	exit_dialog.popup_centered()

func _on_exit_confirmed():
	game_manager.quit_to_lobby()
