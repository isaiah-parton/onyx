package ronin

Exact_Width_Or_Height :: f32
Exact_Size :: [2]f32
Preferred_Size_Of_Object :: struct {}
Factor_Of_Remaining_Width :: distinct f32
Factor_Of_Remaining_Height :: distinct f32
Factor_Of_Remaining_Space :: distinct [2]f32
Factor_Of_Remaining_Cut_Space :: distinct f32
Subtract_From_Size :: distinct f32
Account_For_Spacing :: Subtract_From_Size
Factor_Of_Predefined_Scale :: distinct f32

exactly :: Exact_Size
whatever :: Preferred_Size_Of_Object{}
that_of_object :: Preferred_Size_Of_Object{}
at_most :: Size_Method.Min
at_least :: Size_Method.Max
with_spacing :: Account_For_Spacing
to_scale :: Factor_Of_Predefined_Scale
to_layout_width :: Factor_Of_Remaining_Width(1)
to_layout_height :: Factor_Of_Remaining_Height(1)
to_layout_size :: Factor_Of_Remaining_Space(1)
of_layout_width :: proc(fraction: f32) -> f32 {return remaining_space().x * fraction}
of_layout_height :: proc(fraction: f32) -> f32 {return remaining_space().y * fraction}
of_layout_size :: proc(fraction: [2]f32) -> [2]f32 {return remaining_space() * fraction}

Size_Option :: union {
	Exact_Size,
	Exact_Width_Or_Height,
	Size_Method,
	Factor_Of_Predefined_Scale,
	Factor_Of_Remaining_Width,
	Factor_Of_Remaining_Height,
	Factor_Of_Remaining_Space,
	Factor_Of_Remaining_Cut_Space,
	Preferred_Size_Of_Object,
	Subtract_From_Size,
}

Size_Method :: enum {
	Max,
	Min,
	Fixed,
	Dont_Care,
}

Options :: struct {
	align:          [2]f32,
	padding:        [4]f32,
	radius:         [4]f32,
	size:           [2]f32,
	methods:        [2]Size_Method,
	hover_to_focus: bool,
	object_height:  int,
}

exact_size_and_method_from_options :: proc(axis: int, opts: ..Size_Option) -> (value: f32, method: Size_Method) {
	for opt in opts {
		switch v in opt {
		case Exact_Width_Or_Height:
			value = f32(v)
			method = .Fixed
		case Exact_Size:
			value = v[axis]
			method = .Fixed
		case Factor_Of_Predefined_Scale:
			value = get_current_style().scale * f32(v)
			method = .Fixed
		case Factor_Of_Remaining_Width:
			value = remaining_space().x * f32(v)
			method = .Fixed
		case Factor_Of_Remaining_Height:
			value = remaining_space().y * f32(v)
			method = .Fixed
		case Factor_Of_Remaining_Space:
			value = remaining_space()[axis] * f32(v[axis])
			method = .Fixed
		case Factor_Of_Remaining_Cut_Space:
			current_axis := get_current_axis()
			value = remaining_space()[current_axis] * f32(v)
			method = .Fixed
		case Subtract_From_Size:
			value -= f32(v)
		case Size_Method:
			method = v
		case Preferred_Size_Of_Object:
			value = 0
			method = .Max
		}
	}
	return
}

set_width :: proc(opts: ..Size_Option) {
	options := get_current_options()
	options.size.x, options.methods.x = exact_size_and_method_from_options(0, ..opts)
}

set_height :: proc(opts: ..Size_Option) {
	options := get_current_options()
	options.size.y, options.methods.y = exact_size_and_method_from_options(1, ..opts)
}

set_size :: proc(opts: ..Size_Option) {
	options := get_current_options()
	options.size.x, options.methods.x = exact_size_and_method_from_options(0, ..opts)
	options.size.y, options.methods.y = exact_size_and_method_from_options(1, ..opts)
}

set_cut_size :: proc(opts: ..Size_Option) {
	options := get_current_options()
	axis := get_current_axis()
	options.size[axis], options.methods[axis] = exact_size_and_method_from_options(axis, ..opts)
}

default_options :: proc() -> Options {
	return Options {
		radius = get_current_style().rounding,
		size = {},
		methods = {},
	}
}

get_current_options :: proc() -> ^Options {
	return &global_state.options_stack.items[max(global_state.options_stack.height - 1, 0)]
}

push_get_current_options :: proc() {
	push_stack(&global_state.options_stack, get_current_options()^)
}

push_options :: proc(options: Options = {}) {
	push_stack(&global_state.options_stack, options)
}

pop_options :: proc() {
	pop_stack(&global_state.options_stack)
}
