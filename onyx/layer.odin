package onyx

/*
	Layers are surfaces with a unique z-index on which widgets are drawn.
	They can be reordered by the mouse

	FIXME: Opened layers on menus cause frame drop the first time opened (only on D3D11)
*/

import "core:fmt"
import "core:math"
import "core:math/ease"
import "core:math/linalg"
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
	index:             int,
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

set_layer_index :: proc(layer: ^Layer, index: int) {
	assert(layer != nil)

	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue

		if other_layer.index >= index {
			other_layer.index += 1
		}
	}
	layer.index = index
}

get_highest_layer_of_kind :: proc(kind: Layer_Kind) -> int {
	index: int
	for i in 0 ..< len(core.layers) {
		layer := &core.layers[i]
		if layer.id == 0 do continue

		if int(layer.kind) <= int(kind) {
			index = max(index, layer.index + 1)
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

		set_layer_index(
			layer,
			layer.parent.index + 1 if layer.parent != nil else get_highest_layer_of_kind(kind),
		)
	}

	// Push layer
	push_stack(&core.layer_stack, layer)

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

	// Set vertex z position
	push_clip(layer.box)
	core.current_draw_call.texture = core.font_atlas.texture

	set_global_alpha(layer.opacity)

	// Transform matrix
	scale: [2]f32 = info.scale.? or_else 1
	push_matrix()
	translate_matrix(info.origin.x, info.origin.y, 0)
	scale_matrix(scale.x, scale.y, 1)
	rotate_matrix(info.rotation, 0, 0, 1)
	translate_matrix(-info.origin.x, -info.origin.y, 0)

	// Push layout
	push_layout(Layout{box = layer.box, original_box = layer.box, next_side = .Top})

	return true
}

end_layer :: proc() {

	pop_matrix()

	layer := current_layer().?

	// Get hover state
	if (.Ghost not_in layer.options) && point_in_box(core.mouse_pos, layer.box) {
		if layer.index >= core.highest_layer_index {
			// The layer has the highest z index yet
			core.highest_layer_index = layer.index
			core.next_hovered_layer = layer.id
		}
	}

	// Pop the current layout
	pop_layout()

	// Pop the layer stack
	pop_stack(&core.layer_stack)

	// Reset z-level to that of the previous layer or to zero
	if layer, ok := current_layer().?; ok {
		pop_clip()
		core.current_draw_call.texture = core.font_atlas.texture

		set_global_alpha(layer.opacity)
	}
}

bring_layer_to_front :: proc(layer: ^Layer) {
	assert(layer != nil)

	// First pass determines the new z-index
	highest_of_kind := get_highest_layer_kind_index(layer.kind)

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

get_highest_layer_kind_index :: proc(kind: Layer_Kind) -> int {
	index: int
	for i in 0 ..< len(core.layers) {
		other_layer := &core.layers[i]
		if other_layer.id == 0 do continue
		if int(other_layer.kind) <= int(kind) {
			index = max(index, other_layer.index)
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
