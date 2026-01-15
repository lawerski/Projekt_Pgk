# Lobby.gd
extends Control

func _ready():
	# Poprawione łączenie sygnałów (składnia Godot 4)
	if not NetworkManager.host_registered.is_connected(_on_host_registered):
		NetworkManager.host_registered.connect(_on_host_registered)
	
	if not NetworkManager.player_connected.is_connected(_on_player_connected):
		NetworkManager.player_connected.connect(_on_player_connected)
	
	# Rozpocznij połączenie
	NetworkManager.connect_to_relay()
	print("[Lobby] Oczekiwanie na serwer...")

func _on_host_registered(code):
	print(">>> OTRZYMANO KOD POKOJU: ", code, " <<<")
	# Jeśli masz Label w scenie, ustaw go:
	if has_node("RoomCodeLabel"):
		$RoomCodeLabel.text = str(code)

func _on_player_connected(client_id, player_info):
	var p_name = "Nieznany"
	if typeof(player_info) == TYPE_DICTIONARY and player_info.has("name"):
		p_name = player_info.name
		
	print("[Lobby] Dołączył gracz: ", p_name)
	
	# Obsługa awatara
	var avatar_texture = null
	if typeof(player_info) == TYPE_DICTIONARY and player_info.has("avatar_base64"):
		avatar_texture = NetworkManager.base64_to_texture(player_info.avatar_base64)
	
	var avatar_sprite = TextureRect.new()
	if avatar_texture:
		avatar_sprite.texture = avatar_texture
		avatar_sprite.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		avatar_sprite.custom_minimum_size = Vector2(100, 100) # Ustaw stały rozmiar
		
	avatar_sprite.tooltip_text = p_name
	
	if has_node("AvatarsContainer"):
		$AvatarsContainer.add_child(avatar_sprite)
