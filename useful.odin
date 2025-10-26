package svk

import "core:log"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"

delta_time :: proc() -> f32 {
	@(static) prev: u64 = 0

	now := sdl.GetPerformanceCounter()

	delta_ms := f64(now - prev) / f64(sdl.GetPerformanceFrequency())
	prev = now

	return cast(f32)delta_ms
}

align_size :: proc(size, alignment: vk.DeviceSize) -> vk.DeviceSize {
	if alignment <= 1 {
		return size
	}

	/*
	we want to align the instance_size to be a multiple of alignment
	it only works on powers of 2!

	we will set the lower x bits to 0 (with 2^x = alignment)
	alignment == 1 -> & 11111111 (x4)
	alignment == 2 -> & 11111111 11111111 11111111 11111110
	alignment == 8 -> & 11111111 11111111 11111111 11111000
	...
	
	example:
	instance_size = 32
	alignment = 2
	            v this is the instance_size + alignment - 1
	alignment = 33 & 11111111 11111111 11111111 11111110
	          = 32 (already aligned)

	another example:
	instance_size = 34
	alignment = 8
	alignment = 41 & 11111111 11111111 11111111 11111000
	          = ...0 00101001 & ...1 11111000
	          = ...0 00101000 = 40

	the & basically "rounds down" to the next multiple of alignment
	we add a alignment to the instance_size first because we want
	the result to be >= than instance_size
	*/

	return (size + alignment - 1) & ~(alignment - 1)
}

find_memory_type_index :: proc(
	ctx: Context,
	mem_requirements: vk.MemoryRequirements,
	properties: vk.MemoryPropertyFlags,
) -> u32 {
	mem_properties: vk.PhysicalDeviceMemoryProperties
	vk.GetPhysicalDeviceMemoryProperties(ctx.physical_device, &mem_properties)

	for i in 0 ..< mem_properties.memoryTypeCount {
		if (mem_requirements.memoryTypeBits) & (1 << i) != 0 &&
		   (mem_properties.memoryTypes[i].propertyFlags & properties) == properties {
			return i
		}
	}

	log.panic("Failed to find a supported memory type")
}

create_basic_ahh_sampler :: proc(
	ctx: Context,
	anisotropy_enable := true,
) -> (
	sampler: vk.Sampler,
) {
	properties: vk.PhysicalDeviceProperties

	if anisotropy_enable {
		vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)
	}

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .NEAREST,
		addressModeU            = .REPEAT,
		addressModeV            = .REPEAT,
		addressModeW            = .REPEAT,
		mipLodBias              = 0,
		anisotropyEnable        = cast(b32)anisotropy_enable,
		maxAnisotropy           = anisotropy_enable ? properties.limits.maxSamplerAnisotropy : 1.0,
		compareEnable           = false,
		compareOp               = .NEVER,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	log.ensure(result == .SUCCESS, "Failed to create the basic ahh sampler")

	return sampler
}

