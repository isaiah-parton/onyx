package onyx

/*
	Layers are surfaces with a unique z-index on which widgets are drawn.
	They can be reordered by the mouse

	FIXME: Opened layers on menus cause frame drop the first time opened (only on D3D11)
*/

import "core:fmt"
import "core:math"
import "core:slice"

Layer_Kind :: enum int {
	Background,
	Floating,
	Topmost,
	Debug,
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
	Ghost,
	Isolated,
	Attached,
}

Layer_Options :: bit_set[Layer_Option]

Layer :: struct {
	id:                Id,
	parent:            ^Layer, // The layer's parent
	children:          [dynamic]^Layer, // The layer's children

	last_state, state: Layer_State,
	options:           Layer_Options, // Option bit flags
	kind:              Layer_Kind,
	box:               Box,
	dead:              bool, // Should be deleted?
	opacity:           f32,
	z_index:           int,
}

Layer_Info :: struct {
	id:       Id,
	parent:   ^Layer,
	options:  Layer_Options,
	box:      Box,
	kind:     Maybe(Layer_Kind),
	origin:   [2]f32,
	scale:    Maybe([2]f32),
	rotation: f32,
	opacity:  Maybe(f32),
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

set_layer_z_index :: proc(layer: ^Layer, z_index: int) {
	assert(layer != nil)

	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue

		if other_layer.z_index >= z_index {
			other_layer.z_index += 1
		}
	}
	layer.z_index = z_index
}

get_highest_layer_of_kind :: proc(kind: Layer_Kind) -> int {
	z_index: int
	for i in 0 ..< len(core.layers) {
		layer := &core.layers[i]
		if layer.id == 0 do continue

		if int(layer.kind) <= int(kind) {
			z_index = max(z_index, layer.z_index + 1)
		}
	}
	return z_index
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

begin_layer :: proc(info: Layer_Info, loc := #caller_location) -> bool {
	id := info.id if info.id != 0 else hash(loc)
	kind := info.kind.? or_else .Floating

	// Get a layer with `id` or create one
	layer, ok := get_layer_by_id(id)
	if !ok {
		layer = create_layer(id) or_return

		if info.parent != nil {
			set_layer_parent(layer, info.parent)
		}

		set_layer_z_index(
			layer,
			layer.parent.z_index + 1 if layer.parent != nil else get_highest_layer_of_kind(kind),
		)
	}

	// Set parameters
	layer.dead = false
	layer.id = id
	layer.box = info.box
	layer.options = info.options
	layer.kind = kind
	layer.opacity = info.opacity.? or_else 1

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
	push_layout(Layout{box = layer.box, original_box = layer.box, next_side = .Top})

	// Set vertex z position
	add_layer_draw_call(layer)

	// Transform matrix
	scale: [2]f32 = info.scale.? or_else 1
	push_matrix()
	translate_matrix(info.origin.x, info.origin.y, 0)
	scale_matrix(scale.x, scale.y, 1)
	rotate_matrix(info.rotation, 0, 0, 1)
	translate_matrix(-info.origin.x, -info.origin.y, 0)

	return true
}

end_layer :: proc() {
	pop_matrix()
	layer := current_layer().?

	// Get hover state
	if (.Ghost not_in layer.options) && point_in_box(core.mouse_pos, layer.box) {
		if layer.z_index >= core.highest_layer_index {
			// The layer has the highest z index yet
			core.highest_layer_index = layer.z_index
			core.next_hovered_layer = layer.id
		}
	}

	// Pop the stacks
	pop_layout()
	pop_stack(&core.layer_stack)

	// Reset z-level to that of the previous layer or to zero
	if layer, ok := current_layer().?; ok {
		add_layer_draw_call(layer)
	}
}

add_layer_draw_call :: proc(layer: ^Layer) {
	push_draw_call()
	core.current_draw_call.texture = core.font_atlas.texture
	core.current_draw_call.index = layer.z_index
	core.current_draw_call.clip_box = layer.box

	core.vertex_state.alpha = layer.opacity
}

bring_layer_to_front :: proc(layer: ^Layer) {
	assert(layer != nil)

	// First pass determines the new z-index
	highest_of_kind := get_highest_layer_kind_index(layer.kind)

	if layer.z_index >= highest_of_kind {
		return
	}

	// Second pass lowers other layers
	for i in 0 ..< len(core.layers) {
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
	for i in 0 ..< len(core.layers) {
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
	for i in 0 ..< len(core.layers) {
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
