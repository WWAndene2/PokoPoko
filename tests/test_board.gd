extends SceneTree
## Run: godot --headless --path . -s tests/test_board.gd

var failures := 0


func check(cond: bool, msg: String) -> void:
	if not cond:
		failures += 1
		printerr("FAIL: ", msg)


func _init() -> void:
	test_pop_four()
	test_two_chain()
	test_wall_rotation()
	test_game_over()
	test_garbage_never_groups()
	test_garbage_cleared_by_adjacent_pop()
	test_drop_garbage_spreads()
	test_offset_cancels_incoming()
	test_all_clear()
	test_ccw_rotation()
	test_ai_match()
	print("Tests done, failures: ", failures)
	quit(1 if failures else 0)


func test_pop_four() -> void:
	var b := Board.new(1)
	var bottom := Board.H - 1
	for x in 4:
		b.grid[bottom][x] = 1
	var groups := b.find_groups()
	check(groups.size() == 1 and groups[0].cells.size() == 4, "four in a row pops")
	check(Board.chain_score(groups, 1) == 40, "1-chain of 4 scores 40")


func test_two_chain() -> void:
	var b := Board.new(1)
	var y := Board.H - 1
	# Red column under a blue; three blues beside it. Popping red drops the blue into place.
	for i in 4:
		b.grid[y - i][0] = 1
	b.grid[y - 4][0] = 2
	for i in 3:
		b.grid[y - i][1] = 2
	var g1 := b.find_groups()
	check(g1.size() == 1 and g1[0].color == 1, "only red pops first")
	b.clear_cells(g1[0].cells)
	b.apply_gravity()
	var g2 := b.find_groups()
	check(g2.size() == 1 and g2[0].color == 2, "blue pops as chain 2")
	check(Board.chain_score(g2, 2) == 320, "2-chain of 4 scores 320")


func test_wall_rotation() -> void:
	var b := Board.new(1)
	b.spawn()
	while b.move(1):
		pass
	check(b.pos.x == Board.COLS - 1, "pair reaches right wall")
	b.rotate_cw()
	check(b.rot == 1 and b.pos.x == Board.COLS - 2, "rotation kicks off the wall")


func test_game_over() -> void:
	var b := Board.new(1)
	b.grid[Board.HIDDEN][Board.SPAWN_COL] = 1
	check(not b.spawn(), "blocked spawn means game over")


func test_garbage_never_groups() -> void:
	var b := Board.new(1)
	for x in 6:
		b.grid[Board.H - 1][x] = Board.GARBAGE
	check(b.find_groups().is_empty(), "a row of garbage does not pop")


func test_garbage_cleared_by_adjacent_pop() -> void:
	var b := Board.new(1)
	var y := Board.H - 1
	for x in 4:
		b.grid[y][x] = 1
	b.grid[y][4] = Board.GARBAGE
	b.grid[y - 1][0] = Board.GARBAGE
	b.grid[y - 2][0] = Board.GARBAGE
	var g := b.find_groups()
	var near := b.adjacent_garbage(g[0].cells)
	check(near.size() == 2, "only garbage touching the group is cleared (got %d)" % near.size())


func test_drop_garbage_spreads() -> void:
	var b := Board.new(1)
	b.drop_garbage(14)
	var per := []
	for x in Board.COLS:
		var n := 0
		for y in Board.H:
			if b.grid[y][x] == Board.GARBAGE:
				n += 1
		per.append(n)
	check(per.reduce(func(acc, v): return acc + v, 0) == 14, "14 garbage dropped")
	check(per.min() == 2 and per.max() == 3, "garbage spread evenly: %s" % [per])


func test_offset_cancels_incoming() -> void:
	var p := Player.new()
	p.start(1, true)
	p.pending_garbage = 10
	p._add_attack(70 * 4) # 4 garbage worth of points
	check(p.pending_garbage == 6 and p.attack == 0, "points cancel incoming garbage first")
	p._add_attack(70 * 10)
	check(p.pending_garbage == 0 and p.attack == 4, "surplus becomes an attack")


func test_all_clear() -> void:
	var p := Player.new()
	p.start(1, true)
	p.board.grid = Board.new(1).grid
	p.board.has_piece = false
	p.chain = 1
	p._end_chain()
	check(p.all_clear_bonus and p.score == Player.ALL_CLEAR_SCORE, "empty board after a chain gives the all clear bonus")
	p._add_attack(0)
	check(p.attack == Player.ALL_CLEAR_GARBAGE, "all clear adds 30 garbage to the next attack")


func test_ccw_rotation() -> void:
	var b := Board.new(1)
	b.spawn()
	b.rotate_ccw()
	check(b.rot == 3, "counter-clockwise turns the satellite to the left")


## Two hard AIs play each other headless: checks the whole loop runs and garbage is exchanged.
func test_ai_match() -> void:
	var p1 := Player.new()
	var p2 := Player.new()
	p1.start(42, true)
	p2.start(42, true)
	var ais := [AI.new(p1, AI.Level.HARD), AI.new(p2, AI.Level.NORMAL)]
	var ps := [p1, p2]
	var sent := 0
	var over := false
	for frame in 60 * 60 * 5: # up to 5 simulated minutes at 60 fps
		for i in 2:
			ais[i].update(1.0 / 60)
			ps[i].update(1.0 / 60)
			for e in ps[i].events:
				if e[0] == "attack":
					ps[1 - i].pending_garbage += e[1]
					sent += e[1]
				elif e[0] == "dead":
					over = true
			ps[i].events.clear()
		if over:
			break
	print("  AI match: scores %d / %d, garbage sent %d, finished %s" % [p1.score, p2.score, sent, over])
	check(p1.score > 0 and p2.score > 0, "both AIs score")
	check(sent > 0, "garbage is exchanged")
