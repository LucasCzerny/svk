package svk

import "core:log"

import vk "vendor:vulkan"

create_framebuffers_for_swapchain :: proc(
	ctx: Context,
	render_pass: vk.RenderPass,
	framebuffers: ^[]vk.Framebuffer,
	loc := #caller_location,
) {
	if len(framebuffers) != 0 {
		destroy_framebuffers(ctx, framebuffers)
		delete(framebuffers^, loc = loc)
	}

	framebuffers^ = make([]vk.Framebuffer, ctx.swapchain.image_count, loc = loc)

	for i in 0 ..< ctx.swapchain.image_count {
		attachments := [2]vk.ImageView {
			ctx.swapchain.image_views[i],
			ctx.swapchain.depth_image_views[i],
		}

		framebuffer_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = len(attachments),
			pAttachments    = raw_data(attachments[:]),
			width           = ctx.swapchain.extent.width,
			height          = ctx.swapchain.extent.height,
			layers          = 1,
		}

		result := vk.CreateFramebuffer(ctx.device, &framebuffer_info, nil, &framebuffers[i])
		log.ensuref(
			result == .SUCCESS,
			"Failed to create a graphics render_pass framebuffer (result: %v)",
			result,
		)
	}
}

create_framebuffers_from_images :: proc(
	ctx: Context,
	render_pass: vk.RenderPass,
	images_per_framebuffer: [][]vk.ImageView,
	framebuffers: ^[]vk.Framebuffer,
	width, height: u32,
	loc := #caller_location,
) {
	if len(framebuffers) != 0 {
		destroy_framebuffers(ctx, framebuffers)
		delete(framebuffers^, loc = loc)
	}

	nr_framebuffers := len(images_per_framebuffer)
	framebuffers^ = make([]vk.Framebuffer, nr_framebuffers, loc = loc)

	for i in 0 ..< ctx.swapchain.image_count {
		attachments := images_per_framebuffer[i]

		framebuffer_info := vk.FramebufferCreateInfo {
			sType           = .FRAMEBUFFER_CREATE_INFO,
			renderPass      = render_pass,
			attachmentCount = cast(u32)len(attachments),
			pAttachments    = raw_data(attachments[:]),
			width           = width,
			height          = height,
			layers          = 1,
		}

		result := vk.CreateFramebuffer(ctx.device, &framebuffer_info, nil, &framebuffers[i])
		log.ensuref(
			result == .SUCCESS,
			"Failed to create a graphics render_pass framebuffer (result: %v)",
			result,
		)
	}
}

destroy_framebuffers :: proc(ctx: Context, framebuffers: ^[]vk.Framebuffer) {
	for framebuffer in framebuffers {
		vk.DestroyFramebuffer(ctx.device, framebuffer, nil)
	}
}

