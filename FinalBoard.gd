extends Control

@onready var timer_label = $CenterContainer/InfoBox/TimerLabel
@onready var score_label = $CenterContainer/InfoBox/TotalScore
@onready var question_label = $CenterContainer/CurrentQ
@onready var rows_container = $CenterContainer/RowsContainer
@onready var message_label = $CenterContainer/Message

var row_scene = preload("res://FinalRow.tscn")

func _ready():
	# Clear rows initially
	for c in rows_container.get_children(): c.queue_free()

func setup_rows(count: int = 5):
	for c in rows_container.get_children(): c.queue_free()
	for i in range(count):
		var row = row_scene.instantiate()
		rows_container.add_child(row)

func update_info(q_text, time, total):
	question_label.text = str(q_text)
	timer_label.text = "%.1f s" % time
	score_label.text = "SUMA: %d" % total

func update_rows_data(results: Array):
	var rows = rows_container.get_children()
	for i in range(min(rows.size(), results.size())):
		rows[i].update_row(results[i], false)

func show_message(msg):
	message_label.text = msg
