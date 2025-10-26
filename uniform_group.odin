package svk

import vk "vendor:vulkan"

Uniform_Group :: struct {
	buffers:     []Buffer,
	descriptors: Descriptor_Group,
}

create_uniform_group :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	stage_flags: vk.ShaderStageFlags,
	amount: int,
	loc := #caller_location,
) -> (
	uniform_group: Uniform_Group,
) {
	uniform_group.buffers = make([]Buffer, amount)
	for i in 0 ..< amount {
		buffer := &uniform_group.buffers[i]

		buffer^ = create_buffer(
			ctx,
			instance_size,
			instance_count,
			{.UNIFORM_BUFFER},
			{.DEVICE_LOCAL, .HOST_COHERENT},
		)
		map_buffer(ctx, buffer)
	}

	binding := vk.DescriptorSetLayoutBinding {
		binding         = 0,
		descriptorType  = .UNIFORM_BUFFER,
		descriptorCount = 1,
		stageFlags      = stage_flags,
	}

	uniform_group.descriptors = create_descriptor_group(ctx, {binding}, amount, loc)

	for i in 0 ..< amount {
		update_descriptor_set(
			ctx,
			get_set(uniform_group.descriptors, i),
			uniform_group.buffers[i],
			0,
		)
	}

	return
}

destroy_uniform_group :: proc(ctx: Context, uniform_group: ^Uniform_Group) {
	for &buffer in uniform_group.buffers {
		unmap_buffer(ctx, &buffer)
		destroy_buffer(ctx, buffer)
	}

	destroy_descriptor_group_layout(ctx, uniform_group.descriptors)
}

copy_to_all_uniforms :: proc(
	ctx: Context,
	uniform_group: ^Uniform_Group,
	data: rawptr,
	loc := #caller_location,
) {
	for &buffer in uniform_group.buffers {
		copy_to_buffer(ctx, &buffer, data, loc)
	}
}

get_uniform :: proc(uniform_group: Uniform_Group, index: int) -> Uniform {
	return Uniform{uniform_group.buffers[index], get_set(uniform_group.descriptors, index)}
}
