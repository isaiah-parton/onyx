package onyx
// Layers exist only for widget drawing and interaction to be arbitrarily ordered
// Layers have no interaction of their own, but clicking or hovering a widget in a given layer, will update its
// state.
//
// Layer ordering is somewhat complex
// some layers are attached to their parent and are therefore always one index above it
//
// All layers are stored contiguously in the order they are to be rendered
// a layer's index is an important value and must always be valid
import "../../vgo"
import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
import "core:slice"

Layer_Kind :: enum int {
	// Stuff in the background
	Background,
	// Panels and things that are reordered by clicking on them
	Floating,
	// Tooltips and such
	Topmost,
	// Debug layer, allways on top
	Debug,
}


Layer_Option :: enum {
	// State isolated
	Isolated,
	// Locked in front of parent
	Attached,
	// Can't be brought to front by clicking
	No_Sorting,
	// Contents will not be rendered
	Invisible,
}

Layer_Options :: bit_set[Layer_Option]

Layer :: struct {
	id:              Id,
	parent:          ^Layer,
	children:        [dynamic]^Layer,
	state:           Widget_State,
	last_state:      Widget_State,
	options:         Layer_Options,
	box:             Box,
	// Will be deleted at the end of this frame
	dead:            bool,
	// Render order
	kind:            Layer_Kind,
	index:           int,
	// Frame
	frames:          int,
}

Layer_Info :: struct {
	id:       Id,
	self:     ^Layer,
	options:  Layer_Options,
	box:      Box,
	kind:     Maybe(Layer_Kind),
	origin:   [2]f32,
	scale:    Maybe([2]f32),
	rotation: f32,
	opacity:  Maybe(f32),
}

current_layer :: proc(loc := #caller_location) -> Maybe(^Layer) {
	if core.layer_stack.height > 0 {
		return core.layer_stack.items[core.layer_stack.height - 1]
	}
	return nil
}

create_layer :: proc(id: Id) -> (layer: ^Layer, ok: bool) {
	layer = new(Layer)
	layer.id = id
	if id in core.layer_map do return
	core.layer_map[id] = layer
	ok = true
	return
}

destroy_layer :: proc(layer: ^Layer) {
	for child in layer.children {
		destroy_layer(child)
		free(child)
	}
	delete(layer.children)
}

get_layer :: proc(info: ^Layer_Info) -> (layer: ^Layer, ok: bool) {
	assert(info != nil)
	layer, ok = get_layer_by_id(info.id)
	if !ok {
		layer = create_layer(info.id) or_return
		if parent, ok := current_layer().?; ok {
			layer.parent = parent
			append(&parent.children, layer)
			layer.index = layer.parent.index + 1
			// set_layer_index(layer, parent.index + len(parent.children) + 1)
		} else {
			layer.index = len(core.layers)
			append(&core.layers, layer)
		}
		ok = true
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
	info.self.dead = false
	info.self.id = info.id
	info.self.box = info.box
	info.self.options = info.options
	info.self.kind = info.kind.? or_else .Floating
	info.self.last_state = info.self.state
	info.self.state = {}

	// Set input state
	if core.hovered_layer == info.self.id {
		info.self.state += {.Hovered}
		// Re-order layers if clicked
		if mouse_pressed(.Left) && info.self.kind == .Floating {
			bring_layer_to_front(info.self)
		}
	}

	if core.focused_layer == info.self.id {
		info.self.state += {.Focused}
	}

	core.highest_layer_index = max(core.highest_layer_index, info.self.index)

	// Push layer
	push_stack(&core.layer_stack, info.self)

	// Set draw order
	vgo.set_draw_order(info.self.index)
	vgo.save_scissor()
	scale: [2]f32 = info.scale.? or_else 1
	vgo.push_matrix()
	vgo.translate(info.origin)
	vgo.scale(scale)
	vgo.rotate(info.rotation)
	vgo.translate(-info.origin)

	// Push layout
	push_layout(
		Layout{box = info.self.box, bounds = info.self.box, next_cut_side = .Top},
	) or_return

	return true
}

end_layer :: proc() {
	vgo.pop_matrix()
	vgo.restore_scissor()
	pop_layout()
	if layer, ok := current_layer().?; ok {
		// Remove draw calls if invisible
		if .Invisible in layer.options {
			// remove_range(&core.draw_calls, layer.draw_call_index, len(core.draw_calls))
		}
	}
	pop_stack(&core.layer_stack)
	if layer, ok := current_layer().?; ok {
		vgo.set_draw_order(layer.index)
	}
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

get_highest_layer_child :: proc(layer: ^Layer, kind: Layer_Kind) -> int {
	if layer == nil do return 0
	highest := int(0)
	for child in layer.children {
		if int(child.kind) <= int(kind) {
			highest = max(highest, child.index)
		}
	}
	return highest
}

bring_layer_to_front :: proc(layer: ^Layer) {
	assert(layer != nil)
	list: []^Layer = core.layers[:] if layer.parent == nil else layer.parent.children[:]
	new_index := len(list)
	if layer.index >= new_index do return
	// Second pass lowers other layers
	for child in list {
		if child.index > layer.index && child.index <= new_index {
			child.index -= 1
		}
	}
	layer.index = new_index
}

get_layer_by_id :: proc(id: Id) -> (result: ^Layer, ok: bool) {
	return core.layer_map[id]
}
