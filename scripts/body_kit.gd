class_name BodyKit
extends RefCounted
## Builds smooth body-part meshes in code (no imported models).
##
## Every vertex stores a material "slot" in COLOR.r (slot / 255) and an ambient
## occlusion factor in COLOR.g. shaders/body.gdshader turns slots into the
## outfit's colors, so one material covers a whole person and parts batch well.
##
## Shapes are made of "lofts": a stack of ellipse rings joined into a tube.
## Ring angle 0 is the front of the body (-Z), angles grow towards +X.

enum { SKIN, TOP, BOTTOM, SHOES, HAIR, GEAR, DARK, METAL, WHITE, GLOW, ACCENT, LIPS, FLESH }

var st := SurfaceTool.new()
var _count := 0


func _init() -> void:
	st.begin(Mesh.PRIMITIVE_TRIANGLES)


func commit() -> ArrayMesh:
	if _count == 0:
		# keep a valid (invisible) mesh
		box(Vector3.ZERO, Vector3.ONE * 0.001, DARK)
	return st.commit()


func _v(p: Vector3, n: Vector3, slot: int, ao: float) -> int:
	st.set_color(Color(slot / 255.0, ao, 0.0, 1.0))
	st.set_normal(n)
	st.add_vertex(p)
	_count += 1
	return _count - 1


static func ring(y: float, rx: float, rz: float, slot: int, z := 0.0, ao := 1.0, x := 0.0) -> Array:
	return [Vector3(x, y, z), rx, rz, slot, ao]


## rings: arrays from ring(). Each band between two rings takes the first ring's slot.
## arc/arc_start make an open loft (for coats and beards). xf places the result.
func loft(rings: Array, xf := Transform3D.IDENTITY, segs := 12, caps := true, arc := TAU, arc_start := 0.0, double_sided := false) -> void:
	var n_r := rings.size()
	if n_r < 2:
		return
	var closed := is_equal_approx(arc, TAU)
	var cols := segs + 1
	var pts: Array = []
	var mid := Vector3.ZERO
	for r in rings:
		mid += r[0]
	mid /= float(n_r)
	for i in n_r:
		var row := PackedVector3Array()
		var c: Vector3 = rings[i][0]
		var rx: float = rings[i][1]
		var rz: float = rings[i][2]
		for j in cols:
			var a := arc_start + arc * float(j) / float(segs)
			row.append(c + Vector3(sin(a) * rx, 0.0, -cos(a) * rz))
		pts.append(row)
	var nb := xf.basis.inverse().transposed()
	# normals from the surface tangents, pointing away from the ring center
	var norms: Array = []
	for i in n_r:
		var row_n := PackedVector3Array()
		var c: Vector3 = rings[i][0]
		for j in cols:
			var jp := j + 1
			var jm := j - 1
			if closed:
				if jp >= cols:
					jp = 1
				if jm < 0:
					jm = cols - 2
			else:
				jp = mini(jp, cols - 1)
				jm = maxi(jm, 0)
			var tu: Vector3 = pts[i][jp] - pts[i][jm]
			var tv: Vector3 = pts[mini(i + 1, n_r - 1)][j] - pts[maxi(i - 1, 0)][j]
			var n := tv.cross(tu)
			var radial: Vector3 = pts[i][j] - c
			if n.length_squared() < 1e-12:
				n = pts[i][j] - mid
			elif radial.length_squared() > 1e-10 and n.dot(radial) < 0.0:
				n = -n
			row_n.append(n.normalized())
		norms.append(row_n)
	for side in (2 if double_sided else 1):
		var flip := side == 1
		for i in n_r - 1:
			var slot: int = rings[i][3]
			var ao0: float = rings[i][4]
			var ao1: float = rings[i + 1][4]
			if flip:
				ao0 *= 0.45
				ao1 *= 0.45
			var base := _count
			for k in 2:
				for j in cols:
					var p: Vector3 = pts[i + k][j]
					var n: Vector3 = norms[i + k][j]
					if flip:
						n = -n
					_v(xf * p, (nb * n).normalized(), slot, ao0 if k == 0 else ao1)
			for j in segs:
				var a0 := base + j
				var a1 := base + j + 1
				var b0 := base + cols + j
				var b1 := base + cols + j + 1
				_tri(a0, b0, a1, flip, pts[i][j], pts[i + 1][j], pts[i][j + 1], norms[i][j])
				_tri(a1, b0, b1, flip, pts[i][j + 1], pts[i + 1][j], pts[i + 1][j + 1], norms[i][j + 1])
	if caps:
		_cap(rings[0], pts[0], xf, nb, (rings[0][0] - rings[1][0]))
		_cap(rings[n_r - 1], pts[n_r - 1], xf, nb, (rings[n_r - 1][0] - rings[n_r - 2][0]))


## adds a triangle with the winding that faces along its normal
func _tri(a: int, b: int, c: int, flip: bool, pa: Vector3, pb: Vector3, pc: Vector3, n: Vector3) -> void:
	var face := (pb - pa).cross(pc - pa)
	var want_ccw := face.dot(n) < 0.0   # Godot front faces are clockwise
	if flip:
		want_ccw = not want_ccw
	if want_ccw:
		st.add_index(a)
		st.add_index(c)
		st.add_index(b)
	else:
		st.add_index(a)
		st.add_index(b)
		st.add_index(c)


func _cap(r: Array, row: PackedVector3Array, xf: Transform3D, nb: Basis, out_dir: Vector3) -> void:
	if r[1] < 0.004 or r[2] < 0.004 or out_dir.length_squared() < 1e-12:
		return
	var n := out_dir.normalized()
	var wn := (nb * n).normalized()
	var c: Vector3 = r[0]
	var ci := _v(xf * c, wn, r[3], r[4])
	var base := _count
	for p in row:
		_v(xf * p, wn, r[3], r[4])
	for j in row.size() - 1:
		_tri(ci, base + j, base + j + 1, false, c, row[j], row[j + 1], n)


func ellipsoid(c: Vector3, r: Vector3, slot: int, ao := 1.0, basis := Basis.IDENTITY, lat := 7, lon := 12) -> void:
	var rings: Array = []
	for i in lat + 1:
		var t := float(i) / float(lat)
		var y := -cos(PI * t) * r.y
		var s := sin(PI * t)
		rings.append(ring(y, maxf(s * r.x, 0.0), maxf(s * r.z, 0.0), slot, 0.0, ao))
	loft(rings, Transform3D(basis, c), lon, false)


## Part of an ellipsoid that covers the top of a head: front_lat / back_lat are how far
## down (radians from the top) it reaches at the front and back. Used for hair, hats, hoods.
func shell(c: Vector3, r: Vector3, slot: int, front_lat: float, back_lat: float, ao := 1.0, inner := true, lon := 18, lat := 8) -> void:
	for side in (2 if inner else 1):
		var flip := side == 1
		var sc := 0.94 if flip else 1.0
		var base := _count
		var pts := PackedVector3Array()
		var nrm := PackedVector3Array()
		for j in lon + 1:
			var th := TAU * float(j) / float(lon)
			var lat_max := lerpf(front_lat, back_lat, (1.0 - cos(th)) * 0.5)
			for i in lat + 1:
				var ph := lat_max * float(i) / float(lat)
				var d := Vector3(sin(ph) * sin(th), cos(ph), -sin(ph) * cos(th))
				var p := c + Vector3(d.x * r.x, d.y * r.y, d.z * r.z) * sc
				var q := p - c
				var n := Vector3(q.x / (r.x * r.x), q.y / (r.y * r.y), q.z / (r.z * r.z)).normalized()
				if flip:
					n = -n
				pts.append(p)
				nrm.append(n)
				var edge := float(i) / float(lat)
				_v(p, n, slot, (ao * lerpf(1.0, 0.8, edge * edge)) if not flip else 0.3)
		for j in lon:
			for i in lat:
				var a0 := j * (lat + 1) + i
				var a1 := a0 + 1
				var b0 := (j + 1) * (lat + 1) + i
				var b1 := b0 + 1
				_tri(base + a0, base + b0, base + a1, flip, pts[a0], pts[b0], pts[a1], nrm[a0] if not flip else -nrm[a0])
				_tri(base + a1, base + b0, base + b1, flip, pts[a1], pts[b0], pts[b1], nrm[a1] if not flip else -nrm[a1])


## flat-shaded box, optionally rotated
func box(c: Vector3, size: Vector3, slot: int, basis := Basis.IDENTITY, ao := 1.0) -> void:
	var h := size * 0.5
	var faces := [
		[Vector3.RIGHT, Vector3.UP, Vector3.BACK], [Vector3.LEFT, Vector3.UP, Vector3.FORWARD],
		[Vector3.UP, Vector3.BACK, Vector3.RIGHT], [Vector3.DOWN, Vector3.FORWARD, Vector3.RIGHT],
		[Vector3.BACK, Vector3.UP, Vector3.LEFT], [Vector3.FORWARD, Vector3.UP, Vector3.RIGHT],
	]
	for f in faces:
		var n: Vector3 = f[0]
		var u: Vector3 = f[1]
		var v: Vector3 = f[2]
		var center := Vector3(n.x * h.x, n.y * h.y, n.z * h.z)
		var uu := Vector3(u.x * h.x, u.y * h.y, u.z * h.z)
		var vv := Vector3(v.x * h.x, v.y * h.y, v.z * h.z)
		var corners := [center - uu - vv, center + uu - vv, center + uu + vv, center - uu + vv]
		var wn := (basis * n).normalized()
		var base := _count
		var wp: Array = []
		for k in 4:
			var p: Vector3 = c + basis * Vector3(corners[k])
			wp.append(p)
			_v(p, wn, slot, ao)
		_tri(base, base + 1, base + 2, false, wp[0], wp[1], wp[2], wn)
		_tri(base, base + 2, base + 3, false, wp[0], wp[2], wp[3], wn)


## a cylinder (or cone) from a to b
func tube(a: Vector3, b: Vector3, r0: float, r1: float, slot: int, segs := 8, ao := 1.0, caps := true) -> void:
	var d := b - a
	var length := d.length()
	if length < 1e-5:
		return
	var y := d / length
	var x := y.cross(Vector3.FORWARD if absf(y.z) < 0.9 else Vector3.RIGHT).normalized()
	var z := x.cross(y).normalized()
	var basis := Basis(x, y, -z)
	loft([ring(0.0, r0, r0, slot, 0.0, ao), ring(length, r1, r1, slot, 0.0, ao)], Transform3D(basis, a), segs, caps)


## a ring (torus) facing -Z, e.g. glasses frames
func torus(c: Vector3, major: float, minor: float, slot: int, basis := Basis.IDENTITY, segs := 12, sides := 5) -> void:
	var base := _count
	var pts := PackedVector3Array()
	var nrm := PackedVector3Array()
	for i in segs + 1:
		var a := TAU * float(i) / float(segs)
		var center := Vector3(cos(a) * major, sin(a) * major, 0.0)
		var out := Vector3(cos(a), sin(a), 0.0)
		for k in sides + 1:
			var b := TAU * float(k) / float(sides)
			var n := out * cos(b) + Vector3(0, 0, sin(b))
			var p := c + basis * (center + n * minor)
			pts.append(p)
			nrm.append((basis * n).normalized())
			_v(p, (basis * n).normalized(), slot, 1.0)
	for i in segs:
		for k in sides:
			var a0 := i * (sides + 1) + k
			var a1 := a0 + 1
			var b0 := (i + 1) * (sides + 1) + k
			var b1 := b0 + 1
			_tri(base + a0, base + b0, base + a1, false, pts[a0], pts[b0], pts[a1], nrm[a0])
			_tri(base + a1, base + b0, base + b1, false, pts[a1], pts[b0], pts[b1], nrm[a1])


## a flat, two-sided triangle (wing membranes)
func tri(a: Vector3, b: Vector3, c: Vector3, slot: int, ao := 1.0) -> void:
	var n := (b - a).cross(c - a).normalized()
	for side in 2:
		var nn := n if side == 0 else -n
		var base := _count
		_v(a, nn, slot, ao)
		_v(b, nn, slot, ao)
		_v(c, nn, slot, ao)
		_tri(base, base + 1, base + 2, false, a, b, c, nn)
