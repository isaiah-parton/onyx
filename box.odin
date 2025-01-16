package onyx

import "../vgo"
import "base:intrinsics"
import "core:math"
import "core:math/linalg"

Box :: vgo.Box

Alignment :: enum {
	Near,
	Middle,
	Far,
}

Corner :: enum {
	Top_Left,
	Top_Right,
	Bottom_Left,
	Bottom_Right,
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
	None,
	Partial,
	Full,
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

box_size :: proc(box: Box) -> [2]f32 {
	return box.hi - box.lo
}

size_ratio :: proc(size: [2]f32, ratio: [2]f32) -> [2]f32 {
	return [2]f32 {
		max(size.x, size.y * (ratio.x / ratio.y)),
		max(size.y, size.x * (ratio.y / ratio.x)),
	}
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

snapped_box :: proc(box: Box) -> Box {
	return Box{linalg.floor(box.lo), linalg.floor(box.hi)}
}

box_center :: proc(a: Box) -> [2]f32 {
	return {(a.lo.x + a.hi.x) * 0.5, (a.lo.y + a.hi.y) * 0.5}
}

cut_box_left :: proc(box: ^Box, a: f32) -> (res: Box) {
	left := min(box.lo.x + a, box.hi.x)
	res = {box.lo, {left, box.hi.y}}
	box.lo.x = left
	return
}

cut_box_top :: proc(box: ^Box, a: f32) -> (res: Box) {
	top := min(box.lo.y + a, box.hi.y)
	res = {box.lo, {box.hi.x, top}}
	box.lo.y = top
	return
}

cut_box_right :: proc(box: ^Box, a: f32) -> (res: Box) {
	right := max(box.lo.x, box.hi.x - a)
	res = {{right, box.lo.y}, box.hi}
	box.hi.x = right
	return
}

cut_box_bottom :: proc(box: ^Box, a: f32) -> (res: Box) {
	bottom := max(box.lo.y, box.hi.y - a)
	res = {{box.lo.x, bottom}, box.hi}
	box.hi.y = bottom
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

point_aligned_in_box :: proc(box: Box, align_h: Alignment, align_v: Alignment) -> [2]f32 {
	point: [2]f32
	switch align_h {
	case .Near:
		point.x = box.lo.x
	case .Far:
		point.x = box.hi.x
	case .Middle:
		point.x = (box.lo.x + box.hi.x) / 2
	}
	switch align_v {
	case .Near:
		point.y = box.lo.y
	case .Far:
		point.y = box.hi.y
	case .Middle:
		point.y = (box.lo.y + box.hi.y) / 2
	}
	return point
}

shrink_box :: proc(a: Box, amount: [2]f32) -> Box {
	return {a.lo + amount, a.hi - amount}
}

expand_box :: proc(a: Box, amount: f32) -> Box {
	return {a.lo - amount, a.hi + amount}
}

move_box :: proc(a: Box, delta: [2]f32) -> Box {
	return {a.lo + delta, a.hi + delta}
}

split_box_left :: proc(box: Box, left: f32) -> (left_box, right_box: Box) {
	left_box = {box.lo, {box.lo.x + left, box.hi.y}}
	right_box = {{left_box.hi.x, left_box.lo.y}, box.hi}
	return
}
split_box_right :: proc(box: Box, right: f32) -> (right_box, left_box: Box) {
	left_box = {box.lo, {box.hi.x - right, box.hi.y}}
	right_box = {{left_box.hi.x, left_box.lo.y}, box.hi}
	return
}
split_box_top :: proc(box: Box, top: f32) -> (top_box, bottom_box: Box) {
	top_box = {box.lo, {box.hi.x, box.lo.y + top}}
	bottom_box = {{top_box.lo.x, top_box.hi.y}, box.hi}
	return
}
split_box_bottom :: proc(box: Box, bottom: f32) -> (bottom_box, top_box: Box) {
	top_box = {box.lo, {box.hi.x, box.hi.y - bottom}}
	bottom_box = {{top_box.lo.x, top_box.hi.y}, box.hi}
	return
}
split_box :: proc(box: Box, side: Side, amount: f32) -> (new_box, remainder: Box) {
	switch side {
	case .Bottom:
		return split_box_bottom(box, amount)
	case .Top:
		return split_box_top(box, amount)
	case .Left:
		return split_box_left(box, amount)
	case .Right:
		return split_box_right(box, amount)
	}
	return
}

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
