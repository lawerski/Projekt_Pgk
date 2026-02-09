extends Node3D

@onready var game_manager = get_node("/root/Main/GameManager")
# @onready var round_manager = game_manager.get_node("RoundManager")

# Referencje do obiektów 3D
@onready var questions_label = $Studio/BigScreen/ScreenContent/Label3D
@onready var score_a_label = $Studio/PodiumA/ScoreLabel
@onready var score_b_label = $Studio/PodiumB/ScoreLabel
@onready var timer_label = $Studio/BigScreen/TimerLabel
@onready var camera = $Camera3D

# Proste materiały do zmiany kolorów (np. aktywnego gracza)
var mat_active = StandardMaterial3D.new()
var mat_inactive = StandardMaterial3D.new()

func _ready():
	print("--- STARTING 3D GAME MODE ---")
	
	# Konfiguracja materiałów
	mat_active.albedo_color = Color(1.0, 1.0, 0.0) # Żółty dla aktywnego
	mat_inactive.albedo_color = Color(0.3, 0.3, 0.3) # Szary dla nieaktywnego
	
	# Podłączenie sygnałów (analogicznie do wersji 2D)
	# Tutaj musielibyśmy podłączyć się do RoundManagera, 
	# ale w tym demo pokażę tylko statyczną scenę i prostą interakcję.
	
	questions_label.text = "WITAJCIE W STUDIU 3D!\nCzekam na pytanie..."
	score_a_label.text = "0"
	score_b_label.text = "0"

func update_question(text: String):
	questions_label.text = text

func update_scores(score_a: int, score_b: int):
	score_a_label.text = str(score_a)
	score_b_label.text = str(score_b)

# Funkcja do testu kamery (można wywołać, żeby zobaczyć ruch)
func camera_zoom_to_screen():
	var tween = create_tween()
	tween.tween_property(camera, "position", Vector3(0, 2, 2), 1.0).set_trans(Tween.TRANS_CUBIC)

func camera_reset():
	var tween = create_tween()
	tween.tween_property(camera, "position", Vector3(0, 3, 6), 1.0).set_trans(Tween.TRANS_CUBIC)
