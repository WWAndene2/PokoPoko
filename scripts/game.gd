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
	["Versus IA · Easy", AI.Level.EASY],
	["Versus IA · Normal", AI.Level.NORMAL],
	["Versus IA · Hard", AI.Level.HARD],
	["Versus IA · Extreme", AI.Level.EXTREME],
	["Versus IA · Insane", AI.Level.INSANE],
]
const MENU_COLORS := [Color("#2f8fff"), Color("#7ee36b"), Color("#ffd84f"), Color("#ff9a3c"), Color("#ff4f6a"), Color("#9b6bff")]

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

# Visual-only physics: particles, attack orbs and the smoothed falling pair
const PARTICLE_GRAVITY := 1400.0
const ORB_TIME := 0.45
var particles: Array = [] # {pos, vel, color, life, max, size}
var orbs: Array = [] # {from, to, t, color, size, target}
var piece_vis := [{"id": -1}, {"id": -1}] # per player: {id, x, ang}
var link_birth := [{}, {}] # per player: Vector3i(x, y, dir) -> time the fusion formed
# Soft bodies (see SoftPoko), per player: grid Pokos keyed by cell, plus the falling pair
var bodies := [{}, {}]
var piece_bodies := [[], []]
var piece_body_id := [-1, -1]
var body_serial := [Vector2i.ZERO, Vector2i.ZERO] # last seen (lock_serial, fall_serial)
var land_done := [0.0, 0.0] # landing impacts already applied up to this player time
var links := [[], []] # current fusions, for the element effects: [a, b, kind, grow]

# _draw_blob layers, so fused groups can be drawn as one body
const L_SHADE := 1
const L_FILL := 2
const L_DETAIL := 4
const FUSE_TIME := 0.6

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
	particles.clear()
	orbs.clear()
	piece_vis = [{"id": -1}, {"id": -1}]
	link_birth = [{}, {}]
	bodies = [{}, {}]
	piece_bodies = [[], []]
	piece_body_id = [-1, -1]
	body_serial = [Vector2i.ZERO, Vector2i.ZERO]
	land_done = [0.0, 0.0]
	links = [[], []]
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
	_update_piece_vis(delta)
	if screen != Screen.MENU:
		for i in players.size():
			_sync_bodies(i)
			_step_bodies(i, delta)
	_update_fx(delta)
	for i in 2:
		chain_text_t[i] = maxf(0.0, chain_text_t[i] - delta)
	shake = maxf(0.0, shake - delta * 60.0)
	queue_redraw()


func _handle_events(i: int) -> void:
	var p := players[i]
	for e in p.events:
		match e[0]:
			"chain":
				_on_pop(i)
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
			"garbage":
				if i == 0 and e[1] >= 6:
					shake = minf(3.0 + e[1] * 0.4, 14.0)
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
	return get_viewport_rect().size.y * 0.4 + i * 100


func _menu_tap(at: Vector2) -> void:
	if screen == Screen.RESULT:
		if match_over:
			screen = Screen.MENU
		else:
			_start_round()
		return
	for i in MENU_ITEMS.size():
		if absf(at.y - _menu_y(i)) < 44:
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
	_draw_fx()
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
	_text_centered("PokoPoko", vp.y * 0.25, 120, ACCENT)
	_text_centered("Record solo : %d" % best, vp.y * 0.3, 30, MUTED)
	for i in MENU_ITEMS.size():
		var y := _menu_y(i)
		_panel(Rect2(vp.x * 0.13, y - 40, vp.x * 0.74, 80), Color(BOARD_BG, 0.9), MENU_COLORS[i], 6, 40)
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

	# Pokos are soft bodies (stepped in _step_bodies). Draw them layer by layer so fused
	# bodies blend into one mass: aura, shade, body, element life, faces.
	var r := cell / 2 - 2
	var bod: Dictionary = bodies[i]
	var popping := {}
	if p.state == Player.State.POPPING:
		for c in p.popping:
			popping[c] = true
	for l in links[i]:
		for c in [l[0], l[1]]:
			if bod.has(c):
				_draw_aura(l[2], bod[c].center + jitter, r)
	for layer in [L_SHADE, L_FILL]:
		for c in bod:
			if not popping.has(c):
				_draw_soft(bod[c], b.grid[c.y][c.x], jitter, layer)
	for l in links[i]:
		if bod.has(l[0]) and bod.has(l[1]):
			_link_fx(l[2], bod[l[0]].center + jitter, bod[l[1]].center + jitter, r, l[3], float(l[0].x * 3 + l[0].y * 5) * 0.71)
	for c in bod:
		if not popping.has(c):
			_draw_soft(bod[c], b.grid[c.y][c.x], jitter, L_DETAIL, 1.0, null, 1.0, _idle(b.grid[c.y][c.x], c.x, c.y).blink)
	for c in popping:
		if bod.has(c):
			# Swell and flash, then burst (particles spawn in _on_pop)
			var pt := p.anim_t / Player.POP_TIME
			var flash := int(p.anim_t / 0.06) % 2 == 1
			_draw_soft(bod[c], b.grid[c.y][c.x], jitter, L_SHADE | L_FILL | L_DETAIL, 1 - pt * pt, Color.WHITE if flash else null, 1 + pt * 0.35)

	if b.has_piece and p.state == Player.State.FALLING:
		var g := b.ghost_pos()
		for pc in b.piece_cells(g):
			if pc[0].y >= Board.HIDDEN:
				_draw_blob(at.call(pc[0].x, pc[0].y), pc[1], cell, 0.45, 0.35)
		var pb: Array = piece_bodies[i]
		if pb.size() == 2:
			for k in 2:
				if pb[k].center.y >= origin.y - cell * 0.5:
					_draw_soft(pb[k], b.a if k == 0 else b.b, jitter, L_SHADE | L_FILL | L_DETAIL)

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
## `squash` scales around the Poko's bottom (x = width, y = height), `tilt` rotates it.
func _draw_blob(at: Vector2, kind: int, size: float, scale: float = 1.0, alpha: float = 1.0, tint: Variant = null,
		squash := Vector2.ONE, tilt := 0.0, blink := false, layers := L_SHADE | L_FILL | L_DETAIL) -> void:
	var r := (size / 2 - 2) * scale
	draw_set_transform(at + Vector2(size / 2, size / 2 + r), tilt, squash)
	var c := Vector2(0, -r)
	var base: Color = GARBAGE_COLOR if kind == Board.GARBAGE else COLORS[kind - 1]
	var fill: Color = tint if tint != null else base
	if layers & L_SHADE:
		draw_circle(c + Vector2(0, r * 0.08), r, Color(base.darkened(0.35), alpha)) # bottom shade
	if layers & L_FILL:
		draw_circle(c, r * 0.96, Color(fill, alpha))
	if not layers & L_DETAIL:
		draw_set_transform(Vector2.ZERO)
		return
	draw_circle(c - Vector2(r, r) * 0.35, r * 0.28, Color(1, 1, 1, 0.45 * alpha))
	if kind == Board.GARBAGE:
		# Nuisance: big empty eyes, no emotion
		for sx in [-1, 1]:
			draw_circle(c + Vector2(sx * r * 0.32, 0), r * 0.24, Color(INK, alpha * 0.7))
			draw_circle(c + Vector2(sx * r * 0.32, 0), r * 0.14, Color(1, 1, 1, alpha))
	else:
		_draw_face(c, r, kind - 1, Color(INK, alpha), blink)
	draw_set_transform(Vector2.ZERO)


## Each element has its own expression.
func _draw_face(c: Vector2, r: float, element: int, ink: Color, blink := false) -> void:
	var w := maxf(1.5, r * 0.09)
	var le := c + Vector2(-r * 0.3, 0)
	var re := c + Vector2(r * 0.3, 0)
	var mouth := c + Vector2(0, r * 0.35)
	match element:
		Element.AQUA: # confident and brave: round eyes, determined brows, firm smile
			if blink:
				draw_line(le - Vector2(r * 0.12, 0), le + Vector2(r * 0.12, 0), ink, w)
				draw_line(re - Vector2(r * 0.12, 0), re + Vector2(r * 0.12, 0), ink, w)
			else:
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
			if not blink:
				draw_circle(le + Vector2(0, r * 0.05), r * 0.06, ink)
				draw_circle(re + Vector2(0, r * 0.05), r * 0.06, ink)
			draw_line(mouth + Vector2(-r * 0.07, 0), mouth + Vector2(r * 0.07, 0), ink, w)




# --- Animation and effects ---------------------------------------------------

## Damped spring after landing: squashed flat at impact, then wobbles back to round.
## Idle "emotion" of a Poko, expressed as physics inputs for its soft body:
## offset (cells) moves its center, breath scales its rest size, jitter shakes it.
func _idle(kind: int, x: int, y: int) -> Dictionary:
	var res := {"offset": Vector2.ZERO, "breath": 1.0, "jitter": 0.0, "blink": false}
	var ph := float(x * 7 + y * 13) * 0.37
	var t := clock
	match kind - 1:
		Element.AQUA: # confident: deep, steady breathing; blinks now and then
			res.breath = 1.0 + 0.035 * sin(t * 2.2 + ph)
			res.blink = fmod(t + ph * 3.0, 5.0) < 0.12
		Element.BLAZE: # aggressive: restless trembling with bursts of anger
			res.jitter = 0.05
			var flare := fmod(t + ph, 3.0)
			if flare < 0.3:
				res.jitter = 0.16
				res.breath = 1.0 + 0.05 * sin(flare / 0.3 * PI)
		Element.LEAF: # calm: leans gently from side to side
			res.offset = Vector2(sin(t * 1.2 + ph) * 0.035, 0)
		Element.SUNNY: # joyful: little hops, landing squashes it
			var u := fmod(t * 0.8 + ph, 2.0)
			if u < 0.4:
				res.offset = Vector2(0, -sin(u / 0.4 * PI) * 0.12)
		Element.NOVA: # mysterious: slow floating, long blinks
			res.offset = Vector2(0, sin(t * 1.0 + ph) * 0.03)
			res.blink = fmod(t + ph * 2.0, 4.0) < 0.3
	return res


func _update_piece_vis(delta: float) -> void:
	for i in players.size():
		var b := players[i].board
		if not b.has_piece:
			continue
		var target_ang := -PI / 2 + b.rot * PI / 2
		var vis: Dictionary = piece_vis[i]
		if vis.id != players[i].piece_id:
			piece_vis[i] = {"id": players[i].piece_id, "x": float(b.pos.x), "ang": target_ang}
			continue
		var k := minf(1.0, delta * 22.0)
		vis.x = lerpf(vis.x, b.pos.x, k)
		vis.ang = lerp_angle(vis.ang, target_ang, minf(1.0, delta * 26.0))


func _cell_center(i: int, c: Vector2i) -> Vector2:
	return _origin(i) + (Vector2(c) + Vector2(0.5, 0.5 - Board.HIDDEN)) * _cell()


## A group starts popping: splash droplets, and in versus an attack orb flies off.
func _on_pop(i: int) -> void:
	var p := players[i]
	var cell := _cell()
	var centroid := Vector2.ZERO
	var count := 0
	var orb_color := Color.WHITE
	for c in p.popping:
		var kind: int = p.board.grid[c.y][c.x]
		var col: Color = GARBAGE_COLOR if kind == Board.GARBAGE else COLORS[kind - 1]
		var pos := _cell_center(i, c)
		if kind != Board.GARBAGE:
			centroid += pos
			count += 1
			orb_color = col
		for k in 7:
			var ang := randf_range(-PI * 0.95, -PI * 0.05)
			particles.append({"pos": pos, "vel": Vector2.from_angle(ang) * randf_range(180, 520) * cell / 50.0,
				"color": col, "life": 0.0, "max": randf_range(0.35, 0.7), "size": randf_range(0.08, 0.16) * cell})
	if count == 0 or not _versus():
		return
	centroid /= count
	# Sending if the chain produced attack, otherwise it is cancelling our own garbage
	var target := 1 - i if p.attack > 0 else i
	var to := _origin(target) + Vector2(_board_size().x / 2, -cell * 0.45 - 4)
	orbs.append({"from": centroid, "to": to, "t": 0.0, "color": orb_color, "size": cell * 0.35, "target": target})


func _update_fx(delta: float) -> void:
	for pt in particles:
		pt.vel.y += PARTICLE_GRAVITY * delta
		pt.pos += pt.vel * delta
		pt.life += delta
	particles = particles.filter(func(pt): return pt.life < pt.max)
	for o in orbs:
		o.t += delta / ORB_TIME
		if o.t >= 1.0:
			for k in 12:
				particles.append({"pos": o.to, "vel": Vector2.from_angle(randf() * TAU) * randf_range(120, 360),
					"color": o.color.lightened(0.3), "life": 0.0, "max": 0.4, "size": o.size * 0.3})
			if o.target == 0:
				shake = maxf(shake, 5.0)
	orbs = orbs.filter(func(o): return o.t < 1.0)


func _orb_pos(o: Dictionary, t: float) -> Vector2:
	# Quadratic Bezier arcing upward between the boards
	var mid: Vector2 = (o.from + o.to) / 2 + Vector2(0, -220)
	var e := ease(clampf(t, 0, 1), 0.6)
	return o.from.lerp(mid, e).lerp(mid.lerp(o.to, e), e)


func _draw_fx() -> void:
	for pt in particles:
		var k: float = 1.0 - pt.life / pt.max
		draw_circle(pt.pos, pt.size * (0.4 + 0.6 * k), Color(pt.color, k))
	for o in orbs:
		for s in range(6, 0, -1):
			var tp: float = o.t - s * 0.035
			if tp > 0:
				draw_circle(_orb_pos(o, tp), o.size * (1.0 - s * 0.13), Color(o.color, 0.5 - s * 0.07))
		var head := _orb_pos(o, o.t)
		draw_circle(head, o.size * 1.5, Color(o.color, 0.25))
		draw_circle(head, o.size, o.color.lightened(0.2))
		draw_circle(head, o.size * 0.5, Color(1, 1, 1, 0.9))


# --- Fusion ------------------------------------------------------------------

## How far a fusion has formed: snaps in, overshoots and wobbles like sticky jelly.
func _jelly_grow(age: float) -> float:
	if age >= FUSE_TIME:
		return 1.0
	return 1.0 - exp(-7.0 * age) * cos(16.0 * age)


## Soft elemental glow behind a fused Poko.
func _draw_aura(kind: int, c: Vector2, r: float) -> void:
	match kind - 1:
		Element.AQUA:
			draw_circle(c, r * 1.22, Color(COLORS[Element.AQUA], 0.14))
		Element.BLAZE:
			draw_circle(c, r * (1.2 + 0.07 * sin(clock * 9.0 + c.x * 0.1 + c.y * 0.07)), Color("#ff8a3a", 0.18))
		Element.LEAF:
			draw_circle(c, r * 1.2, Color("#9cff7a", 0.11))
		Element.SUNNY:
			draw_circle(c, r * (1.26 + 0.05 * sin(clock * 3.0)), Color("#fff2a0", 0.2))
		Element.NOVA:
			draw_circle(c, r * 1.24, Color("#14062e", 0.45))


## Element life where two Pokos are stuck together (no lines: particles living in the jelly).
func _link_fx(kind: int, c1: Vector2, c2: Vector2, r: float, grow: float, seed: float) -> void:
	var a := clampf(grow, 0.0, 1.0)
	if a <= 0.05:
		return
	var t := clock
	var mid := (c1 + c2) / 2
	var horizontal := absf(c2.x - c1.x) > absf(c2.y - c1.y)
	match kind - 1:
		Element.AQUA: # water: bubbles rising through the joint, a wet shine
			draw_circle(mid + Vector2(-r * 0.1, -r * 0.15), r * 0.16, Color(1, 1, 1, 0.28 * a))
			for k in 3:
				var s := fmod(t * 0.5 + k / 3.0 + seed, 1.0)
				var bp := mid + Vector2(sin(s * TAU + seed + k) * r * 0.22, (0.5 - s) * r * 0.9)
				var br := r * 0.11 * (0.5 + 0.5 * sin(s * PI))
				draw_arc(bp, br, 0, TAU, 12, Color(1, 1, 1, 0.85 * a * sin(s * PI)), maxf(1.5, r * 0.05))
				draw_circle(bp - Vector2(br, br) * 0.35, br * 0.3, Color(1, 1, 1, 0.9 * a * sin(s * PI)))
		Element.BLAZE: # fire: flames licking up from the joint, embers drifting away
			draw_circle(mid, r * 0.3, Color("#ffd36b", 0.35 * a))
			for k in 3:
				var base := mid + (Vector2((k - 1) * r * 0.28, -r * 0.45) if horizontal else Vector2((k - 1) * r * 0.3, r * 0.05))
				var h := r * (0.6 + 0.22 * sin(t * 13.0 + k * 2.1 + seed)) * a
				var sway := sin(t * 17.0 + k * 1.7 + seed) * r * 0.1
				_flame(base, r * 0.2, h, sway, Color("#ffae2e", 0.95 * a))
				_flame(base, r * 0.11, h * 0.62, sway * 0.6, Color("#fff3a0", a))
			for k in 2:
				var s := fmod(t * 0.8 + k * 0.5 + seed, 1.0)
				draw_circle(mid + Vector2(sin(s * 9.0 + seed) * r * 0.3, -r * 0.5 - s * r * 1.2), r * 0.05 * (1 - s), Color("#ffcf5a", (1 - s) * a))
		Element.LEAF: # plant: two leaves sprouting from the joint, swaying
			var sway := sin(t * 1.6 + seed) * 0.35
			var up := -PI / 2 if horizontal else 0.0
			_leaf(mid, up - 0.7 + sway, r * 0.5 * a, r * 0.17, Color("#c4ff8a", 0.95 * a))
			_leaf(mid, up + 0.7 + sway, r * 0.42 * a, r * 0.14, Color("#a8f07a", 0.95 * a))
			draw_circle(mid, r * 0.08, Color("#2f8a34", 0.9 * a))
		Element.SUNNY: # light: a warm glowing heart with twinkling sparkles
			var pulse := 0.5 + 0.5 * sin(t * 4.0 + seed)
			draw_circle(mid, r * (0.38 + 0.08 * pulse), Color("#fffbe0", 0.35 * a))
			draw_circle(mid, r * 0.2, Color(1, 1, 1, (0.45 + 0.3 * pulse) * a))
			for k in 2:
				var sp := mid + Vector2.from_angle(t * 0.8 + k * PI + seed) * r * 0.42
				_sparkle(sp, r * 0.24 * absf(sin(t * 4.0 + k * 2.0 + seed)) * a, Color(1, 1, 1, 0.95 * a))
		Element.NOVA: # shadow: a dark swirl in the joint with tiny stars orbiting
			draw_circle(mid, r * 0.34, Color("#1a0838", 0.45 * a))
			draw_circle(mid, r * 0.2, Color("#1a0838", 0.5 * a))
			for k in 3:
				var sp := mid + Vector2.from_angle(-t * 1.2 + k * TAU / 3 + seed) * r * 0.3
				_sparkle(sp, r * 0.12 * (0.5 + 0.5 * absf(sin(t * 2.5 + k * 1.9 + seed))) * a, Color(1, 1, 1, 0.9 * a))


func _flame(base: Vector2, half_w: float, h: float, sway: float, color: Color) -> void:
	var pts := PackedVector2Array()
	for k in 9:
		var s := k / 8.0
		var w := sin(s * PI) * half_w * (1.0 - s * 0.5) + (half_w * 0.5 if k == 0 else 0.0) # rounded base
		pts.append(base + Vector2(-w + sway * s * s, -h * s))
	for k in range(7, 0, -1):
		var s := k / 8.0
		var w := sin(s * PI) * half_w * (1.0 - s * 0.5)
		pts.append(base + Vector2(w + sway * s * s, -h * s))
	draw_colored_polygon(pts, color)


func _leaf(base: Vector2, angle: float, length: float, width: float, color: Color) -> void:
	if length < 1.0:
		return
	var dir := Vector2.from_angle(angle)
	var perp := Vector2(-dir.y, dir.x)
	var pts := PackedVector2Array()
	for k in 9:
		var s := k / 8.0
		pts.append(base + dir * s * length + perp * sin(s * PI) * width)
	for k in range(7, 0, -1):
		var s := k / 8.0
		pts.append(base + dir * s * length - perp * sin(s * PI) * width)
	draw_colored_polygon(pts, color)
	draw_line(base, base + dir * length * 0.85, Color(color.darkened(0.35), color.a), maxf(1.0, width * 0.18))


## Four-pointed twinkle.
func _sparkle(c: Vector2, size: float, color: Color) -> void:
	if size < 0.5:
		return
	var pts := PackedVector2Array()
	for k in 8:
		pts.append(c + Vector2.from_angle(k * PI / 4) * (size if k % 2 == 0 else size * 0.25))
	draw_colored_polygon(pts, color)


# --- Soft bodies ---------------------------------------------------------------

## Keeps each Poko's soft body attached to it as the board changes (lock, falls, pops).
func _sync_bodies(i: int) -> void:
	var p := players[i]
	var b := p.board
	var bod: Dictionary = bodies[i]
	if p.lock_serial != body_serial[i].x:
		var pb: Array = piece_bodies[i]
		if pb.size() == 2:
			for e in p.last_lock:
				bod[e[0]] = pb[1 if e[1] else 0]
		piece_bodies[i] = []
	if p.fall_serial != body_serial[i].y:
		var moved := {}
		var nb := {}
		for dest in p.drops:
			var src: Vector2i = dest - Vector2i(0, p.drops[dest])
			if bod.has(src):
				nb[dest] = bod[src]
				moved[src] = true
		for c in bod:
			if not moved.has(c) and not nb.has(c):
				nb[c] = bod[c]
		bod = nb
	body_serial[i] = Vector2i(p.lock_serial, p.fall_serial)
	for c in bod.keys():
		if c.y < Board.HIDDEN or b.grid[c.y][c.x] == 0:
			bod.erase(c)
	var r := _cell() / 2 - 2
	for y in range(Board.HIDDEN, Board.H):
		for x in Board.COLS:
			if b.grid[y][x] != 0 and not bod.has(Vector2i(x, y)):
				bod[Vector2i(x, y)] = SoftPoko.new(r)
	bodies[i] = bod


func _step_bodies(i: int, delta: float) -> void:
	var p := players[i]
	var b := p.board
	var cell := _cell()
	var r := cell / 2 - 2
	var reach := cell / 2 - r + r * 0.55
	var bod: Dictionary = bodies[i]
	var resting := func(c: Vector2i) -> bool:
		return p.fall_offset(c) <= 0.0 and not (p.state == Player.State.POPPING and p.popping.has(c))

	# Fusions between resting same-color Pokos; each one snaps in like sticky jelly
	var grow := {}
	var births := {}
	links[i] = []
	for c in bod:
		var kind: int = b.grid[c.y][c.x]
		if kind == Board.GARBAGE or not resting.call(c):
			continue
		for d in [Vector2i.RIGHT, Vector2i.DOWN]:
			var n: Vector2i = c + d
			if n.x < Board.COLS and n.y < Board.H and b.grid[n.y][n.x] == kind and bod.has(n) and resting.call(n):
				var key := Vector3i(c.x, c.y, 0 if d == Vector2i.RIGHT else 1)
				births[key] = link_birth[i].get(key, clock)
				grow[key] = _jelly_grow(clock - births[key])
				links[i].append([c, n, kind, grow[key]])
	link_birth[i] = births

	# Landing impacts: flatten the Poko, and its fused group feels it too
	for c in p.land:
		var lt: float = p.land[c][0]
		if lt > land_done[i] and lt <= p.time and bod.has(c):
			var strength: float = p.land[c][1] * 5.0
			bod[c].squash_kick(strength)
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				if bod.has(n) and b.grid[n.y][n.x] == b.grid[c.y][c.x]:
					bod[n].squash_kick(strength * 0.5)
	land_done[i] = p.time

	for c in bod:
		var kind: int = b.grid[c.y][c.x]
		var home := _cell_center(i, c)
		var fall := p.fall_offset(c)
		var idle := _idle(kind, c.x, c.y)
		var center: Vector2 = home - Vector2(0, fall * cell) + idle.offset * cell
		var planes := []
		var sticks := []
		if fall <= 0.0:
			for d in [Vector2i.LEFT, Vector2i.RIGHT, Vector2i.UP, Vector2i.DOWN]:
				var n: Vector2i = c + d
				var nd := Vector2(d)
				# Contact plane at the cell edge, measured from the current (possibly hopping) center
				var dist: float = cell / 2 - 1 - (center - home).dot(nd)
				if n.x < 0 or n.x >= Board.COLS or n.y >= Board.H:
					planes.append([nd, dist])
					continue
				if n.y < Board.HIDDEN:
					continue
				var nk: int = b.grid[n.y][n.x]
				if nk == 0 or p.fall_offset(n) > 0.0:
					continue
				var key := Vector3i(mini(c.x, n.x), mini(c.y, n.y), 0 if d.y == 0 else 1)
				if grow.has(key):
					sticks.append([nd, grow[key], reach])
				else:
					planes.append([nd, dist])
		bod[c].step(center, delta, planes, sticks, idle.breath, 0.0, idle.jitter * r)

	# Falling pair: wobbles as it slides, swings when turning, squashes on the floor
	if b.has_piece and p.state == Player.State.FALLING:
		if piece_body_id[i] != p.piece_id or (piece_bodies[i] as Array).size() != 2:
			piece_bodies[i] = [SoftPoko.new(r), SoftPoko.new(r)]
			piece_body_id[i] = p.piece_id
		var smooth := minf(1.0, p.fall_timer / p.fall_delay) if b.can_fall() else 0.0
		var vis: Dictionary = piece_vis[i]
		var pivot := Vector2(vis.get("x", b.pos.x), b.pos.y + smooth)
		var sat := pivot + Vector2.from_angle(vis.get("ang", -PI / 2))
		for k in 2:
			var cp: Vector2 = pivot if k == 0 else sat
			piece_bodies[i][k].step(_origin(i) + (cp + Vector2(0.5, 0.5 - Board.HIDDEN)) * cell, delta, [], [])


## Draws one soft body. `scale` swells it (popping), `alpha`/`tint` fade or flash it.
func _draw_soft(body: SoftPoko, kind: int, shift: Vector2, layers: int, alpha := 1.0, tint: Variant = null,
		scale := 1.0, blink := false) -> void:
	var r := body.r * scale
	var base: Color = GARBAGE_COLOR if kind == Board.GARBAGE else COLORS[kind - 1]
	var fill: Color = tint if tint != null else base
	if layers & L_SHADE:
		_soft_polygon(body.outline(shift + Vector2(0, r * 0.08), scale), body.center + shift, r, Color(base.darkened(0.35), alpha))
	if layers & L_FILL:
		_soft_polygon(body.outline(shift, scale * 0.96), body.center + shift, r * 0.96, Color(fill, alpha))
	if not layers & L_DETAIL:
		return
	# Face and shine ride on the deformed body and squash with it
	var sy := body.squash_ratio()
	sy = clampf(sy, 0.75, 1.12)
	draw_set_transform(body.center + shift + body.centroid() * scale * 0.3, 0.0, Vector2(1.0 / sy, sy))
	draw_circle(Vector2(-r * 0.35, -r * 0.35), r * 0.28, Color(1, 1, 1, 0.45 * alpha))
	if kind == Board.GARBAGE:
		for sx in [-1, 1]:
			draw_circle(Vector2(sx * r * 0.32, 0), r * 0.24, Color(INK, alpha * 0.7))
			draw_circle(Vector2(sx * r * 0.32, 0), r * 0.14, Color(1, 1, 1, alpha))
	else:
		_draw_face(Vector2.ZERO, r, kind - 1, Color(INK, alpha), blink)
	draw_set_transform(Vector2.ZERO)


## Fills a soft-body outline; falls back to a circle if the ring ever folds over itself.
func _soft_polygon(pts: PackedVector2Array, c: Vector2, r: float, color: Color) -> void:
	if Geometry2D.triangulate_polygon(pts).is_empty():
		draw_circle(c, r, color)
	else:
		draw_colored_polygon(pts, color)
