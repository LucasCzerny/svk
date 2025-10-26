package svk

import "core:bytes"
import "core:log"
import "core:strings"

import "vendor:stb/image"
import vk "vendor:vulkan"

// Most GPUs only really support images with 4 channels (so does svk (for now?))
CHANNELS :: 4

Image :: struct {
	handle:        vk.Image,
	view:          vk.ImageView,
	memory:        vk.DeviceMemory,
	width, height: u32,
	depth:         u32,
	channels:      u32,
	format:        vk.Format,
	layout:        vk.ImageLayout,
}

load_image :: proc {
	load_image_from_file,
	load_image_from_bytes,
}

load_image_from_file :: proc(
	ctx: Context,
	path: string,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> Image {
	depth := 8
	split, err := strings.split_after(path, ".")
	log.ensuref(err == {}, "Failed to split the image file path %s", path)

	if len(split) != 2 {
		log.warnf(
			"Failed to extract the file extension from %s. Default to 8 bit per channel, which is used in png, jpg, bmp, but not in tiff, ext or hdr f.e. If your image looks wrong, this might be the reason",
			path,
		)
	} else {
		extension := split[1]
		switch extension {
		case "png", "jpg", "bmp":
			depth = 8
		case "tiff", "exr":
			depth = 16
		case "hdr":
			depth = 32
		}
	}

	width, height, channels_in_file: i32
	pixels: rawptr
	path_cstring := strings.unsafe_string_to_cstring(path)

	switch depth {
	case 8:
		pixels = image.load(path_cstring, &width, &height, &channels_in_file, CHANNELS)
	case 16:
		pixels = image.load_16(path_cstring, &width, &height, &channels_in_file, CHANNELS)
	case 32:
		pixels = image.loadf(path_cstring, &width, &height, &channels_in_file, CHANNELS)
	}
	log.ensuref(pixels != nil, "Failed to load the image from %s", path)

	defer image.image_free(pixels)

	img := create_image(
		ctx,
		cast(u32)width,
		cast(u32)height,
		cast(u32)depth,
		cast(u32)CHANNELS,
		srgb,
		tiling,
		usage + {.TRANSFER_DST},
		layout,
	)

	copy_to_image(ctx, img, pixels)

	return img
}

load_image_from_bytes :: proc(
	ctx: Context,
	data_bytes: []u8,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> Image {
	depth :: 8

	width, height, channels_in_file: i32
	pixels := image.load_from_memory(
		raw_data(data_bytes),
		cast(i32)len(data_bytes),
		&width,
		&height,
		&channels_in_file,
		CHANNELS,
	)
	log.ensuref(pixels != nil, "Failed to load the image from the specified buffer")

	defer image.image_free(pixels)

	img := create_image(
		ctx,
		cast(u32)width,
		cast(u32)height,
		cast(u32)depth,
		cast(u32)CHANNELS,
		srgb,
		tiling,
		usage + {.TRANSFER_DST},
		layout,
	)

	copy_to_image(ctx, img, pixels)

	return img
}

create_image :: proc(
	ctx: Context,
	width, height: u32,
	depth: u32,
	channels: u32,
	srgb: bool,
	tiling: vk.ImageTiling = .OPTIMAL,
	usage: vk.ImageUsageFlags = {.SAMPLED},
	layout: vk.ImageLayout = .SHADER_READ_ONLY_OPTIMAL,
) -> (
	img: Image,
) {
	img.format = determine_format(channels, depth, srgb)
	log.debugf("Creating image with format %v", img.format)

	queue_families := [2]u32{ctx.graphics_queue.family, ctx.present_queue.family}

	image_info := vk.ImageCreateInfo {
		sType                 = .IMAGE_CREATE_INFO,
		imageType             = .D2,
		format                = img.format,
		extent                = {width, height, 1},
		mipLevels             = 1,
		arrayLayers           = 1,
		samples               = {._1},
		tiling                = tiling,
		usage                 = usage,
		sharingMode           = .EXCLUSIVE,
		queueFamilyIndexCount = len(queue_families),
		pQueueFamilyIndices   = raw_data(queue_families[:]),
		initialLayout         = .UNDEFINED,
	}

	result := vk.CreateImage(ctx.device, &image_info, nil, &img.handle)
	log.ensuref(result == .SUCCESS, "Failed to create the image (result: %v)", result)

	mem_requirements: vk.MemoryRequirements
	vk.GetImageMemoryRequirements(ctx.device, img.handle, &mem_requirements)

	alloc_info := vk.MemoryAllocateInfo {
		sType           = .MEMORY_ALLOCATE_INFO,
		allocationSize  = mem_requirements.size,
		memoryTypeIndex = find_memory_type_index(ctx, mem_requirements, {.DEVICE_LOCAL}),
	}

	result = vk.AllocateMemory(ctx.device, &alloc_info, nil, &img.memory)
	log.ensuref(result == .SUCCESS, "Failed to create the image memory (result: %v)", result)

	result = vk.BindImageMemory(ctx.device, img.handle, img.memory, 0)
	log.ensuref(result == .SUCCESS, "Failed to bind the image memory (result: %v)", result)

	view_info := vk.ImageViewCreateInfo {
		sType = .IMAGE_VIEW_CREATE_INFO,
		image = img.handle,
		viewType = .D2,
		format = img.format,
		components = {.R, .G, .B, .A},
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	result = vk.CreateImageView(ctx.device, &view_info, nil, &img.view)
	log.ensuref(result == .SUCCESS, "Failed to create the image view (result: %v)", result)

	img.width = width
	img.height = height
	img.depth = depth
	img.channels = channels

	img.layout = layout

	return
}

copy_to_image :: proc(ctx: Context, img: Image, pixels: rawptr, loc := #caller_location) {
	bytes_per_channel := img.depth / 8

	staging_buffer := create_buffer(
		ctx,
		1,
		img.width * img.height * img.channels * bytes_per_channel,
		{.TRANSFER_SRC},
		{.HOST_VISIBLE, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &staging_buffer, pixels)

	transition_image(
		ctx,
		img,
		.UNDEFINED,
		.TRANSFER_DST_OPTIMAL,
		{.TOP_OF_PIPE},
		{.TRANSFER},
		{},
		{.TRANSFER_WRITE},
	)

	copy_from_staging_buffer(ctx, img, staging_buffer)

	transition_image(
		ctx,
		img,
		.TRANSFER_DST_OPTIMAL,
		img.layout,
		{.TRANSFER},
		{.FRAGMENT_SHADER},
		{.TRANSFER_READ},
		{.SHADER_READ},
	)

	destroy_buffer(ctx, staging_buffer)
}

destroy_image :: proc(ctx: Context, img: Image) {
	vk.DestroyImage(ctx.device, img.handle, nil)
	vk.DestroyImageView(ctx.device, img.view, nil)
	vk.FreeMemory(ctx.device, img.memory, nil)
}

transition_image :: proc(
	ctx: Context,
	image: Image,
	from, to: vk.ImageLayout,
	src_stage_mask, dst_stage_mask: vk.PipelineStageFlags,
	src_access_mask, dst_access_mask: vk.AccessFlags,
	command_buffer: vk.CommandBuffer = vk.CommandBuffer{},
) {
	command_buffer := command_buffer
	use_single_time_commands := command_buffer == {}

	if use_single_time_commands {
		command_buffer = begin_single_time_commands(ctx)
	}

	memory_barrier := vk.ImageMemoryBarrier {
		sType = .IMAGE_MEMORY_BARRIER,
		oldLayout = from,
		newLayout = to,
		srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
		srcAccessMask = src_access_mask,
		dstAccessMask = dst_access_mask,
		image = image.handle,
		subresourceRange = vk.ImageSubresourceRange {
			aspectMask = {.COLOR},
			baseArrayLayer = 0,
			layerCount = 1,
			baseMipLevel = 0,
			levelCount = 1,
		},
	}

	vk.CmdPipelineBarrier(
		command_buffer,
		src_stage_mask,
		dst_stage_mask,
		{},
		0,
		nil,
		0,
		nil,
		1,
		&memory_barrier,
	)

	if use_single_time_commands {
		end_single_time_commands(ctx, command_buffer)
	}
}

// TODO: ugh
@(private = "file")
determine_format :: proc(channels, depth: u32, srgb: bool) -> vk.Format {
	log.ensure(
		channels == 4,
		"Most GPUs only really support images with 4 channels (so does svk (for now?))",
	)

	switch depth {
	case 8:
		format_int := cast(i32)vk.Format.R8G8B8A8_UNORM
		if srgb do format_int += 6
		return cast(vk.Format)format_int
	// TODO: unorm or sfloat
	case 16:
		return .R16G16B16A16_SFLOAT
	case 32:
		return .R32G32B32A32_SFLOAT
	}

	log.ensure(false, "The image depth (bits per pixel) must be 8, 16 or 32")
	return .UNDEFINED
}

@(private = "file")
copy_from_staging_buffer :: proc(ctx: Context, image: Image, buffer: Buffer) {
	command_buffer := begin_single_time_commands(ctx)

	region := vk.BufferImageCopy {
		imageSubresource = vk.ImageSubresourceLayers {
			aspectMask = {.COLOR},
			mipLevel = 0,
			baseArrayLayer = 0,
			layerCount = 1,
		},
		imageExtent = {image.width, image.height, 1},
	}

	vk.CmdCopyBufferToImage(
		command_buffer,
		buffer.handle,
		image.handle,
		.TRANSFER_DST_OPTIMAL,
		1,
		&region,
	)

	end_single_time_commands(ctx, command_buffer)
}

