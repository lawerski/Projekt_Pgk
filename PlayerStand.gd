extends Control

@onready var head_texture = $Frame/VBox/AvatarMargin/Head
@onready var nick_label = $Frame/VBox/NamePanel/NickLabel
@onready var bubble_root = $BubbleRoot
@onready var bubble_label = $BubbleRoot/Label

var client_id = -1
var bubble_timer: Timer
var active_tween: Tween
var base_bubble_y: float = 0.0

func _ready():
	bubble_timer = Timer.new()
	bubble_timer.one_shot = true
	bubble_timer.timeout.connect(hide_bubble)
	add_child(bubble_timer)
	
	# Initial Y
	base_bubble_y = bubble_root.position.y
	
	# Ensure bubble is high z-index
	bubble_root.z_index = 20

func set_player_data(nick: String, avatar_texture: Texture2D):
	nick_label.text = nick
	if avatar_texture:
		head_texture.texture = avatar_texture
	else:
		# Fallback icon if no texture provided
		head_texture.texture = preload("res://icon.svg")

func set_visual_index(index: int):
	# Alternująca wysokość dymków (tzw. Staggering)
	# Parzyści: nisko, Nieparzyści: wysoko
	# Dzięki temu dymki sąsiadów nie będą na siebie nachodzić
	var offset = 0
	if index % 2 != 0:
		offset = -90 # Przesuń w górę o 90px
	
	bubble_root.position.y = base_bubble_y + offset

func show_bubble(text: String, duration: float = 4.0):
	# Stop logic to prevent race conditions
	bubble_timer.stop()
	
	# Bring to front visually
	bubble_root.z_index = 100
	
	# Kill active tween to prevent conflict (e.g. hiding fighting showing)
	if active_tween and active_tween.is_valid():
		active_tween.kill()

	bubble_label.text = text
	bubble_root.visible = true
	# Reset scale only if it was hidden or zero
	if bubble_root.scale == Vector2.ZERO:
		bubble_root.scale = Vector2(0.1, 0.1) # Start small but not zero to avoid processing glitches
	
	bubble_root.pivot_offset = Vector2(bubble_root.size.x / 2, bubble_root.size.y)
	
	active_tween = create_tween()
	active_tween.tween_property(bubble_root, "scale", Vector2.ONE, 0.3).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	
	bubble_timer.start(duration)

func hide_bubble():
	if active_tween and active_tween.is_valid():
		active_tween.kill()
		
	active_tween = create_tween()
	active_tween.tween_property(bubble_root, "scale", Vector2.ZERO, 0.2).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_IN)
	active_tween.tween_callback(func(): bubble_root.visible = false)


