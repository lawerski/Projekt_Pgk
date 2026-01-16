extends Control

func _ready():
	$CenterContainer/VBoxContainer/Buttons/PlayButton.pressed.connect(_on_play_pressed)
	$CenterContainer/VBoxContainer/Buttons/SettingsButton.pressed.connect(_on_settings_pressed)
	$CenterContainer/VBoxContainer/Buttons/QuitButton.pressed.connect(_on_quit_pressed)

func _on_play_pressed():
	# Change to Lobby Scene
	get_tree().change_scene_to_file("res://Lobby.tscn")

func _on_settings_pressed():
	# Change to Settings Scene
	get_tree().change_scene_to_file("res://SettingsScreen.tscn")

func _on_quit_pressed():
	get_tree().quit()
