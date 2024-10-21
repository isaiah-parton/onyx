package onyx
// Layers exist only to allow ordered rendering
// Layers have no interaction of their own, but clicking or hovering a widget in a given layer, will update its
// state.
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:slice"

Layer_Order :: enum int {
	Background,
	Floating,
	Topmost,
	Debug,
}

Layer_Sorting :: enum {
	Above,
	Below,
}

Layer_Option :: enum {
	Isolated,
	Attached,
	No_Sorting,
	No_Scissor,
}

Layer_Options :: bit_set[Layer_Option]

Layer :: struct {
	id:                Id,
	parent:            ^Layer,
	children:          [dynamic]^Layer,
	last_state, state: Widget_State,
	options:           Layer_Options,
	kind:              Layer_Order,
	// Contents are clipped to this box
	box:               Box,
	// Will be deleted at the end of this frame
	dead:              bool,
	// Global draw opacity
	opacity:           f32,
	// Render order
	index:             int,
	frames:            int,
}

Layer_Info :: struct {
	id:       Id,
	self:     ^Layer,
	parent:   ^Layer,
	options:  Layer_Options,
	box:      Box,
	kind:     Maybe(Layer_Order),
	origin:   [2]f32,
	scale:    Maybe([2]f32),
	rotation: f32,
	opacity:  Maybe(f32),
	sorting:  Layer_Sorting,
	index:    Maybe(int),
}

destroy_layer :: proc(layer: ^Layer) {
	delete(layer.children)
}

current_layer :: proc(loc := #caller_location) -> Maybe(^Layer) {
	if core.layer_stack.height > 0 {
		return core.layer_stack.items[core.layer_stack.height - 1]
	}
	return nil
}

set_layer_index :: proc(layer: ^Layer, index: int) {
	assert(layer != nil)

	if layer.index == index do return

	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 || other_layer.id == layer.id do continue

		assert(other_layer.index != layer.index)
		if index > layer.index {
			if layer.index > 0 {
				if other_layer.index <= index {
					other_layer.index -= 1
				} else if other_layer.index > index {
					other_layer.index += 1
				}
			} else {
				if other_layer.index >= index {
					other_layer.index += 1
				}
			}
		} else {
			if other_layer.index >= index && other_layer.index < layer.index {
				other_layer.index += 1
			}
		}
	}
	layer.index = index
}

get_lowest_layer_of_kind :: proc(kind: Layer_Order) -> int {
	return get_highest_layer_of_kind(Layer_Order(int(kind) - 1)) + 1
}

get_highest_layer_of_kind :: proc(kind: Layer_Order) -> int {
	index: int
	for i in 0 ..< len(core.layers) {
		layer := &core.layers[i]
		if layer.id == 0 do continue

		if int(layer.kind) <= int(kind) {
			index = max(index, layer.index)
		}
	}
	return index
}

create_layer :: proc(id: Id) -> (result: ^Layer, ok: bool) {
	for i in 0 ..< MAX_LAYERS {
		if core.layers[i].id == 0 {
			core.layers[i] = Layer {
				id = id,
			}
			result = &core.layers[i]
			core.layer_map[id] = result
			ok = true
			return
		}
	}
	return
}

get_layer :: proc(info: ^Layer_Info) -> (layer: ^Layer, ok: bool) {
	assert(info != nil)
	layer, ok = get_layer_by_id(info.id)
	if !ok {
		layer, ok = create_layer(info.id)

		if !ok {
			return
		}
		if info.parent != nil {
			set_layer_parent(layer, info.parent)
		}

		if index, ok := info.index.?; ok {
			set_layer_index(layer, index)
		} else {
			if layer.parent != nil {
				set_layer_index(layer, layer.parent.index + 1)
			} else {
				if info.sorting == .Above {
					set_layer_index(layer, get_highest_layer_of_kind(info.kind.? or_return) + 1)
				} else {
					set_layer_index(layer, get_lowest_layer_of_kind(info.kind.? or_return))
				}
			}
		}
	}
	return
}

begin_layer :: proc(info: ^Layer_Info, loc := #caller_location) -> bool {
	assert(info != nil)
	if info.id == 0 do info.id = hash(loc)

	info.self = get_layer(info) or_return

	if info.self.frames == core.frames {
		when ODIN_DEBUG {
			fmt.println("Layer ID collision: %i", info.id)
		}
		return false
	}
	info.self.frames = core.frames

	// Push info.self
	push_stack(&core.layer_stack, info.self)

	// Set parameters
	info.self.dead = false
	info.self.id = info.id
	info.self.box = info.box
	info.self.options = info.options
	info.self.kind = info.kind.? or_else .Floating
	info.self.opacity = info.opacity.? or_else 1

	info.self.last_state = info.self.state
	info.self.state = {}

	// Set input state
	if core.hovered_layer == info.self.id {
		info.self.state += {.Hovered}
		// Re-order layers if clicked
		if mouse_pressed(.Left) &&
		   info.self.kind == .Floating &&
		   .No_Sorting not_in info.self.options {
			bring_layer_to_front(info.self)
		}
	}

	if core.focused_layer == info.self.id {
		info.self.state += {.Focused}
	}

	// Set vertex z position
	if .No_Scissor not_in info.self.options {
		push_scissor(info.self.box)
	}
	append_draw_call(current_layer().?.index)

	// Transform matrix
	scale: [2]f32 = info.scale.? or_else 1
	push_matrix()
	translate_matrix(info.origin.x, info.origin.y, 0)
	scale_matrix(scale.x, scale.y, 1)
	rotate_matrix(info.rotation, 0, 0, 1)
	translate_matrix(-info.origin.x, -info.origin.y, 0)

	// Push layout
	push_layout(
		Layout {
			box = {linalg.floor(info.self.box.lo), linalg.floor(info.self.box.hi)},
			bounds = info.self.box,
			next_cut_side = .Top,
		},
	) or_return

	return true
}

end_layer :: proc() {
	pop_matrix()
	pop_layout()
	if layer, ok := current_layer().?; ok {
		if .No_Scissor not_in layer.options {
			pop_scissor()
		}
		append_draw_call(layer.index)
	}
	pop_stack(&core.layer_stack)
}

@(deferred_out = __layer)
layer :: proc(info: ^Layer_Info, loc := #caller_location) -> bool {
	info := info
	return begin_layer(info, loc)
}

@(private)
__layer :: proc(ok: bool) {
	if ok {
		end_layer()
	}
}

bring_layer_to_front :: proc(layer: ^Layer) {
	assert(layer != nil)
	// First pass determines the new z-index
	highest_of_kind := get_highest_layer_of_kind(layer.kind)
	if layer.index >= highest_of_kind {
		return
	}
	// Second pass lowers other layers
	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if other_layer.index > layer.index && other_layer.index <= highest_of_kind {
			other_layer.index -= 1
		}
	}
	layer.index = highest_of_kind
}

bring_layer_to_front_of_children :: proc(layer: ^Layer) {
	assert(layer != nil)

	if layer.parent == nil do return

	// First pass determines the new z-index
	highest_of_kind: int
	for &child in layer.parent.children {
		if int(child.kind) <= int(layer.kind) {
			highest_of_kind = max(highest_of_kind, child.index)
		}
	}

	if layer.index >= highest_of_kind {
		return
	}

	// Second pass lowers other layers
	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if other_layer.index > layer.index && other_layer.index <= highest_of_kind {
			other_layer.index -= 1
		}
	}

	layer.index = highest_of_kind
}

set_layer_parent :: proc(layer, parent: ^Layer) {
	assert(layer != nil)
	assert(parent != nil)

	if layer.parent == parent {
		return
	}

	append(&parent.children, layer)
	layer.parent = parent
}

remove_layer_parent :: proc(layer: ^Layer) {
	assert(layer != nil)

	if layer.parent == nil {
		return
	}

	for &child, c in layer.parent.children {
		if child.id == layer.id {
			ordered_remove(&layer.parent.children, c)
		}
	}
	layer.parent = nil
}

get_layer_by_id :: proc(id: Id) -> (result: ^Layer, ok: bool) {
	return core.layer_map[id]
}
