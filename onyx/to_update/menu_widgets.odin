package onyx

import "../../vgo"
import "base:intrinsics"
import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"

@(deferred_out = __menu_bar)
menu_bar :: proc() -> bool {
	begin_layout({}) or_return
	box := layout_box()
	vgo.fill_box(box, core.style.rounding, core.style.color.field)
	vgo.stroke_box(box, core.style.rounding, 1, core.style.color.substance)
	add_padding(core.style.menu_padding)
	return true
}
@(private)
__menu_bar :: proc(ok: bool) {
	if ok {
		end_layout()
	}
}

Menu_Info :: struct {
	using _:     Widget_Info,
	text:        string,
	menu_align:  Alignment,
	text_layout: vgo.Text_Layout,
	container:   Container_Info,
}

Menu_State :: struct {
	size:      [2]f32,
	open_time: f32,
}

init_menu :: proc(using info: ^Menu_Info, loc := #caller_location) -> bool {
	id = hash(loc)
	self = get_widget(id)
	text_layout = vgo.make_text_layout(text, core.style.default_font, core.style.default_text_size)
	// desired_size = {
	// 	text_layout.size.x + 20 + core.style.text_padding.x * 2,
	// 	core.style.visual_size.y,
	// }
	self.desired_size = core.style.visual_size
	return true
}

begin_menu :: proc(info: ^Menu_Info) -> bool {
	begin_widget(info) or_return

	if info.self.visible {
		vgo.fill_box(info.self.box, core.style.rounding, paint = core.style.color.field)
		text_pos := [2]f32 {
			info.self.box.lo.x + core.style.text_padding.x,
			box_center_y(info.self.box),
		}
		vgo.fill_text_layout_aligned(
			info.text_layout,
			text_pos,
			.Left,
			.Center,
			paint = core.style.color.content,
		)

		icon_box := shrink_box(get_box_cut_right(info.self.box, box_height(info.self.box)), 5)
		r := box_height(icon_box) / 10
		vgo.set_paint(vgo.WHITE)
		vgo.fill_circle({box_center_x(icon_box), icon_box.lo.y + r}, r)
		vgo.fill_circle(box_center(icon_box), r)
		vgo.fill_circle({box_center_x(icon_box), icon_box.hi.y - r}, r)
		// s := box_height(icon_box) / 5
		// vgo.fill_box(cut_box_top(&icon_box, s))
		// cut_box_top(&icon_box, s)
		// vgo.fill_box(cut_box_top(&icon_box, s))
		// cut_box_top(&icon_box, s)
		// vgo.fill_box(cut_box_top(&icon_box, s))

		// vgo.stroke_box(info.self.box, 1, core.style.rounding, paint = core.style.color.substance)
	}

	menu_behavior(info.self)

	if .Open in info.self.state {
		menu_layer := get_popup_layer_info(
			info.self,
			linalg.max(info.self.menu.size, info.self.desired_size),
		)
		scale := math.lerp(f32(0.9), f32(1), ease.quadratic_in_out(info.self.open_time))
		if !begin_layer(
			&{
				box = {
					info.self.box.lo,
					linalg.lerp(
						info.self.box.hi,
						// Clamp to view
						linalg.min(linalg.max(info.self.box.hi, info.self.box.lo + info.self.menu.size), core.view),
						[2]f32{1, ease.quadratic_in_out(info.self.open_time)},
					),
				},
			},
		) {
			info.self.state -= {.Open}
		}
	}
	if .Open in info.self.state {
		push_id(info.self.id)
		draw_shadow(layout_box())
		background()
		set_width_fill()
		set_height_fill()
		// Init container
		info.container = Container_Info {
			space = info.self.menu.size,
			hide_scrollbars = info.self.open_time < 1,
		}
		init_container(&info.container) or_return
		begin_container(&info.container) or_return
		// Prepare for content
		set_width_fill()
		set_height_auto()
	}

	return .Open in info.self.state
}

end_menu :: proc(info: ^Menu_Info) -> bool {
	assert(info != nil)
	assert(info.self != nil)
	if .Open in info.self.state {
		pop_id()
		// Save desired menu size
		layout := current_layout().?
		info.self.menu.size = layout.content_size + layout.spacing_size
		layer := current_layer().?
		if (.Hovered not_in layer.state && .Focused not_in info.self.state) ||
		   .Clicked in layer.state {
			info.self.state -= {.Open}
		}
		// End the container
		end_container(&info.container)
		// End the layer
		end_layer()
	}
	end_widget()
	return true
}

@(deferred_in = __menu)
menu :: proc(info: ^Menu_Info, loc := #caller_location) -> bool {
	info := info
	init_menu(info, loc) or_return
	return begin_menu(info)
}

@(private)
__menu :: proc(info: ^Menu_Info, _: runtime.Source_Code_Location) {
	end_menu(info)
}

Menu_Item_Decal :: enum {
	None,
	Check,
	Dot,
}

Menu_Item_Info :: struct {
	using _:     Widget_Info,
	text:        string,
	decal:       Menu_Item_Decal,
	text_layout: vgo.Text_Layout,
	clicked:     bool,
}

init_menu_item :: proc(info: ^Menu_Item_Info) -> bool {
	info.self = get_widget(info.id)
	info.text_layout = vgo.make_text_layout(
		info.text,
		core.style.default_font,
		core.style.default_text_size,
	)
	info.self.desired_size = info.text_layout.size + core.style.text_padding * 2
	info.self.desired_size.x += info.self.desired_size.y
	return true
}

menu_item :: proc(info: Menu_Item_Info, loc := #caller_location) -> Menu_Item_Info {
	info := info
	if info.id == 0 do info.id = hash(loc)

	if init_menu_item(&info) {
		if begin_widget(&info) {
			defer end_widget()

			button_behavior(info.self)

			if info.self.visible {
				if .Hovered in info.self.state {
					vgo.fill_box(
						info.self.box,
						core.style.rounding,
						paint = vgo.fade(core.style.color.substance, 0.1),
					)
				}
				vgo.fill_text_layout_aligned(
					info.text_layout,
					{info.self.box.lo.x + core.style.text_padding.x, box_center_y(info.self.box)},
					.Left,
					.Center,
					core.style.color.content,
				)
				switch info.decal {
				case .None:
				case .Check:
					vgo.check(
						info.self.box.hi - box_height(info.self.box) / 2,
						5,
						core.style.color.content,
					)
				case .Dot:
					vgo.fill_circle(
						info.self.box.hi - box_height(info.self.box) / 2,
						5,
						core.style.color.content,
					)
				}
			}

			info.clicked = .Clicked in info.self.state
		}
	}

	return info
}

enum_selector :: proc(value: ^$T, loc := #caller_location) where intrinsics.type_is_enum(T) {
	if value == nil do return
	if menu(&{text = fmt.tprintf("%v \ue14e", value^)}) {
		set_side(.Top)
		set_width_fill()
		for member, m in T {
			if menu_item({id = hash(m + 1), text = fmt.tprint(member), decal = .Check if value^ == member else .None}).clicked {
				value^ = member
			}
		}
	}
}
