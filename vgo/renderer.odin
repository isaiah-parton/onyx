package vgo

import "base:runtime"
import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:sys/windows"
import "core:thread"
import "core:time"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

WGPU_Buffer :: struct($T: typeid) {
	buffer:   wgpu.Buffer,
	data:     [dynamic]T,
	capacity: int,
	label:    cstring,
}

wgpu_buffer_create :: proc(
	self: ^WGPU_Buffer($T),
	device: wgpu.Device,
	label: cstring,
	capacity: int,
) -> bool {
	self.label = label
	self.capacity = capacity
	self.buffer = wgpu.DeviceCreateBuffer(
		device,
		&{
			label = self.label,
			size = u64(self.capacity * size_of(T)),
			usage = {.Storage, .CopyDst},
		},
	)
	return true
}
wgpu_buffer_update :: proc(self: ^WGPU_Buffer($T), queue: wgpu.Queue) {
	size := len(self.data) * size_of(T)
	max_size := self.capacity * size_of(T)
	if size > max_size {
		fmt.printfln("Insufficient space in buffer '%s' (%i > %i)", self.label, size, max_size)
		size = max_size
	}
	wgpu.QueueWriteBuffer(queue, self.buffer, 0, raw_data(self.data), uint(size))
}
wgpu_buffer_bind_group_layout_entry :: proc(
	self: ^WGPU_Buffer($T),
	binding: u32,
) -> wgpu.BindGroupLayoutEntry {
	return wgpu.BindGroupLayoutEntry {
		binding = binding,
		buffer = {type = .ReadOnlyStorage, minBindingSize = size_of(T)},
		visibility = {.Fragment, .Vertex},
	}
}
wgpu_buffer_bind_group_entry :: proc(self: ^WGPU_Buffer($T), binding: u32) -> wgpu.BindGroupEntry {
	return wgpu.BindGroupEntry {
		binding = binding,
		size = u64(self.capacity * size_of(T)),
		buffer = self.buffer,
	}
}
wgpu_buffer_destroy :: proc(self: ^WGPU_Buffer($T)) {
	delete(self.data)
	wgpu.BufferDestroy(self.buffer)
}

Shader_Uniforms :: struct #align (8) {
	size: [2]f32,
	time: f32,
}

Renderer :: struct {
	// Infrastructure
	device:                    wgpu.Device,
	surface:                   wgpu.Surface,
	pipeline:                  wgpu.RenderPipeline,
	queue:                     wgpu.Queue,
	// Settings
	surface_config:            wgpu.SurfaceConfiguration,
	device_limits:             wgpu.Limits,
	// Resources
	uniform_bind_group:        wgpu.BindGroup,
	texture_bind_group:        wgpu.BindGroup,
	storage_bind_group:        wgpu.BindGroup,
	texture_bind_group_layout: wgpu.BindGroupLayout,
	uniform_buffer:            wgpu.Buffer,
	vertex_buffer:             wgpu.Buffer,
	index_buffer:              wgpu.Buffer,
	vertices:                  [dynamic]Vertex,
	indices:                   [dynamic]u16,
	shapes:                    WGPU_Buffer(Shape),
	paints:                    WGPU_Buffer(Paint),
	cvs:                       WGPU_Buffer([2]f32),
	xforms:                    WGPU_Buffer(Matrix),
}

init_renderer_with_device_and_surface :: proc(
	renderer: ^Renderer,
	device: wgpu.Device,
	surface: wgpu.Surface,
) {
	assert(renderer != nil)
	// Save device for later
	renderer.device = device
	renderer.surface = surface
	// Know your limits
	if supported_limits, ok := wgpu.DeviceGetLimits(renderer.device); ok {
		renderer.device_limits = supported_limits.limits
	}
	// Get the command queue
	renderer.queue = wgpu.DeviceGetQueue(renderer.device)
	// Create buffers
	renderer.uniform_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&{label = "UniformBuffer", size = size_of(Shader_Uniforms), usage = {.Uniform, .CopyDst}},
	)
	renderer.vertex_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&{label = "VertexBuffer", size = BUFFER_SIZE, usage = {.Vertex, .CopyDst}},
	)
	renderer.index_buffer = wgpu.DeviceCreateBuffer(
		renderer.device,
		&{label = "IndexBuffer", size = BUFFER_SIZE, usage = {.Index, .CopyDst}},
	)
	wgpu_buffer_create(&renderer.shapes, renderer.device, "ShapeBuffer", 4096)
	wgpu_buffer_create(&renderer.paints, renderer.device, "PaintBuffer", 128)
	wgpu_buffer_create(&renderer.cvs, renderer.device, "ControlVertexBuffer", 1024)
	wgpu_buffer_create(&renderer.xforms, renderer.device, "MatrixBuffer", 256)
	// Create bind group layouts
	uniform_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&{
			label = "UniformBindGroupLayout",
			entryCount = 1,
			entries = &wgpu.BindGroupLayoutEntry {
				binding = 0,
				buffer = wgpu.BufferBindingLayout{type = .Uniform},
				visibility = {.Vertex, .Fragment},
			},
		},
	)
	renderer.texture_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&{
			label = "TextureBindGroupLayout",
			entryCount = 4,
			entries = transmute([^]wgpu.BindGroupLayoutEntry)&[?]wgpu.BindGroupLayoutEntry {
				{binding = 0, sampler = {type = .Filtering}, visibility = {.Fragment}},
				{
					binding = 1,
					texture = {sampleType = .Float, viewDimension = ._2D},
					visibility = {.Fragment},
				},
				{binding = 2, sampler = {type = .Filtering}, visibility = {.Fragment}},
				{
					binding = 3,
					texture = {sampleType = .Float, viewDimension = ._2D},
					visibility = {.Fragment},
				},
			},
		},
	)
	storage_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
		renderer.device,
		&{
			label = "StorageBindGroupLayout",
			entryCount = 4,
			entries = ([^]wgpu.BindGroupLayoutEntry)(
				&[?]wgpu.BindGroupLayoutEntry {
					wgpu_buffer_bind_group_layout_entry(&renderer.shapes, 0),
					wgpu_buffer_bind_group_layout_entry(&renderer.paints, 1),
					wgpu_buffer_bind_group_layout_entry(&renderer.cvs, 2),
					wgpu_buffer_bind_group_layout_entry(&renderer.xforms, 3),
				},
			),
		},
	)
	// Create bind group
	renderer.uniform_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&{
			label = "UniformBindGroup",
			layout = uniform_bind_group_layout,
			entryCount = 1,
			entries = &wgpu.BindGroupEntry {
				binding = 0,
				buffer = renderer.uniform_buffer,
				size = size_of(Shader_Uniforms),
			},
		},
	)
	renderer.storage_bind_group = wgpu.DeviceCreateBindGroup(
		renderer.device,
		&{
			label = "StorageBindGroup",
			layout = storage_bind_group_layout,
			entryCount = 4,
			entries = ([^]wgpu.BindGroupEntry)(
				&[?]wgpu.BindGroupEntry {
					wgpu_buffer_bind_group_entry(&renderer.shapes, 0),
					wgpu_buffer_bind_group_entry(&renderer.paints, 1),
					wgpu_buffer_bind_group_entry(&renderer.cvs, 2),
					wgpu_buffer_bind_group_entry(&renderer.xforms, 3),
				},
			),
		},
	)
	// Create pipeline layout
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(
		renderer.device,
		&{
			label = "PipelineLayout",
			bindGroupLayoutCount = 3,
			bindGroupLayouts = ([^]wgpu.BindGroupLayout)(
				&[?]wgpu.BindGroupLayout {
					uniform_bind_group_layout,
					renderer.texture_bind_group_layout,
					storage_bind_group_layout,
				},
			),
		},
	)
	// Create shader module
	module := wgpu.DeviceCreateShaderModule(
		renderer.device,
		&{
			label = "Shader",
			nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
				sType = .ShaderModuleWGSLDescriptor,
				code = #load("shader.wgsl", cstring),
			},
		},
	)
	// Vertex attribs
	vertex_attributes := [?]wgpu.VertexAttribute {
		{format = .Float32x2, offset = u64(offset_of(Vertex, pos)), shaderLocation = 0},
		{format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 1},
		{format = .Unorm8x4, offset = u64(offset_of(Vertex, col)), shaderLocation = 2},
		{format = .Uint32, offset = u64(offset_of(Vertex, shape)), shaderLocation = 3},
		{format = .Uint32, offset = u64(offset_of(Vertex, paint)), shaderLocation = 4},
	}
	// Create the pipeline
	renderer.pipeline = wgpu.DeviceCreateRenderPipeline(
		renderer.device,
		&{
			label = "RenderPipeline",
			layout = pipeline_layout,
			vertex = {
				module = module,
				entryPoint = "vs_main",
				bufferCount = 1,
				buffers = &wgpu.VertexBufferLayout {
					arrayStride = size_of(Vertex),
					stepMode = .Vertex,
					attributeCount = len(vertex_attributes),
					attributes = &vertex_attributes[0],
				},
			},
			fragment = &{
				module = module,
				entryPoint = "fs_main",
				targetCount = 1,
				targets = &wgpu.ColorTargetState {
					format = renderer.surface_config.format,
					writeMask = {.Red, .Green, .Blue, .Alpha},
					blend = &{
						color = {
							srcFactor = .SrcAlpha,
							dstFactor = .OneMinusSrcAlpha,
							operation = .Add,
						},
						alpha = {srcFactor = .One, dstFactor = .One, operation = .Add},
					},
				},
			},
			primitive = {topology = .TriangleList},
			multisample = {count = u32(1), mask = 0xffffffff},
		},
	)
}

destroy_renderer :: proc(renderer: ^Renderer) {
	wgpu_buffer_destroy(&renderer.shapes)
	wgpu_buffer_destroy(&renderer.paints)
	wgpu_buffer_destroy(&renderer.cvs)
	wgpu_buffer_destroy(&renderer.xforms)
	wgpu.BufferRelease(renderer.vertex_buffer)
	wgpu.BufferRelease(renderer.index_buffer)
	wgpu.QueueRelease(renderer.queue)
	wgpu.RenderPipelineRelease(renderer.pipeline)
}

render :: proc(renderer: ^Renderer, draw_calls: []Draw_Call) {
	// Write buffer data
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.vertex_buffer,
		0,
		raw_data(renderer.vertices),
		len(renderer.vertices) * size_of(Vertex),
	)
	wgpu.QueueWriteBuffer(
		renderer.queue,
		renderer.index_buffer,
		0,
		raw_data(renderer.indices),
		len(renderer.indices) * size_of(u32),
	)

	// Sort draw calls by index
	slice.sort_by(core.draw_calls[:], proc(i, j: Draw_Call) -> bool {
		return i.index < j.index
	})

	encoder := wgpu.DeviceCreateCommandEncoder(renderer.device)
	defer wgpu.CommandEncoderRelease(encoder)

	surface_texture := wgpu.SurfaceGetCurrentTexture(renderer.surface)
	switch surface_texture.status {
	case .Success:
	case .Timeout, .Outdated, .Lost:
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		return
	case .OutOfMemory, .DeviceLost:
		fmt.panicf("Surface texture status: %v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	surface_width := f32(wgpu.TextureGetWidth(surface_texture.texture))
	surface_height := f32(wgpu.TextureGetHeight(surface_texture.texture))

	// Create shader uniform
	uniform := Shader_Uniforms {
		size = {surface_width, surface_height},
		time = f32(time.duration_seconds(time.since(core.start_time))),
	}

	surface_view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(surface_view)

	// Render pass
	rpass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = linalg.array_cast(core.style.color.background, f64) / 255.0,
			},
		},
	)
	wgpu.RenderPassEncoderSetPipeline(rpass, renderer.pipeline)
	wgpu.RenderPassEncoderSetViewport(
		rpass,
		0,
		0,
		// Quick fix to avoid a validation error
		max(core.view.x, 1),
		max(core.view.y, 1),
		//
		0,
		0,
	)

	// Set element buffers with sanity checks
	if len(renderer.vertices) > 0 {
		wgpu.RenderPassEncoderSetVertexBuffer(
			rpass,
			0,
			renderer.vertex_buffer,
			0,
			u64(len(renderer.vertices) * size_of(Vertex)),
		)
	}
	if len(renderer.indices) > 0 {
		wgpu.RenderPassEncoderSetIndexBuffer(
			rpass,
			renderer.index_buffer,
			.Uint16 when Index ==
			u16 else .Uint32 when Index ==
			u32 else #panic("Unsupported index type"),
			0,
			u64(len(renderer.indices) * size_of(Index)),
		)
	}

	// Set bind groups
	wgpu.RenderPassEncoderSetBindGroup(rpass, 0, renderer.uniform_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(rpass, 2, renderer.storage_bind_group)

	// Upload shader data
	wgpu.QueueWriteBuffer(renderer.queue, renderer.uniform_buffer, 0, &uniform, size_of(uniform))
	wgpu_buffer_update(&renderer.shapes, renderer.queue)
	wgpu_buffer_update(&renderer.paints, renderer.queue)
	wgpu_buffer_update(&renderer.cvs, renderer.queue)
	wgpu_buffer_update(&renderer.xforms, renderer.queue)
	wgpu.QueueSubmit(renderer.queue, {})

	// Create transient texture view
	atlas_texture_view := wgpu.TextureCreateView(core.atlas.texture.internal)
	defer wgpu.TextureViewRelease(atlas_texture_view)

	// Render draw calls
	for &call in core.draw_calls {

		// Redundancy checks
		if call.elem_count == 0 {
			continue
		}

		// User sampler descriptor
		user_sampler_desc :=
			call.user_sampler_desc.? or_else wgpu.SamplerDescriptor {
				magFilter = .Linear,
				minFilter = .Linear,
				addressModeU = .ClampToEdge,
				addressModeV = .ClampToEdge,
				mipmapFilter = .Linear,
				lodMinClamp = 0,
				maxAnisotropy = 4,
			}

		// Create view for user texture
		user_texture_view: wgpu.TextureView = atlas_texture_view
		defer if user_texture_view != atlas_texture_view do wgpu.TextureViewRelease(user_texture_view)
		if user_texture, ok := call.user_texture.?; ok {
			user_texture_view = wgpu.TextureCreateView(user_texture)
			if call.user_sampler_desc == nil {
				user_sampler_desc.lodMaxClamp = cast(f32)wgpu.TextureGetMipLevelCount(user_texture)
			}
		}

		// Create transient sampler
		atlas_sampler := wgpu.DeviceCreateSampler(
			renderer.device,
			&{
				magFilter = .Linear,
				minFilter = .Linear,
				addressModeU = .ClampToEdge,
				addressModeV = .ClampToEdge,
				maxAnisotropy = 1,
			},
		)
		defer wgpu.SamplerRelease(atlas_sampler)

		// Create transient sampler
		user_sampler := wgpu.DeviceCreateSampler(renderer.device, &user_sampler_desc)
		defer wgpu.SamplerRelease(user_sampler)

		// Create transient bind group
		texture_bind_group := wgpu.DeviceCreateBindGroup(
			renderer.device,
			&{
				label = "TextureBindGroup",
				layout = renderer.texture_bind_group_layout,
				entryCount = 4,
				entries = ([^]wgpu.BindGroupEntry)(
					&[?]wgpu.BindGroupEntry {
						{binding = 0, sampler = atlas_sampler},
						{binding = 1, textureView = atlas_texture_view},
						{binding = 2, sampler = user_sampler},
						{binding = 3, textureView = user_texture_view},
					},
				),
			},
		)
		defer wgpu.BindGroupRelease(texture_bind_group)

		// Set bind groups
		wgpu.RenderPassEncoderSetBindGroup(rpass, 1, texture_bind_group)

		// Draw elements
		wgpu.RenderPassEncoderDrawIndexed(
			rpass,
			u32(call.elem_count),
			1,
			u32(call.elem_offset),
			0,
			0,
		)
	}
	wgpu.RenderPassEncoderEnd(rpass)
	wgpu.RenderPassEncoderRelease(rpass)

	command_buffer := wgpu.CommandEncoderFinish(encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(renderer.queue, {command_buffer})
	wgpu.SurfacePresent(renderer.surface)

	// Reset for next frame
	clear(&renderer.vertices)
	clear(&renderer.indices)
	clear(&renderer.shapes.data)
	clear(&renderer.paints.data)
	clear(&renderer.cvs.data)
	clear(&renderer.xforms.data)
}
