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
	state: Layer_State,
	index: int, 								// z-index
	options: Layer_Options,			// Option bit flags
	order: Layer_Order,					// Basically the type of layer, affects it's place in the list
	box: Box,		
	parent: ^Layer,							// The layer's parent
	children: [dynamic]^Layer,	// The layer's children
	dead: bool,									// Should be deleted?
}

Layer_Info :: struct {
	id: Id,
	options: Layer_Options,
	order: Layer_Order,
	box: Box,
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

	layer := core.layer_map[id] or_else (__new_layer(id) or_else panic("Out of layers!"))
	layer.dead = false
	layer.id = id
	layer.box = info.box
	layer.order = info.order
	layer.options = info.options

	if core.root_layer == nil {
		core.root_layer = layer
	} else {
		parent := core.layer_stack.items[core.layer_stack.height - 1]
		if layer.parent != parent {
			layer.parent = parent
			append(&parent.children, layer)
		}
	}

	push(&core.layer_stack, layer)
	begin_layout({
		box = layer.box,
	})
	side(.Top)
}
end_layer :: proc() {
	end_layout()
	pop(&core.layer_stack)
}
process_layers :: proc() {
	sorted_layer: ^Layer
	core.last_hovered_layer = core.hovered_layer
	core.hovered_layer = 0
	if core.mouse_pos != core.last_mouse_pos {
		core.scrolling_layer = 0
	}
	hovered_layer: ^Layer
	for layer, i in core.layer_list {
		if layer.dead {
			when ODIN_DEBUG {
				fmt.printf("[ui] Deleted layer %x\n", layer.id)
			}
			ordered_remove(&core.layer_list, i)
			delete_key(&core.layer_map, layer.id)
			if layer.parent != nil {
				for child, j in layer.parent.children {
					if child == layer {
						ordered_remove(&layer.parent.children, j)
						break
					}
				}
			}
			destroy_layer(layer)
			(transmute(^Maybe(Layer))layer)^ = nil
			core.sort_layers = true
			core.draw_next_frame = true
		} else {
			layer.state = {}
			layer.dead = true
			if point_in_box(core.mouse_pos, layer.box) {
				core.hovered_layer = layer.id
				hovered_layer = layer
				if core.mouse_pos != core.last_mouse_pos && layer.options & {.Scroll_X, .Scroll_Y} != {} {
					core.scrolling_layer = layer.id
				}
				if mouse_pressed(.Left) {
					core.focused_layer = layer.id
					if .No_Sort not_in layer.options {
						sorted_layer = layer
					}
				}
			}
		}
	}
	for hovered_layer != nil {
		hovered_layer.state += {.Hovered}
		if .Attached in hovered_layer.options {
			hovered_layer = hovered_layer.parent
		} else {
			break
		}
	}
	// If a sorted layer was selected, then find it's root attached parent
	if sorted_layer != nil {
		child := sorted_layer
		for {
			if child.parent != nil {
				core.top_layer = child.id
				sorted_layer = child
				child = child.parent
			} else {
				break
			}
		}
	}
	// Then reorder it with it's siblings
	if core.top_layer != core.last_top_layer {
		if sorted_layer.parent != nil {
			for child in sorted_layer.parent.children {
				if child.order == sorted_layer.order {
					if child.id == core.top_layer {
						child.index = len(sorted_layer.parent.children)
					} else {
						child.index -= 1
					}
				}
			}
		}
		core.sort_layers = true
		core.last_top_layer = core.top_layer
	}
	// Sort the layers
	if core.sort_layers {
		core.sort_layers = false

		clear(&core.layer_list)
		sort_layer(&core.layer_list, core.root_layer)
	}
}
sort_layer :: proc(list: ^[dynamic]^Layer, layer: ^Layer) {
	append(list, layer)
	if len(layer.children) > 0 {
		slice.sort_by(layer.children[:], proc(a, b: ^Layer) -> bool {
			if a.order == b.order {
				return a.index < b.index
			}
			return int(a.order) < int(b.order)
		})
		for child in layer.children do sort_layer(list, child)
	}
}