class_name Player
extends RefCounted
## One player's match: falling / settling / popping / garbage state machine,
## scoring, garbage sending, offsetting and all clear. No rendering here.

enum State { IDLE, FALLING, SETTLING, POPPING, GARBAGE, DEAD }

const SETTLE_TIME := 0.12
const POP_TIME := 0.35
const GARBAGE_TIME := 0.3
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
var anim_t := 0.0
var drops := {} # Vector2i -> fall distance (for the settle / garbage animation)
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
			if anim_t >= SETTLE_TIME:
				_check_pops()
		State.POPPING:
			anim_t += delta
			if anim_t >= POP_TIME:
				board.clear_cells(popping)
				popping = []
				_settle()
		State.GARBAGE:
			anim_t += delta
			if anim_t >= GARBAGE_TIME:
				_spawn()


## 0..1 progress of the current fall animation.
func fall_progress() -> float:
	match state:
		State.SETTLING:
			return minf(1.0, anim_t / SETTLE_TIME)
		State.GARBAGE:
			return minf(1.0, anim_t / GARBAGE_TIME)
	return 1.0


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
	_lock()


func _lock() -> void:
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
		drops.clear()
		for d in board.drop_garbage(n):
			drops[d[0]] = d[1]
		anim_t = 0.0
		state = State.GARBAGE
		events.append(["garbage", n])
		return
	_spawn()
