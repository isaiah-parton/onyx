package onyx

// import "../vgo"
// import "base:intrinsics"
// import "base:runtime"
// import "core:fmt"
// import "core:math"
// import "core:math/ease"
// import "core:math/linalg"

// @(deferred_out = __menu_bar)
// menu_bar :: proc() -> bool {
// 	begin_layout(.Left) or_return
// 	box := current_box()
// 	vgo.fill_box(box, style().rounding, style().color.field)
// 	vgo.stroke_box(box, style().rounding, 1, style().color.substance)
// 	return true
// }
// @(private)
// __menu_bar :: proc(ok: bool) {
// 	if ok {
// 		end_layout()
// 	}
// }

// Menu_State :: struct {
// 	size:      [2]f32,
// 	open_time: f32,
// }

// begin_menu :: proc(text: string, loc := #caller_location) -> bool {
// 	object := persistent_object(hash(loc))
// 	text_layout := vgo.make_text_layout(text, style().default_text_size, style().default_font)
// 	// size = {
// 	// 	text_layout.size.x + 20 + style().text_padding.x * 2,
// 	// 	style().visual_size.y,
// 	// }
// 	object.size = style().visual_size
// 	object.box = next_box(object.size)
// 	begin_object(object) or_return

// 	if object_is_visible(object) {
// 		vgo.fill_box(object.box, style().rounding, paint = style().color.field)
// 		text_pos := [2]f32 {
// 			object.box.lo.x + style().text_padding.x,
// 			box_center_y(object.box),
// 		}
// 		vgo.fill_text_layout(
// 			text_layout,
// 			text_pos,
// 			{0, 0.5},
// 			paint = style().color.content,
// 		)

// 		icon_box := shrink_box(get_box_cut_right(object.box, box_height(object.box)), 5)
// 		r := box_height(icon_box) / 10
// 		vgo.set_paint(vgo.WHITE)
// 		vgo.fill_circle({box_center_x(icon_box), icon_box.lo.y + r}, r)
// 		vgo.fill_circle(box_center(icon_box), r)
// 		vgo.fill_circle({box_center_x(icon_box), icon_box.hi.y - r}, r)
// 		// s := box_height(icon_box) / 5
// 		// vgo.fill_box(cut_box_top(&icon_box, s))
// 		// cut_box_top(&icon_box, s)
// 		// vgo.fill_box(cut_box_top(&icon_box, s))
// 		// cut_box_top(&icon_box, s)
// 		// vgo.fill_box(cut_box_top(&icon_box, s))

// 		// vgo.stroke_box(object.box, 1, style().rounding, paint = style().color.substance)
// 	}


// 	if .Open in object.state.current {
// 		menu_layer := get_popup_layer_info(
// 			object,
// 			linalg.max(object.menu.size, object.size),
// 		)
// 		scale := math.lerp(f32(0.9), f32(1), ease.quadratic_in_out(object.open_time))
// 		if !begin_layer(
// 			&{
// 				box = {
// 					object.box.lo,
// 					linalg.lerp(
// 						object.box.hi,
// 						// Clamp to view
// 						linalg.min(linalg.max(object.box.hi, object.box.lo + object.menu.size), core.view),
// 						[2]f32{1, ease.quadratic_in_out(object.open_time)},
// 					),
// 				},
// 			},
// 		) {
// 			object.state.current -= {.Open}
// 		}
// 	}
// 	if .Open in object.state.current {
// 		push_id(object.id)
// 		draw_shadow(current_box())
// 		background()
// 		set_size(remaining_space())
// 		begin_container() or_return
// 		set_height(0)
// 	}

// 	return .Open in object.state.current
// }

// end_menu :: proc() {
// 	object := current_object().?
// 	if .Open in object.state.current.current {
// 		pop_id()
// 		layout := current_layout().?
// 		layer := current_layer().?
// 		if (.Hovered not_in layer.state && .Focused not_in object.state.current.current) ||
// 		   .Clicked in layer.state {
// 			object.state.current.current -= {.Open}
// 		}
// 		// End the container
// 		end_container()
// 		// End the layer
// 		end_layer()
// 	}
// 	end_object()
// }

// Menu_Item_Decal :: enum {
// 	None,
// 	Check,
// 	Dot,
// }

// Menu_Item_Info :: struct {
// 	text:        string,
// 	decal:       Menu_Item_Decal,
// 	text_layout: vgo.Text_Layout,
// 	clicked:     bool,
// }

// menu_item :: proc(text: string, decal: Menu_Item_Decal = .None, loc := #caller_location) -> bool {
// 	object := persistent_object(hash(loc))
// 	text_layout := vgo.make_text_layout(
// 		text,
// 		style().default_text_size,
// 		style().default_font,
// 	)
// 	object.size = text_layout.size + style().text_padding * 2
// 	object.size.x += object.size.y

// 	if init_menu_item(&info) {
// 		if begin_object(&info) {
// 			defer end_object()

// 			button_behavior(object)

// 			if object.visible {
// 				if .Hovered in object.state.current {
// 					vgo.fill_box(
// 						object.box,
// 						style().rounding,
// 						paint = vgo.fade(style().color.substance, 0.1),
// 					)
// 				}
// 				vgo.fill_text_layout(
// 					text_layout,
// 					{object.box.lo.x + style().text_padding.x, box_center_y(object.box)},
// 					{0, 0.5},
// 					style().color.content,
// 				)
// 				switch decal {
// 				case .None:
// 				case .Check:
// 					vgo.check(
// 						object.box.hi - box_height(object.box) / 2,
// 						5,
// 						style().color.content,
// 					)
// 				case .Dot:
// 					vgo.fill_circle(
// 						object.box.hi - box_height(object.box) / 2,
// 						5,
// 						style().color.content,
// 					)
// 				}
// 			}

// 			clicked = .Clicked in object.state.current
// 		}
// 	}

// 	return info
// }

// enum_selector :: proc(value: ^$T, loc := #caller_location) where intrinsics.type_is_enum(T) {
// 	if value == nil do return
// 	if menu(&{text = fmt.tprintf("%v \ue14e", value^)}) {
// 		set_side(.Top)
// 		set_width_fill()
// 		for member, m in T {
// 			if menu_item({id = hash(m + 1), text = fmt.tprint(member), decal = .Check if value^ == member else .None}).clicked {
// 				value^ = member
// 			}
// 		}
// 	}
// }
