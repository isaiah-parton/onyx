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

SHAPE_BUFFER_CAPACITY :: size_of(Shape) * 4096
PAINT_BUFFER_CAPACITY :: size_of(Paint) * 512
CVS_BUFFER_CAPACITY :: size_of([2]f32) * 512

Shader_Uniforms :: struct {
	proj_mtx: matrix[4, 4]f32,
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
	sample_count:              int,
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
	shape_buffer:              wgpu.Buffer,
	paint_buffer:              wgpu.Buffer,
	cvs_buffer:                wgpu.Buffer,
}

resize_graphics :: proc(gfx: ^Graphics, width, height: int) {
	if width <= 0 || height <= 0 do return
	gfx.width = u32(width)
	gfx.height = u32(height)
	gfx.surface_config.width = gfx.width
	gfx.surface_config.height = gfx.height
	wgpu.SurfaceConfigure(gfx.surface, &gfx.surface_config)
}

init_graphics :: proc(gfx: ^Graphics, window: glfw.WindowHandle, sample_count: int) {

	width, height := glfw.GetWindowSize(window)
	gfx.width, gfx.height = u32(width), u32(height)
	gfx.sample_count = sample_count

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
		gfx.shape_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{label = "ShapeBuffer", size = SHAPE_BUFFER_CAPACITY, usage = {.Storage, .CopyDst}},
		)
		gfx.paint_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{label = "PaintBuffer", size = PAINT_BUFFER_CAPACITY, usage = {.Storage, .CopyDst}},
		)
		gfx.cvs_buffer = wgpu.DeviceCreateBuffer(
			gfx.device,
			&{
				label = "ControlVertexBuffer",
				size = CVS_BUFFER_CAPACITY,
				usage = {.Storage, .CopyDst},
			},
		)
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
				entryCount = 3,
				entries = ([^]wgpu.BindGroupLayoutEntry)(
					&[?]wgpu.BindGroupLayoutEntry {
						{
							binding = 0,
							buffer = wgpu.BufferBindingLayout {
								type = .ReadOnlyStorage,
								minBindingSize = size_of(Shape),
							},
							visibility = {.Fragment},
						},
						{
							binding = 1,
							buffer = wgpu.BufferBindingLayout {
								type = .ReadOnlyStorage,
								minBindingSize = size_of(Paint),
							},
							visibility = {.Fragment},
						},
						{
							binding = 2,
							buffer = wgpu.BufferBindingLayout {
								type = .ReadOnlyStorage,
								minBindingSize = size_of([2]f32),
							},
							visibility = {.Fragment},
						},
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
				entryCount = 3,
				entries = ([^]wgpu.BindGroupEntry)(
					&[?]wgpu.BindGroupEntry {
						{binding = 0, buffer = gfx.shape_buffer, size = SHAPE_BUFFER_CAPACITY},
						{binding = 1, buffer = gfx.paint_buffer, size = PAINT_BUFFER_CAPACITY},
						{binding = 2, buffer = gfx.cvs_buffer, size = CVS_BUFFER_CAPACITY},
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
				multisample = {count = u32(gfx.sample_count), mask = 0xffffffff},
			},
		)
	}
}

uninit_graphics :: proc(gfx: ^Graphics) {
	wgpu.SurfaceRelease(gfx.surface)
	wgpu.BufferRelease(gfx.vertex_buffer)
	wgpu.BufferRelease(gfx.index_buffer)
	wgpu.BufferRelease(gfx.shape_buffer)
	wgpu.BufferRelease(gfx.paint_buffer)
	wgpu.BufferRelease(gfx.cvs_buffer)
	wgpu.AdapterRelease(gfx.adapter)
	wgpu.QueueRelease(gfx.queue)
	wgpu.RenderPipelineRelease(gfx.pipeline)
	wgpu.DeviceRelease(gfx.device)
}

draw :: proc(gfx: ^Graphics, draw_list: ^Draw_List, draw_calls: []Draw_Call) {
	// Write buffer data
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.vertex_buffer,
		0,
		raw_data(draw_list.vertices),
		len(draw_list.vertices) * size_of(Vertex),
	)
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.index_buffer,
		0,
		raw_data(draw_list.indices),
		len(draw_list.indices) * size_of(u32),
	)

	// Set view bounds
	t := f32(0)
	b := f32(core.view.y)
	l := f32(0)
	r := f32(core.view.x)
	n := f32(1000)
	f := f32(-1000)

	uniform := Shader_Uniforms {
		proj_mtx = linalg.matrix_ortho3d(l, r, b, t, n, f),
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
	wgpu.RenderPassEncoderSetVertexBuffer(
		rpass,
		0,
		gfx.vertex_buffer,
		0,
		u64(len(draw_list.vertices) * size_of(Vertex)),
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		rpass,
		gfx.index_buffer,
		.Uint32,
		0,
		u64(len(draw_list.indices) * size_of(u32)),
	)

	wgpu.RenderPassEncoderSetBindGroup(rpass, 0, gfx.uniform_bind_group)
	wgpu.RenderPassEncoderSetBindGroup(rpass, 2, gfx.storage_bind_group)

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

	// Apply projection matrix
	wgpu.QueueWriteBuffer(gfx.queue, gfx.uniform_buffer, 0, &uniform, size_of(uniform))
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.shape_buffer,
		0,
		raw_data(core.draw_list.shapes),
		size_of(Shape) * len(core.draw_list.shapes),
	)
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.paint_buffer,
		0,
		raw_data(core.draw_list.paints),
		size_of(Paint) * len(core.draw_list.paints),
	)
	wgpu.QueueWriteBuffer(
		gfx.queue,
		gfx.cvs_buffer,
		0,
		raw_data(core.draw_list.cvs),
		size_of([2]f32) * len(core.draw_list.cvs),
	)

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
				magFilter = .Nearest,
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
