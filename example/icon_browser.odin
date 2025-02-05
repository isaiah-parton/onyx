package demo

import "../"
import "../../vgo"
import "core:encoding/json"
import "core:os"
import "core:fmt"
import "core:strings"
import "core:math"
import "core:math/linalg"

Icon_Section_State :: struct {
	query: string,
	shown_icons: [dynamic]rune,
	selected_icon: rune,
	loaded_icon_names: bool,
	icon_names: []string,
}

destroy_icon_section_state :: proc(state: ^Icon_Section_State) {
	for s in state.icon_names {
		delete(s)
	}
	delete(state.icon_names)
	delete(state.shown_icons)
	delete(state.query)
	state^ = {}
}

icon_section :: proc(state: ^Icon_Section_State) {
	using onyx

	first_icon :: rune(0xE000)

	if !state.loaded_icon_names {
		if data, ok := os.read_entire_file("../fonts/icon_names.json"); ok {
			if object, err := json.parse(data[:], parse_integers = true); err == nil {
				state.icon_names = make([]string, len(object.(json.Object)))
				for key, value in object.(json.Object) {
					state.icon_names[value.(json.Integer) - i64(first_icon)] = strings.clone(key)
				}
				json.destroy_value(object)
			} else {
				fmt.eprintfln("Failed to parse the json file of icon names: %v", err)
			}
			delete(data)
		} else {
			fmt.eprintln("Failed to load the json file of icon names")
		}
		state.loaded_icon_names = true
	}

	last_icon := rune(0xF429)

	shrink(10)
	set_width(remaining_space().x)
	set_height(style().visual_size.y)
	if begin_layout(.Left) {
		set_size(0)
		if input(&state.query, placeholder = "Search for icons").changed || len(state.shown_icons) == 0 {
			lowercase_query := strings.to_lower(state.query, allocator = context.temp_allocator)
			clear(&state.shown_icons)
			for name, i in state.icon_names {
				if strings.contains(name, lowercase_query) {
					append(&state.shown_icons, first_icon + rune(i))
				}
			}
		}
		space(10)
		set_align(.Center)
		if len(state.query) > 0 {
			label(fmt.tprintf("Showing %i/%i icons", len(state.shown_icons), int(last_icon - first_icon) + 1))
		}
		end_layout()
	}
	space(10)
	divider()
	space(10)

	set_side(.Right)
	set_width(240)
	set_height(remaining_space().y)
	if begin_layout(.Top) {
		set_width(remaining_space().x)
		if state.selected_icon > 0 {
			set_height(remaining_space().x)
			if begin_layout(.Top) {
				background()
				set_size(remaining_space())
				icon(state.selected_icon, size = 40)
				end_layout()
			}
			set_height(0)
			space(10)
			label(state.icon_names[int(state.selected_icon - first_icon)])
			space(10)
			label(fmt.tprintf("\\u%x", state.selected_icon))
		}
		end_layout()
	}
	space(20)

	icon_size := f32(40)
	icon_cell_size := f32(80)
	how_many_icons := len(state.shown_icons)
	how_many_columns := int(math.floor((remaining_space().x - 12) / icon_cell_size))
	how_many_rows := int(math.ceil(f32(how_many_icons) / f32(how_many_columns)))
	set_size(remaining_space())
	if begin_container(
		space = [2]f32{f32(how_many_columns), f32(how_many_rows)} * icon_cell_size,
	) {
		shrink(6)

		container_object := current_object().?
		vgo.fill_box(container_object.box, style().rounding, paint = style().color.background)
		vgo.stroke_box(
			container_object.box,
			1,
			style().rounding,
			paint = style().color.foreground_stroke,
		)

		set_width(remaining_space().x)
		set_height(icon_cell_size)
		for i in 0..<how_many_rows {
			begin_layout(.Left) or_continue
			defer end_layout()

			set_width(icon_cell_size)
			if get_clip(view_box(), current_layout().?.box) == .Full {
				continue
			}

			for j in (i * how_many_columns)..<min((i + 1) * how_many_columns, how_many_icons) {
				icon := state.shown_icons[j]

				object := get_object(hash(int(icon)))
				object.box = next_box({})

				begin_object(object) or_continue
				defer end_object()

				if object_is_visible(object) {
					object.hover_time = animate(
						object.hover_time,
						0.1,
						.Hovered in object.state.current,
					)
					if point_in_box(mouse_point(), object.box) {
						hover_object(object)
					}
					if .Clicked in object.state.current {
						set_clipboard_string(fmt.tprintf("\\u%x", icon))
						state.selected_icon = icon
					}
					vgo.fill_box(
						object.box,
						style().rounding,
						vgo.fade(style().color.button, 0.5 * object.hover_time),
					)
					vgo.stroke_box(
						object.box,
						1,
						style().rounding,
						vgo.fade(style().color.foreground_stroke, object.hover_time),
					)
					size := icon_size * (1.0 + 0.2 * object.hover_time)
					font := style().icon_font
					if glyph, ok := vgo.get_font_glyph(font, icon);
					   ok {
						vgo.fill_glyph(
							glyph,
							size,
							linalg.floor(box_center(object.box)) - size / 2 + {0, -size * (font.line_height - font.ascend)},
							paint = style().color.content,
						)
					}
				}
			}
		}
		pop_id()

		end_container()
	}
}
