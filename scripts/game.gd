extends Node2D
## Rendering, touch input and the falling / settling / popping state machine.

enum State { MENU, FALLING, SETTLING, POPPING, OVER }

# Poko elements, indexed by board color - 1
enum Element { AQUA, BLAZE, LEAF, SUNNY, NOVA }
const COLORS := [Color("#4fb8ff"), Color("#ff5a4f"), Color("#7ee36b"), Color("#ffd84f"), Color("#9b6bff")]
const BG := Color("#1b1430")
const PANEL := Color("#2a2048")
const ACCENT := Color("#ffcf5a")
const SETTLE_TIME := 0.12
const POP_TIME := 0.35
const SAVE_PATH := "user://save.cfg"

var board := Board.new()
var state := State.MENU
var cell := 64.0
var origin := Vector2.ZERO
var fall_timer := 0.0
var fall_delay := 0.7
var anim_t := 0.0
var drops := {} # Vector2i -> fall distance
var popping: Array = []
var chain := 0
var score := 0
var best := 0
var chain_text := ""
var chain_text_t := 0.0
var shake := 0.0

# Touch tracking
var touch_start := Vector2.ZERO
var touch_last_x := 0.0
var touch_moved := false
var touching := false

var font: Font = ThemeDB.fallback_font


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("score", "best", 0)
	get_viewport().size_changed.connect(_layout)
	_layout()


func _layout() -> void:
	var vp := get_viewport_rect().size
	cell = floor(min((vp.x - 32) / Board.COLS, (vp.y - 260) / Board.ROWS))
	origin = Vector2((vp.x - cell * Board.COLS) / 2, 180)


func start() -> void:
	board.reset()
	score = 0
	fall_delay = 0.7
	_spawn()


func _spawn() -> void:
	chain = 0
	fall_timer = 0.0
	if board.spawn():
		state = State.FALLING
	else:
		_game_over()


func _game_over() -> void:
	state = State.OVER
	if score > best:
		best = score
		var cfg := ConfigFile.new()
		cfg.set_value("score", "best", best)
		cfg.save(SAVE_PATH)


func _lock_and_resolve() -> void:
	board.lock()
	_settle()


func _settle() -> void:
	drops.clear()
	for d in board.apply_gravity():
		drops[d[0]] = d[1]
	anim_t = 0.0
	state = State.SETTLING


func _check_pops() -> void:
	var groups := board.find_groups()
	if groups.is_empty():
		fall_delay = max(0.18, fall_delay - 0.004)
		_spawn()
		return
	chain += 1
	score += Board.chain_score(groups, chain)
	popping = []
	for g in groups:
		popping.append_array(g.cells)
	if chain >= 2:
		chain_text = "%d chaînes !" % chain
		chain_text_t = 0.9
	shake = min(4.0 + chain * 3.0, 20.0)
	Input.vibrate_handheld(min(30 + chain * 20, 150))
	anim_t = 0.0
	state = State.POPPING


func _process(delta: float) -> void:
	match state:
		State.FALLING:
			fall_timer += delta
			if fall_timer >= fall_delay:
				fall_timer = 0.0
				if not board.step_down():
					_lock_and_resolve()
		State.SETTLING:
			anim_t += delta
			if anim_t >= SETTLE_TIME:
				_check_pops()
		State.POPPING:
			anim_t += delta
			if anim_t >= POP_TIME:
				board.clear_cells(popping)
				popping = []
				_settle()
	chain_text_t = max(0.0, chain_text_t - delta)
	shake = max(0.0, shake - delta * 60.0)
	queue_redraw()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if state == State.MENU or state == State.OVER:
		if (event is InputEventScreenTouch and not event.pressed) or event.is_action_pressed("ui_accept"):
			start()
		return
	if event is InputEventScreenTouch:
		if event.pressed:
			touching = true
			touch_start = event.position
			touch_last_x = event.position.x
			touch_moved = false
		elif touching:
			touching = false
			var d: Vector2 = event.position - touch_start
			if d.y > cell * 1.5 and d.y > abs(d.x):
				_hard_drop()
			elif not touch_moved and d.length() < 12:
				board.rotate_cw()
	elif event is InputEventScreenDrag and touching:
		var step := cell * 0.8
		while event.position.x - touch_last_x > step:
			board.move(1)
			touch_last_x += step
			touch_moved = true
		while touch_last_x - event.position.x > step:
			board.move(-1)
			touch_last_x -= step
			touch_moved = true
	elif event is InputEventKey and event.pressed:
		match event.keycode:
			KEY_LEFT: board.move(-1)
			KEY_RIGHT: board.move(1)
			KEY_UP, KEY_X: board.rotate_cw()
			KEY_DOWN:
				if state == State.FALLING:
					fall_timer = 0.0
					if not board.step_down():
						_lock_and_resolve()
			KEY_SPACE: _hard_drop()


func _hard_drop() -> void:
	if state != State.FALLING:
		return
	while board.step_down():
		score += 1
	_lock_and_resolve()


# --- Rendering ---------------------------------------------------------------

func _cell_pos(x: float, y: float) -> Vector2:
	return origin + Vector2(x, y - Board.HIDDEN) * cell


func _draw_blob(at: Vector2, element: int, size: float, scale: float = 1.0, alpha: float = 1.0, tint: Variant = null) -> void:
	var r := (size / 2 - 3) * scale
	var c := at + Vector2(size, size) / 2
	draw_circle(c, r, Color(tint if tint != null else COLORS[element], alpha))
	draw_circle(c - Vector2(r, r) * 0.35, r * 0.3, Color(1, 1, 1, 0.35 * alpha))
	_draw_face(c, r, element, Color(BG, alpha))


## Each element has its own expression.
func _draw_face(c: Vector2, r: float, element: int, ink: Color) -> void:
	var w := maxf(1.5, r * 0.09)
	var le := c + Vector2(-r * 0.3, 0)
	var re := c + Vector2(r * 0.3, 0)
	var mouth := c + Vector2(0, r * 0.35)
	match element:
		Element.AQUA: # confident and brave: round eyes, determined brows, firm smile
			draw_circle(le, r * 0.12, ink)
			draw_circle(re, r * 0.12, ink)
			draw_line(le + Vector2(-r * 0.15, -r * 0.28), le + Vector2(r * 0.12, -r * 0.2), ink, w)
			draw_line(re + Vector2(r * 0.15, -r * 0.28), re + Vector2(-r * 0.12, -r * 0.2), ink, w)
			draw_arc(mouth + Vector2(0, -r * 0.12), r * 0.18, PI * 0.2, PI * 0.8, 8, ink, w)
		Element.BLAZE: # aggressive and smug: half-lidded eyes, lopsided smirk
			draw_line(le + Vector2(-r * 0.14, -r * 0.05), le + Vector2(r * 0.14, r * 0.02), ink, w * 1.6)
			draw_line(re + Vector2(-r * 0.14, r * 0.02), re + Vector2(r * 0.14, -r * 0.05), ink, w * 1.6)
			draw_line(mouth + Vector2(-r * 0.2, 0), mouth + Vector2(r * 0.1, r * 0.04), ink, w)
			draw_line(mouth + Vector2(r * 0.1, r * 0.04), mouth + Vector2(r * 0.24, -r * 0.08), ink, w)
		Element.LEAF: # calm and gentle: closed relaxed eyes, soft smile
			draw_arc(le + Vector2(0, -r * 0.06), r * 0.12, PI * 0.1, PI * 0.9, 8, ink, w)
			draw_arc(re + Vector2(0, -r * 0.06), r * 0.12, PI * 0.1, PI * 0.9, 8, ink, w)
			draw_arc(mouth + Vector2(0, -r * 0.1), r * 0.12, PI * 0.25, PI * 0.75, 8, ink, w)
		Element.SUNNY: # joyful and cheerful: ^ ^ eyes, wide open smile
			draw_arc(le + Vector2(0, r * 0.06), r * 0.12, PI * 1.1, PI * 1.9, 8, ink, w)
			draw_arc(re + Vector2(0, r * 0.06), r * 0.12, PI * 1.1, PI * 1.9, 8, ink, w)
			var smile := PackedVector2Array()
			for i in 9:
				smile.append(mouth + Vector2(-r * 0.16, -r * 0.08) + Vector2(r * 0.16, 0) + Vector2.from_angle(PI * i / 8.0) * r * 0.16)
			draw_colored_polygon(smile, ink)
		Element.NOVA: # apathetic and mysterious (kuudere): flat half-closed eyes, no smile
			draw_line(le + Vector2(-r * 0.13, 0), le + Vector2(r * 0.13, 0), ink, w)
			draw_line(re + Vector2(-r * 0.13, 0), re + Vector2(r * 0.13, 0), ink, w)
			draw_circle(le + Vector2(0, r * 0.05), r * 0.06, ink)
			draw_circle(re + Vector2(0, r * 0.05), r * 0.06, ink)
			draw_line(mouth + Vector2(-r * 0.07, 0), mouth + Vector2(r * 0.07, 0), ink, w)


func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	var jitter := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if shake > 0 else Vector2.ZERO
	draw_set_transform(jitter)

	var board_rect := Rect2(origin, Vector2(Board.COLS, Board.ROWS) * cell)
	draw_rect(board_rect.grow(8), PANEL)
	draw_rect(Rect2(_cell_pos(Board.SPAWN_COL, Board.HIDDEN), Vector2(cell, cell)), Color(COLORS[Element.BLAZE], 0.15))

	for y in range(Board.HIDDEN, Board.H):
		for x in Board.COLS:
			var color: int = board.grid[y][x]
			if color == 0:
				continue
			var c := Vector2i(x, y)
			if state == State.POPPING and popping.has(c):
				var t := anim_t / POP_TIME
				var flash := int(anim_t / 0.06) % 2 == 1
				_draw_blob(_cell_pos(x, y), color - 1, cell, 1 + t * 0.4, 1 - t, Color.WHITE if flash else null)
			else:
				var off: float = drops.get(c, 0) * (1 - min(1.0, anim_t / SETTLE_TIME)) if state == State.SETTLING else 0.0
				_draw_blob(_cell_pos(x, y - off), color - 1, cell)

	if board.has_piece:
		var g := board.ghost_pos()
		for pc in board.piece_cells(g):
			if pc[0].y >= Board.HIDDEN:
				_draw_blob(_cell_pos(pc[0].x, pc[0].y), pc[1] - 1, cell, 0.45, 0.35)
		var smooth := minf(1.0, fall_timer / fall_delay) if board.can_fall() else 0.0
		for pc in board.piece_cells():
			if pc[0].y + smooth >= Board.HIDDEN:
				_draw_blob(_cell_pos(pc[0].x, pc[0].y + smooth), pc[1] - 1, cell)

	draw_set_transform(Vector2.ZERO)
	_draw_hud(vp)


func _draw_hud(vp: Vector2) -> void:
	_label("SCORE", Vector2(24, 60), 22, Color("#a99cc9"))
	_label(str(score), Vector2(24, 110), 44, Color.WHITE)
	_label("RECORD", Vector2(vp.x - 200, 60), 22, Color("#a99cc9"))
	_label(str(best), Vector2(vp.x - 200, 110), 44, Color.WHITE)
	if not board.queue.is_empty():
		var nxt: Array = board.queue[0]
		var s := cell * 0.8
		var p := Vector2(vp.x / 2 - s / 2, 20)
		_draw_blob(p, nxt[1] - 1, s)
		_draw_blob(p + Vector2(0, s), nxt[0] - 1, s)
	if chain_text_t > 0:
		var a := minf(1.0, chain_text_t * 3)
		_label_centered(chain_text, vp.y * 0.4, 72, Color(ACCENT, a))
	if state == State.MENU or state == State.OVER:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(BG, 0.9))
		_label_centered("PokoPoko", vp.y * 0.35, 96, ACCENT)
		if state == State.OVER:
			_label_centered("Score : %d" % score, vp.y * 0.45, 40, Color.WHITE)
		_label_centered("Glisser ↔ déplacer · Toucher tourner · Glisser ↓ chute", vp.y * 0.55, 24, Color("#a99cc9"))
		_label_centered("Touchez pour %s" % ("rejouer" if state == State.OVER else "jouer"), vp.y * 0.65, 40, Color.WHITE)


func _label(text: String, at: Vector2, size: int, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _label_centered(text: String, y: float, size: int, color: Color) -> void:
	var w := get_viewport_rect().size.x
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, w, size, color)
