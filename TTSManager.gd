extends Node

var available_voices = []
var current_voice_id = ""
var tts_volume_percent = 100

func _ready():
	available_voices = DisplayServer.tts_get_voices()
	print("Dostępne głosy TTS: ", available_voices)
	
	# Wybór polskiego głosu jeśli dostępny
	for voice in available_voices:
		if "pl" in voice["language"]:
			current_voice_id = voice["id"]
			break
			
	if current_voice_id == "" and not available_voices.is_empty():
		current_voice_id = available_voices[0]["id"]
		
	# Wczytaj z ustawień jeśli istnieje
	var config = ConfigFile.new()
	var err = config.load("user://settings.cfg")
	if err == OK:
		var saved_voice = config.get_value("General", "tts_voice_id", "")
		# Sprawdź czy zapisany głos nadal istnieje
		if saved_voice != "":
			var exists = false
			for v in available_voices:
				if v["id"] == saved_voice:
					exists = true
					break
			if exists:
				current_voice_id = saved_voice

	print("Wybrany głos: ", current_voice_id)

func set_voice(voice_id: String):
	current_voice_id = voice_id
	print("Zmiana głosu na: ", voice_id)

func set_volume(linear_val: float):
	# linear_val 0.0 - 1.0 -> 0 - 100
	tts_volume_percent = int(linear_val * 100)
	print("TTS Volume set to: ", tts_volume_percent)

func speak(text: String, is_player: bool = false):
	if text.is_empty(): return
	
	# Parametry głosu
	var pitch = 1.0
	var rate = 1.0
	var volume = tts_volume_percent
	
	if is_player:
		pitch = 1.2 # Gracze lżej/wyżej
		rate = 1.1
	else:
		pitch = 0.9 # Prowadzący niżej/powolniej
		
	# Check if DisplayServer supports TTS and if voice is valid
	if available_voices.is_empty():
		print("TTS not supported or no voices available.")
		return
		
	DisplayServer.tts_speak(text, current_voice_id, volume, pitch, rate)

func stop():
	DisplayServer.tts_stop()
