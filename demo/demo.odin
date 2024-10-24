package demo

import onyx "../onyx"
import "base:runtime"
import "core:fmt"
import img "core:image"
import "core:image/png"
import "core:math"
import "core:math/bits"
import "core:math/linalg"
import "core:math/rand"
import "core:mem"
import "core:os"
import "core:reflect"
import "core:slice"
import "core:strconv"
import "core:strings"
import "core:sys/windows"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"

Option :: enum {
	Process,
	Wave,
	Manifold,
	Function,
}

Section :: enum {
	Primitives,
	Style,
	Tables,
	Button,
	Data_Input,
	Boolean,
	Graph,
	Scroll_Zone,
}

State :: struct {
	component:     Section,
	light_mode:    bool,
	shape_mode:    onyx.Shape_Mode,
	checkboxes:    [Option]bool,
	bio:           string,
	full_name:     string,
	birth_country: string,
	from_angle:    f32,
	to_angle:      f32,
	start_time:    time.Time,
	option:        Option,
	date_range:    [2]Maybe(onyx.Date),
	month_offset:  int,
	entries:       [dynamic]Table_Entry,
	sort_order:    onyx.Sort_Order,
	sorted_column: int,
	hsva:          [4]f32,
	hex:           strings.Builder,
	texture:       wgpu.Texture,
}

state: State

Table_Entry :: struct {
	id:          u64,
	hash:        string,
	public_key:  string,
	private_key: string,
	location:    string,
}

component_showcase :: proc(state: ^State) -> bool {
	using onyx

	layer_info := Layer_Info {
		box  = view_box(),
		kind = .Background,
	}

	begin_layer(&layer_info) or_return
	defer end_layer()

	draw_box_fill(current_layout().?.box, core.style.color.background)
	shrink_layout(100)
	foreground()
	if layout({size = 65, side = .Top}) {
		shrink_layout(15)
		box_tabs(
			{
				index = (^int)(&state.component),
				options = reflect.enum_field_names(Section),
				tab_width = 100,
			},
		)
		set_side(.Right)
		if toggle_switch({state = &state.light_mode, text = "\uf1bc" if state.light_mode else "\uef72", text_side = .Left}).toggled {
			if state.light_mode {
				core.style.color = light_color_scheme()
			} else {
				core.style.color = dark_color_scheme()
			}
		}
	}
	shrink_layout(40)

	#partial switch state.component {
	case .Style:
		set_width_percent(100 / 3)
		set_side(.Left)
		if layout({}) {
			shrink_layout_x(50)
			header({text = "Color"})
			add_space(20)
			si := runtime.type_info_base(type_info_of(Color_Scheme)).variant.(runtime.Type_Info_Struct)
			for i in 0 ..< si.field_count {
				if i > 0 {
					add_space(10)
				}
				push_id(int(i + 1))
				label({text = si.names[i]})
				color_button(
					{
						value = (^Color)(rawptr(uintptr(&core.style.color) + si.offsets[i])),
						show_alpha = true,
						input_formats = {.RGB, .HSL, .HEX},
					},
				)
				pop_id()
			}
		}
		if layout({}) {
			shrink_layout_x(50)
			header({text = "Shape"})
			add_space(20)
			label({text = "rounding"})
			slider(
				Slider_Info(f32){value = &core.style.rounding, lo = 0, hi = 10, format = "%.1f"},
			)
			add_space(10)
			label({text = "size x/y"})
			slider(
				Slider_Info(f32) {
					value = &core.style.visual_size.x,
					lo = 0,
					hi = 200,
					format = "%.1f",
				},
			)
			slider(
				Slider_Info(f32) {
					value = &core.style.visual_size.y,
					lo = 0,
					hi = 50,
					format = "%.1f",
				},
			)
			add_space(10)
			label({text = "label padding x/y"})
			slider(
				Slider_Info(f32) {
					value = &core.style.text_padding.x,
					lo = 0,
					hi = 10,
					format = "%.1f",
				},
			)
			slider(
				Slider_Info(f32) {
					value = &core.style.text_padding.y,
					lo = 0,
					hi = 10,
					format = "%.1f",
				},
			)
			add_space(10)
			label({text = "menu padding"})
			slider(
				Slider_Info(f32) {
					value = &core.style.menu_padding,
					lo = 0,
					hi = 10,
					format = "%.1f",
				},
			)
			add_space(10)
			label({text = "tooltip padding"})
			slider(
				Slider_Info(f32) {
					value = &core.style.tooltip_padding,
					lo = 0,
					hi = 10,
					format = "%.1f",
				},
			)
			add_space(10)
			label({text = "button text size"})
			slider(
				Slider_Info(f32) {
					value = &core.style.button_text_size,
					lo = 14,
					hi = 48,
					format = "%.1f",
				},
			)
		}
		if layout({}) {
			shrink_layout_x(50)
			header({text = "Fonts"})
			add_space(20)
		}
	case .Tables:
		set_side(.Left)
		rows_active: [dynamic]bool
		resize(&rows_active, len(state.entries))

		table := Table_Info {
			sorted_column      = &state.sorted_column,
			sort_order         = &state.sort_order,
			columns            = {
				{name = "Name", width = 120},
				{name = "Hash", width = 200},
				{name = "Public Key", width = 150},
				{name = "Private Key", width = 150},
				{name = "Location", width = 150},
			},
			row_count          = len(state.entries),
			max_displayed_rows = 15,
		}
		if begin_table(&table) {
			defer end_table(&table)
			for index in table.first ..= table.last {
				entry := &state.entries[index]
				begin_table_row(&table, {index = index})
				set_width_auto()
				number_input(Number_Input_Info(u64){value = &entry.id, undecorated = true})
				string_input({value = &entry.hash, undecorated = true})
				string_input({value = &entry.public_key, undecorated = true})
				string_input({value = &entry.private_key, undecorated = true})
				string_input({value = &entry.location, undecorated = true})
				end_table_row()
			}
		}
		if table.sorted {
			sort_proc :: proc(i, j: Table_Entry) -> bool {
				i := i
				j := j
				field := reflect.struct_field_at(Table_Entry, state.sorted_column)
				switch field.type.id {
				case string:
					return(
						(^string)(uintptr(&i) + field.offset)^ <
						(^string)(uintptr(&j) + field.offset)^ \
					)
				case u64, u32:
					return(
						(^u64)(uintptr(&i) + field.offset)^ <
						(^u64)(uintptr(&j) + field.offset)^ \
					)
				case:
					return false
				}
			}
			switch state.sort_order {
			case .Ascending:
				slice.sort_by(state.entries[:], sort_proc)
			case .Descending:
				slice.reverse_sort_by(state.entries[:], sort_proc)
			}
			core.draw_next_frame = true
		}
	case .Scroll_Zone:
		set_side(.Left)
		set_width(300)
		set_height_fill()
		if container(&{space = [2]f32{0, 2000}}) {
			set_width_fill()
			set_height_auto()
			for i in 0 ..< 50 {
				if i > 0 {
					add_space(4)
				}
				push_id(i)
				button({text = fmt.tprintf("Button #%i", i + 1), style = .Ghost})
				pop_id()
			}
		}
		add_space(50)
		set_width(500)
		set_height(300)
		if container(&{space = [2]f32{1000, 0}}) {
			set_side(.Left)
			set_height_fill()
			set_width(200)
			set_padding(10)
			for i in 0 ..< 5 {
				push_id(i)
				button({text = fmt.tprint(i + 1), style = .Outlined})
				pop_id()
			}
		}
	// Small showcase of drawing capabilities
	case .Primitives:
		gradient_colors := [2]Color{{0, 182, 255, 255}, {244, 0, 255, 255}}

		if key_down(.H) {
			draw_box_stroke(layout_box(), 1, {255, 0, 0, 255})
		}

		size := [2]f32{0, 50}

		push_id(hash(#location()))
		defer pop_id()

		new_shape, shape: u32

		enum_selector(&state.shape_mode)

		set_side(.Left)
		for i in 0 ..= 3 {
			if i > 0 do add_space(20)
			info := Widget_Info {
				id           = hash(i + 1),
				desired_size = 80,
				sticky       = true,
			}
			if begin_widget(&info) {
				defer end_widget()

				button_behavior(info.self)

				if .Pressed in info.self.state {
					info.self.offset += core.mouse_pos - core.last_mouse_pos
				}

				if info.self.visible {

					switch i {
					case 0:
						new_shape = add_shape_box(info.self.box, 10)
					case 1:
						new_shape = add_shape_circle(
							box_center(info.self.box),
							box_height(info.self.box) / 2,
						)
					case 2:
						new_shape = add_shape_arc(
							box_center(info.self.box),
							math.TAU * 0.25,
							math.TAU * 0.75,
							box_height(info.self.box) / 2 - 2,
							2,
						)
					case 3:
						new_shape = add_shape_pie(
							box_center(info.self.box),
							math.TAU * 0.1,
							math.TAU * 0.9,
							box_height(info.self.box) / 2,
						)
					case 4:
						path_begin()
						path_move_to(info.self.box.lo)
						path_line_to(info.self.box.hi)
						path_quad_to(
							{info.self.box.lo.x, info.self.box.hi.y},
							box_center(info.self.box),
						)
						path_quad_to({info.self.box.hi.x, info.self.box.lo.y}, info.self.box.lo)
						new_shape = add_shape_path_fill()
					case 5:
						new_shape = add_shape_cubic_bezier(
							info.self.box.lo,
							{info.self.box.hi.x, info.self.box.lo.y},
							{info.self.box.lo.x, info.self.box.hi.y},
							info.self.box.hi,
							2,
						)
					}

					core.gfx.shapes.data[new_shape].mode = state.shape_mode
					// Join shapes
					if shape != 0 && new_shape != shape {
						next_shape := new_shape
						shape_data := &core.gfx.shapes.data[next_shape]
						for shape_data.next != 0 {
							next_shape = shape_data.next
							shape_data = &core.gfx.shapes.data[next_shape]
						}
						shape_data.next = shape
					}
					shape = new_shape
				}
			}
		}
		set_paint(
			add_paint(
				Paint {
					kind = .Skeleton,
					col0 = normalize_color(gradient_colors[0]),
					col1 = normalize_color(gradient_colors[1]),
				},
			),
		)
		render_shape(shape, 255)
		set_paint(0)
		core.draw_this_frame = true
	// Buttons of all shapes and sizes
	case .Button:
		set_side(.Top)
		label({text = "Fit to label"})
		add_space(10)
		if layout({size = 30}) {
			set_width_auto()
			for member, m in Button_Style {
				push_id(m)
				if m > 0 {
					add_space(10)
				}
				button({text = fmt.tprint(member), style = member})
				pop_id()
			}
		}
		add_space(10)
		enum_selector(&state.option)
	// Boolean controls
	case .Boolean:
		set_side(.Top)
		label({text = "Checkboxes"})
		add_space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				add_space(10)
			}
			checkbox({text = fmt.tprint(member), state = &state.checkboxes[member]})
			pop_id()
		}
		add_space(10)
		label({text = "Radio Buttons"})
		add_space(10)
		for member, m in Option {
			push_id(m)
			if m > 0 {
				add_space(10)
			}
			yes := state.option == member
			if radio_button({text = fmt.tprint(member), state = &yes}).toggled {
				state.option = member
			}
			pop_id()
		}
	// Data input (text, numbers, sliders)
	case .Data_Input:
		set_side(.Top)
		set_width(250)
		add_space(10)
		set_height_auto()
		string_input({value = &state.full_name, placeholder = "Full Name", decal = .Check})
		add_space(10)
		string_input({value = &state.birth_country, placeholder = "Country of birth"})
		add_space(10)
		set_height_auto()
		date_picker({first = &state.date_range[0]})
		add_space(10)
		date_picker({first = &state.date_range[0], second = &state.date_range[1]})
		add_space(10)
		set_height(120)
		string_input({value = &state.bio, placeholder = "Bio", multiline = true})
	// Graph and chart showcase
	case .Graph:
		set_side(.Left)
		set_width_percent(50)
		if layout({}) {
			shrink_layout(30)
			set_width_fill()
			set_height_fill()
			graph(
				{
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					kind = Bar_Graph{value_labels = true, show_tooltip = true},
					label_tooltip = true,
					fields = {{"Field 1", {255, 25, 96, 255}}, {"Field 2", {0, 58, 255, 255}}},
					entries = {
						{"Feb 2nd", {1, 5}},
						{"Feb 3rd", {4, 2}},
						{"Feb 4th", {6, 5}},
						{"Feb 5th", {2, 8}},
						{"Feb 6th", {3, 12}},
						{"Feb 7th", {4, 13}},
						{"Feb 8th", {4, 10}},
						{"Feb 9th", {5, 10}},
						{"Feb 10th", {7, 7}},
						{"Feb 11th", {8, 6}},
						{"Feb 12th", {11, 6}},
						{"Feb 13th", {12, 7}},
						{"Feb 14th", {9, 4}},
					},
				},
			)
		}
		if layout({}) {
			shrink_layout(30)
			set_width_fill()
			set_height_fill()
			graph(
				{
					lo = 0,
					hi = 30,
					increment = 5,
					spacing = 10,
					kind = Line_Graph{show_dots = false},
					label_tooltip = true,
					fields = {{"Minecraft", {255, 25, 96, 255}}, {"Terraria", {0, 58, 255, 255}}},
					entries = {
						{label = "Jan 5th", values = {1, 5}},
						{label = "Jan 6th", values = {4, 2}},
						{label = "Jan 7th", values = {6, 5}},
						{label = "Jan 8th", values = {2, 6}},
						{label = "Jan 9th", values = {4, 7}},
						{label = "Jan 10th", values = {2, 4}},
						{label = "Jan 11th", values = {8, 5}},
						{label = "Jan 12th", values = {18, 6}},
						{label = "Jan 13th", values = {15, 7}},
						{label = "Jan 14th", values = {14, 8}},
						{label = "Jan 15th", values = {11, 6}},
					},
				},
			)
		}
	}
	return true
}

allocator: runtime.Allocator

main :: proc() {
	when ODIN_DEBUG {
		track: mem.Tracking_Allocator
		mem.tracking_allocator_init(&track, context.allocator)
		allocator = mem.tracking_allocator(&track)

		defer {
			if len(track.allocation_map) > 0 {
				fmt.eprintf("=== %v allocations not freed: ===\n", len(track.allocation_map))
				for _, entry in track.allocation_map {
					fmt.eprintf("- %v bytes @ %v\n", entry.size, entry.location)
				}
			}
			if len(track.bad_free_array) > 0 {
				fmt.eprintf("=== %v incorrect frees: ===\n", len(track.bad_free_array))
				for entry in track.bad_free_array {
					fmt.eprintf("- %p @ %v\n", entry.memory, entry.location)
				}
			}
			mem.tracking_allocator_destroy(&track)
		}
	} else {
		allocator = runtime.default_allocator()
	}

	state.date_range = {onyx.Date{2024, 2, 17}, onyx.Date{2024, 3, 2}}

	for i in 0 ..< 100 {
		append(
			&state.entries,
			Table_Entry {
				hash = fmt.aprintf("%x", rand.int31()),
				id = u64(rand.int_max(999)),
				public_key = fmt.aprintf("%x", rand.int31()),
				private_key = fmt.aprintf("%x", rand.int31()),
				location = fmt.aprintf("%x", rand.int31()),
			},
		)
	}

	glfw.Init()
	window := glfw.CreateWindow(1600, 900, "demo", nil, nil)

	onyx.init(window)

	for !glfw.WindowShouldClose(onyx.core.window) {
		using onyx
		new_frame()
		component_showcase(&state)
		render()
	}

	onyx.destroy()
}
