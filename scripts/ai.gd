class_name AI
extends RefCounted
## Computer opponent: picks a placement for each new pair, then plays it
## with human-like inputs (one action every few frames).

enum Level { EASY, NORMAL, HARD }

const ACTION_DELAY := [0.28, 0.14, 0.07]
const TARGET_CHAIN := [1, 3, 5] # chain length it tries to build before firing
const NOISE := [400.0, 60.0, 0.0]

var player: Player
var level := Level.NORMAL
var plan: Array = [] # "L", "R", "CW", "CCW", "DROP"
var planned_for := -1
var action_timer := 0.0


func _init(p: Player, lvl: int) -> void:
	player = p
	level = lvl


func update(delta: float) -> void:
	if player.state != Player.State.FALLING:
		return
	if planned_for != player.piece_id:
		planned_for = player.piece_id
		plan = _make_plan()
		action_timer = 0.0
	action_timer += delta
	if action_timer < ACTION_DELAY[level] or plan.is_empty():
		return
	action_timer = 0.0
	match plan.pop_front():
		"L": player.move(-1)
		"R": player.move(1)
		"CW": player.rotate(1)
		"CCW": player.rotate(-1)
		"DROP":
			if level == Level.EASY:
				player.soft_drop = true
			else:
				player.hard_drop()


func _make_plan() -> Array:
	player.soft_drop = false
	var b := player.board
	var best_score := -INF
	var best := Vector2i(Board.SPAWN_COL, 0)
	for r in 4:
		for x in Board.COLS:
			var sim := b.clone()
			var res := sim.simulate_drop(x, r, b.a, b.b)
			if not res.ok:
				continue
			var value: float = _evaluate(sim, res) + randf() * NOISE[level]
			if value > best_score:
				best_score = value
				best = Vector2i(x, r)
	var actions := []
	match best.y:
		1: actions.append("CW")
		2: actions.append_array(["CW", "CW"])
		3: actions.append("CCW")
	var dx := best.x - Board.SPAWN_COL
	for i in absi(dx):
		actions.append("R" if dx > 0 else "L")
	actions.append("DROP")
	return actions


func _evaluate(sim: Board, res: Dictionary) -> float:
	if sim.grid[Board.HIDDEN][Board.SPAWN_COL] != 0:
		return -1e9
	var heights := _heights(sim)
	var max_h: int = heights.max()
	var danger: bool = max_h >= 9 or heights[Board.SPAWN_COL] >= 8 or player.pending_garbage >= 6
	var value := 0.0
	if res.chains > 0:
		# Fire when the chain is big enough, or when under pressure; otherwise keep building
		if res.chains >= TARGET_CHAIN[level] or danger:
			value += res.points * 2.0 + res.chains * 500.0
		else:
			value -= 300.0
	value += _connections(sim) * 12.0
	value -= max_h * 8.0 + heights[Board.SPAWN_COL] * 25.0
	if level == Level.HARD:
		value += _chain_potential(sim) * 250.0
	return value


func _heights(sim: Board) -> Array:
	var h := []
	for x in Board.COLS:
		var n := 0
		for y in Board.H:
			if sim.grid[y][x] != 0:
				n = Board.H - y
				break
		h.append(n)
	return h


## Pairs of touching same-color Pokos: rewards keeping colors together.
func _connections(sim: Board) -> int:
	var n := 0
	for y in range(Board.HIDDEN, Board.H):
		for x in Board.COLS:
			var c: int = sim.grid[y][x]
			if c == 0 or c == Board.GARBAGE:
				continue
			if x + 1 < Board.COLS and sim.grid[y][x + 1] == c:
				n += 1
			if y + 1 < Board.H and sim.grid[y + 1][x] == c:
				n += 1
	return n


## Longest chain triggerable by dropping one vertical same-color pair anywhere.
func _chain_potential(sim: Board) -> int:
	var best := 0
	for color in range(1, sim.num_colors + 1):
		for x in Board.COLS:
			var t := sim.clone()
			var res := t.simulate_drop(x, 0, color, color)
			if res.ok:
				best = maxi(best, res.chains)
	return best
