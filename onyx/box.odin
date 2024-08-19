package onyx

import "core:math"
import "core:math/linalg"

import "base:intrinsics"

Box :: struct {
	lo, hi: [2]f32,
}

Alignment :: enum {
	Near,
	Middle,
	Far,
}

Corner :: enum {
	Top_Left,
	Top_Right,
	Bottom_Right,
	Bottom_Left,
}

Side :: enum {
	Left,
	Right,
	Top,
	Bottom,
}

Corners :: bit_set[Corner;u8]

ALL_CORNERS :: Corners{.Top_Left, .Top_Right, .Bottom_Left, .Bottom_Right}

Clip :: enum {
	None, // completely visible
	Partial, // partially visible
	Full, // hidden
}

box_width :: proc(box: Box) -> f32 {
	return box.hi.x - box.lo.x
}
box_height :: proc(box: Box) -> f32 {
	return box.hi.y - box.lo.y
}
box_center_x :: proc(box: Box) -> f32 {
	return (box.lo.x + box.hi.x) * 0.5
}
box_center_y :: proc(box: Box) -> f32 {
	return (box.lo.y + box.hi.y) * 0.5
}

// If `a` is inside of `b`
point_in_box :: proc(a: [2]f32, b: Box) -> bool {
	return (a.x >= b.lo.x) && (a.x < b.hi.x) && (a.y >= b.lo.y) && (a.y < b.hi.y)
}

// If `a` is touching `b`
box_touches_box :: proc(a, b: Box) -> bool {
	return (a.hi.x >= b.lo.x) && (a.lo.x <= b.hi.x) && (a.hi.y >= b.lo.y) && (a.lo.y <= b.hi.y)
}

// If `a` is contained entirely in `b`
box_contains_box :: proc(a, b: Box) -> bool {
	return (b.lo.x >= a.lo.x) && (b.hi.x <= a.hi.x) && (b.lo.y >= a.lo.y) && (b.hi.y <= a.hi.y)
}

// Get the clip status of `b` inside `a`
get_clip :: proc(a, b: Box) -> Clip {
	if a.lo.x > b.hi.x || a.hi.x < b.lo.x || a.lo.y > b.hi.y || a.hi.y < b.lo.y {
		return .Full
	}
	if a.lo.x >= b.lo.x && a.hi.x <= b.hi.x && a.lo.y >= b.lo.y && a.hi.y <= b.hi.y {
		return .None
	}
	return .Partial
}

// Updates `a` to fit `b` inside it
update_bounding :: proc(a, b: Box) -> Box {
	a := a
	a.lo = linalg.min(a.lo, b.lo)
	a.hi = linalg.max(a.hi, b.hi)
	return a
}

// Clamps `a` inside `b`
clamp_box :: proc(a, b: Box) -> Box {
	return {linalg.clamp(a.lo, b.lo, b.hi), linalg.clamp(a.hi, b.lo, b.hi)}
}

box_center :: proc(a: Box) -> [2]f32 {
	return {(a.lo.x + a.hi.x) * 0.5, (a.lo.y + a.hi.y) * 0.5}
}

// Shrink a box by pushing one of its sides
squish_box_left :: proc(box: Box, amount: f32) -> Box {
	box := box
	box.lo.x += amount
	return box
}
squish_box_right :: proc(box: Box, amount: f32) -> Box {
	box := box
	box.hi.x -= amount
	return box
}
squish_box_top :: proc(box: Box, amount: f32) -> Box {
	box := box
	box.lo.y += amount
	return box
}
squish_box_bottom :: proc(box: Box, amount: f32) -> Box {
	box := box
	box.hi.y -= amount
	return box
}
squish_box :: proc(box: Box, side: Side, amount: f32) -> (result: Box) {
	switch side {
	case .Bottom:
		result = squish_box_bottom(box, amount)
	case .Top:
		result = squish_box_top(box, amount)
	case .Left:
		result = squish_box_left(box, amount)
	case .Right:
		result = squish_box_right(box, amount)
	}
	return
}

align_inner :: proc(b: Box, size: [2]f32, align: [2]Alignment) -> Box {
	a: Box
	switch align.x {
	case .Far:
		a.hi.x = b.hi.x
		a.lo.x = b.hi.x - size.x
	case .Middle:
		c := (b.lo.x + b.hi.x) / 2
		d := size.x / 2
		a.lo.x = c - d
		a.hi.x = c + d
	case .Near:
		a.lo.x = b.lo.x
		a.hi.x = b.lo.x + size.x
	}
	switch align.y {
	case .Far:
		a.hi.y = b.hi.y
		a.lo.y = b.hi.y - size.y
	case .Middle:
		c := (b.lo.y + b.hi.y) / 2
		d := size.y / 2
		a.lo.y = c - d
		a.hi.y = c + d
	case .Near:
		a.lo.y = b.lo.y
		a.hi.y = b.lo.y + size.y
	}
	return a
}

shrink_box_single :: proc(a: Box, amount: f32) -> Box {
	return {a.lo + amount, a.hi - amount}
}

shrink_box_double :: proc(a: Box, amount: [2]f32) -> Box {
	return {a.lo + amount, a.hi - amount}
}

shrink_box :: proc {
	shrink_box_single,
	shrink_box_double,
}

expand_box :: proc(a: Box, amount: f32) -> Box {
	return {a.lo - amount, a.hi + amount}
}

move_box :: proc(a: Box, delta: [2]f32) -> Box {
	return {a.lo + delta, a.hi + delta}
}

// cut a box and return the cut piece
cut_box_left :: proc(box: ^Box, a: f32) -> (res: Box) {
	res = {box.lo, {box.lo.x + a, box.hi.y}}
	box.lo.x += a
	return
}
cut_box_top :: proc(box: ^Box, a: f32) -> (res: Box) {
	res = {box.lo, {box.hi.x, box.lo.y + a}}
	box.lo.y += a
	return
}
cut_box_right :: proc(box: ^Box, a: f32) -> (res: Box) {
	res = {{box.hi.x - a, box.lo.y}, box.hi}
	box.hi.x -= a
	return
}
cut_box_bottom :: proc(box: ^Box, a: f32) -> (res: Box) {
	res = {{box.lo.x, box.hi.y - a}, box.hi}
	box.hi.y -= a
	return
}
cut_box :: proc(box: ^Box, side: Side, amount: f32) -> Box {
	switch side {
	case .Bottom:
		return cut_box_bottom(box, amount)
	case .Top:
		return cut_box_top(box, amount)
	case .Left:
		return cut_box_left(box, amount)
	case .Right:
		return cut_box_right(box, amount)
	}
	return {}
}
// extend a box and return the attached piece
grow_box_left :: proc(box: ^Box, a: f32) {
	box.hi.x = max(box.hi.x, box.lo.x + a)
}
grow_box_top :: proc(box: ^Box, a: f32) {
	box.hi.y = max(box.hi.y, box.lo.y + a)
}
grow_box_right :: proc(box: ^Box, a: f32) {
	box.lo.x = min(box.lo.x, box.hi.x - a)
}
grow_box_bottom :: proc(box: ^Box, a: f32) {
	box.lo.y = min(box.lo.y, box.hi.y - a)
}
grow_box :: proc(box: ^Box, side: Side, amount: f32) {
	switch side {
	case .Bottom:
		grow_box_top(box, amount)
	case .Top:
		grow_box_bottom(box, amount)
	case .Right:
		grow_box_left(box, amount)
	case .Left:
		grow_box_right(box, amount)
	}
}

// get a cut piece of a box
get_box_cut_left :: proc(b: Box, a: f32) -> Box {
	return {b.lo, {b.lo.x + a, b.hi.y}}
}
get_box_cut_top :: proc(b: Box, a: f32) -> Box {
	return {b.lo, {b.hi.x, b.lo.y + a}}
}
get_box_cut_right :: proc(b: Box, a: f32) -> Box {
	return {{b.hi.x - a, b.lo.y}, b.hi}
}
get_box_cut_bottom :: proc(b: Box, a: f32) -> Box {
	return {{b.lo.x, b.hi.y - a}, b.hi}
}
get_box_cut :: proc(box: Box, side: Side, amount: f32) -> Box {
	switch side {
	case .Bottom:
		return get_box_cut_bottom(box, amount)
	case .Top:
		return get_box_cut_top(box, amount)
	case .Left:
		return get_box_cut_left(box, amount)
	case .Right:
		return get_box_cut_right(box, amount)
	}
	return {}
}

// attach a box
attach_box_left :: proc(box: Box, size: f32) -> Box {
	return {{box.lo.x - size, box.lo.y}, {box.lo.x, box.hi.y}}
}
attach_box_top :: proc(box: Box, size: f32) -> Box {
	return {{box.lo.x, box.lo.y - size}, {box.hi.x, box.lo.y}}
}
attach_box_right :: proc(box: Box, size: f32) -> Box {
	return {{box.hi.x, box.lo.y}, {box.hi.x + size, box.hi.y}}
}
attach_box_bottom :: proc(box: Box, size: f32) -> Box {
	return {{box.lo.x, box.hi.y}, {box.hi.x, box.hi.y + size}}
}
attach_box :: proc(box: Box, side: Side, size: f32) -> Box {
	switch side {
	case .Bottom:
		return attach_box_bottom(box, size)
	case .Top:
		return attach_box_top(box, size)
	case .Left:
		return attach_box_left(box, size)
	case .Right:
		return attach_box_right(box, size)
	}
	return {}
}

// Get the valid corners for the given sides or whatever
side_corners :: proc(side: Side) -> Corners {
	switch side {
	case .Bottom:
		return {.Top_Left, .Top_Right}
	case .Top:
		return {.Bottom_Left, .Bottom_Right}
	case .Left:
		return {.Top_Right, .Bottom_Right}
	case .Right:
		return {.Top_Left, .Bottom_Left}
	}
	return ALL_CORNERS
}

// attach a box
get_attached_box :: proc(box: Box, side: Side, size: [2]f32, offset: f32) -> Box {
	switch side {

	case .Bottom:
		middle := (box.lo.x + box.hi.x) / 2
		return {
			{middle - size.x / 2, box.hi.y + offset},
			{middle + size.x / 2, box.hi.y + offset + size.y},
		}

	case .Left:
		middle := (box.lo.y + box.hi.y) / 2
		return {
			{box.lo.x - (offset + size.x), middle - size.y / 2},
			{box.lo.x - offset, middle + size.y / 2},
		}

	case .Right:
		middle := (box.lo.y + box.hi.y) / 2
		return {
			{box.hi.x + offset, middle - size.y / 2},
			{box.lo.x + offset + size.x, middle + size.y / 2},
		}

	case .Top:
		middle := (box.lo.x + box.hi.x) / 2
		return {
			{middle - size.x / 2, box.lo.y - offset - size.y},
			{middle + size.x / 2, box.lo.y - offset},
		}
	}
	return {}
}

Ray_Box_Info :: struct {
	point, normal: [2]f32,
	time:          f32,
}
box_touches_line :: proc(box: Box, a, b: [2]f32) -> (info: Ray_Box_Info, ok: bool) {
	start := a
	direction := b - a

	normal: [2]f32

	inv_direction := 1.0 / direction
	t_near := (box.lo - start) * inv_direction
	t_far := (box.hi - start) * inv_direction

	if math.is_nan(t_far.y) || math.is_nan(t_far.x) {
		return
	}
	if math.is_nan(t_near.y) || math.is_nan(t_near.x) {
		return
	}

	if t_near[0] > t_far[0] {t_near[0], t_far[0] = t_far[0], t_near[0]}
	if t_near[1] > t_far[1] {t_near[1], t_far[1] = t_far[1], t_near[1]}

	if t_near[0] > t_far[1] || t_near[1] > t_far[0] {
		return
	}

	info.time = max(t_near[0], t_near[1])

	t_hit_far := min(t_far[0], t_far[1])

	if t_hit_far < 0 {
		return
	}

	info.point = start + info.time * direction

	if t_near[0] > t_near[1] {
		if inv_direction[0] < 0 {
			info.normal = {1, 0}
		} else {
			info.normal = {-1, 0}
		}
	} else if t_near[0] < t_near[1] {
		if inv_direction[1] < 0 {
			info.normal = {0, 1}
		} else {
			info.normal = {0, -1}
		}
	}

	ok = info.time >= 0 && info.time <= 1

	return
}
