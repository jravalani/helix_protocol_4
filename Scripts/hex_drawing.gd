#extends Control
#
### ═══════════════════════════════════════════════════════════════
### HEX DRAWING LAYER
### Draws all decorative lines for the tech tree.
### Animations:
###   - Marching circuit dashes on locked edges (dormant feel)
###   - Slow breathing glow behind locked nodes
###   - Electricity spark burst on segment purchase
### All game state is read from parent TechTree node.
### ═══════════════════════════════════════════════════════════════
#
## ── Palette ────────────────────────────────────────────────────
#const COL_MAGENTA       := Color(1.0,  0.08, 0.58)
#const COL_MAGENTA_DIM   := Color(0.45, 0.04, 0.26)
#const COL_MAGENTA_GLOW  := Color(1.0,  0.08, 0.58, 0.12)
#const COL_FRAME         := Color(0.16, 0.16, 0.20)
#
## Dormant palette
#const COL_LOCKED_LINE   := Color(0.35, 0.04, 0.22, 0.13)
#const COL_LOCKED_FILL   := Color(0.10, 0.10, 0.14)
#const COL_LOCKED_BORDER := Color(0.32, 0.30, 0.40)
#
#const SMALL_NODE_RADIUS := 10.0
#const LINE_W            := 2.5
#const GLOW_W            := 14.0
#const NUM_NODES         := 5
#
## ── Circuit dash animation ─────────────────────────────────────
## Dashes march along locked edges giving a dormant-circuit feel.
## dash_offset increases continuously; draw_line is called in
## segments to simulate marching dashes.
#const DASH_LEN      := 10.0   # pixels per visible dash
#const GAP_LEN       := 14.0   # pixels per gap
#const DASH_SPEED    := 18.0   # pixels per second
#var _dash_offset    : float = 0.0
#
#const HEX_RADIUS := 220.0
#
## ── Node breathing ─────────────────────────────────────────────
## A very faint glow circle behind each locked node pulses slowly.
#const BREATHE_PERIOD := 4.0   # seconds for one full cycle
#const BREATHE_MIN    := 0.03  # minimum glow alpha
#const BREATHE_MAX    := 0.09  # maximum glow alpha
#const BREATHE_RADIUS := 28.0  # glow circle radius behind node
#var _time            : float = 0.0
#
## ── Electricity spark ──────────────────────────────────────────
## On segment purchase, a jagged spark burst plays along the
## newly activated edge then fades.
#const SPARK_DURATION    := 0.45   # seconds
#const SPARK_SEGMENTS    := 10     # jagged line sub-segments
#const SPARK_JITTER      := 12.0   # max perpendicular deviation px
#
## List of active sparks: {edge: int, timer: float, seed: int}
#var _sparks : Array = []
#
## ── Parent reference ───────────────────────────────────────────
#var _tree : Control
#
#func _ready() -> void:
	#_tree = get_parent()
#
## ═══════════════════════════════════════════════════════════════
## PUBLIC API
## ═══════════════════════════════════════════════════════════════
#
### Called by tech_tree.gd when a segment is purchased.
### edge_index: the pentagon edge between the two newly-lit nodes.
### Pass the index of the lower-phase node (0–4).
#func spark_edge(edge_index: int) -> void:
	#_sparks.append({
		#"edge":  edge_index,
		#"timer": SPARK_DURATION,
		#"seed":  randi(),         # unique random seed per spark
	#})
#
## ═══════════════════════════════════════════════════════════════
## PROCESS
## ═══════════════════════════════════════════════════════════════
#
#func _process(delta: float) -> void:
	#_time        += delta
	#_dash_offset  = fmod(_dash_offset + DASH_SPEED * delta, DASH_LEN + GAP_LEN)
#
	## Tick sparks
	#for i in range(_sparks.size() - 1, -1, -1):
		#_sparks[i]["timer"] -= delta
		#if _sparks[i]["timer"] <= 0.0:
			#_sparks.remove_at(i)
#
	#queue_redraw()
#
## ═══════════════════════════════════════════════════════════════
## DRAW
## ═══════════════════════════════════════════════════════════════
#
#func _draw() -> void:
	#if not _tree or _tree.hex_pts.size() < NUM_NODES:
		#return
	#_draw_bg_rings()
	##_draw_outer_frame()
	#_draw_radial_lines()
	#_draw_hex_edges()
	#_draw_edge_dots()
	#_draw_node_breathe()
	#_draw_sparks()
#
## ── Background concentric rings ────────────────────────────────
##func _draw_bg_rings() -> void:
	##for i in range(4):
		##var r := 62.0 + 35.0 + i * 55.0
		##draw_arc(_tree.hex_center, r, 0, TAU, 64, Color(COL_FRAME, 0.04), 1.0, true)
#
### ── Outer decorative pentagon frame ───────────────────────────
##func _draw_outer_frame() -> void:
	##for i in NUM_NODES:
		##draw_line(
			##_tree.outer_pts[i],
			##_tree.outer_pts[(i + 1) % NUM_NODES],
			##Color(COL_FRAME, 0.5), 2.0, true
		##)
	##for i in NUM_NODES:
		##var dir_out: Vector2 = (_tree.outer_pts[i] - _tree.hex_center).normalized()
		##draw_line(
			##_tree.outer_pts[i],
			##_tree.outer_pts[i] + dir_out * 8.0,
			##Color(COL_FRAME, 0.7), 2.0
		##)
#
## ── Radial spokes ─────────────────────────────────────────────
##func _draw_radial_lines() -> void:
	##for i in NUM_NODES:
		##var ph : int = _tree.phase_map[i]
		##if _tree._unlocked(ph):
			##draw_line(_tree.hex_center, _tree.hex_pts[i], COL_MAGENTA_GLOW, GLOW_W, true)
			##draw_line(_tree.hex_center, _tree.hex_pts[i], Color(COL_MAGENTA, 0.25), 4.0, true)
			##draw_line(_tree.hex_center, _tree.hex_pts[i], COL_MAGENTA_DIM, 1.5, true)
		##else:
			##draw_line(_tree.hex_center, _tree.hex_pts[i], COL_LOCKED_LINE, 1.5, true)
#
## ── Pentagon edges ────────────────────────────────────────────
##func _draw_hex_edges() -> void:
	##if _tree._edge_lit(0, 1):
		##draw_arc(_tree.hex_center, HEX_RADIUS, 0, TAU, 128, COL_MAGENTA_GLOW, GLOW_W, true)
		##draw_arc(_tree.hex_center, HEX_RADIUS, 0, TAU, 128, Color(COL_MAGENTA, 0.35), 6.0, true)
		##draw_arc(_tree.hex_center, HEX_RADIUS, 0, TAU, 128, COL_MAGENTA, LINE_W, true)
	##else:
		##draw_arc(_tree.hex_center, HEX_RADIUS, 0, TAU, 128, COL_LOCKED_LINE, 1.5, true)
		##_draw_circuit_dashes_arc()
#
## ── Marching dashes along a locked edge ───────────────────────
#func _draw_circuit_dashes(a: Vector2, b: Vector2, edge_idx: int) -> void:
	#var total_len := a.distance_to(b)
	#if total_len < 1.0:
		#return
#
	#var dir      := (b - a) / total_len
	#var period   := DASH_LEN + GAP_LEN
#
	## Each edge gets a phase offset so they don't all march in sync
	#var phase_offset := edge_idx * (period / NUM_NODES)
	#var offset := fmod(-_dash_offset + phase_offset + period * 100.0, period)
#
	## Walk the edge placing dashes
	#var cursor := -offset   # start slightly before edge so dashes enter cleanly
	#while cursor < total_len:
		#var dash_start := maxf(cursor, 0.0)
		#var dash_end   := minf(cursor + DASH_LEN, total_len)
		#if dash_end > dash_start:
			#draw_line(
				#a + dir * dash_start,
				#a + dir * dash_end,
				#Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, 0.22),
				#1.2, true
			#)
		#cursor += period
#
## ── Edge midpoint dots ────────────────────────────────────────
#func _draw_edge_dots() -> void:
	#var breathe := 1.0 + 0.03 * sin(_time * TAU / BREATHE_PERIOD)
#
	#for i in NUM_NODES:
		#var lit : bool    = _tree._edge_lit(i, (i + 1) % NUM_NODES)
		#var p   : Vector2 = _tree.edge_mids[i]
		#if lit:
			#draw_circle(p, SMALL_NODE_RADIUS + 3.0, COL_MAGENTA_GLOW)
			#draw_circle(p, SMALL_NODE_RADIUS, Color(COL_MAGENTA_DIM, 0.6))
			#draw_arc(p, SMALL_NODE_RADIUS, 0, TAU, 24, COL_MAGENTA, 1.5, true)
		#else:
			#var r := SMALL_NODE_RADIUS * breathe
			#draw_circle(p, r + 2.0, Color(COL_LOCKED_LINE.r, COL_LOCKED_LINE.g, COL_LOCKED_LINE.b, 0.08))
			#draw_circle(p, r, COL_LOCKED_FILL)
			#draw_arc(p, r, 0, TAU, 24, COL_LOCKED_BORDER, 1.2, true)
#
## ── Faint breathing glow behind locked nodes ──────────────────
#func _draw_node_breathe() -> void:
	#var alpha := BREATHE_MIN + (BREATHE_MAX - BREATHE_MIN) * \
		#(0.5 + 0.5 * sin(_time * TAU / BREATHE_PERIOD))
#
	#for i in NUM_NODES:
		#var ph : int = _tree.phase_map[i]
		#if not _tree._unlocked(ph):
			#draw_circle(
				#_tree.hex_pts[i],
				#BREATHE_RADIUS,
				#Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, alpha)
			#)
#
## ── Electricity spark on edge ─────────────────────────────────
#func _draw_sparks() -> void:
	#for spark in _sparks:
		#var edge  : int   = spark["edge"]
		#var timer : float = spark["timer"]
		#var seed  : int   = spark["seed"]
#
		#var j := (edge + 1) % NUM_NODES
		#var a : Vector2 = _tree.hex_pts[edge]
		#var b : Vector2 = _tree.hex_pts[j]
#
		## Fade: full brightness in first half, fades out in second half
		#var progress := 1.0 - (timer / SPARK_DURATION)
		#var alpha    := 1.0 - progress
		#alpha = clampf(alpha * 2.0, 0.0, 1.0)   # fast fade out
#
		#var dir  := (b - a).normalized()
		#var perp := Vector2(-dir.y, dir.x)       # perpendicular for jitter
#
		## Build jagged polyline using seeded random
		#var rng := RandomNumberGenerator.new()
		#rng.seed = seed
#
		#var points : Array[Vector2] = []
		#points.append(a)
		#for k in range(1, SPARK_SEGMENTS):
			#var t      := float(k) / SPARK_SEGMENTS
			#var base   := a.lerp(b, t)
			#var jitter := rng.randf_range(-SPARK_JITTER, SPARK_JITTER)
			## Jitter fades toward endpoints so spark meets the nodes cleanly
			#var edge_fade := sin(t * PI)
			#points.append(base + perp * jitter * edge_fade)
		#points.append(b)
#
		## Draw two passes: wide glow + sharp core
		#for k in range(points.size() - 1):
			#var col_glow := Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, alpha * 0.3)
			#var col_core := Color(1.0, 0.6, 0.9, alpha)
			#draw_line(points[k], points[k + 1], col_glow, 6.0, true)
			#draw_line(points[k], points[k + 1], col_core, 1.5, true)
#
#func _draw_circuit_dashes_arc() -> void:
	#var circumference := TAU * HEX_RADIUS
	#var period        := DASH_LEN + GAP_LEN
	#var offset        := fmod(-_dash_offset + period * 100.0, period)
	#var cursor        := -offset
	#while cursor < circumference:
		#var dash_start := maxf(cursor, 0.0)
		#var dash_end   := minf(cursor + DASH_LEN, circumference)
		#if dash_end > dash_start:
			#var angle_start := (dash_start / circumference) * TAU
			#var angle_end   := (dash_end   / circumference) * TAU
			#draw_arc(_tree.hex_center, HEX_RADIUS, angle_start, angle_end, 16, Color(COL_MAGENTA.r, COL_MAGENTA.g, COL_MAGENTA.b, 0.22), 1.2, true)
		#cursor += period
