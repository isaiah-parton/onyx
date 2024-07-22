package nanovg_sokol

import "core:log"
import "core:strings"
import "core:mem"
import "core:slice"
import "core:math"
import "core:fmt"
import sg "../../../sokol-odin/sokol/gfx"
import nvg "../"

Color :: nvg.Color
Vertex :: nvg.Vertex
ImageFlags :: nvg.ImageFlags
TextureType :: nvg.Texture
Paint :: nvg.Paint
ScissorT :: nvg.ScissorT

Create_Flag :: enum {
	// Flag indicating if geometry based anti-aliasing is used (may not be needed when using MSAA).
	ANTI_ALIAS,
	// Flag indicating if strokes should be drawn using stencil buffer. The rendering will be a little
	// slower, but path overlaps (i.e. self-intersecting or sharp turns) will be drawn just once.
	STENCIL_STROKES,
	// additional debug checks
	DEBUG,
}
Create_Flags :: bit_set[Create_Flag]

USE_STATE_FILTER :: #config(USE_STATE_FILTER, true)

UniformLoc :: enum {
	VIEW_SIZE,
	TEX,
	FRAG,
}

ShaderType :: enum i32 {
	FILL_GRAD,
	FILL_IMG,
	SIMPLE,
	IMG,
}

Shader :: struct {
	prog: u32,
	frag: u32,
	vert: u32,
	loc: [UniformLoc]i32,
}

Texture :: struct {
	id: int,
	image: sg.Image,
	sampler: sg.Sampler,
	data: []u8,
	width, height: int,
	type: TextureType,
	flags: ImageFlags,
}

Blend :: struct {
	src_RGB: u32,
	dst_RGB: u32,
	src_alpha: u32,
	dst_alpha: u32,
}

CallType :: enum {
	NONE,
	FILL,
	CONVEX_FILL,
	STROKE,
	TRIANGLES,
}

Call :: struct {
	type: CallType,
	image: int,
	pathOffset: int,
	pathCount: int,
	triangleOffset: int,
	triangleCount: int,
	uniformOffset: int,
	blendFunc: Blend,
}

Path :: struct {
	fillOffset: int,
	fillCount: int,
	strokeOffset: int,
	strokeCount: int,
}

Context :: struct {
	pipeline: sg.Pipeline,
	bindings: sg.Bindings,
	textures: [dynamic]Texture,
	view: [2]f32,
	image_id: int,

	vertBuf: u32,
	vertArr: u32, // GL3
	fragBuf: u32, // USE_UNIFORMBUFFER
	fragSize: int,
	flags: Create_Flags,
	frag_binding: u32,

	// Per frame buffers
	calls: [dynamic]Call,
	paths: [dynamic]Path,
	verts: [dynamic]Vertex,
	uniforms: [dynamic]byte,

	// cached state used for state filter
	boundTexture: u32,
	stencilMask: u32,
	stencilFunc: u32,
	stencilFuncRef: i32,
	stencilFuncMask: u32,
	blendFunc: Blend,

	dummyTex: int,
}

__nearestPow2 :: proc(num: uint) -> uint {
	n := num > 0 ? num - 1 : 0
	n |= n >> 1
	n |= n >> 2
	n |= n >> 4
	n |= n >> 8
	n |= n >> 16
	n += 1
	return n
}

__bindTexture :: proc(ctx: ^Context, tex: u32) {
	when USE_STATE_FILTER {
		if ctx.boundTexture != tex {
			ctx.boundTexture = tex
			gl.BindTexture(gl.TEXTURE_2D, tex)
		}
	} else {
		gl.BindTexture(gl.TEXTURE_2D, tex)
	}
}

__stencilMask :: proc(ctx: ^Context, mask: u32) {
	when USE_STATE_FILTER {
		if ctx.stencilMask != mask {
			ctx.stencilMask = mask
			gl.StencilMask(mask)
		}
	} else {
		gl.StencilMask(mask)
	}
}

__stencilFunc :: proc(ctx: ^Context, func: u32, ref: i32, mask: u32) {
	when USE_STATE_FILTER {
		if ctx.stencilFunc != func ||
			ctx.stencilFuncRef != ref ||
			ctx.stencilFuncMask != mask {
			ctx.stencilFunc = func
			ctx.stencilFuncRef = ref
			ctx.stencilFuncMask = mask
			gl.StencilFunc(func, ref, mask)
		}
	} else {
		gl.StencilFunc(func, ref, mask)
	}
}

__blendFuncSeparate :: proc(ctx: ^Context, blend: ^Blend) {
	when USE_STATE_FILTER {
		if ctx.blendFunc != blend^ {
			ctx.blendFunc = blend^
			gl.BlendFuncSeparate(blend.src_RGB, blend.dst_RGB, blend.src_alpha, blend.dst_alpha)
		}
	} else {
		gl.BlendFuncSeparate(blend.src_RGB, blend.dst_RGB, blend.src_alpha, blend.dst_alpha)
	}
}

__allocTexture :: proc(ctx: ^Context) -> (tex: ^Texture) {
	for &texture in ctx.textures {
		if texture.id == 0 {
			tex = &texture
			break
		}
	}

	if tex == nil {
		append(&ctx.textures, Texture{})
		tex = &ctx.textures[len(ctx.textures) - 1]
	}

	tex^ = {}
	ctx.textureId += 1
	tex.id = ctx.textureId

	return
}

__findTexture :: proc(ctx: ^Context, id: int) -> ^Texture {
	for &texture in ctx.textures {
		if texture.id == id {
			return &texture
		}
	}

	return nil
}

__deleteTexture :: proc(ctx: ^Context, id: int) -> bool {
	for &texture, i in ctx.textures {
		if texture.id == id {
			if texture.image != {} && (.NO_DELETE not_in texture.flags) {
				sg.destroy_image(texture.image)
				sg.destroy_sampler(texture.sampler)
				delete(texture.data)
			}

			ctx.textures[i] = {}
			return true
		}
	}

	return false
}

__getUniforms :: proc(shader: ^Shader) {
	shader.loc[.VIEW_SIZE] = gl.GetUniformLocation(shader.prog, "viewSize")
	shader.loc[.TEX] = gl.GetUniformLocation(shader.prog, "tex")
	
	when GL_USE_UNIFORMBUFFER {
		shader.loc[.FRAG] = i32(gl.GetUniformBlockIndex(shader.prog, "frag"))
	} else {
		shader.loc[.FRAG] = gl.GetUniformLocation(shader.prog, "frag")
	}
}

__renderCreate :: proc(uptr: rawptr) -> bool {
	ctx := cast(^Context) uptr

	ctx.pipeline = sg.make_pipeline(sg.Pipeline_Desc{
		shader = sg.make_shader(ui_shader_desc(sg.query_backend())),
		layout = {
			attrs = {
				0 = { offset = i32(offset_of(Vertex, pos)), format = .FLOAT2 },
				1 = { offset = i32(offset_of(Vertex, uv)), format = .FLOAT2 },
			},
			buffers = {
				0 = { stride = size_of(Vertex) },
			},
		},
		colors = {
			0 = {
				pixel_format = sg.Pixel_Format.RGBA8,
				write_mask = sg.Color_Mask.RGBA,
				blend = {
					enabled = true,
					src_factor_rgb = sg.Blend_Factor.SRC_ALPHA,
					dst_factor_rgb = sg.Blend_Factor.ONE_MINUS_SRC_ALPHA,
				},
			},
		},
		stencil = sg.Stencil_State{
			read_mask = 0xffffffff,
			write_mask = 0xffffffff,
			enabled = true,
			front = sg.Stencil_Face_State{
				compare_func = .ALWAYS,
				fail_op = .KEEP,
				pass_op = .KEEP,
				depth_fail_op = .KEEP,
			},
		},
		cull_mode = .BACK,
		label = "pipeline",
	})

	ctx.bindings.vertex_buffers[0] = sg.make_buffer(sg.Buffer_Desc{
		size = size_of(Vertex),
		usage = .STREAM,
	})
	align := i32(4)

	ctx.fragSize = int(size_of(FragUniforms) + align - size_of(FragUniforms) % align)
	// ctx.fragSize = size_of(FragUniforms)
	ctx.dummyTex = __renderCreateTexture(ctx, .Alpha, 1, 1, {}, nil)



	return true
}

__renderCreateTexture :: proc(
	uptr: rawptr, 
	type: TextureType, 
	w, h: int, 
	imageFlags: ImageFlags,
	data: []byte,
) -> int {
	ctx := cast(^Context) uptr
	tex := __allocTexture(ctx)
	imageFlags := imageFlags

	if tex == nil {
		return 0
	}

	tex.width = w
	tex.height = h
	tex.type = type
	tex.flags = imageFlags
	tex.data = slice.clone(data)
	image_desc := sg.Image_Desc{
		width = i32(w),
		height = i32(h),
		data = sg.Image_Data{
			subimage = {
				0 = {
					0 = {
						ptr = raw_data(data),
						size = u64(len(data)),
					},
				},
			},
		},
	}
	switch type {
		case .Alpha:
		image_desc.pixel_format = .R8
		case .RGBA:
		image_desc.pixel_format = .RGBA8
	}

	tex.image = sg.make_image(image_desc)

	sampler_desc: sg.Sampler_Desc

	if .GENERATE_MIPMAPS in imageFlags {
		if .NEAREST in imageFlags {
			sampler_desc.mipmap_filter = .NEAREST
		} else {
			sampler_desc.mipmap_filter = .LINEAR
		}
	} else {
		if .NEAREST in imageFlags {
			sampler_desc.min_filter = .NEAREST
		} else {
			sampler_desc.min_filter = .LINEAR
		}
	}

	if .NEAREST in imageFlags {
		sampler_desc.mag_filter = .NEAREST
	} else {
		sampler_desc.mag_filter = .LINEAR
	}

	if .REPEAT_X in imageFlags {
		sampler_desc.wrap_u = .REPEAT
	}	else {
		sampler_desc.wrap_u = .CLAMP_TO_BORDER
	}

	if .REPEAT_Y in imageFlags {
		sampler_desc.wrap_v = .REPEAT
	}	else {
		sampler_desc.wrap_v = .CLAMP_TO_BORDER
	}

	tex.sampler = sg.make_sampler(sampler_desc)

	return tex.id
}

__renderDeleteTexture :: proc(uptr: rawptr, image: int) -> bool {
	ctx := cast(^Context) uptr
	return __deleteTexture(ctx, image)
}

__renderUpdateTexture :: proc(
	uptr: rawptr, 
	image: int,
	x, y: int,
	w, h: int,
	data: []byte,
) -> bool {
	ctx := cast(^Context) uptr
	tex := __findTexture(ctx, image)

	if tex == nil {
		return false
	}

	for row in 0..<h {
		copy(tex.data[(y + row) * tex.width + x:], data[row * tex.width:][:w])
	}

	sg.update_image(tex.image, sg.Image_Data{
		subimage = {
			0 = {
				0 = {
					ptr = raw_data(tex.data),
					size = u64(len(tex.data)),
				},
			},
		},
	})

	return true
}

__renderGetTextureSize :: proc(uptr: rawptr, image: int, w, h: ^int) -> bool {
	ctx := cast(^Context) uptr
	tex := __findTexture(ctx, image)

	if tex == nil {
		return false
	}

	w^ = tex.width
	h^ = tex.height
	return true
}

__xformToMat3x4 :: proc(m3: ^[12]f32, t: [6]f32) {
	m3[0] = t[0]
	m3[1] = t[1]
	m3[2] = 0
	m3[3] = 0
	m3[4] = t[2]
	m3[5] = t[3]
	m3[6] = 0
	m3[7] = 0
	m3[8] = t[4]
	m3[9] = t[5]
	m3[10] = 1
	m3[11] = 0
}

__premulColor :: proc(c: Color) -> (res: Color) {
	res = c
	res.r *= c.a
	res.g *= c.a
	res.b *= c.a
	return
}

__convertPaint :: proc(
	ctx: ^Context,
	frag: ^FragUniforms,
	paint: ^Paint,
	scissor: ^ScissorT,
	width: f32,
	fringe: f32,
	strokeThr: f32,
) -> bool {
	invxform: [6]f32
	frag^ = {}
	frag.innerColor = __premulColor(paint.innerColor)
	frag.outerColor = __premulColor(paint.outerColor)

	if scissor.extent[0] < -0.5 || scissor.extent[1] < -0.5 {
		frag.scissorMat = {}
		frag.scissorExt[0] = 1.0
		frag.scissorExt[1] = 1.0
		frag.scissorScale[0] = 1.0
		frag.scissorScale[1] = 1.0
	} else {
		nvg.TransformInverse(&invxform, scissor.xform)
		__xformToMat3x4(&frag.scissorMat, invxform)
		frag.scissorExt[0] = scissor.extent[0]
		frag.scissorExt[1] = scissor.extent[1]
		frag.scissorScale[0] = math.sqrt(scissor.xform[0]*scissor.xform[0] + scissor.xform[2]*scissor.xform[2]) / fringe
		frag.scissorScale[1] = math.sqrt(scissor.xform[1]*scissor.xform[1] + scissor.xform[3]*scissor.xform[3]) / fringe
	}

	frag.extent = paint.extent
	frag.strokeMult = (width * 0.5 + fringe * 0.5) / fringe
	frag.strokeThr = strokeThr

	if paint.image != 0 {
		tex := __findTexture(ctx, paint.image)
		
		if tex == nil {
			return false
		}
		
		// TODO maybe inversed?
		if .FLIP_Y in tex.flags {
			m1: [6]f32
			m2: [6]f32
			nvg.TransformTranslate(&m1, 0.0, frag.extent[1] * 0.5)
			nvg.TransformMultiply(&m1, paint.xform)
			nvg.TransformScale(&m2, 1.0, -1.0)
			nvg.TransformMultiply(&m2, m1)
			nvg.TransformTranslate(&m1, 0.0, -frag.extent[1] * 0.5)
			nvg.TransformMultiply(&m1, m2)
			nvg.TransformInverse(&invxform, m1)
		} else {
			nvg.TransformInverse(&invxform, paint.xform)
		}

		frag.type = .FILL_IMG

		when GL_USE_UNIFORMBUFFER {
			if tex.type == .RGBA {
				frag.texType = (.PREMULTIPLIED in tex.flags) ? 0 : 1
			}	else {
				frag.texType = 2
			}
		} else {
			if tex.type == .RGBA {
				frag.texType = (.PREMULTIPLIED in tex.flags) ? 0.0 : 1.0
			}	else {
				frag.texType = 2.0
			}
		}
	} else {
		frag.type = .FILL_GRAD
		frag.radius = paint.radius
		frag.feather = paint.feather
		nvg.TransformInverse(&invxform, paint.xform)
	}

	__xformToMat3x4(&frag.paintMat, invxform)

	return true
}

__setUniforms :: proc(ctx: ^Context, uniformOffset: int, image: int) {

		frag := __fragUniformPtr(ctx, uniformOffset)
		gl.Uniform4fv(ctx.shader.loc[.FRAG], GL_UNIFORMARRAY_SIZE, cast(^f32) frag)

	tex: ^Texture
	if image != 0 {
		tex = __findTexture(ctx, image)
	}
	
	// If no image is set, use empty texture
	if tex == nil {
		tex = __findTexture(ctx, ctx.dummyTex)
	}

}

__renderViewport :: proc(uptr: rawptr, width, height, devicePixelRatio: f32) {
	ctx := cast(^Context) uptr
	ctx.view[0] = width
	ctx.view[1] = height
}

__fill :: proc(ctx: ^Context, call: ^Call) {
	paths := ctx.paths[call.pathOffset:]

	sg.draw(i32(call.triangleOffset), i32(call.triangleCount), 0)
	ctx.pipeline.stencil.enabled = true

	// Draw shapes
	gl.Enable(gl.STENCIL_TEST)
	__stencilMask(ctx, 0xff)
	__stencilFunc(ctx, gl.ALWAYS, 0, 0xff)
	gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE)

	// set bindpoint for solid loc
	__setUniforms(ctx, call.uniformOffset, 0)

	gl.StencilOpSeparate(gl.FRONT, gl.KEEP, gl.KEEP, gl.INCR_WRAP)
	gl.StencilOpSeparate(gl.BACK, gl.KEEP, gl.KEEP, gl.DECR_WRAP)
	gl.Disable(gl.CULL_FACE)
	for i in 0..<call.pathCount {
		gl.DrawArrays(gl.TRIANGLE_FAN, i32(paths[i].fillOffset), i32(paths[i].fillCount))
	}
	gl.Enable(gl.CULL_FACE)

	// Draw anti-aliased pixels
	gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE)

	__setUniforms(ctx, call.uniformOffset + ctx.fragSize, call.image)
	__checkError(ctx, "fill fill")

	if .ANTI_ALIAS in ctx.flags {
		__stencilFunc(ctx, gl.EQUAL, 0x00, 0xff)
		gl.StencilOp(gl.KEEP, gl.KEEP, gl.KEEP)
		// Draw fringes
		for i in 0..<call.pathCount {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}
	}

	// Draw fill
	__stencilFunc(ctx, gl.NOTEQUAL, 0x0, 0xff)
	gl.StencilOp(gl.ZERO, gl.ZERO, gl.ZERO)
	gl.DrawArrays(gl.TRIANGLE_STRIP, i32(call.triangleOffset), i32(call.triangleCount))

	gl.Disable(gl.STENCIL_TEST)
}

__convexFill :: proc(ctx: ^Context, call: ^Call) {
	paths := ctx.paths[call.pathOffset:]

	__setUniforms(ctx, call.uniformOffset, call.image)
	__checkError(ctx, "convex fill")

	for i in 0..<call.pathCount {
		gl.DrawArrays(gl.TRIANGLE_FAN, i32(paths[i].fillOffset), i32(paths[i].fillCount))
	
		// draw fringes
		if paths[i].strokeCount > 0 {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}
	}
}

__stroke :: proc(ctx: ^Context, call: ^Call) {
	paths := ctx.paths[call.pathOffset:]

	if .STENCIL_STROKES in ctx.flags {
		gl.Enable(gl.STENCIL_TEST)
		__stencilMask(ctx, 0xff)

		// Fill the stroke base without overlap
		__stencilFunc(ctx, gl.EQUAL, 0x0, 0xff)
		gl.StencilOp(gl.KEEP, gl.KEEP, gl.INCR)
		__setUniforms(ctx, call.uniformOffset + ctx.fragSize, call.image)
		__checkError(ctx, "stroke fill 0")
		
		for i in 0..<call.pathCount {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}

		// Draw anti-aliased pixels.
		__setUniforms(ctx, call.uniformOffset, call.image)
		__stencilFunc(ctx, gl.EQUAL, 0x00, 0xff)
		gl.StencilOp(gl.KEEP, gl.KEEP, gl.KEEP)
		for i in 0..<call.pathCount {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}

		// Clear stencil buffer.
		gl.ColorMask(gl.FALSE, gl.FALSE, gl.FALSE, gl.FALSE)
		__stencilFunc(ctx, gl.ALWAYS, 0x0, 0xff)
		gl.StencilOp(gl.ZERO, gl.ZERO, gl.ZERO)
		__checkError(ctx, "stroke fill 1")
		for i in 0..<call.pathCount {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}
		gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE)

		gl.Disable(gl.STENCIL_TEST)
	} else {
		__setUniforms(ctx, call.uniformOffset, call.image)
		__checkError(ctx, "stroke fill")
		
		// Draw Strokes
		for i in 0..<call.pathCount {
			gl.DrawArrays(gl.TRIANGLE_STRIP, i32(paths[i].strokeOffset), i32(paths[i].strokeCount))
		}
	}
}

__triangles :: proc(ctx: ^Context, call: ^Call) {
	__setUniforms(ctx, call.uniformOffset, call.image)
	__checkError(ctx, "triangles fill")
	gl.DrawArrays(gl.TRIANGLES, i32(call.triangleOffset), i32(call.triangleCount))
}

__renderCancel :: proc(uptr: rawptr) {
	ctx := cast(^Context) uptr
	clear(&ctx.verts)
	clear(&ctx.paths)
	clear(&ctx.calls)
	clear(&ctx.uniforms)
}

BLEND_FACTOR_TABLE :: [nvg.BlendFactor]sg.Blend_Factor {
	.ZERO = .ZERO,
	.ONE = .ONE,
	.SRC_COLOR = .SRC_COLOR,
	.ONE_MINUS_SRC_COLOR = .ONE_MINUS_SRC_COLOR,
	.DST_COLOR = .DST_COLOR,
	.ONE_MINUS_DST_COLOR = .ONE_MINUS_DST_COLOR,
	.SRC_ALPHA = .SRC_ALPHA,
	.ONE_MINUS_SRC_ALPHA = .ONE_MINUS_SRC_ALPHA,
	.DST_ALPHA = .DST_ALPHA,
	.ONE_MINUS_DST_ALPHA = .ONE_MINUS_DST_ALPHA,
	.SRC_ALPHA_SATURATE = .SRC_ALPHA_SATURATED,
}

__blendCompositeOperation :: proc(op: nvg.CompositeOperationState) -> Blend {
	table := BLEND_FACTOR_TABLE
	blend := Blend {
		table[op.srcRGB],
		table[op.dstRGB],
		table[op.srcAlpha],
		table[op.dstAlpha],
	}
	return blend
}

__renderFlush :: proc(uptr: rawptr) {
	ctx := cast(^Context) uptr

	if len(ctx.calls) > 0 {
		sg.apply_pipeline(ctx.pipeline)
		sg.apply_bindings(sg.Bindings{

		})
		sg.apply_uniforms(.FS, 0, {ptr = &ctx.uniforms, size = size_of(Frag)})

		sg.update_buffer(ctx.bindings.vertex_buffers[0], {ptr = raw_data(ctx.verts), size = size_of(Vertex) * len(ctx.verts)})

		gl.Enable(gl.CULL_FACE)
		gl.CullFace(gl.BACK)
		gl.FrontFace(gl.CCW)
		gl.Enable(gl.BLEND)
		gl.Disable(gl.DEPTH_TEST)
		gl.Disable(gl.SCISSOR_TEST)
		gl.ColorMask(gl.TRUE, gl.TRUE, gl.TRUE, gl.TRUE)
		gl.StencilMask(0xffffffff)
		gl.StencilOp(gl.KEEP, gl.KEEP, gl.KEEP)
		gl.StencilFunc(gl.ALWAYS, 0, 0xffffffff)
		gl.ActiveTexture(gl.TEXTURE0)
		gl.BindTexture(gl.TEXTURE_2D, 0)
		
		when USE_STATE_FILTER {
			ctx.boundTexture = 0
			ctx.stencilMask = 0xffffffff
			ctx.stencilFunc = gl.ALWAYS
			ctx.stencilFuncRef = 0
			ctx.stencilFuncMask = 0xffffffff
			ctx.blendFunc.src_RGB = gl.INVALID_ENUM
			ctx.blendFunc.src_alpha = gl.INVALID_ENUM
			ctx.blendFunc.dst_RGB = gl.INVALID_ENUM
			ctx.blendFunc.dst_alpha = gl.INVALID_ENUM
		}

		// Upload vertex data
		when GL3 {
			gl.BindVertexArray(ctx.vertArr)
		}

		gl.BufferData(gl.ARRAY_BUFFER, len(ctx.verts) * size_of(Vertex), raw_data(ctx.verts), gl.STREAM_DRAW)
		gl.EnableVertexAttribArray(0)
		gl.EnableVertexAttribArray(1)
		gl.VertexAttribPointer(0, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), 0)
		gl.VertexAttribPointer(1, 2, gl.FLOAT, gl.FALSE, size_of(Vertex), 2 * size_of(f32))

		// Set view and texture just once per frame.
		gl.Uniform1i(ctx.shader.loc[.TEX], 0)
		gl.Uniform2fv(ctx.shader.loc[.VIEW_SIZE], 1, &ctx.view[0])

		when GL_USE_UNIFORMBUFFER {
			gl.BindBuffer(gl.UNIFORM_BUFFER, ctx.fragBuf)
		}

		for i in 0..<len(ctx.calls) {
			call := &ctx.calls[i]
			__blendFuncSeparate(ctx, &call.blendFunc)

			switch call.type {
			case .NONE: {}
			case .FILL: __fill(ctx, call)
			case .CONVEX_FILL: __convexFill(ctx, call)
			case .STROKE: __stroke(ctx, call)
			case .TRIANGLES: __triangles(ctx, call)
			}
		}

		gl.DisableVertexAttribArray(0)
		gl.DisableVertexAttribArray(1)

		when GL3 {
			gl.BindVertexArray(0)
		}

		gl.Disable(gl.CULL_FACE)
		gl.BindBuffer(gl.ARRAY_BUFFER, 0)
		gl.UseProgram(0)
		__bindTexture(ctx, 0)
	}

	// Reset calls
	clear(&ctx.verts)
	clear(&ctx.paths)
	clear(&ctx.calls)
	clear(&ctx.uniforms)
}

__maxVertCount :: proc(paths: []nvg.Path) -> (count: int) {
	for i in 0..<len(paths) {
		count += len(paths[i].fill)
		count += len(paths[i].stroke)
	}
	return
}

__allocCall :: #force_inline proc(ctx: ^Context) -> ^Call {
	append(&ctx.calls, Call {})
	return &ctx.calls[len(ctx.calls) - 1]
}

// alloc paths and return the original start position
__allocPaths :: proc(ctx: ^Context, count: int) -> int {
	old := len(ctx.paths)
	resize(&ctx.paths, len(ctx.paths) + count)
	return old
}

// alloc verts and return the original start position
__allocVerts :: proc(ctx: ^Context, count: int) -> int {
	old := len(ctx.verts)
	resize(&ctx.verts, len(ctx.verts) + count)
	return old
}

// alloc uniforms and return the original start position
__allocFragUniforms :: proc(ctx: ^Context, count: int) -> int {
	ret := len(ctx.uniforms)
	resize(&ctx.uniforms, len(ctx.uniforms) + count * ctx.fragSize)
	return ret
}

// get frag uniforms from byte slice offset
__fragUniformPtr :: proc(ctx: ^Context, offset: int) -> ^FragUniforms {
	return cast(^FragUniforms) &ctx.uniforms[offset]
}

///////////////////////////////////////////////////////////
// CALLBACKS
///////////////////////////////////////////////////////////

__renderFill :: proc(
	uptr: rawptr, 
	paint: ^nvg.Paint, 
	compositeOperation: nvg.CompositeOperationState, 
	scissor: ^ScissorT,
	fringe: f32,
	bounds: [4]f32,
	paths: []nvg.Path,
) {
	ctx := cast(^Context) uptr
	call := __allocCall(ctx)

	call.type = .FILL
	call.triangleCount = 4
	call.pathOffset = __allocPaths(ctx, len(paths))
	call.pathCount = len(paths)
	call.image = paint.image
	call.blendFunc = __blendCompositeOperation(compositeOperation)

	if len(paths) == 1 && paths[0].convex {
		call.type = .CONVEX_FILL
		call.triangleCount = 0
	}

	// allocate vertices for all the paths
	maxverts := __maxVertCount(paths) + call.triangleCount
	offset := __allocVerts(ctx, maxverts)

	for i in 0..<len(paths) {
		copy := &ctx.paths[call.pathOffset + i]
		copy^ = {}
		path := &paths[i]

		if len(path.fill) > 0 {
			copy.fillOffset = offset
			copy.fillCount = len(path.fill)
			mem.copy(&ctx.verts[offset], &path.fill[0], size_of(Vertex) * len(path.fill))
			offset += len(path.fill)
		}

		if len(path.stroke) > 0 {
			copy.strokeOffset = offset
			copy.strokeCount = len(path.stroke)
			mem.copy(&ctx.verts[offset], &path.stroke[0], size_of(Vertex) * len(path.stroke))
			offset += len(path.stroke)
		}
	}

	// setup uniforms for draw calls
	if call.type == .FILL {
		// quad
		call.triangleOffset = offset
		quad := ctx.verts[call.triangleOffset:call.triangleOffset+4]
		quad[0] = { bounds[2], bounds[3], 0.5, 1 }
		quad[1] = { bounds[2], bounds[1], 0.5, 1 }
		quad[2] = { bounds[0], bounds[3], 0.5, 1 }
		quad[3] = { bounds[0], bounds[1], 0.5, 1 }

		// simple shader for stencil
		call.uniformOffset = __allocFragUniforms(ctx, 2)
		frag := __fragUniformPtr(ctx, call.uniformOffset)
		frag^ = {}
		frag.strokeThr = -1
		frag.type = .SIMPLE

		// fill shader
		__convertPaint(
			ctx, 
			__fragUniformPtr(ctx, call.uniformOffset + ctx.fragSize),
			paint, 
			scissor,
			fringe,
			fringe,
			-1,
		)
	} else {
		call.uniformOffset = __allocFragUniforms(ctx, 1)
		// fill shader
		__convertPaint(
			ctx,
			__fragUniformPtr(ctx, call.uniformOffset),
			paint, 
			scissor,
			fringe,
			fringe,
			-1,
		)
	}
} 

__renderStroke :: proc(
	uptr: rawptr, 
	paint: ^Paint, 
	compositeOperation: nvg.CompositeOperationState, 
	scissor: ^ScissorT,
	fringe: f32,
	strokeWidth: f32,
	paths: []nvg.Path,
) {
	ctx := cast(^Context) uptr
	call := __allocCall(ctx)

	call.type = .STROKE
	call.pathOffset = __allocPaths(ctx, len(paths))
	call.pathCount = len(paths)
	call.image = paint.image
	call.blendFunc = __blendCompositeOperation(compositeOperation)

	// allocate vertices for all the paths
	maxverts := __maxVertCount(paths)
	offset := __allocVerts(ctx, maxverts)

	for i in 0..<len(paths) {
		copy := &ctx.paths[call.pathOffset + i]
		copy^ = {}
		path := &paths[i]

		if len(path.stroke) != 0 {
			copy.strokeOffset = offset
			copy.strokeCount = len(path.stroke)
			mem.copy(&ctx.verts[offset], &path.stroke[0], size_of(Vertex) * len(path.stroke))
			offset += len(path.stroke)
		}
	}

	if .STENCIL_STROKES in ctx.flags {
		// fill shader 
		call.uniformOffset = __allocFragUniforms(ctx, 2)

		__convertPaint(
			ctx,
			__fragUniformPtr(ctx, call.uniformOffset),
			paint,
			scissor,
			strokeWidth,
			fringe,
			-1,
		)

		__convertPaint(
			ctx,
			__fragUniformPtr(ctx, call.uniformOffset + ctx.fragSize),
			paint,
			scissor,
			strokeWidth,
			fringe,
			1 - 0.5 / 255,
		)
	} else {
		// fill shader
		call.uniformOffset = __allocFragUniforms(ctx, 1)
		__convertPaint(
			ctx,
			__fragUniformPtr(ctx, call.uniformOffset),
			paint,
			scissor,
			strokeWidth,
			fringe,
			-1,
		)
	}
}

__renderTriangles :: proc(
	uptr: rawptr, 
	paint: ^Paint, 
	compositeOperation: nvg.CompositeOperationState, 
	scissor: ^ScissorT,
	verts: []Vertex,
	fringe: f32,
) {
	ctx := cast(^Context) uptr
	call := __allocCall(ctx)

	call.type = .TRIANGLES
	call.image = paint.image
	call.blendFunc = __blendCompositeOperation(compositeOperation)

	// allocate the vertices for all the paths
	call.triangleOffset = __allocVerts(ctx, len(verts))
	call.triangleCount = len(verts)
	mem.copy(&ctx.verts[call.triangleOffset], raw_data(verts), size_of(Vertex) * len(verts))

	// fill shader
	call.uniformOffset = __allocFragUniforms(ctx, 1)
	frag := __fragUniformPtr(ctx, call.uniformOffset)
	__convertPaint(ctx, frag, paint, scissor, 1, fringe, -1)
	frag.type = .IMG	
}

__renderDelete :: proc(uptr: rawptr) {
	ctx := cast(^Context) uptr
	
	sg.destroy_pipeline(ctx.pipeline)
	for image in ctx.images {
		sg.destroy_image(image)
	}

	delete(ctx.images)
	delete(ctx.paths)
	delete(ctx.verts)
	delete(ctx.uniforms)
	delete(ctx.calls)
	free(ctx)
}

///////////////////////////////////////////////////////////
// CREATION?
///////////////////////////////////////////////////////////

Create :: proc(flags: Create_Flags) -> ^nvg.Context {
	ctx := new(Context)
	params: nvg.Params
	params.renderCreate = __renderCreate
	params.renderCreateTexture = __renderCreateTexture
	params.renderDeleteTexture = __renderDeleteTexture
	params.renderUpdateTexture = __renderUpdateTexture
	params.renderGetTextureSize = __renderGetTextureSize
	params.renderViewport = __renderViewport
	params.renderCancel = __renderCancel
	params.renderFlush = __renderFlush
	params.renderFill = __renderFill
	params.renderStroke = __renderStroke
	params.renderTriangles = __renderTriangles
	params.renderDelete = __renderDelete
	params.userPtr = ctx
	params.edgeAntiAlias = (.ANTI_ALIAS in flags)
	ctx.flags = flags
	return nvg.CreateInternal(params)
}

Destroy :: proc(ctx: ^nvg.Context) {
	nvg.DeleteInternal(ctx)
}

create_image_from_handle :: proc(ctx: ^nvg.Context, textureId: u32, w, h: int, imageFlags: ImageFlags) -> int {
	gctx := cast(^Context) ctx.params.userPtr
	tex := __allocTexture(gctx)
	tex.type = .RGBA
	tex.tex = textureId
	tex.flags = imageFlags
	tex.width = w
	tex.height = h
	return tex.id
}

ImageHandle :: proc(ctx: ^nvg.Context, textureId: int) -> u32 {
	gctx := cast(^Context) ctx.params.userPtr
	tex := __findTexture(gctx, textureId)
	return tex.tex
}

// framebuffer additional

framebuffer :: struct {
	ctx: ^nvg.Context,
	fbo: u32,
	rbo: u32,
	texture: u32,
	image: int,
}

DEFAULT_FBO :: 100_000
defaultFBO := i32(DEFAULT_FBO)

// helper function to create GL frame buffer to render to
BindFramebuffer :: proc(fb: ^framebuffer) {
	if defaultFBO == DEFAULT_FBO {
		gl.GetIntegerv(gl.FRAMEBUFFER_BINDING, &defaultFBO)
	}
	gl.BindFramebuffer(gl.FRAMEBUFFER, fb != nil ? fb.fbo : u32(defaultFBO))
}

CreateFramebuffer :: proc(ctx: ^nvg.Context, w, h: int, imageFlags: ImageFlags) -> (fb: framebuffer) {
	tempFBO: i32
	tempRBO: i32
	gl.GetIntegerv(gl.FRAMEBUFFER_BINDING, &tempFBO)
	gl.GetIntegerv(gl.RENDERBUFFER_BINDING, &tempRBO)

	imageFlags := imageFlags
	incl(&imageFlags, ImageFlags { .FLIP_Y, .PREMULTIPLIED })
	fb.image = nvg.CreateImageRGBA(ctx, w, h, imageFlags, nil)
	fb.texture = ImageHandle(ctx, fb.image)
	fb.ctx = ctx

	// frame buffer object
	gl.GenFramebuffers(1, &fb.fbo)
	gl.BindFramebuffer(gl.FRAMEBUFFER, fb.fbo)

	// render buffer object
	gl.GenRenderbuffers(1, &fb.rbo)
	gl.BindRenderbuffer(gl.RENDERBUFFER, fb.rbo)
	gl.RenderbufferStorage(gl.RENDERBUFFER, gl.STENCIL_INDEX8, i32(w), i32(h))

	// combine all
	gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fb.texture, 0)
	gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, gl.RENDERBUFFER, fb.rbo)

	if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
// #ifdef gl.DEPTH24_STENCIL8
		// If gl.STENCIL_INDEX8 is not supported, try gl.DEPTH24_STENCIL8 as a fallback.
		// Some graphics cards require a depth buffer along with a stencil.
		gl.RenderbufferStorage(gl.RENDERBUFFER, gl.DEPTH24_STENCIL8, i32(w), i32(h))
		gl.FramebufferTexture2D(gl.FRAMEBUFFER, gl.COLOR_ATTACHMENT0, gl.TEXTURE_2D, fb.texture, 0)
		gl.FramebufferRenderbuffer(gl.FRAMEBUFFER, gl.STENCIL_ATTACHMENT, gl.RENDERBUFFER, fb.rbo)

		if gl.CheckFramebufferStatus(gl.FRAMEBUFFER) != gl.FRAMEBUFFER_COMPLETE {
			fmt.eprintln("ERROR")
		}
// #endif // gl.DEPTH24_STENCIL8
// 			goto error
	}

	gl.BindFramebuffer(gl.FRAMEBUFFER, u32(tempFBO))
	gl.BindRenderbuffer(gl.RENDERBUFFER, u32(tempRBO))
	return 
}

DeleteFramebuffer :: proc(fb: ^framebuffer) {
	if fb == nil {
		return
	}

	if fb.fbo != 0 {
		gl.DeleteFramebuffers(1, &fb.fbo)
	}
	
	if fb.rbo != 0 {
		gl.DeleteRenderbuffers(1, &fb.rbo)
	}
	
	if fb.image >= 0 {
		nvg.DeleteImage(fb.ctx, fb.image)
	}

	fb.ctx = nil
	fb.fbo = 0
	fb.rbo = 0
	fb.texture = 0
	fb.image = -1
}