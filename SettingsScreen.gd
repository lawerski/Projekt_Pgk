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
var tts_option: OptionButton
var sfx_slider: HSlider
var tts_slider: HSlider

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
	
	# --- 5. TTS (Dynamic Add) ---
	_add_tts_controls()
	
	# --- 6. Load from file if exists ---
	_load_settings()

func _add_volume_controls():
	# --- MASTER ---
	var label_master = Label.new()
	label_master.text = "Głośność Główna:"
	grid.add_child(label_master)
	
	var slider_master = HSlider.new()
	slider_master.min_value = 0.0
	slider_master.max_value = 1.0
	slider_master.step = 0.05
	
	var bus_idx = AudioServer.get_bus_index("Master")
	var db = AudioServer.get_bus_volume_db(bus_idx)
	slider_master.value = db_to_linear(db)
	
	slider_master.custom_minimum_size = Vector2(200, 30)
	slider_master.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider_master.value_changed.connect(_on_volume_changed)
	grid.add_child(slider_master)
	
	# --- TTS ---
	var label_tts = Label.new()
	label_tts.text = "Głośność Lektora (TTS):"
	grid.add_child(label_tts)
	
	tts_slider = HSlider.new()
	tts_slider.min_value = 0.0
	tts_slider.max_value = 1.0
	tts_slider.step = 0.05
	tts_slider.value = float(TTSManager.tts_volume_percent) / 100.0
	
	tts_slider.custom_minimum_size = Vector2(200, 30)
	tts_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tts_slider.value_changed.connect(_on_tts_volume_changed)
	grid.add_child(tts_slider)
	
	# --- SFX ---
	var label_sfx = Label.new()
	label_sfx.text = "Głośność Dźwięków (SFX):"
	grid.add_child(label_sfx)
	
	sfx_slider = HSlider.new()
	sfx_slider.min_value = 0.0
	sfx_slider.max_value = 1.0
	sfx_slider.step = 0.05
	# Default approximation logic:
	# If SoundManager Main Player is -15dB, that is ~0.17 linear.
	if SoundManager.main_player:
		sfx_slider.value = db_to_linear(SoundManager.main_player.volume_db) # 0 to 1
	else:
		sfx_slider.value = 0.5
		
	sfx_slider.custom_minimum_size = Vector2(200, 30)
	sfx_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sfx_slider.value_changed.connect(_on_sfx_volume_changed)
	grid.add_child(sfx_slider)

func _on_tts_volume_changed(value):
	TTSManager.set_volume(value)

func _on_sfx_volume_changed(value):
	SoundManager.set_volume(value)

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

func _add_tts_controls():
	# Label
	var label = Label.new()
	label.text = "Głos TTS:"
	grid.add_child(label)
	
	# OptionButton
	tts_option = OptionButton.new()
	tts_option.custom_minimum_size = Vector2(250, 30)
	tts_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tts_option.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	
	var voices = DisplayServer.tts_get_voices()
	if voices.is_empty():
		tts_option.add_item("Brak dostępnych głosów", 0)
		tts_option.disabled = true
		grid.add_child(tts_option)
	else:
		var index = 0
		for v in voices:
			var label_text = "%s (%s)" % [v.get("name", "Unknown"), v.get("language", "??")]
			tts_option.add_item(label_text, index)
			# Store voice ID as metadata
			tts_option.set_item_metadata(index, v.get("id"))
			index += 1
		
		# Create a container for Dropdown + Test Button
		var hbox = HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_theme_constant_override("separation", 10)
		
		tts_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(tts_option)
		
		var test_btn = Button.new()
		test_btn.text = "🔊 Testuj"
		test_btn.pressed.connect(_on_test_voice_pressed)
		hbox.add_child(test_btn)
		
		grid.add_child(hbox)

func _on_test_voice_pressed():
	if tts_option and not tts_option.disabled and tts_option.selected >= 0:
		var voice_id = tts_option.get_selected_metadata()
		DisplayServer.tts_stop()
		DisplayServer.tts_speak("Raz, dwa, trzy, próba mikrofonu.", voice_id, 50, 1.0, 1.0)

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
	
	# Save SFX/TTS
	if sfx_slider:
		config.set_value("General", "sfx_volume", sfx_slider.value)
	if tts_slider:
		config.set_value("General", "tts_volume", tts_slider.value)
	
	# Save resolution index
	if res_option:
		config.set_value("General", "resolution_idx", res_option.selected)
	
	# Save TTS voice
	if tts_option and not tts_option.disabled and tts_option.selected >= 0:
		var voice_id = tts_option.get_selected_metadata()
		config.set_value("General", "tts_voice_id", voice_id)
	
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
		
		# SFX Volume
		var sfx_val = config.get_value("General", "sfx_volume", -1.0)
		if sfx_val >= 0.0 and sfx_slider:
			sfx_slider.value = sfx_val
			SoundManager.set_volume(sfx_val)
			
		# TTS Volume
		var tts_val = config.get_value("General", "tts_volume", -1.0)
		if tts_val >= 0.0 and tts_slider:
			tts_slider.value = tts_val
			TTSManager.set_volume(tts_val)
		
		# Update slider visuals (Master is first usually, or we can just fetch it differently)
		# But since we rebuilt the UI, we should update the Master slider explicitly if possible.
		# However, in _add_volume_controls we already set slider.value from AudioServer.
		# So if we set AudioServer volume above, the slider created in _ready (if _ready called load) 
		# Wait, _ready calls: 1. Add controls (which read AudioServer), 2. Load settings.
		# So if Load Settings changes AudioServer, the Slider (created in step 1) will be OUT OF SYNC.
		# We must update the Master slider specifically.
		
		# Find Master slider (It's the 2nd child of grid: Label, Slider, Label, Slider...)
		# Actually safer to look for HSlider among children.
		var sliders = []
		for child in grid.get_children():
			if child is HSlider:
				sliders.append(child)
		
		if sliders.size() > 0:
			sliders[0].value = db_to_linear(vol_db) # Master
		
		# Load TTS voice
		var saved_voice = config.get_value("General", "tts_voice_id", "")
		if saved_voice != "" and tts_option and not tts_option.disabled:
			for i in range(tts_option.item_count):
				if tts_option.get_item_metadata(i) == saved_voice:
					tts_option.selected = i
					break
