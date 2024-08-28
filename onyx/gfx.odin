package onyx

import "core:fmt"
import "core:mem"
import "core:math"
import "core:math/linalg"
import "core:slice"
import "core:thread"

import "base:runtime"
import "vendor:wgpu"
import "vendor:wgpu/glfwglue"
import "vendor:glfw"
import "core:sys/windows"

Shader_Uniform :: struct {
	proj_mtx: matrix[4, 4]f32,
}

Graphics :: struct {
	instance: wgpu.Instance,
	adapter: wgpu.Adapter,
	pipeline: wgpu.RenderPipeline,
	surface: wgpu.Surface,
	device: wgpu.Device,
	queue: wgpu.Queue,
	config: wgpu.SurfaceConfiguration,

	texture_bind_group_layout: wgpu.BindGroupLayout,

	waiting: bool,

	uniform_buffer,
	vertex_buffer,
	index_buffer: wgpu.Buffer,
}

init_graphics :: proc(gfx: ^Graphics, window: glfw.WindowHandle) {

	gfx.instance = wgpu.CreateInstance()

	// gfx.surface = wgpu.InstanceCreateSurface(
	// 	gfx.instance, 
	// 	&{
	// 		nextInChain = &wgpu.SurfaceDescriptorFromWindowsHWND{
	// 			chain = {
	// 				sType = .SurfaceDescriptorFromWindowsHWND,
	// 			},
	// 			hinstance = windows.GetModuleHandleA(nil),
	// 			hwnd = glfw.GetWin32Window(window),
	// 		},
	// 	})
	gfx.surface = glfwglue.GetSurface(gfx.instance, window)
	fmt.println("Created surface")

	adapters := wgpu.InstanceEnumerateAdapters(gfx.instance)
	defer delete(adapters)
	fmt.println("Enumerated adapters")

	gfx.waiting = true
	wgpu.InstanceRequestAdapter(
		gfx.instance, 
		&wgpu.RequestAdapterOptions{
			compatibleSurface = gfx.surface,
		},
		proc "c" (status: wgpu.RequestAdapterStatus, adapter: wgpu.Adapter, message: cstring, userdata: rawptr) {
			context = runtime.default_context()
			gfx := transmute(^Graphics)userdata
			#partial switch status {
			case .Success:
				gfx.adapter = adapter
			case:
				fmt.println(status, message)
			}
			gfx.waiting = false
		},
		gfx)
	for gfx.waiting {}

	adapter_properties := wgpu.AdapterGetProperties(gfx.adapter)
	fmt.printf(
`Suitable adapter found:
	Device name: %s
	Driver version: %s
	Backend type: %v
`,
		adapter_properties.name,
		adapter_properties.backendType,
		adapter_properties.driverDescription,
		)

	gfx.waiting = true
	wgpu.AdapterRequestDevice(
		gfx.adapter, 
		&{}, 
		proc "c" (status: wgpu.RequestDeviceStatus, device: wgpu.Device, message: cstring, userdata: rawptr) {
			context = runtime.default_context()
			gfx := transmute(^Graphics)userdata
			#partial switch status {
			case .Success:
				gfx.device = device
			case:
				fmt.println(status, message)
			}
			gfx.waiting = false
		}, 
		gfx)
	for gfx.waiting {}

	// Create buffers
	gfx.uniform_buffer = wgpu.DeviceCreateBuffer(gfx.device, &{
		label = "UniformBuffer",
		size = size_of(Shader_Uniform),
		usage = {.Uniform, .CopyDst},
	})
	gfx.vertex_buffer = wgpu.DeviceCreateBuffer(gfx.device, &{
		label = "VertexBuffer",
		size = BUFFER_SIZE,
		usage = {.Vertex},
	})
	gfx.index_buffer = wgpu.DeviceCreateBuffer(gfx.device, &{
		label = "IndexBuffer",
		size = BUFFER_SIZE,
		usage = {.Index},
	})

	// Create bind group layouts
	uniform_bind_group_layout := wgpu.DeviceCreateBindGroupLayout(gfx.device, &{
		label = "UniformBindGroupLayout",
		entryCount = 1,
		entries = &wgpu.BindGroupLayoutEntry{
			binding = 0,
			buffer = wgpu.BufferBindingLayout{
				type = .Uniform,
			},
			visibility = {.Vertex},
		}
	})
	fmt.println("Created uniform_bind_group_layout")
	gfx.texture_bind_group_layout = wgpu.DeviceCreateBindGroupLayout(gfx.device, &{
		label = "TextureBindGroupLayout",
		entryCount = 2,
		entries = transmute([^]wgpu.BindGroupLayoutEntry)&[?]wgpu.BindGroupLayoutEntry{
			{
				binding = 0,
				texture = wgpu.TextureBindingLayout{
					sampleType = .Uint,
					viewDimension = ._2D,
				},
				visibility = {.Fragment},
			},
			{
				binding = 1,
				sampler = wgpu.SamplerBindingLayout{
					type = .Filtering,
				},
				visibility = {.Fragment},
			},
		}
	})
	fmt.println("Created texture_bind_group_layout")

	// Create bind group
	// 	Requires: uniform_buffer
	uniform_bind_group := wgpu.DeviceCreateBindGroup(gfx.device, &wgpu.BindGroupDescriptor{
		layout = uniform_bind_group_layout,
		entryCount = 1,
		entries = &wgpu.BindGroupEntry{
			binding = 0,
			buffer = gfx.uniform_buffer,
			size = 1,
		}
	})
	fmt.println("Created uniform_bind_group")

	// Create pipeline layout
	pipeline_layout := wgpu.DeviceCreatePipelineLayout(gfx.device, &{
		label = "PipelineLayout",
		bindGroupLayoutCount = 2,
		bindGroupLayouts = transmute([^]wgpu.BindGroupLayout)&[?]wgpu.BindGroupLayout{uniform_bind_group_layout, gfx.texture_bind_group_layout}
	})
	fmt.println("Created pipeline_layout")

	module := wgpu.DeviceCreateShaderModule(gfx.device, &wgpu.ShaderModuleDescriptor{
		nextInChain = &wgpu.ShaderModuleWGSLDescriptor{
			sType = .ShaderModuleWGSLDescriptor,
			code = #load("shader.wgsl"),
		},
	})
	fmt.println("Created module")

	gfx.pipeline = wgpu.DeviceCreateRenderPipeline(gfx.device, &{
		label = "RenderPipeline",
		vertex = wgpu.VertexState{
			entryPoint = "vs_main",
			module = module,
			buffers = &wgpu.VertexBufferLayout{
				arrayStride = size_of(Vertex),
				stepMode = .Vertex,
				attributeCount = 3,
				attributes = transmute([^]wgpu.VertexAttribute)&[?]wgpu.VertexAttribute{
					{
						format = .Float32x2,
						shaderLocation = 0,
					},
					{
						format = .Float32x2,
						shaderLocation = 1,
					},
					{
						format = .Float32x4,
						shaderLocation = 2,
					},
				},
			},
		},
		primitive = {
			topology = .TriangleList,
			cullMode = .Back,
		},
		multisample = {
			count = 4,
			mask = 0xffffffff,
		},
		fragment = &{
			module = module,
			entryPoint = "fs_main",
			targets = &wgpu.ColorTargetState{
				format = .RGBA8Uint,
				writeMask = wgpu.ColorWriteMaskFlags_All,
				blend = &{
					color = {
						srcFactor = .One,
						dstFactor = .OneMinusSrcAlpha,
						operation = .Add,
					},
					alpha = {
						srcFactor = .OneMinusDstAlpha,
						dstFactor = .One,
						operation = .Add,
					},
				}
			}
		}
	})
}

draw :: proc(gfx: ^Graphics, draw_list: ^Draw_List, draw_calls: []Draw_Call) {
	// UPDATE BUFFERS
	wgpu.QueueWriteBuffer(gfx.queue, gfx.vertex_buffer, 0, raw_data(draw_list.vertices), len(draw_list.vertices) * size_of(Vertex))
	wgpu.QueueWriteBuffer(gfx.queue, gfx.index_buffer, 0, raw_data(draw_list.indices), len(draw_list.indices) * size_of(u32))
	

	// Set view bounds
	t := f32(0)
	b := f32(core.view.y)
	l := f32(0)
	r := f32(core.view.x)
	n := f32(1000)
	f := f32(-1000)

	uniform := Shader_Uniform{
		proj_mtx = linalg.matrix_ortho3d(l, r, b, t, n, f),
	}

	// Apply projection matrix
	wgpu.QueueWriteBuffer(gfx.queue, gfx.uniform_buffer, 0, &uniform, size_of(uniform))
	
	// Sort draw calls by index
	slice.sort_by(core.draw_calls[:core.draw_call_count], proc(i, j: Draw_Call) -> bool {
		return i.index < j.index
	})
	encoder := wgpu.DeviceCreateCommandEncoder(gfx.device)
	pass := wgpu.CommandEncoderBeginRenderPass(
		encoder, 
		&{
			colorAttachments = transmute([^]wgpu.RenderPassColorAttachment)&[?]wgpu.RenderPassColorAttachment{
				{
					loadOp = .Clear,
					storeOp = .Store,
					clearValue = {0, 0, 0, 1},
				}
			}
		})
	// Render them
	for &call in core.draw_calls[:core.draw_call_count] {
		if call.elem_count == 0 {
			continue
		}
		wgpu.RenderPassEncoderSetScissorRect(
			pass,
			u32(call.clip_box.lo.x),
			u32(call.clip_box.lo.y),
			u32(call.clip_box.hi.x - call.clip_box.lo.x),
			u32(call.clip_box.hi.y - call.clip_box.lo.y))
		wgpu.RenderPassEncoderDrawIndexedIndirect(
			pass, 
			gfx.index_buffer, 
			cast(u64)call.elem_offset)
	}
	wgpu.RenderPassEncoderRelease(pass)
	wgpu.CommandEncoderRelease(encoder)
}