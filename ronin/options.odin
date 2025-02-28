package ronin

Size_Option :: union {
	Exact_Size,
	Exact_Width_Or_Height,
	Size_Method,
	Factor_Of_Predefined_Scale,
	Factor_Of_Remaining_Width,
	Factor_Of_Remaining_Height,
	Factor_Of_Remaining_Space,
	Factor_Of_Remaining_Width_Or_Height,
	Preferred_Size_Of_Object,
	Subtract_From_Size,
}

Size_Method :: enum {
	Max,
	Min,
	Fixed,
	Dont_Care,
}

Exact_Object_Size :: distinct [2]f32
Relative_Object_Size :: distinct [2]f32
Object_Size_Variant :: union {
	Exact_Object_Size,
	Relative_Object_Size,
}

Object_Metrics_Descriptor :: struct($T: typeid) {
	cut_size: T,
	desired_size: T,
	compare_methods: T,
}

Object_Cut_Descriptor :: struct {
	amount: f32,
	method: Size_Method,
}

Options :: struct {
	align:          [2]f32,
	padding:        [4]f32,
	radius:         [4]f32,
	size:           [2]f32,
	methods:        [2]Size_Method,
	unlocked: [2]bool,
	hover_to_focus: bool,
	object_height:  int,
}

exact_size_and_method_from_options :: proc(axis: int, opts: ..Size_Option) -> (value: f32, method: Size_Method) {
	defined_method: Maybe(Size_Method)
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
			method = .Max
		case Factor_Of_Remaining_Height:
			value = remaining_space().y * f32(v)
			method = .Max
		case Factor_Of_Remaining_Space:
			value = remaining_space()[axis] * f32(v[axis])
			method = .Max
		case Factor_Of_Remaining_Width_Or_Height:
			current_axis := get_current_axis()
			value = remaining_space()[current_axis] * f32(v)
			method = .Max
		case Subtract_From_Size:
			value -= f32(v)
		case Size_Method:
			defined_method = v
		case Preferred_Size_Of_Object:
			value = 0
			method = .Max
		}
	}
	if defined_method, ok := defined_method.?; ok {
		method = defined_method
	}
	return
}

set_axis_locks :: proc(x, y: bool) {
	get_current_options().unlocked = {!x, !y}
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
