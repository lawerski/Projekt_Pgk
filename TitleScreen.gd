extends Control

func _ready():
	_setup_visuals()
	_setup_fade()
	$CenterContainer/VBoxContainer/Buttons/PlayButton.pressed.connect(_on_play_pressed)
	$CenterContainer/VBoxContainer/Buttons/SettingsButton.pressed.connect(_on_settings_pressed)
	$CenterContainer/VBoxContainer/Buttons/QuitButton.pressed.connect(_on_quit_pressed)
	await _fade_in()

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
			# JeÅ›li to TextureRect, moÅ¼e wymagaÄ‡ jakiejÅ› tekstury (np. Placeholder)
			# GradientTexture2D zadziaÅ‚a jako 'pÅ‚Ã³tno' dla shadera
			if bg_node is TextureRect and not bg_node.texture:
				bg_node.texture = PlaceholderTexture2D.new()

	# 2. Tytuł (Glow & Shadow)
	var title = $CenterContainer/VBoxContainer/TitleLabel
	if title:
		title.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2)) # Gold
		title.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
		title.add_theme_constant_override("shadow_offset_x", 6)
		title.add_theme_constant_override("shadow_offset_y", 6)
		title.add_theme_constant_override("shadow_outline_size", 10)

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

func _fade_out(scene_path):
	var fade = get_node("FadeRect")
	if fade:
		fade.visible = true
		fade.modulate.a = 0.0
		var tween = fade.create_tween()
		tween.tween_property(fade, "modulate:a", 1.0, 0.7).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
		await get_tree().create_timer(0.7).timeout
		if scene_path:
			get_tree().change_scene_to_file(scene_path)
		else:
			get_tree().quit()

func _on_play_pressed():
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_settings_pressed():
	get_tree().change_scene_to_file("res://SettingsScreen.tscn")

func _on_quit_pressed():
	get_tree().quit()

func _style_button(btn: Button):
	# Normal Styling
	var style_normal = StyleBoxFlat.new()
	style_normal.bg_color = Color(0.1, 0.3, 0.8, 0.8) # Royal Blue
	style_normal.border_color = Color(0.4, 0.7, 1.0, 1.0) # Light Blue Border
	style_normal.border_width_top = 2
	style_normal.border_width_left = 2
	style_normal.border_width_right = 2
	style_normal.corner_radius_bottom_left = 12
	style_normal.corner_radius_bottom_right = 12
	style_normal.corner_radius_top_left = 12
	style_normal.corner_radius_top_right = 12
	btn.add_theme_stylebox_override("normal", style_normal)
	# Hover Styling (Brighter)
	var style_hover = style_normal.duplicate()
	style_hover.bg_color = Color(0.2, 0.4, 0.9, 1.0)
	style_hover.border_color = Color(1.0, 0.9, 0.4, 1.0) # Gold border on hover!
	btn.add_theme_stylebox_override("hover", style_hover)
	
	# Pressed Styling (Darker)
	var style_pressed = style_normal.duplicate()
	style_pressed.bg_color = Color(0.05, 0.15, 0.5, 1.0)
	btn.add_theme_stylebox_override("pressed", style_pressed)
	
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.add_theme_font_size_override("font_size", 28)
