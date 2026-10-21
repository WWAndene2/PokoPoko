extends Node2D
## Screens (menu, solo, versus AI, result), rendering and touch input.
## Match rules live in Player / Board, the computer opponent in AI.

enum Screen { MENU, PLAYING, RESULT }

# Poko elements, indexed by board color - 1
enum Element { AQUA, BLAZE, LEAF, SUNNY, NOVA }
const COLORS := [Color("#4fb8ff"), Color("#ff5a4f"), Color("#7ee36b"), Color("#ffd84f"), Color("#9b6bff")]
const GARBAGE_COLOR := Color("#8e88a3")
const BG := Color("#1b1430")
const PANEL := Color("#2a2048")
const MUTED := Color("#a99cc9")
const ACCENT := Color("#ffcf5a")
const SAVE_PATH := "user://save.cfg"

# Margin time: after MARGIN_START seconds, points per garbage drop by 25 % every MARGIN_STEP
const MARGIN_START := 96.0
const MARGIN_STEP := 16.0

# Pending garbage icons, biggest first: [value, color, radius factor]
const GARBAGE_ICONS := [
	[720, Color("#ffcf5a"), 0.5], [360, Color("#9b6bff"), 0.46], [180, Color("#ffe79a"), 0.42],
	[30, Color("#b07a4f"), 0.4], [6, GARBAGE_COLOR, 0.34], [1, GARBAGE_COLOR, 0.2],
]

const MENU_ITEMS := [
	["Solo", -1],
	["Versus IA · Facile", AI.Level.EASY],
	["Versus IA · Normal", AI.Level.NORMAL],
	["Versus IA · Difficile", AI.Level.HARD],
]

var screen := Screen.MENU
var players: Array[Player] = []
var ai: AI = null
var elapsed := 0.0
var won := false
var best := 0
var font: Font = ThemeDB.fallback_font

# Per-player visual state
var chain_text := ["", ""]
var chain_text_t := [0.0, 0.0]
var shake := 0.0

# Touch tracking
var touch_start := Vector2.ZERO
var touch_start_t := 0
var touch_last_x := 0.0
var touch_moved := false
var touching := false


func _ready() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("score", "best", 0)


func _start(ai_level: int) -> void:
	var seed_value := randi()
	players.clear()
	var human := Player.new()
	human.start(seed_value, ai_level >= 0)
	players.append(human)
	ai = null
	if ai_level >= 0:
		var cpu := Player.new()
		cpu.start(seed_value, true) # same seed: both players get the same pairs
		players.append(cpu)
		ai = AI.new(cpu, ai_level)
	elapsed = 0.0
	chain_text = ["", ""]
	chain_text_t = [0.0, 0.0]
	screen = Screen.PLAYING


func _end(human_won: bool) -> void:
	won = human_won
	screen = Screen.RESULT
	var s := players[0].score
	if players.size() == 1 and s > best:
		best = s
		var cfg := ConfigFile.new()
		cfg.set_value("score", "best", best)
		cfg.save(SAVE_PATH)


func _process(delta: float) -> void:
	if screen == Screen.PLAYING:
		elapsed += delta
		if players.size() == 2 and elapsed > MARGIN_START:
			var steps := int((elapsed - MARGIN_START) / MARGIN_STEP) + 1
			var target := maxi(1, int(70 * pow(0.75, steps)))
			for p in players:
				p.target_points = target
		if ai:
			ai.update(delta)
		for i in players.size():
			players[i].update(delta)
			_handle_events(i)
	for i in 2:
		chain_text_t[i] = maxf(0.0, chain_text_t[i] - delta)
	shake = maxf(0.0, shake - delta * 60.0)
	queue_redraw()


func _handle_events(i: int) -> void:
	var p := players[i]
	for e in p.events:
		match e[0]:
			"chain":
				if e[1] >= 2:
					chain_text[i] = "%d chaînes !" % e[1]
					chain_text_t[i] = 0.9
				if i == 0:
					shake = minf(4.0 + e[1] * 3.0, 20.0)
					Input.vibrate_handheld(mini(30 + e[1] * 20, 150))
			"all_clear":
				chain_text[i] = "Grille vide !"
				chain_text_t[i] = 1.2
			"attack":
				players[1 - i].pending_garbage += e[1]
			"dead":
				if screen == Screen.PLAYING:
					_end(i != 0 and players.size() == 2)
	p.events.clear()


# --- Input -------------------------------------------------------------------

func _human() -> Player:
	return players[0] if screen == Screen.PLAYING else null


func _unhandled_input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	if screen != Screen.PLAYING:
		if event is InputEventScreenTouch and not event.pressed:
			_menu_tap(event.position)
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]:
			_menu_tap(Vector2(vp.x / 2, _menu_y(0)))
		return
	var p := _human()
	if event is InputEventScreenTouch:
		if event.pressed:
			touching = true
			touch_start = event.position
			touch_start_t = Time.get_ticks_msec()
			touch_last_x = event.position.x
			touch_moved = false
		elif touching:
			touching = false
			p.soft_drop = false
			var d: Vector2 = event.position - touch_start
			var quick := Time.get_ticks_msec() - touch_start_t < 250
			if quick and d.y > _cell() * 1.5 and d.y > abs(d.x) * 2:
				p.hard_drop()
			elif not touch_moved and d.length() < 12:
				# Puyo-style two buttons: left half turns counter-clockwise, right half clockwise
				p.rotate(-1 if event.position.x < vp.x / 2 else 1)
	elif event is InputEventScreenDrag and touching:
		var step := _cell() * 0.8
		while event.position.x - touch_last_x > step:
			p.move(1)
			touch_last_x += step
			touch_moved = true
		while touch_last_x - event.position.x > step:
			p.move(-1)
			touch_last_x -= step
			touch_moved = true
		var d: Vector2 = event.position - touch_start
		p.soft_drop = d.y > _cell() * 0.8 and d.y > abs(d.x) * 2
	elif event is InputEventKey and not event.echo:
		if event.keycode == KEY_DOWN:
			p.soft_drop = event.pressed
		elif event.pressed:
			match event.keycode:
				KEY_LEFT: p.move(-1)
				KEY_RIGHT: p.move(1)
				KEY_UP, KEY_X: p.rotate(1)
				KEY_Z: p.rotate(-1)
				KEY_SPACE: p.hard_drop()
	elif event is InputEventKey and event.echo and event.keycode in [KEY_LEFT, KEY_RIGHT]:
		p.move(-1 if event.keycode == KEY_LEFT else 1)


func _menu_y(i: int) -> float:
	return get_viewport_rect().size.y * 0.5 + i * 110


func _menu_tap(at: Vector2) -> void:
	if screen == Screen.RESULT:
		screen = Screen.MENU
		return
	for i in MENU_ITEMS.size():
		if absf(at.y - _menu_y(i)) < 45:
			_start(MENU_ITEMS[i][1])
			return


# --- Layout ------------------------------------------------------------------

func _cell() -> float:
	var vp := get_viewport_rect().size
	if players.size() == 2:
		return floor(minf((vp.x - 48) / (Board.COLS * 2), (vp.y - 330) / Board.ROWS))
	return floor(minf((vp.x - 32) / Board.COLS, (vp.y - 300) / Board.ROWS))


func _origin(i: int) -> Vector2:
	var vp := get_viewport_rect().size
	var c := _cell()
	var w := c * Board.COLS
	if players.size() == 2:
		return Vector2(16 + i * (w + 16), 230)
	return Vector2((vp.x - w) / 2, 230)


# --- Rendering ---------------------------------------------------------------

func _draw() -> void:
	var vp := get_viewport_rect().size
	draw_rect(Rect2(Vector2.ZERO, vp), BG)
	if screen == Screen.MENU:
		_draw_menu(vp)
		return
	for i in players.size():
		_draw_player(i)
	if players.size() == 2:
		var bottom := _origin(0).y + _cell() * Board.ROWS + 60
		_label_centered("%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], bottom, 30, MUTED)
	if screen == Screen.RESULT:
		draw_rect(Rect2(Vector2.ZERO, vp), Color(BG, 0.85))
		var title := ("Victoire !" if won else "Défaite…") if players.size() == 2 else "Fin de partie"
		_label_centered(title, vp.y * 0.4, 80, ACCENT)
		_label_centered("Score : %d" % players[0].score, vp.y * 0.48, 40, Color.WHITE)
		if players.size() == 1:
			_label_centered("Record : %d" % best, vp.y * 0.53, 30, MUTED)
		_label_centered("Touchez pour continuer", vp.y * 0.65, 34, Color.WHITE)


func _draw_menu(vp: Vector2) -> void:
	_label_centered("PokoPoko", vp.y * 0.25, 110, ACCENT)
	_label_centered("Record solo : %d" % best, vp.y * 0.32, 28, MUTED)
	for i in MENU_ITEMS.size():
		var y := _menu_y(i)
		draw_rect(Rect2(vp.x * 0.15, y - 42, vp.x * 0.7, 84), PANEL)
		_label_centered(MENU_ITEMS[i][0], y + 13, 36, Color.WHITE)
	_label_centered("Glisser ↔ déplacer · Toucher gauche/droite tourner", vp.y * 0.9, 22, MUTED)
	_label_centered("Glisser ↓ lentement : descente · vite : chute", vp.y * 0.93, 22, MUTED)


func _draw_player(i: int) -> void:
	var p := players[i]
	var b := p.board
	var cell := _cell()
	var origin := _origin(i)
	var jitter := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if i == 0 and shake > 0 else Vector2.ZERO
	var at := func(x: float, y: float) -> Vector2: return origin + jitter + Vector2(x, y - Board.HIDDEN) * cell
	var w := cell * Board.COLS

	# Header: score, next two pairs, pending garbage
	_label(str(p.score), origin + Vector2(0, -150), 34 if players.size() == 2 else 44, Color.WHITE)
	if players.size() == 1:
		_label("Record %d" % best, origin + Vector2(0, -112), 22, MUTED)
	else:
		_label("Toi" if i == 0 else "IA", origin + Vector2(0, -190), 24, MUTED)
	var s := cell * 0.75
	for k in mini(2, b.queue.size()):
		var nxt: Array = b.queue[k]
		var scale := 1.0 if k == 0 else 0.7
		var np := origin + Vector2(w - s * (2.3 - k * 1.1), -190 + k * s * 0.3)
		_draw_blob(np, nxt[1], s * scale)
		_draw_blob(np + Vector2(0, s * scale), nxt[0], s * scale)
	_draw_pending(p.pending_garbage, origin + Vector2(0, -60), cell)

	draw_rect(Rect2(origin + jitter, Vector2(Board.COLS, Board.ROWS) * cell).grow(6), PANEL)
	draw_rect(Rect2(at.call(Board.SPAWN_COL, Board.HIDDEN), Vector2(cell, cell)), Color(COLORS[Element.BLAZE], 0.15))

	var t := p.fall_progress()
	for y in range(Board.HIDDEN, Board.H):
		for x in Board.COLS:
			var color: int = b.grid[y][x]
			if color == 0:
				continue
			var c := Vector2i(x, y)
			if p.state == Player.State.POPPING and p.popping.has(c):
				var pt := p.anim_t / Player.POP_TIME
				var flash := int(p.anim_t / 0.06) % 2 == 1
				_draw_blob(at.call(x, y), color, cell, 1 + pt * 0.4, 1 - pt, Color.WHITE if flash else null)
			else:
				var off: float = p.drops.get(c, 0) * (1 - t)
				_draw_blob(at.call(x, y - off), color, cell)

	if b.has_piece and p.state == Player.State.FALLING:
		var g := b.ghost_pos()
		for pc in b.piece_cells(g):
			if pc[0].y >= Board.HIDDEN:
				_draw_blob(at.call(pc[0].x, pc[0].y), pc[1], cell, 0.45, 0.35)
		var smooth := minf(1.0, p.fall_timer / p.fall_delay) if b.can_fall() else 0.0
		for pc in b.piece_cells():
			if pc[0].y + smooth >= Board.HIDDEN:
				_draw_blob(at.call(pc[0].x, pc[0].y + smooth), pc[1], cell)

	if chain_text_t[i] > 0:
		var size := 64 if players.size() == 1 else 40
		draw_string(font, origin + Vector2(0, cell * Board.ROWS * 0.4), chain_text[i], HORIZONTAL_ALIGNMENT_CENTER, w, size, Color(ACCENT, minf(1.0, chain_text_t[i] * 3)))


## Incoming garbage shown as icons (crown 720, moon 360, star 180, rock 30, big 6, small 1).
func _draw_pending(n: int, at: Vector2, cell: float) -> void:
	var x := 0.0
	var shown := 0
	for icon in GARBAGE_ICONS:
		while n >= icon[0] and shown < 6:
			n -= icon[0]
			var r: float = cell * icon[2]
			draw_circle(at + Vector2(x + cell * 0.5, 0), r, icon[1])
			x += cell * 0.9
			shown += 1


## `kind` is a board value: 1..5 element, Board.GARBAGE for nuisance.
func _draw_blob(at: Vector2, kind: int, size: float, scale: float = 1.0, alpha: float = 1.0, tint: Variant = null) -> void:
	var r := (size / 2 - 3) * scale
	var c := at + Vector2(size, size) / 2
	var base: Color = GARBAGE_COLOR if kind == Board.GARBAGE else COLORS[kind - 1]
	draw_circle(c, r, Color(tint if tint != null else base, alpha))
	draw_circle(c - Vector2(r, r) * 0.35, r * 0.3, Color(1, 1, 1, 0.35 * alpha))
	if kind == Board.GARBAGE:
		var ink := Color(BG, alpha * 0.6)
		draw_circle(c + Vector2(-r * 0.3, 0), r * 0.08, ink)
		draw_circle(c + Vector2(r * 0.3, 0), r * 0.08, ink)
	else:
		_draw_face(c, r, kind - 1, Color(BG, alpha))


func _label(text: String, at: Vector2, size: int, color: Color) -> void:
	draw_string(font, at, text, HORIZONTAL_ALIGNMENT_LEFT, -1, size, color)


func _label_centered(text: String, y: float, size: int, color: Color) -> void:
	draw_string(font, Vector2(0, y), text, HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x, size, color)


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


