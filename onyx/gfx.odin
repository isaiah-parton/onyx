package onyx

import "core:fmt"
import "core:math"
import "core:math/linalg"
import "core:mem"
import "core:slice"
import "core:thread"

import "base:runtime"
import "core:sys/windows"
import "vendor:glfw"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"

Shader_Uniforms :: struct {
	proj_mtx: matrix[4, 4]f32,
}

Graphics :: struct {
	width, height:                               u32,
	instance:                                    wgpu.Instance,
	adapter:                                     wgpu.Adapter,
	pipeline:                                    wgpu.RenderPipeline,
	surface:                                     wgpu.Surface,
	device:                                      wgpu.Device,
	queue:                                       wgpu.Queue,
	config:                                      wgpu.SurfaceConfiguration,
	uniform_bind_group, texture_bind_group:      wgpu.BindGroup,
	texture_bind_group_layout:                   wgpu.BindGroupLayout,
	waiting:                                     bool,
	uniform_buffer, vertex_buffer, index_buffer: wgpu.Buffer,
	surface_config:                              wgpu.SurfaceConfiguration,
	msaa_texture:                                wgpu.Texture,
}

resize_graphics :: proc(gfx: ^Graphics, width, height: int) {
	gfx.width = u32(width)
	gfx.height = u32(height)
	gfx.surface_config.width = gfx.width
	gfx.surface_config.height = gfx.height
	wgpu.SurfaceConfigure(gfx.surface, &gfx.surface_config)
	wgpu.TextureDestroy(gfx.msaa_texture)
	wgpu.TextureRelease(gfx.msaa_texture)
	gfx.msaa_texture = wgpu.DeviceCreateTexture(
		gfx.device,
		&{
			sampleCount = 4,
			format = gfx.surface_config.format,
			usage = {.RenderAttachment},
			dimension = ._2D,
			mipLevelCount = 1,
			size = {gfx.width, gfx.height, 1},
		},
	)
}

init_graphics :: proc(gfx: ^Graphics, window: glfw.WindowHandle) {

	width, height := glfw.GetWindowSize(window)
	gfx.width, gfx.height = u32(width), u32(height)

	// &{
	// 		nextInChain = &wgpu.InstanceExtras {
	// 			sType = .InstanceExtras,
	// 			backends = {.GL},
	// 			flags = {.Debug},
	// 		},
	// 	},
	// }
	gfx.instance = wgpu.CreateInstance()
	gfx.surface = glfwglue.GetSurface(gfx.instance, window)

	// adapters := wgpu.InstanceEnumerateAdapters(gfx.instance)
	// defer delete(adapters)

	gfx.waiting = true
	wgpu.InstanceRequestAdapter(gfx.instance, &{compatibleSurface = gfx.surface}, on_adapter, gfx)

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
		gfx.adapter = adapter
		wgpu.AdapterRequestDevice(adapter, &{}, on_device, gfx)
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

		gfx.device = device

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


		// Create MSAA Texture
		gfx.msaa_texture = wgpu.DeviceCreateTexture(
			gfx.device,
			&{
				sampleCount = 4,
				format = gfx.surface_config.format,
				usage = {.RenderAttachment},
				dimension = ._2D,
				mipLevelCount = 1,
				size = {u32(gfx.width), u32(gfx.height), 1},
			},
		)

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
				entryCount = 2,
				entries = transmute([^]wgpu.BindGroupLayoutEntry)&[?]wgpu.BindGroupLayoutEntry {
					{binding = 0, sampler = {type = .Filtering}, visibility = {.Fragment}},
					{
						binding = 1,
						texture = {sampleType = .Float, viewDimension = ._2D},
						visibility = {.Fragment},
					},
				},
			},
		)

		// Create bind group
		// 	Requires: uniform_buffer
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

		// Create pipeline layout
		pipeline_layout := wgpu.DeviceCreatePipelineLayout(
			gfx.device,
			&{
				label = "PipelineLayout",
				bindGroupLayoutCount = 2,
				bindGroupLayouts = transmute([^]wgpu.BindGroupLayout)&[?]wgpu.BindGroupLayout {
					uniform_bind_group_layout,
					gfx.texture_bind_group_layout,
				},
			},
		)
		module := wgpu.DeviceCreateShaderModule(
			gfx.device,
			&wgpu.ShaderModuleDescriptor {
				nextInChain = &wgpu.ShaderModuleWGSLDescriptor {
					sType = .ShaderModuleWGSLDescriptor,
					code = #load("shader.wgsl", cstring),
				},
			},
		)

		vertex_attributes := [?]wgpu.VertexAttribute {
			{format = .Float32x2, offset = u64(offset_of(Vertex, pos)), shaderLocation = 0},
			{format = .Float32x2, offset = u64(offset_of(Vertex, uv)), shaderLocation = 1},
			{format = .Unorm8x4, offset = u64(offset_of(Vertex, col)), shaderLocation = 2},
		}

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
				multisample = {count = 4, mask = 0xffffffff},
			},
		)
	}
}

draw :: proc(gfx: ^Graphics, draw_list: ^Draw_List, draw_calls: []Draw_Call) {
	// UPDATE BUFFERS
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
	slice.sort_by(core.draw_calls[:core.draw_call_count], proc(i, j: Draw_Call) -> bool {
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

	msaa_view := wgpu.TextureCreateView(gfx.msaa_texture, nil)
	defer wgpu.TextureViewRelease(msaa_view)

	surface_view := wgpu.TextureCreateView(surface_texture.texture, nil)
	defer wgpu.TextureViewRelease(surface_view)

	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder,
		&{
			colorAttachmentCount = 1,
			colorAttachments = &wgpu.RenderPassColorAttachment {
				view = msaa_view,
				resolveTarget = surface_view,
				loadOp = .Clear,
				storeOp = .Store,
				clearValue = {0, 0, 0, 0},
			},
		},
	)
	wgpu.RenderPassEncoderSetPipeline(pass, gfx.pipeline)
	wgpu.RenderPassEncoderSetVertexBuffer(
		pass,
		0,
		gfx.vertex_buffer,
		0,
		u64(len(draw_list.vertices) * size_of(Vertex)),
	)
	wgpu.RenderPassEncoderSetIndexBuffer(
		pass,
		gfx.index_buffer,
		.Uint32,
		0,
		u64(len(draw_list.indices) * size_of(u32)),
	)
	wgpu.RenderPassEncoderSetBindGroup(pass, 0, gfx.uniform_bind_group)
	wgpu.RenderPassEncoderSetViewport(pass, 0, 0, core.view.x, core.view.y, 0, 0)

	// Apply projection matrix
	wgpu.QueueWriteBuffer(gfx.queue, gfx.uniform_buffer, 0, &uniform, size_of(uniform))

	// Render them
	for &call in core.draw_calls[:core.draw_call_count] {
		if call.elem_count == 0 ||
		   call.clip_box.hi.x <= call.clip_box.lo.x ||
		   call.clip_box.hi.y <= call.clip_box.lo.y {
			continue
		}

		texture_view := wgpu.TextureCreateView(call.texture)
		defer wgpu.TextureViewRelease(texture_view)

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

		texture_bind_group := wgpu.DeviceCreateBindGroup(
			gfx.device,
			&{
				label = "TextureBindGroup",
				layout = gfx.texture_bind_group_layout,
				entryCount = 2,
				entries = transmute([^]wgpu.BindGroupEntry)&[?]wgpu.BindGroupEntry {
					{binding = 0, sampler = sampler},
					{binding = 1, textureView = texture_view},
				},
			},
		)
		wgpu.RenderPassEncoderSetBindGroup(pass, 1, texture_bind_group)

		wgpu.RenderPassEncoderSetScissorRect(
			pass,
			u32(call.clip_box.lo.x),
			u32(call.clip_box.lo.y),
			u32(call.clip_box.hi.x - call.clip_box.lo.x),
			u32(call.clip_box.hi.y - call.clip_box.lo.y),
		)
		wgpu.RenderPassEncoderDrawIndexed(
			pass,
			u32(call.elem_count),
			1,
			u32(call.elem_offset),
			0,
			0,
		)
	}
	wgpu.RenderPassEncoderEnd(pass)
	wgpu.RenderPassEncoderRelease(pass)

	command_buffer := wgpu.CommandEncoderFinish(encoder)
	defer wgpu.CommandBufferRelease(command_buffer)

	wgpu.QueueSubmit(gfx.queue, {command_buffer})
	wgpu.SurfacePresent(gfx.surface)
}
