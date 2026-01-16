extends HBoxContainer

@onready var p1_ans_label = $P1Ans
@onready var p1_pts_label = $P1Pts
@onready var p2_ans_label = $P2Ans
@onready var p2_pts_label = $P2Pts

func update_row(data: Dictionary, player_1_done: bool):
	# data: { p1_ans, p1_pts, p2_ans, p2_pts }
	
	p1_ans_label.text = data["p1_ans"]
	p1_pts_label.text = str(data["p1_pts"])
	
	p2_ans_label.text = data["p2_ans"]
	p2_pts_label.text = str(data["p2_pts"])
	
	# Opcjonalnie: ukryj P1 ans podczas tury P2, jeśli chcemy dramaturgii.
	# Ale w oryginale widać odpowiedzi P1, tylko P2 stoi tyłem.
	# Tutaj pokazujemy wszystko.
	
	if data["p1_ans"] == "":
		p1_pts_label.visible = false
	else:
		p1_pts_label.visible = true
		
	if data["p2_ans"] == "":
		p2_pts_label.visible = false
	else:
		p2_pts_label.visible = true
