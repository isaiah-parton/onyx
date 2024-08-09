package onyx

/*
	Layers are surfaces with a unique z-index on which widgets are drawn. 
	They can be reordered by the mouse
*/

import "core:fmt"
import "core:slice"

Layer_Kind :: enum int {
	Background,
	Floating,
	Topmost,
	__Debug,
}

Layer_Status :: enum {
	Hovered,
	Focused,
	Pressed,
}

Layer_State :: bit_set[Layer_Status]

Layer_Option :: enum {
	Scroll_X,
	Scroll_Y,
	Isolated,
	No_Sort,
	Attached,
}

Layer_Options :: bit_set[Layer_Option]

Layer :: struct {
	id: Id,

	last_state,
	state: Layer_State,
	options: Layer_Options,			// Option bit flags
	kind: Layer_Kind,

	box: Box,		

	parent: ^Layer,							// The layer's parent
	children: [dynamic]^Layer,	// The layer's children

	dead: bool,									// Should be deleted?

	z_index: int,
}

Layer_Info :: struct {
	id: Id,
	parent: Id,
	options: Layer_Options,
	box: Box,
	kind: Maybe(Layer_Kind),

	origin: [2]f32,
	scale: Maybe([2]f32),
	rotation: f32,
}

current_layer :: proc(loc := #caller_location) -> ^Layer {
	assert(core.layer_stack.height > 0, "No current layer", loc)
	return core.layer_stack.items[core.layer_stack.height - 1]
}

create_layer :: proc(id: Id, kind: Layer_Kind) -> (result: ^Layer, ok: bool) {

	z_index: int
	for i in 0..<len(core.layers) {
		layer := &core.layers[i]
		if layer.id == 0 do continue

		if int(layer.kind) <= int(kind) {
			z_index = max(z_index, layer.z_index + 1)
		}
	}

	for i in 0..<len(core.layers) {
		layer := &core.layers[i]
		if layer.id == 0 do continue

		if layer.z_index >= z_index {
			layer.z_index += 1
		}
	}

	for i in 0..<MAX_LAYERS {
		if core.layers[i].id == 0 {
			core.layers[i] = Layer{
				id = id,
				kind = kind,
				z_index = z_index,
			}
			result = &core.layers[i]
			core.layer_map[id] = result
			ok = true

			return
		}
	}
	return
}

begin_layer :: proc(info: Layer_Info, loc := #caller_location) {
	id := info.id if info.id != 0 else hash(loc)
	kind := info.kind.? or_else .Floating

	// Get a layer with `id` or create one
	layer := get_layer_by_id(id) or_else (create_layer(id, kind) or_else panic("Out of layers!"))

	// Set parameters
	layer.dead = false
	layer.id = id
	layer.box = info.box
	layer.options = info.options
	layer.kind = kind

	// Check if there is a root layer
	if info.parent != 0 {
		if parent, ok := get_layer_by_id(info.parent); ok {
			set_layer_parent(layer, parent)
		}
	}

	// Set input state
	if core.hovered_layer == layer.id {
		layer.state += {.Hovered}

		// Re-order layers if clicked
		if mouse_pressed(.Left) {
			bring_layer_to_front(layer)
		}
	}
	
	if core.focused_layer == layer.id {
		layer.state += {.Focused}
	}

	// Push stacks
	push_stack(&core.layer_stack, layer)
	begin_layout({
		box = layer.box,
	})

	// Set vertex z position
	core.vertex_state.z = 0.001 * f32(layer.z_index)

	// Transform matrix
	scale: [2]f32 = info.scale.? or_else 1
	push_matrix()
	translate_matrix(info.origin.x, info.origin.y, 0)
	scale_matrix(scale.x, scale.y, 1)
	rotate_matrix(info.rotation, 0, 0, 1)
	translate_matrix(-info.origin.x, -info.origin.y, 0)

	// Draw debug bounding box
	if core.debug.enabled && core.debug.boxes {
		// draw_box_fill(layer.box, {255, 0, 0, 50})
		draw_box_stroke(layer.box, 1, {255, 0, 0, 255})
	}
}

end_layer :: proc() {
	pop_matrix()
	layer := current_layer()

	// Get hover state
	if point_in_box(core.mouse_pos, layer.box) && layer.z_index >= core.hovered_layer_z_index {
		core.hovered_layer_z_index = layer.z_index
		core.next_hovered_layer = layer.id
	}

	core.highest_layer = max(core.highest_layer, layer.z_index)

	// Pop the stacks
	end_layout()
	pop_stack(&core.layer_stack)

	// Reset z-level to that of the previous layer or to zero
	core.vertex_state.z = (0.001 * f32(current_layer().z_index)) if core.layer_stack.height > 0 else 0
}

bring_layer_to_front :: proc(layer: ^Layer) {
	assert(layer != nil)

	// First pass determines the new z-index
	highest_of_kind := get_highest_layer_kind_index(layer.kind)

	if layer.z_index >= highest_of_kind {
		return
	}

	// Second pass lowers other layers
	for i in 0..<len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if other_layer.z_index > layer.z_index && other_layer.z_index <= highest_of_kind {
			other_layer.z_index -= 1
		}
	}

	layer.z_index = highest_of_kind
}

bring_layer_to_front_of_children :: proc(layer: ^Layer) {
	assert(layer != nil)

	if layer.parent == nil do return

	// First pass determines the new z-index
	highest_of_kind: int
	for &child in layer.parent.children {
		if int(child.kind) <= int(layer.kind) {
			highest_of_kind = max(highest_of_kind, child.z_index)
		}
	}

	if layer.z_index >= highest_of_kind {
		return
	}

	// Second pass lowers other layers
	for i in 0..<len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if other_layer.z_index > layer.z_index && other_layer.z_index <= highest_of_kind {
			other_layer.z_index -= 1
		}
	}

	layer.z_index = highest_of_kind
}

get_highest_layer_kind_index :: proc(kind: Layer_Kind) -> int {
	index: int
	for i in 0..<len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if int(other_layer.kind) <= int(kind) {
			index = max(index, other_layer.z_index)
		}
	}
	return index
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