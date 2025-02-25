package ronin

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import kn "local:katana"

Carousel :: struct {
	offset:        [2]f32,
	last_offset:   [2]f32,
	timer:         f32,
	selected_page: int,
	page_count:    int,
}

begin_carousel :: proc(loc := #caller_location) -> bool {
	object := get_object(hash(loc))
	if object.variant == nil {
		object.variant = Carousel{}
	}
	carousel := &object.variant.(Carousel)
	carousel.page_count = 0
	begin_object(object) or_return
	begin_layout(
		with_box(move_box(object.box, -carousel.offset)),
		left_to_right,
		is_dynamic,
	) or_return
	set_size(exactly(box_width(object.box)))
	return true
}

end_carousel :: proc() {
	if object, ok := get_current_object(); ok {
		carousel := &object.variant.(Carousel)
		last_selected_page := carousel.selected_page
		if key_pressed(.Left) {
			carousel.selected_page = max(0, carousel.selected_page - 1)
		} else if key_pressed(.Right) {
			carousel.selected_page = min(carousel.page_count - 1, carousel.selected_page + 1)
		}
		carousel.selected_page = clamp(carousel.selected_page + int(global_state.mouse_scroll.y), 0, carousel.page_count - 1)
		if last_selected_page != carousel.selected_page {
			carousel.last_offset = carousel.offset
			carousel.timer = 0
		}
		animation_time := ease.circular_in_out(carousel.timer)
		carousel.offset.x =
			carousel.last_offset.x +
			(box_width(object.box) * f32(carousel.selected_page) - carousel.last_offset.x) *
				animation_time
		carousel.timer = min(1, carousel.timer + global_state.delta_time * 5)
		draw_frames(int(animation_time < 1) * 3)

		// Draw dots
		{
			dot_radius := f32(2.5)
			dot_spacing := f32(20)
			dots_width := dot_spacing * f32(carousel.page_count)
			dots_left_origin := box_center_x(object.box) - dots_width / 2
			for page_index in 0..<carousel.page_count {
				dot_position := [2]f32{dots_left_origin + f32(page_index) * dot_spacing, object.box.hi.y - dot_spacing}
				kn.fill_circle(dot_position, dot_radius * (golden_ratio if carousel.selected_page == page_index else 1), paint = get_current_style().color.content)
			}
		}

		end_layout()
		end_object()
	}
}

@(deferred_out = __do_carousel)
do_carousel :: proc(loc := #caller_location) -> bool {
	return begin_carousel(loc)
}

@(private)
__do_carousel :: proc(ok: bool) {
	if ok {
		end_carousel()
	}
}

begin_page :: proc(props: ..Layout_Property) -> bool {
	parent_object := get_current_object() or_return
	carousel := (&parent_object.variant.(Carousel)) or_return
	set_size(box_size(parent_object.box))
	begin_layout(..props) or_return
	carousel.page_count += 1
	return true
}

end_page :: proc() {
	end_layout()
}

@(deferred_out = __do_page)
do_page :: proc(props: ..Layout_Property) -> bool {
	return begin_page(..props)
}

@(private)
__do_page :: proc(ok: bool) {
	if ok {
		end_page()
	}
}
