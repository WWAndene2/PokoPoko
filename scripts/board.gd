class_name Board
extends RefCounted
## Pure game rules: grid, falling pair, gravity, groups and scoring.
## No rendering or input here so it can be unit-tested headless.

const COLS := 6
const ROWS := 12
const HIDDEN := 1 # row 0 is the hidden spawn row
const H := ROWS + HIDDEN
const SPAWN_COL := 2
const POP_SIZE := 4
const GARBAGE := 9 # grey nuisance Poko ("grumeau"): never groups, cleared by adjacent pops
# Satellite offsets by rotation: up, right, down, left
const ROT: Array[Vector2i] = [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

const CHAIN_POWER := [0, 8, 16, 32, 64, 96, 128, 160, 192, 224, 256, 288, 320]
const COLOR_BONUS := [0, 0, 3, 6, 12, 24]

var grid: Array = [] # grid[y][x], 0 = empty, 1..n = color
var num_colors := 4
var rng := RandomNumberGenerator.new() # pair sequence: same seed => same pairs for both players
var garbage_rng := RandomNumberGenerator.new()

# Falling pair: pivot at pos with color a, satellite at pos + ROT[rot] with color b
var pos := Vector2i.ZERO
var rot := 0
var a := 0
var b := 0
var has_piece := false
var queue: Array = []


func _init(seed_value: int = -1) -> void:
	if seed_value >= 0:
		rng.seed = seed_value
		garbage_rng.seed = seed_value + 1
	else:
		rng.randomize()
		garbage_rng.randomize()
	reset()


func reset() -> void:
	grid = []
	for y in H:
		var row := []
		row.resize(COLS)
		row.fill(0)
		grid.append(row)
	queue = [_rand_pair(), _rand_pair()]
	has_piece = false


func _rand_pair() -> Array:
	return [rng.randi_range(1, num_colors), rng.randi_range(1, num_colors)]


## Spawns the next pair. Returns false when the spawn cell is blocked (game over).
func spawn() -> bool:
	if grid[HIDDEN][SPAWN_COL] != 0:
		return false
	var p: Array = queue.pop_front()
	queue.append(_rand_pair())
	a = p[0]
	b = p[1]
	pos = Vector2i(SPAWN_COL, HIDDEN)
	rot = 0
	has_piece = true
	return true


func piece_cells(p_pos: Vector2i = pos, p_rot: int = rot) -> Array:
	return [[p_pos, a], [p_pos + ROT[p_rot], b]]


func is_free(c: Vector2i) -> bool:
	return c.x >= 0 and c.x < COLS and c.y < H and (c.y < 0 or grid[c.y][c.x] == 0)


func fits(p_pos: Vector2i, p_rot: int) -> bool:
	return is_free(p_pos) and is_free(p_pos + ROT[p_rot])


func move(dx: int) -> bool:
	if has_piece and fits(pos + Vector2i(dx, 0), rot):
		pos.x += dx
		return true
	return false


func rotate_cw() -> bool:
	return rotate(1)


func rotate_ccw() -> bool:
	return rotate(-1)


## dir = 1 clockwise, -1 counter-clockwise
func rotate(dir: int) -> bool:
	if not has_piece:
		return false
	var r := (rot + dir + 4) % 4
	# In place, wall kick, floor kick
	for kick in [Vector2i.ZERO, Vector2i(-ROT[r].x, 0), Vector2i(0, -1)]:
		if fits(pos + kick, r):
			pos += kick
			rot = r
			return true
	# Boxed in (1-wide well): flip 180°
	var flip := (rot + 2) % 4
	for kick in [Vector2i.ZERO, Vector2i(0, -1)]:
		if fits(pos + kick, flip):
			pos += kick
			rot = flip
			return true
	return false


func can_fall() -> bool:
	return has_piece and fits(pos + Vector2i.DOWN, rot)


## Moves the pair down one row. Returns false if it could not (caller should lock).
func step_down() -> bool:
	if can_fall():
		pos.y += 1
		return true
	return false


func ghost_pos() -> Vector2i:
	var g := pos
	while fits(g + Vector2i.DOWN, rot):
		g.y += 1
	return g


func lock() -> void:
	for pc in piece_cells():
		var c: Vector2i = pc[0]
		if c.y >= 0:
			grid[c.y][c.x] = pc[1]
	has_piece = false


## Applies gravity. Returns a list of [Vector2i destination, int fall_distance] for animation.
func apply_gravity() -> Array:
	var drops := []
	for x in COLS:
		var write := H - 1
		for y in range(H - 1, -1, -1):
			if grid[y][x] == 0:
				continue
			if y != write:
				grid[write][x] = grid[y][x]
				grid[y][x] = 0
				drops.append([Vector2i(x, write), write - y])
			write -= 1
	return drops


## Returns groups of POP_SIZE+ connected same-color cells in the visible area.
func find_groups() -> Array:
	var seen := {}
	var groups := []
	for y in range(HIDDEN, H):
		for x in COLS:
			var color: int = grid[y][x]
			var start := Vector2i(x, y)
			if color == 0 or color == GARBAGE or seen.has(start):
				continue
			var stack := [start]
			var cells := []
			seen[start] = true
			while not stack.is_empty():
				var c: Vector2i = stack.pop_back()
				cells.append(c)
				for d in ROT:
					var n: Vector2i = c + d
					if n.x >= 0 and n.x < COLS and n.y >= HIDDEN and n.y < H and not seen.has(n) and grid[n.y][n.x] == color:
						seen[n] = true
						stack.append(n)
			if cells.size() >= POP_SIZE:
				groups.append({"color": color, "cells": cells})
	return groups


static func group_bonus(n: int) -> int:
	if n <= 4:
		return 0
	return 10 if n >= 11 else n - 3


## Score for popping `groups` as link number `chain` (1-based).
static func chain_score(groups: Array, chain: int) -> int:
	var n := 0
	var colors := {}
	var bonus: int = CHAIN_POWER[min(chain - 1, CHAIN_POWER.size() - 1)]
	for g in groups:
		n += g.cells.size()
		colors[g.color] = true
		bonus += group_bonus(g.cells.size())
	bonus += COLOR_BONUS[min(colors.size(), COLOR_BONUS.size() - 1)]
	return 10 * n * clampi(bonus, 1, 999)


func clear_cells(cells: Array) -> void:
	for c in cells:
		grid[c.y][c.x] = 0


## Garbage cells (visible area) touching any of `cells`.
func adjacent_garbage(cells: Array) -> Array:
	var found := {}
	for c in cells:
		for d in ROT:
			var n: Vector2i = c + d
			if n.x >= 0 and n.x < COLS and n.y >= HIDDEN and n.y < H and grid[n.y][n.x] == GARBAGE:
				found[n] = true
	return found.keys()


func is_empty() -> bool:
	for row in grid:
		for v in row:
			if v != 0:
				return false
	return true


## Drops `n` garbage Pokos spread evenly over the columns (remainder on random columns).
## Returns [Vector2i destination, int fall_distance] for animation.
func drop_garbage(n: int) -> Array:
	var per := []
	per.resize(COLS)
	per.fill(n / COLS)
	var cols := range(COLS)
	for i in range(COLS - 1, 0, -1):
		var j := garbage_rng.randi_range(0, i)
		var t = cols[i]
		cols[i] = cols[j]
		cols[j] = t
	for i in n % COLS:
		per[cols[i]] += 1
	var drops := []
	for x in COLS:
		var top := H
		for y in H:
			if grid[y][x] != 0:
				top = y
				break
		for k in per[x]:
			var y: int = top - 1 - k
			if y < 0:
				break
			grid[y][x] = GARBAGE
			drops.append([Vector2i(x, y), y + 2])
	return drops


func clone() -> Board:
	var copy := Board.new(0)
	copy.grid = grid.duplicate(true)
	copy.num_colors = num_colors
	return copy


## Places a pair at column x / rotation r, drops it and resolves every chain.
## Returns {ok, chains, points} — used by the AI. Mutates this board.
func simulate_drop(x: int, r: int, ca: int, cb: int) -> Dictionary:
	a = ca
	b = cb
	if not fits(Vector2i(x, HIDDEN), r):
		return {"ok": false, "chains": 0, "points": 0}
	pos = Vector2i(x, HIDDEN)
	rot = r
	has_piece = true
	pos = ghost_pos()
	lock()
	var chains := 0
	var points := 0
	while true:
		apply_gravity()
		var groups := find_groups()
		if groups.is_empty():
			break
		chains += 1
		points += chain_score(groups, chains)
		for g in groups:
			clear_cells(adjacent_garbage(g.cells))
			clear_cells(g.cells)
	return {"ok": true, "chains": chains, "points": points}
