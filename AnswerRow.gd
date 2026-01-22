extends PanelContainer

@onready var index_label = $MarginContainer/HBoxContainer/IndexLabel
@onready var answer_label = $MarginContainer/HBoxContainer/AnswerLabel
@onready var points_label = $MarginContainer/HBoxContainer/PointsLabel
@onready var cover_panel = $CoverPanel
@onready var cover_label = $CoverPanel/Label

func _ready():
	# Initial visibility
	answer_label.visible = false
	points_label.visible = false
	cover_panel.visible = true

func set_index(idx):
	index_label.text = str(idx)
	cover_label.text = str(idx)
	_apply_visual_style()

func _apply_visual_style():
	# Nowy, lepszy styl dla wierszy (Granatowy gradient-ish effect)
	var style = StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.1, 0.35, 0.95) # Ciemny niebieski
	style.border_width_bottom = 2
	style.border_width_left = 2
	style.border_width_right = 2
	style.border_width_top = 2
	style.border_color = Color(0.3, 0.6, 0.9, 0.5) # Jaśniejsza ramka
	style.corner_radius_bottom_left = 4
	style.corner_radius_bottom_right = 4
	style.corner_radius_top_left = 4
	style.corner_radius_top_right = 4
	style.shadow_color = Color(0,0,0,0.3)
	style.shadow_size = 4
	
	add_theme_stylebox_override("panel", style)
	
	# Styl dla zasłony (CoverPanel)
	if cover_panel:
		var cover_style = StyleBoxFlat.new()
		cover_style.bg_color = Color(0.15, 0.2, 0.25, 1.0) # Szaro-niebieski
		cover_style.border_width_bottom = 2
		cover_style.border_width_left = 2
		cover_style.border_width_right = 2
		cover_style.border_width_top = 2
		cover_style.border_color = Color(0.6, 0.7, 0.8, 1.0)
		cover_panel.add_theme_stylebox_override("panel", cover_style)

func set_hidden_data(text, points):
	# For debug or pre-loading logic if needed, but we usually set it on reveal
	pass

func reveal(text, points):
	print("[AnswerRow] Revealing: " + str(text) + " (" + str(points) + ")")
	
	# Explicitly set visibility immediately just in case tween fails
	# Though we want the animation... let's ensure the final state is enforced
	
	var tween = create_tween()
	
	# Phase 1: Shrink width to 0 (rotate 90 deg)
	tween.tween_property(self, "scale:y", 0.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	
	# Phase 2: Switch content and expand back
	tween.tween_callback(func():
		cover_panel.visible = false
		answer_label.text = str(text) # Ensure string
		answer_label.visible = true
		
		points_label.text = str(points)
		points_label.visible = true
		print("[AnswerRow] Content updated. Visible? ", answer_label.visible)
	)
	
	tween.tween_property(self, "scale:y", 1.0, 0.25).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)

