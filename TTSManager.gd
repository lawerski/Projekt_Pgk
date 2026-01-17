extends Node

var available_voices = []
var current_voice_id = ""

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

	print("Wybrany głos: ", current_voice_id)

func speak(text: String, is_player: bool = false):
	if text.is_empty(): return
	
	# Parametry głosu
	var pitch = 1.0
	var rate = 1.0
	var volume = 50
	
	if is_player:
		pitch = 1.2 # Gracze lżej/wyżej
		rate = 1.1
	else:
		pitch = 0.9 # Prowadzący niżej/powolniej
		
	# Check if DisplayServer supports TTS and if voice is valid
	if not DisplayServer.has_feature(DisplayServer.FEATURE_TTS):
		print("TTS not supported on this platform.")
		return
		
	DisplayServer.tts_speak(text, current_voice_id, volume, pitch, rate)

func stop():
	DisplayServer.tts_stop()
