class_name Player
extends RefCounted
## One player's match: falling / settling / popping / garbage state machine,
## scoring, garbage sending, offsetting and all clear. No rendering here.

enum State { IDLE, FALLING, SETTLING, POPPING, GARBAGE, DEAD }

const GRAVITY := 80.0 # cells / s², drives how long falls take (visual + timing)
const MIN_SETTLE_TIME := 0.08
const POP_TIME := 0.35
const LOCK_DELAY := 0.5
const MAX_LOCK_RESETS := 8
const SOFT_DROP_SPEED := 12.0
const ALL_CLEAR_SCORE := 2100
const ALL_CLEAR_GARBAGE := 30
const MAX_GARBAGE_DROP := 30
const START_FALL_DELAY := 0.7

var board: Board
var state := State.IDLE
var versus := false
var score := 0
var fall_timer := 0.0
var fall_delay := START_FALL_DELAY
var lock_timer := 0.0
var lock_resets := 0
var soft_drop := false
var time := 0.0 # local clock, used for fall and landing animations
var anim_t := 0.0
var settle_time := 0.0 # duration of the current fall, from the longest drop
var drops := {} # Vector2i -> fall distance (for the settle / garbage animation)
var land := {} # Vector2i -> [land time, strength] for squash-and-bounce on landing
# Lets the visuals keep each Poko's soft body attached to it as it moves
var fall_serial := 0 # bumped when a new fall starts (drops = destination -> distance)
var lock_serial := 0 # bumped when the pair locks; last_lock = [[cell, is_satellite], ...]
var last_lock: Array = []
var popping: Array = []
var chain := 0
var piece_id := 0
var pending_garbage := 0 # incoming garbage waiting to fall on this board
var attack := 0 # garbage built up by the current chain, sent when it ends
var score_leftover := 0 # points not yet converted into garbage
var target_points := 70 # points per garbage Poko (lowered by margin time)
var all_clear_bonus := false
var events: Array = [] # [name, value] pairs read and cleared by the game


func start(seed_value: int, is_versus: bool) -> void:
	board = Board.new(seed_value)
	versus = is_versus
	score = 0
	fall_delay = START_FALL_DELAY
	pending_garbage = 0
	attack = 0
	score_leftover = 0
	target_points = 70
	all_clear_bonus = false
	piece_id = 0
	_spawn()


func _spawn() -> void:
	chain = 0
	fall_timer = 0.0
	lock_timer = 0.0
	lock_resets = 0
	if board.spawn():
		piece_id += 1
		state = State.FALLING
	else:
		state = State.DEAD
		events.append(["dead", 0])


func update(delta: float) -> void:
	time += delta
	match state:
		State.FALLING:
			if board.can_fall():
				lock_timer = 0.0
				fall_timer += delta * (SOFT_DROP_SPEED if soft_drop else 1.0)
				if fall_timer >= fall_delay:
					fall_timer = 0.0
					board.step_down()
					if soft_drop:
						score += 1
			else:
				# Grace period on the ground; soft drop locks immediately
				lock_timer += delta
				if soft_drop or lock_timer >= LOCK_DELAY:
					_lock()
		State.SETTLING:
			anim_t += delta
			if anim_t >= settle_time:
				_check_pops()
		State.POPPING:
			anim_t += delta
			if anim_t >= POP_TIME:
				board.clear_cells(popping)
				for c in popping:
					land.erase(c)
				popping = []
				_settle()
		State.GARBAGE:
			anim_t += delta
			if anim_t >= settle_time:
				_spawn()


## How many cells above its grid cell `c` is drawn right now (free fall under GRAVITY).
func fall_offset(c: Vector2i) -> float:
	if (state != State.SETTLING and state != State.GARBAGE) or not land.has(c) or not drops.has(c):
		return 0.0
	var remaining: float = land[c][0] - time
	return 0.5 * GRAVITY * remaining * remaining if remaining > 0 else 0.0


## Starts the fall animation for `new_drops` and records when each Poko lands.
func _start_fall(new_drops: Array, strength: float) -> void:
	fall_serial += 1
	drops.clear()
	var longest := 0.0
	for d in new_drops:
		var c: Vector2i = d[0]
		var t := sqrt(2.0 * d[1] / GRAVITY)
		drops[c] = d[1]
		land[c] = [time + t, strength]
		longest = maxf(longest, t)
		# The Poko it lands on gets a small jiggle too
		var below := c + Vector2i.DOWN
		if below.y < Board.H and board.grid[below.y][below.x] != 0 and not drops.has(below):
			land[below] = [time + t, strength * 0.35]
	anim_t = 0.0
	settle_time = maxf(MIN_SETTLE_TIME, longest + 0.04)


func move(dx: int) -> void:
	if state == State.FALLING and board.move(dx):
		_on_ground_action()


func rotate(dir: int) -> void:
	if state == State.FALLING and board.rotate(dir):
		_on_ground_action()


func _on_ground_action() -> void:
	if not board.can_fall() and lock_resets < MAX_LOCK_RESETS:
		lock_timer = 0.0
		lock_resets += 1


func hard_drop() -> void:
	if state != State.FALLING:
		return
	while board.step_down():
		score += 2
	_lock(1.2)


func _lock(strength: float = 0.8) -> void:
	lock_serial += 1
	last_lock = []
	var cells := board.piece_cells()
	for k in cells.size():
		land[cells[k][0]] = [time, strength]
		last_lock.append([cells[k][0], k == 1])
	board.lock()
	_settle()


func _settle() -> void:
	_start_fall(board.apply_gravity(), 0.8)
	state = State.SETTLING


func _check_pops() -> void:
	var groups := board.find_groups()
	if groups.is_empty():
		_end_chain()
		return
	chain += 1
	var points := Board.chain_score(groups, chain)
	score += points
	if versus:
		_add_attack(points)
	popping = []
	for g in groups:
		popping.append_array(g.cells)
	popping.append_array(board.adjacent_garbage(popping))
	events.append(["chain", chain])
	anim_t = 0.0
	state = State.POPPING


## Converts points into garbage; it first cancels our own incoming garbage (offset).
func _add_attack(points: int) -> void:
	score_leftover += points
	var n := score_leftover / target_points
	score_leftover -= n * target_points
	if all_clear_bonus:
		n += ALL_CLEAR_GARBAGE
		all_clear_bonus = false
	var cancel := mini(n, pending_garbage)
	pending_garbage -= cancel
	attack += n - cancel


func _end_chain() -> void:
	if chain > 0 and board.is_empty():
		score += ALL_CLEAR_SCORE
		all_clear_bonus = versus
		events.append(["all_clear", 0])
	if attack > 0:
		events.append(["attack", attack])
		attack = 0
	fall_delay = maxf(0.18, fall_delay - 0.004)
	if pending_garbage > 0:
		var n := mini(pending_garbage, MAX_GARBAGE_DROP)
		pending_garbage -= n
		_start_fall(board.drop_garbage(n), 1.0)
		state = State.GARBAGE
		events.append(["garbage", n])
		return
	_spawn()
