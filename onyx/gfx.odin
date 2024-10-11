package onyx

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

Shader_Uniforms :: struct {
	size: [2]f32,
}

Graphics :: struct {
	width, height:             u32,
	// Infrastructure
	instance:                  wgpu.Instance,
	adapter:                   wgpu.Adapter,
	pipeline:                  wgpu.RenderPipeline,
	surface:                   wgpu.Surface,
	device:                    wgpu.Device,
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
	indices:                   [dynamic]u32,
	shapes:                    WGPU_Buffer(Shape),
	paints:                    WGPU_Buffer(Paint),
	cvs:                       WGPU_Buffer([2]f32),
	xforms:                    WGPU_Buffer(Matrix),
}

resize_graphics :: proc(gfx: ^Graphics, width, height: int) {
	if width <= 0 || height <= 0 do return
	gfx.width = u32(width)
	gfx.height = u32(height)
	gfx.surface_config.width = gfx.width
	gfx.surface_config.height = gfx.height
	wgpu.SurfaceConfigure(gfx.surface, &gfx.surface_config)
}

@(cold)
init_graphics :: proc(gfx: ^Graphics, window: glfw.WindowHandle) {

	width, height := glfw.GetWindowSize(window)
	gfx.width, gfx.height = u32(width), u32(height)

	// Create the wgpu instance
	when ODIN_OS == .Windows {
		gfx.instance = wgpu.CreateInstance(
			&{nextInChain = &wgpu.InstanceExtras{sType = .InstanceExtras, backends = {.Vulkan}}},
		)
	} else {
		gfx.instance = wgpu.CreateInstance()
	}

	// Create the surface to render onto
	gfx.surface = glfwglue.GetSurface(gfx.instance, window)

	// Find an adapter to use (graphics device and driver combined)
	when true {
		// Works on my machine
		wgpu.InstanceRequestAdapter(
			gfx.instance,
			&{compatibleSurface = gfx.surface, powerPreference = .LowPower},
			on_adapter,
			gfx,
		)
	} else {
		// Some cases might require we get the adapter from a list
		adapters := wgpu.InstanceEnumerateAdapters(gfx.instance)
		defer delete(adapters)

		for adapter in adapters {
			info := wgpu.AdapterGetInfo(adapter)
			defer wgpu.AdapterInfoFreeMembers(info)
			if info.backendType == .Vulkan {
				on_adapter(.Success, adapter, nil, gfx)
				break
			}
		}
	}

	// Print the backend type
	info := wgpu.AdapterGetInfo(gfx.adapter)
	fmt.println("Created graphics pipeline with", info.backendType, "backend")

	on_adapter :: proc "c" (
		status: wgpu.RequestAdapterStatus,
		adapter: wgpu.Adapter,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		gfx := transmute(^Graphics)userdata
		if status != .Success {
			return
		}
		// Set adapter
		gfx.adapter = adapter
		// Request a device
		wgpu.AdapterRequestDevice(
			adapter,
			&{
				requiredFeatureCount = 1,
				requiredFeatures = ([^]wgpu.FeatureName)(
					&[?]wgpu.FeatureName{.VertexWritableStorage},
				),
				deviceLostUserdata = gfx,
				deviceLostCallback = proc "c" (
					reason: wgpu.DeviceLostReason,
					message: cstring,
					userdata: rawptr,
				) {
					context = runtime.default_context()
					fmt.println(reason, message)
				},
			},
			on_device,
			gfx,
		)
	}

	on_device :: proc "c" (
		status: wgpu.RequestDeviceStatus,
		device: wgpu.Device,
		message: cstring,
		userdata: rawptr,
	) {
		context = runtime.default_context()
		gfx := transmute(^Graphics)userdata
		if status != .Success {
			return
		}
		// Save device for later
		gfx.device = device
		if supported_limits, ok := wgpu.DeviceGetLimits(gfx.device); ok {
			gfx.device_limits = supported_limits.limits
		}
		// Initial surface config
		surface_capabilities := wgpu.SurfaceGetCapabilities(gfx.surface, gfx.adapter)
		gfx.surface_config = {
			usage       = {.RenderAttachment},
			width       = gfx.width,
			height      = gfx.height,
			device      = gfx.device,
			format      = .BGRA8Unorm, //surface_capabilities.formats[0],
			presentMode = surface_capabilities.presentModes[0],
			alphaMode   = surface_capabilities.alphaModes[0],
		}
		wgpu.SurfaceConfigure(gfx.surface, &gfx.surface_config)
		// Get the command queue
		gfx.queue = wgpu.DeviceGetQueue(gfx.device)
		// Create buffers
		gfx.uniform_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{
				label = "UniformBuffer",
				size = size_of(Shader_Uniforms),
				usage = {.Uniform, .CopyDst},
			},
		)
		gfx.vertex_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{label = "VertexBuffer", size = BUFFER_SIZE, usage = {.Vertex, .CopyDst}},
		)
		gfx.index_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{label = "IndexBuffer", size = BUFFER_SIZE, usage = {.Index, .CopyDst}},
		)
		wgpu_buffer_create(&gfx.shapes, gfx.device, "ShapeBuffer", 4096)
		wgpu_buffer_create(&gfx.paints, gfx.device, "PaintBuffer", 128)
		wgpu_buffer_create(&gfx.cvs, gfx.device, "ControlVertexBuffer", 1024)
		wgpu_buffer_create(&gfx.xforms, gfx.device, "MatrixBuffer", 256)
		// Create bind group layouts
		uniform_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
			gfx.device,
			&{
				label = "UniformBindGroupLayout",
				entryCount = 1,
				entries = &wgpu.BindGroupLayoutEntry {
					binding = 0,
					buffer = wgpu.BufferBindingLayout{type = .Uniform},
					visibility = {.Vertex},
				},
			},
		)
		gfx.texture_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(
			gfx.device,
			&{
				label = "TextureBindGroupLayout",
				entryCount = 3,
				entries = transmute([^]wgpu.BindGroupLayoutEntry)&[?]wgpu.BindGroupLayoutEntry {
					{binding = 0, sampler = {type = .Filtering}, visibility = {.Fragment}},
					{
						binding = 1,
						texture = {sampleType = .Float, viewDimension = ._2D},
						visibility = {.Fragment},
					},
					{
						binding = 2,
						texture = {sampleType = .Float, viewDimension = ._2D},
						visibility = {.Fragment},
					},
				},
			},
		)
		storage_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(
			gfx.device,
			&{
				label = "StorageBindGroupLayout",
				entryCount = 4,
				entries = ([^]wgpu.BindGroupLayoutEntry)(
					&[?]wgpu.BindGroupLayoutEntry {
						wgpu_buffer_bind_group_layout_entry(&gfx.shapes, 0),
						wgpu_buffer_bind_group_layout_entry(&gfx.paints, 1),
						wgpu_buffer_bind_group_layout_entry(&gfx.cvs, 2),
						wgpu_buffer_bind_group_layout_entry(&gfx.xforms, 3),
					},
				),
			},
		)
		// Create bind group
		gfx.uniform_bind_group = wgpu.DeviceCreateBindGroup(
			gfx.device,
			&{
				label = "UniformBindGroup",
				layout = uniform_bind_group_layout,
				entryCount = 1,
				entries = &wgpu.BindGroupEntry {
					binding = 0,
					buffer = gfx.uniform_buffer,
					size = size_of(Shader_Uniforms),
				},
			},
		)
		gfx.storage_bind_group = wgpu.DeviceCreateBindGroup(
			gfx.device,
			&{
				label = "StorageBindGroup",
				layout = storage_bind_group_layout,
				entryCount = 4,
				entries = ([^]wgpu.BindGroupEntry)(
					&[?]wgpu.BindGroupEntry {
						wgpu_buffer_bind_group_entry(&gfx.shapes, 0),
						wgpu_buffer_bind_group_entry(&gfx.paints, 1),
						wgpu_buffer_bind_group_entry(&gfx.cvs, 2),
						wgpu_buffer_bind_group_entry(&gfx.xforms, 3),
					},
				),
			},
		)
		// Create pipeline layout
		pipeline_layout := wgpu.DeviceCreatePipelineLayout(
			gfx.device,
			&{
				label = "PipelineLayout",
				bindGroupLayoutCount = 3,
				bindGroupLayouts = ([^]wgpu.BindGroupLayout)(
					&[?]wgpu.BindGroupLayout {
						uniform_bind_group_layout,
						gfx.texture_bind_group_layout,
						storage_bind_group_layout,
					},
				),
			},
		)
		// Create shader module
		t := time.now()
		module := wgpu.DeviceCreateShaderModule(
			gfx.device,
			&{
				label = "Shader",
				nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
					sType = .ShaderModuleWGSLDescriptor,
					code = #load("shader.wgsl", cstring),
				},
			},
		)
		fmt.printfln("Shader compilation took %fms", time.duration_milliseconds(time.since(t)))

		vertex_attributes := [?]wgpu.VertexAttribute {
			{format = .Float32x2, offset = u64(offset_of(Vertex, pos)), shaderLocation = 0},
			{format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 1},
			{format = .Unorm8x4, offset = u64(offset_of(Vertex, col)), shaderLocation = 2},
			{format = .Uint32, offset = u64(offset_of(Vertex, shape)), shaderLocation = 3},
		}
		// Create the pipeline
		gfx.pipeline = wgpu.DeviceCreateRenderPipeline(
			gfx.device,
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
						format = gfx.surface_config.format,
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
}

uninit_graphics :: proc(gfx: ^Graphics) {
	wgpu_buffer_destroy(&gfx.shapes)
	wgpu_buffer_destroy(&gfx.paints)
	wgpu_buffer_destroy(&gfx.cvs)
	wgpu_buffer_destroy(&gfx.xforms)
	wgpu.SurfaceRelease(gfx.surface)
	wgpu.BufferRelease(gfx.vertex_buffer)
	wgpu.BufferRelease(gfx.index_buffer)
	wgpu.AdapterRelease(gfx.adapter)
	wgpu.QueueRelease(gfx.queue)
	wgpu.RenderPipelineRelease(gfx.pipeline)
	wgpu.DeviceRelease(gfx.device)
}

reset :: proc(gfx: ^Graphics) {
	clear(&gfx.vertices)
	clear(&gfx.indices)
	clear(&gfx.shapes.data)
	clear(&gfx.paints.data)
	clear(&gfx.cvs.data)
	clear(&gfx.xforms.data)
}

draw :: proc(gfx: ^Graphics, draw_calls: []Draw_Call) {
	// Write buffer data
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.vertex_buffer,
		0,
		raw_data(gfx.vertices),
		len(gfx.vertices) * size_of(Vertex),
	)
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.index_buffer,
		0,
		raw_data(gfx.indices),
		len(gfx.indices) * size_of(u32),
	)

	uniform := Shader_Uniforms {
		size = core.view,
	}

	// Sort draw calls by index
	slice.sort_by(core.draw_calls[:], proc(i, j: Draw_Call) -> bool {
		return i.index < j.index
	})

	encoder := wgpu.DeviceCreateCommandEncoder(gfx.device)
	defer wgpu.CommandEncoderRelease(encoder)

	surface_texture := wgpu.SurfaceGetCurrentTexture(gfx.surface)
	switch surface_texture.status {
	case .Success:
	// All good, could check for `surface_texture.suboptimal` here.
	case .Timeout, .Outdated, .Lost:
		// Skip this frame, and re-configure surface.
		if surface_texture.texture != nil {
			wgpu.TextureRelease(surface_texture.texture)
		}
		return
	case .OutOfMemory, .DeviceLost:
		// Fatal error
		fmt.panicf("[triangle] get_current_texture status=%v", surface_texture.status)
	}
	defer wgpu.TextureRelease(surface_texture.texture)

	surface_view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(surface_view)

	rpass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = surface_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0, 0, 0, 0},
			},
		},
	)
	wgpu.RenderPassEncoderSetPipeline(rpass, gfx.pipeline)
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

	if len(gfx.vertices) > 0 {
		wgpu.RenderPassEncoderSetVertexBuffer(
			rpass,
			0,
			gfx.vertex_buffer,
			0,
			u64(len(gfx.vertices) * size_of(Vertex)),
		)
	}
	if len(gfx.indices) > 0 {
		wgpu.RenderPassEncoderSetIndexBuffer(
			rpass,
			gfx.index_buffer,
			.Uint32,
			0,
			u64(len(gfx.indices) * size_of(u32)),
		)
	}

	wgpu.RenderPassEncoderSetBindGroup(rpass, 0, gfx.uniform_bind_group)
	wgpu.QueueWriteBuffer(gfx.queue, gfx.uniform_buffer, 0, &uniform, size_of(uniform))

	wgpu.RenderPassEncoderSetBindGroup(rpass, 2, gfx.storage_bind_group)
	wgpu_buffer_update(&gfx.shapes, gfx.queue)
	wgpu_buffer_update(&gfx.paints, gfx.queue)
	wgpu_buffer_update(&gfx.cvs, gfx.queue)
	wgpu_buffer_update(&gfx.xforms, gfx.queue)
	wgpu.QueueSubmit(gfx.queue, {})

	// Create transient texture view
	atlas_texture_view := wgpu.TextureCreateView(core.font_atlas.texture.internal)
	defer wgpu.TextureViewRelease(atlas_texture_view)

	// Render them
	for &call in core.draw_calls {

		// Redundancy checks
		if call.elem_count == 0 {
			continue
		}

		// Create view for user texture
		user_texture_view: wgpu.TextureView = atlas_texture_view
		defer if user_texture_view != atlas_texture_view do wgpu.TextureViewRelease(user_texture_view)
		if user_texture, ok := call.user_texture.?; ok {
			user_texture_view = wgpu.TextureCreateView(user_texture)
		}

		// Create transient sampler
		sampler := wgpu.DeviceCreateSampler(
			gfx.device,
			&{
				magFilter = .Linear,
				minFilter = .Linear,
				addressModeU = .ClampToEdge,
				addressModeV = .ClampToEdge,
				maxAnisotropy = 1,
			},
		)
		defer wgpu.SamplerRelease(sampler)

		// Create transient bind group
		texture_bind_group := wgpu.DeviceCreateBindGroup(
			gfx.device,
			&{
				label = "TextureBindGroup",
				layout = gfx.texture_bind_group_layout,
				entryCount = 3,
				entries = transmute([^]wgpu.BindGroupEntry)&[?]wgpu.BindGroupEntry {
					{binding = 0, sampler = sampler},
					{binding = 1, textureView = atlas_texture_view},
					{binding = 2, textureView = user_texture_view},
				},
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

	wgpu.QueueSubmit(gfx.queue, {command_buffer})
	wgpu.SurfacePresent(gfx.surface)
}
