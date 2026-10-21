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
