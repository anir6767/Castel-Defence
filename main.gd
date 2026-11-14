extends Node2D

# Castle Defense v2
# - The enemy castle fires cannonballs. Shields bounce them back at the enemy castle.
# - Destroy the enemy castle to start a tougher wave (you heal a little).
# - Everything is drawn in code, so no art files are needed.

const GROUND_Y := 620.0
const GRAVITY := 600.0
const BALL_RADIUS := 10.0
const PLAYER_POS := Vector2(120, 620)
const ENEMY_POS := Vector2(1160, 620)
const MUZZLE_OFFSET := Vector2(-38, -160)  # where cannonballs leave the enemy cannon
const MAX_HEALTH := 100
const BALL_DAMAGE := 10      # damage to you when a ball gets through
const RETURN_DAMAGE := 25    # damage to the enemy when you bounce a ball back
const SHIELD_SIZE := Vector2(16, 100)
const SHIELD_COST := 30.0
const SHIELD_HITS := 3
const SHIELD_LIFETIME := 12.0
const MAX_ENERGY := 100.0
const ENERGY_REGEN := 15.0
const FIELD_LIMIT := 640.0   # you can only place shields left of this x

var health: int
var enemy_health: int
var enemy_max: int
var wave: int
var wave_banner: float
var energy: float
var survived: float
var fire_timer: float
var game_over: bool
var best: float = 0.0
var anim_time := 0.0

var balls: Array = []
var shields: Array = []
var effects: Array = []

var far_hills: PackedVector2Array
var near_hills: PackedVector2Array
var trees: Array = []
var clouds: Array = []


func _ready() -> void:
	build_scenery()
	restart()


func restart() -> void:
	health = MAX_HEALTH
	wave = 1
	enemy_max = 100
	enemy_health = enemy_max
	wave_banner = 0.0
	energy = MAX_ENERGY
	survived = 0.0
	fire_timer = 2.0
	game_over = false
	balls.clear()
	shields.clear()
	effects.clear()


func build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7

	# far jagged mountains
	far_hills = PackedVector2Array([Vector2(0, GROUND_Y)])
	var x := 0.0
	while x < 1280.0:
		far_hills.append(Vector2(x, 330.0 - rng.randf() * 110.0))
		x += 90.0
	far_hills.append(Vector2(1280.0, 330.0 - rng.randf() * 110.0))
	far_hills.append(Vector2(1280.0, GROUND_Y))

	# near rolling hills
	near_hills = PackedVector2Array([Vector2(0, GROUND_Y)])
	x = 0.0
	while x <= 1280.0:
		near_hills.append(Vector2(x, 520.0 - 45.0 * (0.5 + 0.5 * sin(x * 0.006 + 1.3)) - 10.0 * sin(x * 0.02)))
		x += 20.0
	near_hills.append(Vector2(1280.0, GROUND_Y))

	for i in 14:
		trees.append({"x": rng.randf_range(250.0, 1010.0), "s": rng.randf_range(0.6, 1.0)})

	for i in 6:
		clouds.append({
			"x": rng.randf_range(0.0, 1280.0),
			"y": rng.randf_range(50.0, 220.0),
			"s": rng.randf_range(0.7, 1.4),
			"v": rng.randf_range(5.0, 16.0)
		})


func _process(delta: float) -> void:
	anim_time += delta
	wave_banner = maxf(wave_banner - delta, 0.0)

	for c: Dictionary in clouds:
		c["x"] += c["v"] * delta
		if c["x"] > 1400.0:
			c["x"] = -150.0

	if not game_over:
		survived += delta
		energy = minf(energy + ENERGY_REGEN * delta, MAX_ENERGY)

		fire_timer -= delta
		if fire_timer <= 0.0:
			fire_ball()
			if randf() < 0.1 * (wave - 1):
				fire_ball()
			# shots come faster the longer you survive and the higher the wave
			fire_timer = maxf(0.7, 3.0 - survived * 0.02 - (wave - 1) * 0.15) * randf_range(0.8, 1.2)

		update_shields(delta)
		update_balls(delta)

	for i in range(effects.size() - 1, -1, -1):
		effects[i]["time"] -= delta
		if effects[i]["time"] <= 0.0:
			effects.remove_at(i)

	queue_redraw()


func fire_ball() -> void:
	var start := ENEMY_POS + MUZZLE_OFFSET
	var target := Vector2(randf_range(40.0, 200.0), randf_range(480.0, 600.0))
	var t := randf_range(1.5, 2.2)  # flight time in seconds
	# solve for the launch velocity that lands on the target after t seconds
	var vel := Vector2(
		(target.x - start.x) / t,
		(target.y - start.y - 0.5 * GRAVITY * t * t) / t
	)
	balls.append({"pos": start, "vel": vel, "target": target, "returned": false, "trail": []})
	add_effect(start, Color(1.0, 0.8, 0.3))


# velocity that sends a bounced ball in an arc onto the enemy castle
func return_velocity(from: Vector2) -> Vector2:
	var target := ENEMY_POS + Vector2(randf_range(-40.0, 20.0), randf_range(-140.0, -50.0))
	var t := clampf((target.x - from.x) / 450.0, 0.8, 1.8)
	return Vector2(
		(target.x - from.x) / t,
		(target.y - from.y - 0.5 * GRAVITY * t * t) / t
	)


func update_shields(delta: float) -> void:
	for i in range(shields.size() - 1, -1, -1):
		shields[i]["life"] -= delta
		if shields[i]["life"] <= 0.0 or shields[i]["hits"] <= 0:
			add_effect(shields[i]["pos"], Color(0.8, 0.7, 0.5))
			shields.remove_at(i)


func update_balls(delta: float) -> void:
	for i in range(balls.size() - 1, -1, -1):
		var b: Dictionary = balls[i]
		var vel: Vector2 = b["vel"]
		var pos: Vector2 = b["pos"]
		vel.y += GRAVITY * delta
		pos += vel * delta

		var trail: Array = b["trail"]
		trail.append(pos)
		if trail.size() > 10:
			trail.pop_front()

		var remove := false

		if not b["returned"]:
			# enemy ball: can hit a shield (bounces back) or your castle
			for s: Dictionary in shields:
				var r := Rect2(s["pos"] - SHIELD_SIZE / 2.0, SHIELD_SIZE)
				if circle_hits_rect(pos, BALL_RADIUS, r):
					s["hits"] -= 1
					b["returned"] = true
					pos.x = r.end.x + BALL_RADIUS + 1.0
					vel = return_velocity(pos)
					trail.clear()
					add_effect(pos, Color(1.0, 0.9, 0.5))
					break

			if not b["returned"]:
				if circle_hits_rect(pos, BALL_RADIUS, castle_rect(PLAYER_POS)):
					health = maxi(health - BALL_DAMAGE, 0)
					add_effect(pos, Color(1.0, 0.5, 0.1))
					remove = true
					if health == 0:
						game_over = true
						best = maxf(best, survived)
				elif pos.y > GROUND_Y - BALL_RADIUS or pos.x < -50.0:
					add_effect(pos, Color(0.5, 0.4, 0.3))
					remove = true
		else:
			# bounced ball: flies back and hits the enemy castle
			if circle_hits_rect(pos, BALL_RADIUS, castle_rect(ENEMY_POS)):
				enemy_health -= RETURN_DAMAGE
				add_effect(pos, Color(1.0, 0.6, 0.1))
				remove = true
				if enemy_health <= 0:
					next_wave()
			elif pos.y > GROUND_Y - BALL_RADIUS or pos.x > 1350.0:
				add_effect(pos, Color(0.5, 0.4, 0.3))
				remove = true

		b["vel"] = vel
		b["pos"] = pos
		if remove:
			balls.remove_at(i)


func next_wave() -> void:
	wave += 1
	enemy_max += 25
	enemy_health = enemy_max
	health = mini(health + 20, MAX_HEALTH)
	wave_banner = 2.5
	for i in 6:
		add_effect(ENEMY_POS + Vector2(randf_range(-50.0, 50.0), randf_range(-150.0, -20.0)), Color(1.0, 0.7, 0.2))


func castle_rect(base: Vector2) -> Rect2:
	return Rect2(base + Vector2(-70, -170), Vector2(140, 170))


func circle_hits_rect(c: Vector2, r: float, rect: Rect2) -> bool:
	var closest := Vector2(
		clampf(c.x, rect.position.x, rect.end.x),
		clampf(c.y, rect.position.y, rect.end.y)
	)
	return c.distance_to(closest) <= r


func add_effect(pos: Vector2, color: Color) -> void:
	effects.append({"pos": pos, "time": 0.3, "color": color})


func shield_spot(mouse: Vector2) -> Vector2:
	var x := clampf(mouse.x, SHIELD_SIZE.x / 2.0, FIELD_LIMIT)
	var y := clampf(mouse.y, 60.0, GROUND_Y - SHIELD_SIZE.y / 2.0)
	return Vector2(x, y)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		if game_over:
			restart()
			return
		var mouse := get_global_mouse_position()
		if mouse.x <= FIELD_LIMIT and energy >= SHIELD_COST:
			energy -= SHIELD_COST
			shields.append({"pos": shield_spot(mouse), "hits": SHIELD_HITS, "life": SHIELD_LIFETIME})
	elif event.is_action_pressed("ui_accept") and game_over:
		restart()


# ============================ drawing ============================

func _draw() -> void:
	var font := ThemeDB.fallback_font

	draw_background()

	# castles and enemy cannon
	draw_castle(PLAYER_POS, 1.0, Color(0.64, 0.65, 0.7), Color(0.2, 0.4, 0.85))
	draw_castle(ENEMY_POS, -1.0, Color(0.58, 0.54, 0.56), Color(0.8, 0.2, 0.2))
	draw_cannon()

	draw_health_bar(PLAYER_POS + Vector2(-60, -275), float(health) / MAX_HEALTH, Color(0.3, 0.85, 0.3), "YOU", font)
	draw_health_bar(ENEMY_POS + Vector2(-60, -275), float(enemy_health) / enemy_max, Color(0.9, 0.3, 0.25), "ENEMY", font)

	# warning markers where enemy balls will land
	for b: Dictionary in balls:
		if not b["returned"]:
			var pulse := 0.5 + 0.5 * sin(anim_time * 8.0)
			draw_arc(b["target"], 12.0 + 2.0 * pulse, 0.0, TAU, 20, Color(1, 0.2, 0.2, 0.55), 2.0)

	for s: Dictionary in shields:
		draw_shield(s)

	for b: Dictionary in balls:
		draw_ball(b)

	# hit effects
	for e: Dictionary in effects:
		var p: float = 1.0 - e["time"] / 0.3
		var c: Color = e["color"]
		c.a = 1.0 - p
		draw_circle(e["pos"], 8.0 + 22.0 * p, c)

	# shield placement preview
	if not game_over:
		var mouse := get_local_mouse_position()
		if mouse.x <= FIELD_LIMIT:
			var ok := energy >= SHIELD_COST
			var ghost := Color(0.3, 1.0, 0.4, 0.5) if ok else Color(1.0, 0.3, 0.3, 0.5)
			draw_rect(Rect2(shield_spot(mouse) - SHIELD_SIZE / 2.0, SHIELD_SIZE), ghost)

	draw_hud(font)


func draw_background() -> void:
	# sky gradient
	var top := Color(0.3, 0.55, 0.9)
	var bottom := Color(0.88, 0.94, 1.0)
	draw_polygon(
		PackedVector2Array([Vector2(0, 0), Vector2(1280, 0), Vector2(1280, GROUND_Y), Vector2(0, GROUND_Y)]),
		PackedColorArray([top, top, bottom, bottom])
	)

	# sun with glow
	var sun := Vector2(1010, 120)
	draw_circle(sun, 90.0, Color(1.0, 0.95, 0.6, 0.12))
	draw_circle(sun, 64.0, Color(1.0, 0.95, 0.6, 0.25))
	draw_circle(sun, 40.0, Color(1.0, 0.96, 0.62))

	# clouds
	for c: Dictionary in clouds:
		draw_cloud(Vector2(c["x"], c["y"]), c["s"])

	# mountains and hills
	draw_colored_polygon(far_hills, Color(0.58, 0.67, 0.82))
	draw_colored_polygon(near_hills, Color(0.38, 0.6, 0.4))

	# dirt
	draw_rect(Rect2(0, GROUND_Y, 1280, 100), Color(0.43, 0.3, 0.2))
	draw_rect(Rect2(0, GROUND_Y + 50, 1280, 50), Color(0.36, 0.25, 0.17))
	for i in 40:
		var sx := fposmod(i * 97.0, 1280.0)
		var sy := GROUND_Y + 22.0 + fposmod(i * 53.0, 70.0)
		draw_circle(Vector2(sx, sy), 2.0 + (i % 3), Color(0.3, 0.21, 0.14))

	# grass strip and blades
	draw_rect(Rect2(0, GROUND_Y, 1280, 12), Color(0.3, 0.56, 0.2))
	draw_rect(Rect2(0, GROUND_Y, 1280, 3), Color(0.45, 0.7, 0.3))
	var gx := 0.0
	while gx < 1280.0:
		var tilt := sin(gx * 12.9898) * 4.0
		draw_line(Vector2(gx, GROUND_Y + 1.0), Vector2(gx + tilt, GROUND_Y - 6.0 - absf(tilt)), Color(0.35, 0.62, 0.22), 2.0)
		gx += 9.0

	# pine trees
	for t: Dictionary in trees:
		draw_pine(t["x"], t["s"])

	# line showing how far right you can build
	draw_line(Vector2(FIELD_LIMIT, 0), Vector2(FIELD_LIMIT, GROUND_Y), Color(1, 1, 1, 0.22), 2.0)


func draw_cloud(p: Vector2, s: float) -> void:
	var col := Color(0.98, 0.99, 1.0, 0.95)
	for o: Vector3 in [Vector3(0, 0, 28), Vector3(30, -8, 22), Vector3(-30, -4, 20), Vector3(56, 6, 16), Vector3(-54, 8, 15)]:
		draw_circle(p + Vector2(o.x, o.y) * s, o.z * s, col)


func draw_pine(x: float, s: float) -> void:
	draw_rect(Rect2(x - 3.0 * s, GROUND_Y - 20.0 * s, 6.0 * s, 22.0 * s), Color(0.35, 0.22, 0.12))
	for k in 3:
		var w := (34.0 - k * 8.0) * s
		var by := GROUND_Y - 14.0 * s - k * 20.0 * s
		var green := Color(0.14, 0.4, 0.2).lerp(Color(0.2, 0.55, 0.28), k / 2.0)
		draw_colored_polygon(PackedVector2Array([Vector2(x - w, by), Vector2(x + w, by), Vector2(x, by - 32.0 * s)]), green)


func draw_bricks(rect: Rect2, mortar: Color) -> void:
	var row := 0
	var y := rect.position.y
	while y < rect.end.y:
		draw_line(Vector2(rect.position.x, y), Vector2(rect.end.x, y), mortar, 1.0)
		var h := minf(14.0, rect.end.y - y)
		var x := rect.position.x + (11.0 if row % 2 == 1 else 0.0)
		while x < rect.end.x:
			if x > rect.position.x:
				draw_line(Vector2(x, y), Vector2(x, y + h), mortar, 1.0)
			x += 22.0
		y += 14.0
		row += 1


# flip = 1.0 for the player castle, -1.0 mirrors it for the enemy
func draw_castle(base: Vector2, flip: float, stone: Color, team: Color) -> void:
	draw_set_transform(base, 0.0, Vector2(flip, 1.0))
	var mortar := stone.darkened(0.35)
	var window_dark := Color(0.12, 0.1, 0.15)

	# ground shadow
	draw_rect(Rect2(-76, -3, 152, 7), Color(0, 0, 0, 0.18))

	# keep
	draw_rect(Rect2(-45, -130, 90, 130), stone)
	draw_bricks(Rect2(-45, -130, 90, 130), mortar)
	draw_rect(Rect2(20, -130, 25, 130), Color(0, 0, 0, 0.14))
	# battlements on the keep
	for i in 5:
		draw_rect(Rect2(-45 + i * 20, -144, 10, 14), stone.lightened(0.05))
		draw_rect(Rect2(-45 + i * 20, -144, 10, 3), stone.lightened(0.2))
	draw_rect(Rect2(-45, -130, 90, 6), Color(0, 0, 0, 0.2))

	# towers
	draw_rect(Rect2(-70, -170, 34, 170), stone.lightened(0.05))
	draw_rect(Rect2(36, -170, 34, 170), stone.darkened(0.08))
	draw_bricks(Rect2(-70, -170, 34, 170), mortar)
	draw_bricks(Rect2(36, -170, 34, 170), mortar)
	# arrow slits
	for sx in [-55.0, 51.0]:
		draw_rect(Rect2(sx, -150, 4, 18), window_dark)
		draw_rect(Rect2(sx, -100, 4, 18), window_dark)

	# conical roofs
	var roof := team.darkened(0.15)
	for tx in [-53.0, 53.0]:
		draw_rect(Rect2(tx - 22, -176, 44, 7), stone.darkened(0.3))
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 21, -170), Vector2(tx + 21, -170), Vector2(tx, -218)]), roof)
		draw_colored_polygon(PackedVector2Array([Vector2(tx - 21, -170), Vector2(tx, -170), Vector2(tx, -218)]), roof.lightened(0.18))

	# flag waving on the right tower
	var wave_off := sin(anim_time * 4.0 + base.x) * 3.0
	draw_line(Vector2(53, -218), Vector2(53, -252), Color(0.25, 0.2, 0.15), 2.0)
	draw_colored_polygon(PackedVector2Array([Vector2(53, -252), Vector2(53 + 28, -246 + wave_off), Vector2(53, -238)]), team)

	# windows
	for wx in [-28.0, 14.0]:
		draw_rect(Rect2(wx, -100, 14, 22), window_dark)
		draw_circle(Vector2(wx + 7, -100), 7.0, window_dark)
		draw_rect(Rect2(wx + 3, -98, 8, 18), Color(0.95, 0.78, 0.35, 0.85))
		draw_circle(Vector2(wx + 7, -100), 4.0, Color(0.95, 0.78, 0.35, 0.85))
		draw_rect(Rect2(wx - 2, -78, 18, 4), stone.lightened(0.2))

	# hanging banner
	draw_colored_polygon(PackedVector2Array([Vector2(-9, -125), Vector2(9, -125), Vector2(9, -96), Vector2(0, -86), Vector2(-9, -96)]), team)
	draw_circle(Vector2(0, -110), 4.0, Color(0.95, 0.8, 0.3))

	# gate
	var wood := Color(0.35, 0.22, 0.12)
	draw_rect(Rect2(-14, -48, 28, 48), wood)
	draw_circle(Vector2(0, -48), 14.0, wood)
	for gx in [-7.0, 0.0, 7.0]:
		draw_line(Vector2(gx, -50), Vector2(gx, 0), wood.darkened(0.4), 1.0)
	draw_rect(Rect2(-14, -30, 28, 3), Color(0.2, 0.2, 0.22))
	draw_rect(Rect2(-14, -12, 28, 3), Color(0.2, 0.2, 0.22))
	draw_arc(Vector2(0, -48), 14.0, PI, TAU, 16, stone.darkened(0.45), 3.0)

	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func draw_cannon() -> void:
	var pivot := ENEMY_POS + Vector2(-8, -150)
	var metal := Color(0.14, 0.14, 0.17)
	draw_set_transform(pivot, PI + 0.35, Vector2.ONE)
	draw_rect(Rect2(0, -7, 28, 14), metal)
	draw_rect(Rect2(24, -9, 6, 18), Color(0.08, 0.08, 0.1))
	draw_rect(Rect2(2, -5, 22, 3), Color(1, 1, 1, 0.12))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
	draw_rect(Rect2(pivot + Vector2(-14, 4), Vector2(28, 6)), Color(0.4, 0.26, 0.13))
	draw_circle(pivot + Vector2(0, 4), 8.0, Color(0.45, 0.3, 0.15))
	draw_circle(pivot + Vector2(0, 4), 3.0, Color(0.2, 0.12, 0.06))


func draw_health_bar(pos: Vector2, frac: float, color: Color, label: String, font: Font) -> void:
	draw_string(font, pos + Vector2(0, -4), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color.WHITE)
	draw_rect(Rect2(pos - Vector2(2, 2), Vector2(124, 18)), Color(0.1, 0.1, 0.1))
	draw_rect(Rect2(pos, Vector2(120, 14)), Color(0.25, 0.25, 0.25))
	draw_rect(Rect2(pos, Vector2(120.0 * clampf(frac, 0.0, 1.0), 14)), color)
	draw_rect(Rect2(pos, Vector2(120.0 * clampf(frac, 0.0, 1.0), 4)), Color(1, 1, 1, 0.25))


func draw_shield(s: Dictionary) -> void:
	var r := Rect2(s["pos"] - SHIELD_SIZE / 2.0, SHIELD_SIZE)
	var shade := float(s["hits"]) / SHIELD_HITS
	var wood := Color(0.35, 0.22, 0.12).lerp(Color(0.58, 0.38, 0.2), shade)
	var steel := Color(0.65, 0.68, 0.74)
	draw_rect(r, wood)
	draw_rect(Rect2(r.position + Vector2(3, 0), Vector2(3, r.size.y)), Color(1, 1, 1, 0.15))
	draw_rect(Rect2(r.position.x - 2, r.position.y + 8, r.size.x + 4, 6), steel)
	draw_rect(Rect2(r.position.x - 2, r.end.y - 14, r.size.x + 4, 6), steel)
	draw_circle(Vector2(r.position.x + r.size.x / 2.0, r.position.y + 11), 2.0, Color(0.3, 0.3, 0.35))
	draw_circle(Vector2(r.position.x + r.size.x / 2.0, r.end.y - 11), 2.0, Color(0.3, 0.3, 0.35))
	draw_rect(r, Color(0.15, 0.1, 0.07), false, 2.0)
	if s["hits"] <= 1:
		var m := r.position + Vector2(8, 30)
		draw_polyline(PackedVector2Array([m, m + Vector2(-4, 10), m + Vector2(3, 20), m + Vector2(-3, 34)]), Color(0.1, 0.07, 0.05), 2.0)
	# remaining lifetime bar
	draw_rect(Rect2(r.position.x, r.position.y - 8, r.size.x * float(s["life"]) / SHIELD_LIFETIME, 3), Color(0.95, 0.85, 0.3))


func draw_ball(b: Dictionary) -> void:
	var pos: Vector2 = b["pos"]
	var returned: bool = b["returned"]
	var trail: Array = b["trail"]
	var n := trail.size()
	for i in n:
		var f := float(i + 1) / n
		var tc := Color(1.0, 0.55, 0.1, 0.35 * f) if returned else Color(0.3, 0.3, 0.3, 0.3 * f)
		draw_circle(trail[i], BALL_RADIUS * (0.3 + 0.6 * f), tc)
	if returned:
		draw_circle(pos, BALL_RADIUS + 7.0, Color(1.0, 0.6, 0.1, 0.3))
	draw_circle(pos, BALL_RADIUS, Color(0.12, 0.12, 0.14))
	draw_circle(pos + Vector2(-3, -3), 3.0, Color(1, 1, 1, 0.45))


func draw_hud(font: Font) -> void:
	# top bar
	draw_rect(Rect2(440, 10, 400, 40), Color(0, 0, 0, 0.4))
	draw_string(font, Vector2(0, 38), "Survived: %.1fs    Best: %.1fs" % [survived, best], HORIZONTAL_ALIGNMENT_CENTER, 1280, 24, Color.WHITE)
	draw_string(font, Vector2(1100, 40), "Wave %d" % wave, HORIZONTAL_ALIGNMENT_LEFT, -1, 28, Color.WHITE)

	# bottom panel
	draw_rect(Rect2(10, 638, 440, 76), Color(0, 0, 0, 0.45))
	draw_string(font, Vector2(22, 666), "Energy", HORIZONTAL_ALIGNMENT_LEFT, -1, 18, Color.WHITE)
	draw_rect(Rect2(92, 651, 300, 18), Color(0.15, 0.15, 0.15))
	draw_rect(Rect2(92, 651, 300.0 * energy / MAX_ENERGY, 18), Color(0.95, 0.8, 0.2))
	draw_string(font, Vector2(22, 696), "Click on your side to place a shield (30 energy)", HORIZONTAL_ALIGNMENT_LEFT, -1, 15, Color.WHITE)
	draw_string(font, Vector2(22, 710), "Shields bounce cannonballs back at the enemy", HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(1, 1, 1, 0.8))

	if wave_banner > 0.0:
		draw_string(font, Vector2(0, 220), "Wave %d" % wave, HORIZONTAL_ALIGNMENT_CENTER, 1280, 64, Color(1, 1, 1, minf(wave_banner, 1.0)))

	if game_over:
		draw_rect(Rect2(0, 0, 1280, 720), Color(0, 0, 0, 0.5))
		draw_string(font, Vector2(0, 330), "Castle destroyed", HORIZONTAL_ALIGNMENT_CENTER, 1280, 56, Color.WHITE)
		draw_string(font, Vector2(0, 385), "You survived %.1f seconds and reached wave %d" % [survived, wave], HORIZONTAL_ALIGNMENT_CENTER, 1280, 28, Color.WHITE)
		draw_string(font, Vector2(0, 430), "Click or press Enter to restart", HORIZONTAL_ALIGNMENT_CENTER, 1280, 22, Color(1, 1, 1, 0.8))
