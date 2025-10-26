package svk

import vk "vendor:vulkan"

Uniform :: struct {
	buffer:     Buffer,
	descriptor: Descriptor_Set,
}

create_uniform :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	stage_flags: vk.ShaderStageFlags,
	storage_buffer: bool = false,
) -> (
	uniform: Uniform,
) {
	buffer_usage: vk.BufferUsageFlags = {.UNIFORM_BUFFER} if !storage_buffer else {.STORAGE_BUFFER}
	descriptor_type: vk.DescriptorType = .UNIFORM_BUFFER if !storage_buffer else .STORAGE_BUFFER

	uniform.buffer = create_buffer(
		ctx,
		instance_size,
		instance_count,
		buffer_usage,
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = descriptor_type,
		descriptorCount = 1,
		stageFlags      = stage_flags,
	}

	uniform.descriptor = create_descriptor_set(ctx, bindings = {binding})

	update_descriptor_set(ctx, uniform.descriptor, uniform.buffer, 0, descriptor_type)

	map_buffer(ctx, &uniform.buffer)

	return
}

destroy_uniform :: proc(ctx: Context, uniform: ^Uniform) {
	unmap_buffer(ctx, &uniform.buffer)

	destroy_buffer(ctx, uniform.buffer)
	vk.DestroyDescriptorSetLayout(ctx.device, uniform.descriptor.layout, nil)
}

bind_uniform :: proc(
	ctx: Context,
	uniform: Uniform,
	command_buffer: vk.CommandBuffer,
	layout: vk.PipelineLayout,
	bind_point: vk.PipelineBindPoint,
	first_set: u32,
) {
	bind_descriptor_set(ctx, uniform.descriptor, command_buffer, layout, bind_point, first_set)
}

copy_to_uniform :: proc(ctx: Context, uniform: ^Uniform, data: rawptr, loc := #caller_location) {
	copy_to_buffer(ctx, &uniform.buffer, data, loc)
}
