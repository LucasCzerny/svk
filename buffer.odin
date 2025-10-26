package svk

import "core:log"
import "core:math"
import "core:mem"

import vk "vendor:vulkan"

Buffer :: struct {
	handle:        vk.Buffer,
	memory:        vk.DeviceMemory,
	count:         u32,
	size:          vk.DeviceSize,
	mapped_memory: rawptr,
	mapped:        bool,
}

// TODO: use device instead of the entire context?
create_buffer :: proc(
	ctx: Context,
	instance_size: vk.DeviceSize,
	instance_count: u32,
	usage_flags: vk.BufferUsageFlags,
	memory_property_flags: vk.MemoryPropertyFlags,
	min_offset_alignment: vk.DeviceSize = 1,
) -> (
	buffer: Buffer,
) {
	log.assert(
		math.is_power_of_two(cast(int)min_offset_alignment),
		"min_offset_alignment has to be a power of 2",
	)

	alignment := align_size(instance_size, min_offset_alignment)

	buffer.count = instance_count
	buffer.size = alignment * cast(vk.DeviceSize)instance_count

	buffer_info := vk.BufferCreateInfo {
		sType       = .BUFFER_CREATE_INFO,
		size        = buffer.size,
		usage       = usage_flags,
		sharingMode = .EXCLUSIVE,
	}

	result := vk.CreateBuffer(ctx.device, &buffer_info, nil, &buffer.handle)
	log.ensuref(result == .SUCCESS, "Failed to create a buffer (result: %v)", result)

	mem_requirements: vk.MemoryRequirements
	vk.GetBufferMemoryRequirements(ctx.device, buffer.handle, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = find_memory_type_index(ctx, mem_requirements, memory_property_flags),
	}

	result = vk.AllocateMemory(ctx.device, &alloc_info, nil, &buffer.memory)
	log.ensuref(result == .SUCCESS, "Failed to allocate the buffer memory (result: %v)", result)

	result = vk.BindBufferMemory(ctx.device, buffer.handle, buffer.memory, 0)
	log.ensuref(result == .SUCCESS, "Failed to bind the buffer memory (result: %v)", result)

	return
}

destroy_buffer :: proc(ctx: Context, buffer: Buffer) {
	vk.DeviceWaitIdle(ctx.device)

	vk.DestroyBuffer(ctx.device, buffer.handle, nil)
	vk.FreeMemory(ctx.device, buffer.memory, nil)
}

map_buffer :: proc(
	ctx: Context,
	buffer: ^Buffer,
	offset: vk.DeviceSize = 0,
	loc := #caller_location,
) {
	result := vk.MapMemory(
		ctx.device,
		buffer.memory,
		offset,
		buffer.size,
		nil,
		&buffer.mapped_memory,
	)
	log.ensuref(result == .SUCCESS, "Failed to map a buffer (result: %v)", result)

	buffer.mapped = true
}

unmap_buffer :: proc(ctx: Context, buffer: ^Buffer) {
	vk.UnmapMemory(ctx.device, buffer.memory)
	buffer.mapped = false
}

copy_to_buffer :: proc(ctx: Context, buffer: ^Buffer, data: rawptr, loc := #caller_location) {
	was_mapped := buffer.mapped

	if !was_mapped {
		map_buffer(ctx, buffer)
	}

	mem.copy_non_overlapping(buffer.mapped_memory, data, cast(int)buffer.size)

	if !was_mapped {
		unmap_buffer(ctx, buffer)
	}
}

debug_print_buffer_content :: proc(ctx: Context, buffer: Buffer, title: string, $T: typeid) {
	when !ODIN_DEBUG {return}

	instance_size := size_of(T)
	log.assertf(
		int(buffer.count) * instance_size == int(buffer.size),
		"buffer.count * size_of(T) must be == buffer.size. You probably set the wrong typeid for the %s buffer (buffer.count = %d, instance_size = %d, buffer.size = %d)",
		title,
		buffer.count,
		instance_size,
		buffer.size,
	)

	buffer := buffer
	was_mapped := buffer.mapped

	if !was_mapped {
		map_buffer(ctx, &buffer)
	}

	log.info("Printing buffer:", title)
	log.infof(
		"-> buffer.count = %d, instance_size = %d, buffer.size = %d",
		buffer.count,
		instance_size,
		buffer.size,
	)


	for i in 0 ..< buffer.count {
		data_ptr := mem.ptr_offset(cast(^T)buffer.mapped_memory, i)
		log.info(data_ptr^)
	}

	if !was_mapped {
		unmap_buffer(ctx, &buffer)
	}
}

