package ui

import "core:fmt"
import "core:slice"

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
}
Layer_Options :: bit_set[Layer_Option]
Layer :: struct {
	id: Id,
	index: int, 								// z-index
	options: Layer_Options,			// Option bit flags
	order: Layer_Order,					// Basically the type of layer, affects it's place in the list
	box: Box,		
	surface: Draw_Surface,			// The graphical drawing surface
	parent: Maybe(^Layer),			// The layer's parent
	children: [dynamic]^Layer,	// The layer's children
	dead: bool,									// Should be deleted?
}
init_layer :: proc(layer: ^Layer) {
	init_draw_surface(&layer.surface)
}
destroy_layer :: proc(layer: ^Layer) {
	destroy_draw_surface(&layer.surface)
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
begin_layer :: proc(box: Box, options: Layer_Options = {}, loc := #caller_location) {
	id := hash(loc)

	layer := core.layer_map[id] or_else (__new_layer(id) or_else panic("Out of layers!"))
	layer.id = id
	layer.box = box
	layer.options = options

	if core.root_layer == nil {
		core.root_layer = layer
	}
	core.draw_surface = &layer.surface

	push(&core.layer_stack, layer)
	begin_layout(layer.box)
}
end_layer :: proc() {
	end_layout()

	pop(&core.layer_stack)
	core.draw_surface = &core.layer_stack.items[core.layer_stack.height - 1].surface if core.layer_stack.height > 0 else nil
}
process_layers :: proc() {
	sorted_layer: ^Layer
	core.last_hovered_layer = core.hovered_layer
	core.hovered_layer = 0
	if core.mouse_pos != core.last_mouse_pos {
		core.scrolling_layer = 0
	}
	for layer, i in core.layer_list {
		if layer.dead {
			when ODIN_DEBUG {
				fmt.printf("[ui] Deleted layer %x\n", layer.id)
			}
			delete_key(&core.layer_map, layer.id)
			if parent, ok := layer.parent.?; ok {
				for child, j in parent.children {
					if child == layer {
						ordered_remove(&parent.children, j)
						break
					}
				}
			}
			destroy_layer(layer)
			(transmute(^Maybe(Layer))layer)^ = nil
			core.sort_layers = true
			core.draw_next_frame = true
		} else {
			layer.dead = true
			if point_in_box(core.mouse_pos, layer.box) {
				core.hovered_layer = layer.id
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
	// If a sorted layer was selected, then find it's root attached parent
	if sorted_layer != nil {
		child := sorted_layer
		for {
			if parent, ok := child.parent.?; ok {
				core.top_layer = child.id
				sorted_layer = child
				child = parent
			} else {
				break
			}
		}
	}
	// Then reorder it with it's siblings
	if core.top_layer != core.last_top_layer {
		if parent, ok := sorted_layer.parent.?; ok {
			for child in parent.children {
				if child.order == sorted_layer.order {
					if child.id == core.top_layer {
						child.index = len(parent.children)
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