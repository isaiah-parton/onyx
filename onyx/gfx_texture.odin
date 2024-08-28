package onyx

import "vendor:wgpu"

create_bind_group_for_texture :: proc(gfx: ^Graphics, texture_view: wgpu.TextureView, sampler_descriptor: wgpu.SamplerDescriptor) -> wgpu.BindGroup {

	sampler_descriptor := sampler_descriptor
	sampler_descriptor.compare = .Never
	sampler := wgpu.DeviceCreateSampler(gfx.device, &sampler_descriptor)

	bind_group := wgpu.DeviceCreateBindGroup(gfx.device, &{
		layout = gfx.texture_bind_group_layout,
		entryCount = 2,
		entries = transmute([^]wgpu.BindGroupEntry)&[?]wgpu.BindGroupEntry{
			{
				binding = 0,
				textureView = texture_view,
			},
			{
				binding = 1,
				sampler = sampler,
			}
		},
	})

	return bind_group
}