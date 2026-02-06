extends Control

@onready var room_code_label = $VBoxContainer/InfoHBox/RoomCodeLabel
@onready var container_a = $VBoxContainer/TeamsSplit/TeamA/Scroll/Container
@onready var container_b = $VBoxContainer/TeamsSplit/TeamB/Scroll/Container
@onready var label_team_a = $VBoxContainer/TeamsSplit/TeamA/Header/Label
@onready var label_team_b = $VBoxContainer/TeamsSplit/TeamB/Header/Label
@onready var start_button = $VBoxContainer/StartGameButton

func _ready():
	print("[Lobby] Init")
	_setup_visuals()
	_setup_fade()
	await _fade_in()

	# Connect Button
	start_button.pressed.connect(_on_start_game_pressed)

	# Network signals
	if not NetworkManager.host_registered.is_connected(_on_host_registered):
		NetworkManager.host_registered.connect(_on_host_registered)

	if not NetworkManager.player_joined.is_connected(_on_player_joined):
		NetworkManager.player_joined.connect(_on_player_joined)

	if not NetworkManager.team_chosen.is_connected(_on_team_chosen):
		NetworkManager.team_chosen.connect(_on_team_chosen)

	if not NetworkManager.team_name_received.is_connected(_on_team_name_received):
		NetworkManager.team_name_received.connect(_on_team_name_received)

	if not NetworkManager.player_left.is_connected(_on_player_left):
		NetworkManager.player_left.connect(_on_player_left)

	# Connect if needed
	if not NetworkManager.connected:
		NetworkManager.connect_to_relay()
	else:
		_on_host_registered(NetworkManager.room_code)
		_update_list()

func _setup_fade():
	if not has_node("FadeRect"):
		var fade = ColorRect.new()
		fade.name = "FadeRect"
		fade.color = Color(0,0,0,1)
		fade.anchor_left = 0
		fade.anchor_top = 0
		fade.anchor_right = 1
		fade.anchor_bottom = 1
		fade.z_index = 100
		add_child(fade)
		fade.visible = true

func _fade_in():
	var fade = get_node("FadeRect")
	if fade:
		fade.visible = true
		fade.modulate.a = 1.0
		var tween = fade.create_tween()
		tween.tween_property(fade, "modulate:a", 0.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		await get_tree().create_timer(0.7).timeout
		fade.visible = false

func _on_host_registered(code):
	room_code_label.text = str(code)

func _input(event):
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		# Reset lobby session logic in NetworkManager
		NetworkManager.reset_session()
		# Powrót do menu głównego
		get_tree().change_scene_to_file("res://TitleScreen.tscn")

func _on_player_joined(client_id, team):
	_update_list()

func _on_team_chosen(client_id, team):
	_update_list()
	
	# Check if this player is the first in the team
	if NetworkManager.client_to_player_id.has(client_id):
		var pid = NetworkManager.client_to_player_id[client_id]
		# Logic is tricky here because _update_list reads from NetworkManager.players_data
		# But TeamManager might not be synced yet if I don't call it.
		# Ideally NetworkManager (or GameManager) calls TeamManager. 
		# But we are in Lobby.gd. 
		# Let's check TeamManager for first player status
		# Note: TeamManager.set_player_team returns is_first.
		# But who calls set_player_team? GameManager usually.
		# Let's just check the count in TeamManager
		var is_first = TeamManager.set_player_team(pid, team)
		if is_first:
			NetworkManager.send_to_client(client_id, { "type": "request_team_name" })

func _on_team_name_received(client_id, name):
	print("[Lobby] Team name received: ", name)
	if NetworkManager.client_to_player_id.has(client_id):
		var pid = NetworkManager.client_to_player_id[client_id]
		var team_idx = TeamManager.get_player_team_index(pid)
		if team_idx != -1:
			TeamManager.set_team_name(team_idx, name)
			_update_team_labels()

func _update_team_labels():
	if label_team_a: label_team_a.text = TeamManager.get_team_name(0)
	if label_team_b: label_team_b.text = TeamManager.get_team_name(1)

func _update_list():
	print("[Lobby] Updating player list. Players: ", NetworkManager.players_data.keys().size())
	
	# Clear old children
	for child in container_a.get_children(): child.queue_free()
	for child in container_b.get_children(): child.queue_free()
	
	for client_id in NetworkManager.players_data.keys():
		var data = NetworkManager.players_data[client_id]
		var nick = data.get("nickname", "Gość")
		var avatar_b64 = data.get("avatar", "")
		
		# Safer retrieval and casting
		var team = -1
		if NetworkManager.client_to_team.has(client_id):
			team = int(NetworkManager.client_to_team[client_id])
		
		# Build Player Card
		var vbox = VBoxContainer.new()
		vbox.custom_minimum_size = Vector2(100, 130)
		vbox.alignment = BoxContainer.ALIGNMENT_CENTER
		
		# Avatar container
		var avatar_bg = ColorRect.new()
		avatar_bg.custom_minimum_size = Vector2(80, 80)
		avatar_bg.color = Color(0.2, 0.2, 0.2)
		
		var tex_rect = TextureRect.new()
		tex_rect.custom_minimum_size = Vector2(80, 80)
		tex_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		
		avatar_bg.add_child(tex_rect)
		
		if avatar_b64 != "":
			var tex = _base64_to_texture(avatar_b64)
			if tex: 
				tex_rect.texture = tex
			else:
				tex_rect.texture = preload("res://icon.svg")
		else:
			tex_rect.texture = preload("res://icon.svg")
		
		var label = Label.new()
		label.text = nick
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.add_theme_font_size_override("font_size", 14)
		label.clip_text = true
		label.custom_minimum_size.x = 100
		
		vbox.add_child(avatar_bg)
		vbox.add_child(label)
		
		# Add to correct team container
		if team == 0:
			container_a.add_child(vbox)
		else:
			container_b.add_child(vbox)
	
	# Check for minimum players
	var player_count = NetworkManager.players_data.keys().size()
	start_button.disabled = player_count < 2
	if player_count < 2:
		start_button.text = "Oczekiwanie na graczy (%d/2)" % player_count
	else:
		start_button.text = "START GRY"

func _on_start_game_pressed():
	if NetworkManager.players_data.keys().size() < 2:
		print("Not enough players!")
		return
		
	# Switch to Game
	get_tree().change_scene_to_file("res://Main.tscn")

func _base64_to_texture(base64_string: String) -> ImageTexture:
	if "base64," in base64_string:
		var parts = base64_string.split("base64,")
		if parts.size() > 1:
			base64_string = parts[1]
	
	var image = Image.new()
	var err = image.load_png_from_buffer(Marshalls.base64_to_raw(base64_string))
	if err != OK: return null
	return ImageTexture.create_from_image(image)

func _on_player_left(client_id):
	print("[Lobby] Player left: ", client_id)
	# Remove from NetworkManager data structures already handled in NetworkManager
	# Just update UI and TeamManager mapping
	if NetworkManager.client_to_player_id.has(client_id):
		var pid = NetworkManager.client_to_player_id[client_id]
		# Remove from TeamManager if present
		# Remove player from team list
		var team_idx = TeamManager.get_player_team_index(pid)
		if team_idx != -1:
			TeamManager.teams[team_idx].erase(pid)
			TeamManager.assign_captains()
	_update_list()

func _setup_visuals():
	# 1. Tło (Animowany Shader)
	if has_node("Background"):
		var bg_node = get_node("Background")
		# UÅ¼yj stworzonego shadera zamiast gradientu
		var shader = load("res://Background.gdshader")
		if shader:
			var mat = ShaderMaterial.new()
			mat.shader = shader
			bg_node.material = mat

	# 2. Tytuł
	var title = $VBoxContainer/Title
	title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.2)) # Gold
	title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 1))
	title.add_theme_constant_override("shadow_offset_y", 4)

	# 3. Panele Drużyn (Glassy)
	_style_team_header($VBoxContainer/TeamsSplit/TeamA/Header, Color(0.1, 0.3, 0.8, 0.8)) # Blue Team
	_style_team_header($VBoxContainer/TeamsSplit/TeamB/Header, Color(0.8, 0.1, 0.1, 0.8)) # Red Team

	# 4. Przycisk Start
	if start_button:
		var style = StyleBoxFlat.new()
		style.bg_color = Color(0.0, 0.5, 0.1, 1.0) # Green
		style.border_width_bottom = 4
		style.border_color = Color(0.0, 0.7, 0.2, 1.0)
		style.corner_radius_bottom_left = 8
		style.corner_radius_bottom_right = 8
		style.corner_radius_top_left = 8
		style.corner_radius_top_right = 8
		start_button.add_theme_stylebox_override("normal", style)

func _style_team_header(panel: PanelContainer, bg_color: Color):
	var style = StyleBoxFlat.new()
	style.bg_color = bg_color
	style.border_width_bottom = 2
	style.border_color = Color(1,1,1,0.3)
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	panel.add_theme_stylebox_override("panel", style)
