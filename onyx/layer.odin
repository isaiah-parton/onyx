package onyx

import "core:fmt"
import "core:slice"

Layer_Status :: enum {
	Hovered,
	Focused,
	Pressed,
}

Layer_State :: bit_set[Layer_Status]

Layer_Order :: enum {
	Background,
	Floating,
	Debug,
}

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
	order: Layer_Order,					// Basically the type of layer, affects it's place in the list
	box: Box,		
	parent: ^Layer,							// The layer's parent
	children: [dynamic]^Layer,	// The layer's children
	dead: bool,									// Should be deleted?

	// Sorted order
	z_index: int,
}

Layer_Info :: struct {
	id: Id,
	options: Layer_Options,
	order: Layer_Order,
	box: Box,

	origin: [2]f32,
	scale: Maybe([2]f32),
	rotation: f32,
}

init_layer :: proc(layer: ^Layer) {
	// init_draw_surface(&layer.surface)
}

destroy_layer :: proc(layer: ^Layer) {
	// destroy_draw_surface(&layer.surface)
}

current_layer :: proc(loc := #caller_location) -> ^Layer {
	assert(core.layer_stack.height > 0, "No current layer", loc)
	return core.layer_stack.items[core.layer_stack.height - 1]
}

__new_layer :: proc(id: Id) -> (layer: ^Layer, ok: bool) {
	for i in 0..<MAX_LAYERS {
		if core.layers[i] == nil {
			core.layers[i] = Layer{
				id = id,
			}
			layer = &core.layers[i].?
			core.layer_map[id] = layer
			init_layer(&core.layers[i].?)
			ok = true
			core.sort_layers = true
			return
		}
	}
	return
}

begin_layer :: proc(info: Layer_Info, loc := #caller_location) {
	id := info.id if info.id != 0 else hash(loc)

	// Get a layer with `id` or create one
	layer := core.layer_map[id] or_else (__new_layer(id) or_else panic("Out of layers!"))

	// Set parameters
	layer.dead = false
	layer.id = id
	layer.box = info.box
	layer.order = info.order
	layer.options = info.options

	// Check if there is a root layer
	if core.root_layer == nil {

		// Set root layer
		core.root_layer = layer
	} else {

		// The parent will be the previous layer
		parent := core.layer_stack.items[core.layer_stack.height - 1]

		// Add self to parent's children
		if layer.parent != parent {

			layer.parent = parent
			append(&parent.children, layer)
			layer.z_index = parent.z_index + len(parent.children)
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

	// Pop the stacks
	end_layout()
	pop_stack(&core.layer_stack)

	// Reset z-level to that of the previous layer or to zero
	core.vertex_state.z = (0.001 * f32(current_layer().z_index)) if core.layer_stack.height > 0 else 0
}

bring_layer_to_front :: proc(layer: ^Layer) {

	if layer.parent == nil do return

	top_z_index := layer.parent.z_index + len(layer.parent.children)

	if layer.z_index == top_z_index do return

	for &child, c in layer.parent.children {
		if child.id == layer.id || child.z_index < layer.z_index {
			continue
		}
		child.z_index -= 1
	}
	layer.z_index = top_z_index
}