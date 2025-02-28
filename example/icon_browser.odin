package demo

import "local:ronin"
import kn "local:katana"
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
	display_size: f32,
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
	using ronin

	style := get_current_style()

	first_icon :: rune(0xE000)

	if !state.loaded_icon_names {
		if data, ok := os.read_entire_file("../ronin/fonts/icon_names.json"); ok {
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
	state.display_size = max(state.display_size, 20)

	set_size(to_layout_size)
	if do_layout(top_to_bottom) {
		set_height(to_scale(4))
		if do_layout(on_top, left_to_right) {
			set_size(that_of_object)
			shrink(style.scale * 1)
			set_padding(0)
			set_width(to_scale(10))
			if input(&state.query, placeholder = "Search for icons").changed || len(state.shown_icons) == 0 {
				lowercase_query := strings.to_lower(state.query, allocator = context.temp_allocator)
				clear(&state.shown_icons)
				for name, i in state.icon_names {
					if strings.contains(name, lowercase_query) {
						append(&state.shown_icons, first_icon + rune(i))
					}
				}
			}
			space()
			set_align(0.5)
			if len(state.query) > 0 {
				label(fmt.tprintf("Showing %i/%i icons", len(state.shown_icons), int(last_icon - first_icon) + 1))
			}
		}
		divider()
		set_size(to_layout_size)
		set_padding(0)
		if do_layout(right_to_left) {
			set_width(to_scale(10))
			if do_layout(on_right, top_to_bottom) {
				shrink(style.scale)
				set_width(to_layout_width)
				if state.selected_icon > 0 {
					set_height(to_layout_width)
					if do_layout(as_column) {
						background()
						set_size(to_layout_size)
						icon(state.selected_icon, size = state.display_size)
					}
					set_height(whatever)
					space()
					slider(&state.display_size, 20, 80)
					space()
					text(fmt.tprintf("%s\n\\u%x", state.icon_names[int(state.selected_icon - first_icon)], state.selected_icon))
				}
			}
			divider()
			icon_size := f32(40)
			icon_cell_size := f32(80)
			how_many_icons := len(state.shown_icons)
			how_many_columns := int(math.floor((remaining_space().x - 12) / icon_cell_size))
			how_many_rows := int(math.ceil(f32(how_many_icons) / f32(how_many_columns)))
			shrink(style.scale)
			set_size(to_layout_size)
			if do_container() {
				if container_object, ok := get_current_object(); ok {
					kn.add_box(container_object.box, style.rounding, paint = style.color.background)
					defer kn.add_box_lines(
						container_object.box,
						style.line_width,
						style.rounding,
						paint = style.color.lines,
					)

					shrink(6)

					set_height(exactly(icon_cell_size))
					for i in 0..<how_many_rows {
						begin_layout(on_top, as_row) or_continue
						defer end_layout()

						if get_clip(get_current_clip(), get_current_layout().box) == .Full {
							continue
						}

						set_width(exactly(icon_cell_size))
						for j in (i * how_many_columns)..<min((i + 1) * how_many_columns, how_many_icons) {
							icon := state.shown_icons[j]

							object := get_object(hash(int(icon)))
							object.size = icon_cell_size

							begin_object(object) or_continue
							defer end_object()

							if object_is_visible(object) {
								object.animation.hover = animate(
								object.animation.hover,
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
								kn.add_box(
									object.box,
									style.rounding,
									kn.fade(style.color.button, 0.5 * object.animation.hover),
								)
								kn.add_box_lines(
									object.box,
									style.line_width,
									style.rounding,
									kn.fade(style.color.lines, object.animation.hover),
								)
								size := icon_size// * (1.0 + 0.2 * object.hover_time)
								font := style.icon_font
								if glyph, ok := kn.get_font_glyph(font, icon);
								   ok {
									kn.add_glyph(
										glyph,
										size,
										linalg.floor(box_center(object.box)) - size / 2 + {0, -size * (font.line_height - font.ascend)},
										paint = style.color.content,
									)
								}
							}
						}
					}
				}
			}
		}
	}
}
