extends Node2D
## Screens (menu, solo, versus AI, result), rendering and touch input.
## Match rules live in Player / Board, the computer opponent in AI.
## Visual style: framed boards per player, stepped NEXT panels, big score digits,
## name bars with Poko avatars, win stars and a rotating light-ray background.

enum Screen { MENU, PLAYING, RESULT }

# Poko elements, indexed by board color - 1
enum Element { AQUA, BLAZE, LEAF, SUNNY, NOVA }
const COLORS := [Color("#4fb8ff"), Color("#ff5a4f"), Color("#7ee36b"), Color("#ffd84f"), Color("#9b6bff")]
const GARBAGE_COLOR := Color("#d9d4e8")
const BG := Color("#1b1430")
const INK := Color("#1b1430")
const BOARD_BG := Color("#1a1838")
const MUTED := Color("#c9bfe6")
const ACCENT := Color("#ffcf5a")
const CHAIN_FILL := Color("#c6ff4f")
const PLAYER_COLORS := [Color("#2f8fff"), Color("#ff4f6a")]
const PLAYER_AVATAR := [Element.AQUA, Element.BLAZE]
const SAVE_PATH := "user://save.cfg"
const ROUNDS_TO_WIN := 2
const CENTER_W := 76.0 # column between the two boards holding the NEXT panels

# Margin time: after MARGIN_START seconds, points per garbage drop by 25 % every MARGIN_STEP
const MARGIN_START := 96.0
const MARGIN_STEP := 16.0

# Pending garbage icons, biggest first: [value, color, radius factor]
const GARBAGE_ICONS := [
	[720, Color("#ffcf5a"), 0.5], [360, Color("#9b6bff"), 0.46], [180, Color("#ffe79a"), 0.42],
	[30, Color("#ff7a4f"), 0.4], [6, GARBAGE_COLOR, 0.36], [1, GARBAGE_COLOR, 0.22],
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
var ai_level := -1
var elapsed := 0.0
var clock := 0.0 # always running, drives background animation
var won := false
var wins := [0, 0]
var match_over := false
var best := 0
var font: Font = ThemeDB.fallback_font

# Per-player visual state
var chain_text := ["", ""]
var chain_text_t := [0.0, 0.0]
const CHAIN_TEXT_TIME := 1.0
var shake := 0.0

# Touch tracking
var touch_start := Vector2.ZERO
var touch_start_t := 0
var touch_last_x := 0.0
var touch_moved := false
var touching := false


func _ready() -> void:
	var f = load("res://assets/fonts/FredokaOne-Regular.ttf")
	if f is Font:
		font = f
	var cfg := ConfigFile.new()
	if cfg.load(SAVE_PATH) == OK:
		best = cfg.get_value("score", "best", 0)


func _start(level: int) -> void:
	ai_level = level
	wins = [0, 0]
	match_over = false
	_start_round()


func _start_round() -> void:
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
	if players.size() == 2:
		wins[0 if human_won else 1] += 1
		match_over = wins.max() >= ROUNDS_TO_WIN
		return
	match_over = true
	var s := players[0].score
	if s > best:
		best = s
		var cfg := ConfigFile.new()
		cfg.set_value("score", "best", best)
		cfg.save(SAVE_PATH)


func _process(delta: float) -> void:
	clock += delta
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
					chain_text_t[i] = CHAIN_TEXT_TIME
				if i == 0:
					shake = minf(4.0 + e[1] * 3.0, 20.0)
					Input.vibrate_handheld(mini(30 + e[1] * 20, 150))
			"all_clear":
				chain_text[i] = "Grille vide !"
				chain_text_t[i] = CHAIN_TEXT_TIME * 1.3
			"attack":
				players[1 - i].pending_garbage += e[1]
			"dead":
				if screen == Screen.PLAYING:
					_end(i != 0 and players.size() == 2)
	p.events.clear()


# --- Input -------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	var vp := get_viewport_rect().size
	if screen != Screen.PLAYING:
		if event is InputEventScreenTouch and not event.pressed:
			_menu_tap(event.position)
		elif event is InputEventKey and event.pressed and event.keycode in [KEY_ENTER, KEY_SPACE]:
			_menu_tap(Vector2(vp.x / 2, _menu_y(0)))
		return
	var p := players[0]
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
	return get_viewport_rect().size.y * 0.5 + i * 115


func _menu_tap(at: Vector2) -> void:
	if screen == Screen.RESULT:
		if match_over:
			screen = Screen.MENU
		else:
			_start_round()
		return
	for i in MENU_ITEMS.size():
		if absf(at.y - _menu_y(i)) < 48:
			_start(MENU_ITEMS[i][1])
			return


# --- Layout ------------------------------------------------------------------

func _versus() -> bool:
	return players.size() == 2


func _cell() -> float:
	var vp := get_viewport_rect().size
	if _versus():
		return floor(minf((vp.x - 56 - CENTER_W) / (Board.COLS * 2), (vp.y - 480) / Board.ROWS))
	return floor(minf((vp.x - 40 - CENTER_W - 16) / Board.COLS, (vp.y - 480) / Board.ROWS))


func _board_size() -> Vector2:
	return Vector2(Board.COLS, Board.ROWS) * _cell()


## Top-left corner of player i's grid (first visible row).
func _origin(i: int) -> Vector2:
	var vp := get_viewport_rect().size
	var size := _board_size()
	var y := maxf(190.0, (vp.y - size.y) / 2 - 70)
	if _versus():
		return Vector2(20 if i == 0 else vp.x - 20 - size.x, y)
	return Vector2((vp.x - size.x - CENTER_W - 16) / 2, y)


# --- Rendering ---------------------------------------------------------------

func _draw() -> void:
	var vp := get_viewport_rect().size
	_draw_background(vp)
	if screen == Screen.MENU:
		_draw_menu(vp)
		return
	for i in players.size():
		_draw_player(i)
	_draw_top_bar(vp)
	_draw_bottom_bar(vp)
	if screen == Screen.RESULT:
		_draw_result(vp)


func _draw_background(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color("#2a1650"))
	# Rotating light rays from behind the boards
	var center := Vector2(vp.x / 2, vp.y * 0.42)
	var rays := 18
	var radius := vp.length()
	for k in rays:
		if k % 2 == 1:
			continue
		var a0 := clock * 0.08 + TAU * k / rays
		var a1 := a0 + TAU / rays
		var tri := PackedVector2Array([center, center + Vector2.from_angle(a0) * radius, center + Vector2.from_angle(a1) * radius])
		draw_colored_polygon(tri, Color(1, 1, 1, 0.05))
	# Soft colored glows in the corners
	for g in [[Vector2(0, 0), COLORS[Element.AQUA]], [Vector2(vp.x, 0), COLORS[Element.BLAZE]],
			[Vector2(0, vp.y), COLORS[Element.LEAF]], [Vector2(vp.x, vp.y), COLORS[Element.NOVA]]]:
		for s in 4:
			draw_circle(g[0], vp.x * (0.55 - s * 0.1), Color(g[1], 0.05))


func _panel(rect: Rect2, fill: Color, border: Color, border_w: int = 6, radius: int = 16) -> void:
	var sb := StyleBoxFlat.new()
	sb.bg_color = fill
	sb.border_color = border
	sb.set_border_width_all(border_w)
	sb.set_corner_radius_all(radius)
	sb.shadow_color = Color(0, 0, 0, 0.35)
	sb.shadow_size = 8
	sb.shadow_offset = Vector2(0, 4)
	draw_style_box(sb, rect)


## Text with a thick dark outline, the "arcade" look used for scores and callouts.
func _text(text: String, pos: Vector2, size: int, fill: Color, align := HORIZONTAL_ALIGNMENT_LEFT, width := -1.0, outline := 0) -> void:
	var o := outline if outline > 0 else maxi(4, size / 6)
	draw_string_outline(font, pos, text, align, width, size, o, Color(INK, fill.a))
	draw_string(font, pos, text, align, width, size, fill)


func _text_centered(text: String, y: float, size: int, fill: Color) -> void:
	_text(text, Vector2(0, y), size, fill, HORIZONTAL_ALIGNMENT_CENTER, get_viewport_rect().size.x)


func _draw_menu(vp: Vector2) -> void:
	# Logo with a bouncing Poko of each element
	for k in 5:
		var bounce := absf(sin(clock * 3.0 + k * 0.7)) * 18
		_draw_blob(Vector2(vp.x / 2 - 190 + k * 76, vp.y * 0.13 - bounce), k + 1, 72)
	_text_centered("PokoPoko", vp.y * 0.3, 120, ACCENT)
	_text_centered("Record solo : %d" % best, vp.y * 0.36, 30, MUTED)
	for i in MENU_ITEMS.size():
		var y := _menu_y(i)
		var color: Color = PLAYER_COLORS[0] if i == 0 else COLORS[[0, Element.LEAF, Element.SUNNY, Element.BLAZE][i]].darkened(0.15)
		_panel(Rect2(vp.x * 0.13, y - 44, vp.x * 0.74, 88), Color(BOARD_BG, 0.9), color, 6, 44)
		_text_centered(MENU_ITEMS[i][0], y + 14, 38, Color.WHITE)
	_text_centered("Glisser : déplacer   ·   Toucher gauche / droite : tourner", vp.y * 0.92, 22, MUTED)
	_text_centered("Glisser vers le bas : descendre   ·   vite : chute", vp.y * 0.95, 22, MUTED)


func _draw_top_bar(vp: Vector2) -> void:
	var names := ["TOI", "IA"] if _versus() else ["SOLO"]
	for i in names.size():
		var w := vp.x / 2 - 24 if _versus() else vp.x - 40
		var x := 16.0 if i == 0 else vp.x / 2 + 8
		var rect := Rect2(x, 40, w, 64)
		_panel(rect, PLAYER_COLORS[i], Color.WHITE, 4, 32)
		# Avatar: a big Poko at the outer end of the bar
		var av := 88.0
		var av_x := rect.position.x - 4 if i == 0 else rect.end.x - av + 4
		draw_circle(Vector2(av_x + av / 2, rect.get_center().y), av / 2, Color.WHITE)
		_draw_blob(Vector2(av_x + 4, rect.get_center().y - av / 2 + 4), PLAYER_AVATAR[i] + 1, av - 8)
		var tx: float = rect.position.x + (av if i == 0 else 16)
		_text(names[i], Vector2(tx, rect.position.y + 46), 36, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, w - av - 16, 6)


func _draw_bottom_bar(vp: Vector2) -> void:
	var y := vp.y - 70
	if _versus():
		_panel(Rect2(vp.x / 2 - 170, y - 34, 340, 68), Color(BOARD_BG, 0.95), Color.WHITE, 4, 34)
		_text_centered("VICTOIRES", y + 12, 30, Color.WHITE)
		for i in 2:
			for k in ROUNDS_TO_WIN:
				var cx := vp.x / 2 + (-1 if i == 0 else 1) * (128 - k * 26)
				_draw_star(Vector2(cx, y), 14, ACCENT if wins[i] > k else Color(1, 1, 1, 0.25))
		_text_centered("%d:%02d" % [int(elapsed) / 60, int(elapsed) % 60], y - 52, 30, MUTED)


func _draw_star(c: Vector2, r: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 10:
		var rr := r if k % 2 == 0 else r * 0.45
		pts.append(c + Vector2.from_angle(-PI / 2 + k * PI / 5) * rr)
	draw_colored_polygon(pts, color)


func _draw_result(vp: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, vp), Color(0, 0, 0, 0.55))
	var title: String
	if not _versus():
		title = "Fin de partie"
	elif match_over:
		title = "Victoire !" if won else "Défaite…"
	else:
		title = "Manche gagnée !" if won else "Manche perdue"
	_panel(Rect2(40, vp.y * 0.33, vp.x - 80, vp.y * 0.34), Color(BOARD_BG, 0.95), PLAYER_COLORS[0 if won or not _versus() else 1], 8, 28)
	_text_centered(title, vp.y * 0.43, 76, ACCENT)
	if _versus():
		_text_centered("%d  -  %d" % wins, vp.y * 0.51, 56, Color.WHITE)
	else:
		_text_centered("Score : %d" % players[0].score, vp.y * 0.5, 44, Color.WHITE)
		_text_centered("Record : %d" % best, vp.y * 0.55, 32, MUTED)
	var next := "Touchez pour continuer" if match_over else "Touchez pour la manche suivante"
	_text_centered(next, vp.y * 0.62, 30, Color.WHITE)


func _draw_player(i: int) -> void:
	var p := players[i]
	var b := p.board
	var cell := _cell()
	var origin := _origin(i)
	var size := _board_size()
	var jitter := Vector2(randf_range(-shake, shake), randf_range(-shake, shake)) if i == 0 and shake > 0 else Vector2.ZERO
	var at := func(x: float, y: float) -> Vector2: return origin + jitter + Vector2(x, y - Board.HIDDEN) * cell

	# Frame: a strip above the grid shows incoming garbage
	var strip := cell * 0.9
	_panel(Rect2(origin + jitter - Vector2(8, strip + 8), size + Vector2(16, strip + 16)), BOARD_BG, PLAYER_COLORS[i], 8, 18)
	draw_rect(Rect2(origin + jitter, size), Color(PLAYER_COLORS[i], 0.07))
	for x in range(1, Board.COLS):
		draw_line(origin + jitter + Vector2(x * cell, 0), origin + jitter + Vector2(x * cell, size.y), Color(1, 1, 1, 0.04), 2)
	_draw_pending(p.pending_garbage, origin + jitter + Vector2(0, -strip / 2 - 4), cell)

	# Spawn marker: a red cross where a blocked spawn means defeat
	if b.grid[Board.HIDDEN][Board.SPAWN_COL] == 0:
		var xc: Vector2 = at.call(Board.SPAWN_COL + 0.5, Board.HIDDEN + 0.5)
		var xr := cell * 0.28
		draw_line(xc - Vector2(xr, xr), xc + Vector2(xr, xr), Color("#ff3b3b", 0.8), cell * 0.16)
		draw_line(xc + Vector2(-xr, xr), xc + Vector2(xr, -xr), Color("#ff3b3b", 0.8), cell * 0.16)

	var t := p.fall_progress()
	var animating := p.state == Player.State.SETTLING or p.state == Player.State.GARBAGE
	var still := func(c: Vector2i) -> bool:
		return not (animating and p.drops.has(c)) and not (p.state == Player.State.POPPING and p.popping.has(c))

	# Same-color neighbours melt together: draw bridges under the blobs
	for y in range(Board.HIDDEN, Board.H):
		for x in Board.COLS:
			var color: int = b.grid[y][x]
			if color == 0 or color == Board.GARBAGE or not still.call(Vector2i(x, y)):
				continue
			var c: Vector2 = at.call(x + 0.5, y + 0.5)
			var bw := cell * 0.62
			if x + 1 < Board.COLS and b.grid[y][x + 1] == color and still.call(Vector2i(x + 1, y)):
				draw_rect(Rect2(c - Vector2(0, bw / 2), Vector2(cell, bw)), COLORS[color - 1])
			if y + 1 < Board.H and b.grid[y + 1][x] == color and still.call(Vector2i(x, y + 1)):
				draw_rect(Rect2(c - Vector2(bw / 2, 0), Vector2(bw, cell)), COLORS[color - 1])

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
				var off: float = p.drops.get(c, 0) * (1 - t) if animating else 0.0
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

	_draw_next(i, cell)

	# Big score digits under the board
	var digits := 44 if _versus() else 56
	_text("%08d" % p.score, Vector2(origin.x - 8, origin.y + size.y + digits + 18), digits, Color.WHITE, HORIZONTAL_ALIGNMENT_CENTER, size.x + 16)

	# Chain callout pops in, then fades
	if chain_text_t[i] > 0:
		var age: float = CHAIN_TEXT_TIME - chain_text_t[i]
		var pop := minf(1.0, age / 0.12)
		var fsize := int((40 if _versus() else 64) * (0.6 + 0.4 * pop + 0.15 * sin(minf(age, 0.3) / 0.3 * PI)))
		var col := Color(CHAIN_FILL, minf(1.0, chain_text_t[i] * 3))
		_text(chain_text[i], Vector2(origin.x - 8, origin.y + size.y * 0.42 - age * 30), fsize, col, HORIZONTAL_ALIGNMENT_CENTER, size.x + 16)


## Stepped NEXT panel: next pair large, the one after smaller and offset.
func _draw_next(i: int, cell: float) -> void:
	var b := players[i].board
	var origin := _origin(i)
	var size := _board_size()
	var s := cell * 0.95
	var box := Vector2(s + 20, s * 2 + 20)
	var small := 0.72
	var box2 := Vector2(s * small + 16, s * small * 2 + 16)
	var p0: Vector2
	var p1: Vector2
	if _versus():
		var cx := get_viewport_rect().size.x / 2
		if i == 0:
			p0 = Vector2(origin.x + size.x + 10, origin.y - cell * 0.9 - 8)
			p1 = Vector2(p0.x + 6, p0.y + box.y + 4)
		else:
			p0 = Vector2(origin.x - 10 - box.x, origin.y + box.y + box2.y + 10)
			p1 = Vector2(origin.x - 10 - box2.x - 6, p0.y + box.y + 4)
	else:
		p0 = Vector2(origin.x + size.x + 20, origin.y - cell * 0.9 - 8)
		p1 = Vector2(p0.x + 8, p0.y + box.y + 4)
	_panel(Rect2(p0, box), Color(PLAYER_COLORS[i], 0.9), Color.WHITE, 4, 12)
	_panel(Rect2(p1, box2), Color(PLAYER_COLORS[i], 0.75), Color.WHITE, 3, 10)
	if b.queue.size() >= 2:
		var n0: Array = b.queue[0]
		var n1: Array = b.queue[1]
		_draw_blob(p0 + Vector2(10, 10), n0[1], s)
		_draw_blob(p0 + Vector2(10, 10 + s), n0[0], s)
		_draw_blob(p1 + Vector2(8, 8), n1[1], s * small)
		_draw_blob(p1 + Vector2(8, 8 + s * small), n1[0], s * small)


## Incoming garbage shown as icons (crown 720, moon 360, star 180, rock 30, big 6, small 1).
func _draw_pending(n: int, at: Vector2, cell: float) -> void:
	var x := 0.0
	var shown := 0
	for icon in GARBAGE_ICONS:
		while n >= icon[0] and shown < 6:
			n -= icon[0]
			var r: float = cell * icon[2]
			var c := at + Vector2(x + cell * 0.5, 0)
			if icon[0] >= 180:
				_draw_star(c, r * 1.2, icon[1])
			else:
				draw_circle(c, r, icon[1])
				draw_circle(c + Vector2(-r * 0.35, 0), r * 0.18, INK)
				draw_circle(c + Vector2(r * 0.35, 0), r * 0.18, INK)
			x += cell
			shown += 1


## `kind` is a board value: 1..5 element, Board.GARBAGE for nuisance.
func _draw_blob(at: Vector2, kind: int, size: float, scale: float = 1.0, alpha: float = 1.0, tint: Variant = null) -> void:
	var r := (size / 2 - 2) * scale
	var c := at + Vector2(size, size) / 2
	var base: Color = GARBAGE_COLOR if kind == Board.GARBAGE else COLORS[kind - 1]
	var fill: Color = tint if tint != null else base
	draw_circle(c + Vector2(0, r * 0.08), r, Color(base.darkened(0.35), alpha)) # bottom shade
	draw_circle(c, r * 0.96, Color(fill, alpha))
	draw_circle(c - Vector2(r, r) * 0.35, r * 0.28, Color(1, 1, 1, 0.45 * alpha))
	if kind == Board.GARBAGE:
		# Nuisance: big empty eyes, no emotion
		for sx in [-1, 1]:
			draw_circle(c + Vector2(sx * r * 0.32, 0), r * 0.24, Color(INK, alpha * 0.7))
			draw_circle(c + Vector2(sx * r * 0.32, 0), r * 0.14, Color(1, 1, 1, alpha))
	else:
		_draw_face(c, r, kind - 1, Color(INK, alpha))


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


