extends Node

var main_player: AudioStreamPlayer
var generator: AudioStreamGenerator
var playback: AudioStreamGeneratorPlayback
var sample_rate = 44100.0

func _ready():
	# Update: Create a dedicated player for procedural sounds
	main_player = AudioStreamPlayer.new()
	add_child(main_player)
	
	generator = AudioStreamGenerator.new()
	generator.mix_rate = sample_rate
	generator.buffer_length = 0.5 # Short buffer for responsiveness
	
	main_player.stream = generator
	main_player.volume_db = -15.0 
	main_player.play()
	
	playback = main_player.get_stream_playback()

func set_volume(linear_value: float):
	if not main_player: return
	
	if linear_value <= 0.001:
		main_player.volume_db = -80.0 
	else:
		var db = 20.0 * (log(linear_value) / log(10.0))
		main_player.volume_db = db

func play_sfx(sound_name: String):
	print("[SoundManager] Playing: ", sound_name)
	
	match sound_name:
		"intro":
			# Bardziej melodyjny jingiel w stylu teleturnieju
			_play_tone_sequence([659.0, 523.0, 587.0, 659.0, 783.0, 1046.0], 0.12)
		"correct":
			# Czysty, wysoki dźwięk "Ding" (dzwonek)
			# Dodajemy delikatny overton dla bogatszego brzmienia
			_play_chord([1046.5, 2093.0], 0.6, "sine") 
		"wrong":
			# Szorstki, dysonujący dźwięk uderzenia ("Buczek")
			# Dwie niskie fale piłokształtne tworzące dysonans
			_play_chord([140.0, 195.0, 145.0], 0.5, "saw")
		"win":
			_play_tone_sequence([523.0, 659.0, 783.0, 1046.0, 783.0, 1046.0], 0.1)
		"reveal":
			# Krótkie plumknięcie przy odkrywaniu/zgłaszaniu
			_play_tone(700.0, 0.15, "sine")
		_:
			print("Unknown sound: ", sound_name)

func _play_tone(freq: float, duration: float, type: String = "sine"):
	_play_chord([freq], duration, type)

func _play_chord(freqs: Array, duration: float, type: String = "sine"):
	if not playback: return
	
	var frames = int(duration * sample_rate)
	var buffer = PackedVector2Array()
	buffer.resize(frames)
	
	# Przygotuj inkrementacje dla każdej częstotliwości
	var phases = []
	var increments = []
	for f in freqs:
		phases.append(0.0)
		increments.append(f / sample_rate)
	
	for i in range(frames):
		var mixed_sample = 0.0
		
		# Sumowanie fal
		for k in range(freqs.size()):
			var wave = 0.0
			if type == "sine":
				wave = sin(TAU * phases[k])
			elif type == "saw":
				# Bardziej "brudna" piła
				wave = (fmod(phases[k], 1.0) * 2.0) - 1.0
			elif type == "square":
				wave = 1.0 if fmod(phases[k], 1.0) < 0.5 else -1.0
			
			mixed_sample += wave
			phases[k] += increments[k]
		
		# Normalizacja (żeby nie przesterować przy kilku dźwiękach)
		mixed_sample /= float(freqs.size())
		
		# Envelope (obwiednia) - szybki atak, wolne wygaszanie
		var t = float(i) / float(frames)
		var envelope = pow(1.0 - t, 2.0) # Bardziej naturalne wygaszanie (kwadratowe)
		
		mixed_sample *= envelope * 0.5 # Volume
		
		buffer[i] = Vector2(mixed_sample, mixed_sample)
		
	if playback.can_push_buffer(frames):
		playback.push_buffer(buffer)

func _play_tone_sequence(freqs: Array, note_duration: float):
	# Requires async handling or queuing. 
	# For simplicity in this generator, we will just construct one long buffer.
	
	var total_frames = 0
	var buffer = PackedVector2Array()
	
	for freq in freqs:
		var frames = int(note_duration * sample_rate)
		var increment = freq / sample_rate
		var phase = 0.0
		
		for i in range(frames):
			var sample = sin(TAU * phase)
			# Envelope
			var envelope = 1.0 - (float(i) / float(frames))
			sample *= envelope * 0.5
			
			buffer.append(Vector2(sample, sample))
			phase += increment
	
	if playback.can_push_buffer(buffer.size()):
		playback.push_buffer(buffer)
