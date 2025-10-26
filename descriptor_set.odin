package svk

import "core:log"

import vk "vendor:vulkan"

Descriptor_Set :: struct {
	set:    vk.DescriptorSet,
	layout: vk.DescriptorSetLayout,
}

create_descriptor_set :: proc(
	ctx: Context,
	bindings: []vk.DescriptorSetLayoutBinding,
	count: u32 = 1,
) -> (
	descriptor_set: Descriptor_Set,
) {
	layout_info := vk.DescriptorSetLayoutCreateInfo {
		sType        = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
		bindingCount = cast(u32)len(bindings),
		pBindings    = raw_data(bindings),
	}

	result := vk.CreateDescriptorSetLayout(ctx.device, &layout_info, nil, &descriptor_set.layout)
	log.ensuref(
		result == .SUCCESS,
		"Failed to create the descriptor set layout (result: %v)",
		result,
	)

	alloc_info := vk.DescriptorSetAllocateInfo {
		sType              = .DESCRIPTOR_SET_ALLOCATE_INFO,
		descriptorPool     = ctx.descriptor_pool,
		descriptorSetCount = count,
		pSetLayouts        = &descriptor_set.layout,
	}

	result = vk.AllocateDescriptorSets(ctx.device, &alloc_info, &descriptor_set.set)
	log.ensuref(result == .SUCCESS, "Failed to allocate the descriptor set (result: %v)", result)

	return
}

destroy_descriptor_layout :: proc(ctx: Context, descriptor_set: Descriptor_Set) {
	vk.DestroyDescriptorSetLayout(ctx.device, descriptor_set.layout, nil)
}

bind_descriptor_set :: proc(
	ctx: Context,
	descriptor_set: Descriptor_Set,
	command_buffer: vk.CommandBuffer,
	layout: vk.PipelineLayout,
	bind_point: vk.PipelineBindPoint,
	first_set: u32,
) {
	set := descriptor_set.set
	vk.CmdBindDescriptorSets(command_buffer, bind_point, layout, first_set, 1, &set, 0, nil)
}

update_descriptor_set :: proc {
	update_descriptor_set_buffer,
	update_descriptor_set_image,
}

update_descriptor_set_buffer :: proc(
	ctx: Context,
	descriptor_set: Descriptor_Set,
	buffer: Buffer,
	binding: u32,
	descriptor_type: vk.DescriptorType = .UNIFORM_BUFFER,
	p_next: rawptr = nil,
) {
	buffer_info := vk.DescriptorBufferInfo {
		buffer = buffer.handle,
		range  = buffer.size,
	}

	write_descriptor := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		pNext           = p_next,
		dstSet          = descriptor_set.set,
		dstBinding      = binding,
		descriptorCount = 1,
		descriptorType  = descriptor_type,
		pBufferInfo     = &buffer_info,
	}

	vk.UpdateDescriptorSets(ctx.device, 1, &write_descriptor, 0, nil)
}

update_descriptor_set_image :: proc(
	ctx: Context,
	descriptor_set: Descriptor_Set,
	sampler: vk.Sampler,
	image: Image,
	binding: u32,
	array_element: u32 = 0,
	descriptor_type: vk.DescriptorType = .COMBINED_IMAGE_SAMPLER,
	p_next: rawptr = nil,
) {
	image_info := vk.DescriptorImageInfo {
		sampler     = sampler,
		imageView   = image.view,
		imageLayout = image.layout,
	}

	write_descriptor := vk.WriteDescriptorSet {
		sType           = .WRITE_DESCRIPTOR_SET,
		pNext           = p_next,
		dstSet          = descriptor_set.set,
		dstBinding      = binding,
		dstArrayElement = array_element,
		descriptorCount = 1,
		descriptorType  = descriptor_type,
		pImageInfo      = &image_info,
	}

	vk.UpdateDescriptorSets(ctx.device, 1, &write_descriptor, 0, nil)
}

