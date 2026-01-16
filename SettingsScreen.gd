extends Control

@onready var address_edit = $CenterContainer/VBoxContainer/GridContainer/AddressEdit
@onready var fullscreen_check = $CenterContainer/VBoxContainer/GridContainer/FullscreenCheck
@onready var back_button = $CenterContainer/VBoxContainer/BackButton
@onready var grid = $CenterContainer/VBoxContainer/GridContainer

const SETTINGS_FILE = "user://settings.cfg"

var available_resolutions = [
	Vector2i(1280, 720),
	Vector2i(1366, 768),
	Vector2i(1600, 900),
	Vector2i(1920, 1080),
	Vector2i(2560, 1440)
]
var res_option: OptionButton

func _ready():
	back_button.pressed.connect(_on_back_pressed)
	
	# --- 1. Fullscreen ---
	var mode = DisplayServer.window_get_mode()
	var is_fullscreen = mode == DisplayServer.WINDOW_MODE_FULLSCREEN or mode == DisplayServer.WINDOW_MODE_EXCLUSIVE_FULLSCREEN
	fullscreen_check.button_pressed = is_fullscreen
	fullscreen_check.toggled.connect(_on_fullscreen_toggled)
	
	# --- 2. Address ---
	address_edit.text = NetworkManager.current_address
	
	# --- 3. Volume (Dynamic Add) ---
	_add_volume_controls()
	
	# --- 4. Resolution (Dynamic Add) ---
	_add_resolution_controls()
	
	# --- 5. Load from file if exists ---
	_load_settings()

func _add_volume_controls():
	# Create Label
	var label = Label.new()
	label.text = "Głośność:"
	grid.add_child(label)
	
	# Create Slider
	var slider = HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	
	# Get current volume from Master bus
	var bus_idx = AudioServer.get_bus_index("Master")
	var db = AudioServer.get_bus_volume_db(bus_idx)
	slider.value = db_to_linear(db)
	
	slider.custom_minimum_size = Vector2(200, 30)
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(_on_volume_changed)
	
	grid.add_child(slider)

func _add_resolution_controls():
	# Label
	var label = Label.new()
	label.text = "Rozdzielczość:"
	grid.add_child(label)
	
	# OptionButton
	res_option = OptionButton.new()
	res_option.custom_minimum_size = Vector2(200, 30)
	res_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	
	for i in range(available_resolutions.size()):
		var res = available_resolutions[i]
		res_option.add_item("%d x %d" % [res.x, res.y], i)
		
	# Connect
	res_option.item_selected.connect(_on_resolution_selected)
	grid.add_child(res_option)
	
	# Init state (match current window size)
	var curr_size = DisplayServer.window_get_size()
	for i in range(available_resolutions.size()):
		if available_resolutions[i] == curr_size:
			res_option.selected = i
			break
			
	# Disable if fullscreen
	res_option.disabled = fullscreen_check.button_pressed

func _on_resolution_selected(index):
	var size = available_resolutions[index]
	DisplayServer.window_set_size(size)
	# Center after resize
	var screen_id = DisplayServer.window_get_current_screen()
	var screen_size = DisplayServer.screen_get_size(screen_id)
	var pos = (screen_size - size) / 2
	DisplayServer.window_set_position(pos)

func _on_volume_changed(value):
	var bus_idx = AudioServer.get_bus_index("Master")
	AudioServer.set_bus_volume_db(bus_idx, linear_to_db(value))

func _on_fullscreen_toggled(toggled_on: bool):
	if res_option:
		res_option.disabled = toggled_on
		
	if toggled_on:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_FULLSCREEN)
	else:
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		# Restore resolution from dropdown if returning to windowed
		if res_option and res_option.selected >= 0:
			_on_resolution_selected(res_option.selected)

func _on_back_pressed():
	# Save changes to singleton
	var new_addr = address_edit.text.strip_edges()
	if new_addr != "":
		NetworkManager.current_address = new_addr
	
	# Save to disk
	_save_settings()
	
	get_tree().change_scene_to_file("res://TitleScreen.tscn")

func _save_settings():
	var config = ConfigFile.new()
	config.set_value("General", "address", NetworkManager.current_address)
	config.set_value("General", "fullscreen", fullscreen_check.button_pressed)
	
	var bus_idx = AudioServer.get_bus_index("Master")
	config.set_value("General", "volume_db", AudioServer.get_bus_volume_db(bus_idx))
	
	# Save resolution index
	if res_option:
		config.set_value("General", "resolution_idx", res_option.selected)
	
	config.save(SETTINGS_FILE)

func _load_settings():
	var config = ConfigFile.new()
	var err = config.load(SETTINGS_FILE)
	if err == OK:
		# Address
		var saved_addr = config.get_value("General", "address", "")
		if saved_addr != "":
			NetworkManager.current_address = saved_addr
			address_edit.text = saved_addr
			
		# Fullscreen
		var fs = config.get_value("General", "fullscreen", false)
		fullscreen_check.button_pressed = fs
		_on_fullscreen_toggled(fs) # Apply immediately
		
		# Resolution (if NOT fullscreen)
		if !fs:
			var res_idx = config.get_value("General", "resolution_idx", -1)
			if res_idx >= 0 and res_idx < available_resolutions.size() and res_option:
				res_option.selected = res_idx
				_on_resolution_selected(res_idx)
		
		# Volume
		var vol_db = config.get_value("General", "volume_db", 0.0)
		var bus_idx = AudioServer.get_bus_index("Master")
		AudioServer.set_bus_volume_db(bus_idx, vol_db)
		
		# Update slider visuals
		var slider = grid.get_child(grid.get_child_count() - 2) # Slider is 2nd to last added (before Res Label, Res Option) -> Wait, order changed.
		# Order: Label(Addr), Edit, Label(FS), Check, Label(Vol), Slider, Label(Res), Option
		# So Slider is child index 5 (0-based)
		# Actually safer to look for HSlider
		for child in grid.get_children():
			if child is HSlider:
				child.value = db_to_linear(vol_db)
