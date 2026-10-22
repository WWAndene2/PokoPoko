class_name SoftPoko
extends RefCounted
## Soft-body Poko: a ring of points held around the center by springs and inner pressure.
## The body lags behind its center (inertia), squashes against walls and other Pokos
## (contact planes) and physically stretches toward same-color neighbours (sticks),
## which is what makes fused Pokos look like one jelly mass. Visual only.

const N := 12
const SUBSTEPS := 2
const STIFFNESS := 360.0 # ring point -> rest shape spring
const DAMPING := 9.0
const PRESSURE := 0.5 # keeps the area close to a circle's when squashed
const INERTIA := 0.55 # how much of the center's velocity change the ring feels
const MAX_KICK := 4.0 # in radii per second, caps impacts

var r := 20.0
var off := PackedVector2Array() # ring points relative to center
var vel := PackedVector2Array()
var center := Vector2.ZERO
var center_vel := Vector2.ZERO
var fresh := true


func _init(radius: float) -> void:
	r = radius
	off.resize(N)
	vel.resize(N)
	for i in N:
		off[i] = dir(i) * r
		vel[i] = Vector2.ZERO


static var DIRS: PackedVector2Array = _make_dirs()


static func _make_dirs() -> PackedVector2Array:
	var d := PackedVector2Array()
	for i in N:
		d.append(Vector2.from_angle(TAU * i / N))
	return d


static func dir(i: int) -> Vector2:
	return DIRS[i]


## planes: [[normal, distance], ...] the ring cannot cross (walls, floor, other Pokos).
## sticks: [[direction, grow, reach], ...] the ring stretches toward (same-color neighbours).
func step(new_center: Vector2, dt: float, planes: Array, sticks: Array,
		breath := 1.0, sway := 0.0, jitter := 0.0) -> void:
	if dt <= 0.0:
		return
	var v := (new_center - center) / dt
	if fresh:
		v = Vector2.ZERO
		fresh = false
	else:
		# Inertia: when the center speeds up or stops, the ring lags behind
		var dv := ((v - center_vel) * INERTIA).limit_length(r * MAX_KICK)
		for i in N:
			vel[i] -= dv
	center_vel = v
	center = new_center
	var h := dt / SUBSTEPS
	var rr := r * breath
	var area0 := PI * rr * rr
	for s in SUBSTEPS:
		var press := PRESSURE * (area0 - area()) / area0
		for i in N:
			var d := DIRS[i] if sway == 0.0 else DIRS[i].rotated(sway)
			var reach := rr
			for st in sticks:
				var w := clampf((d.dot(st[0]) - 0.42) / 0.58, 0.0, 1.0)
				w = w * w * (3.0 - 2.0 * w)
				reach = maxf(reach, rr + st[2] * st[1] * w)
			var f: Vector2 = (d * reach - off[i]) * STIFFNESS - vel[i] * DAMPING + d * press * STIFFNESS * rr
			if jitter > 0.0:
				f += Vector2(randf() - 0.5, randf() - 0.5) * jitter * STIFFNESS
			vel[i] += f * h
			off[i] += vel[i] * h
			for pl in planes:
				var n: Vector2 = pl[0]
				var proj := off[i].dot(n)
				if proj > pl[1]:
					off[i] -= n * (proj - pl[1])
					var vn := vel[i].dot(n)
					if vn > 0.0:
						vel[i] -= n * vn
			off[i] = off[i].limit_length(r * 2.2)


## Impact: flattens the body (top goes down, sides bulge out), then it springs back.
func squash_kick(strength: float) -> void:
	var s := r * strength
	for i in N:
		var d := dir(i)
		vel[i] += Vector2(d.x * s, -d.y * s)


func area() -> float:
	var a := 0.0
	for i in N:
		var p := off[i]
		var q := off[(i + 1) % N]
		a += p.x * q.y - q.x * p.y
	return absf(a) * 0.5


## Center of the deformed body, relative to `center` (the face follows it).
func centroid() -> Vector2:
	var c := Vector2.ZERO
	for p in off:
		c += p
	return c / N


## Vertical squash ratio (1 = round, < 1 = flattened), read from the top and bottom points.
func squash_ratio() -> float:
	return clampf((off[N / 4].y - off[3 * N / 4].y) / (2.0 * r), 0.6, 1.5)


## Smoothed outline in screen space (Catmull-Rom through the ring points).
func outline(offset := Vector2.ZERO, scale := 1.0) -> PackedVector2Array:
	var pts := PackedVector2Array()
	var base := center + offset
	for i in N:
		var p0 := off[(i - 1 + N) % N] * scale
		var p1 := off[i] * scale
		var p2 := off[(i + 1) % N] * scale
		var p3 := off[(i + 2) % N] * scale
		for k in 3:
			var t := k / 3.0
			var t2 := t * t
			var t3 := t2 * t
			pts.append(base + 0.5 * (2.0 * p1 + (p2 - p0) * t + (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 + (3.0 * p1 - p0 - 3.0 * p2 + p3) * t3))
	return pts
