package svk

import "base:runtime"
import "core:log"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"

Context :: struct {
	instance:                vk.Instance,
	window:                  Window,
	//
	device:                  vk.Device,
	physical_device:         vk.PhysicalDevice,
	swapchain_support:       Swapchain_Support,
	//
	graphics_queue:          Queue,
	present_queue:           Queue,
	//
	swapchain:               Swapchain,
	//
	command_pool:            vk.CommandPool,
	command_buffers:         []vk.CommandBuffer,
	//
	descriptor_pool:         vk.DescriptorPool,
	//
	anisotropy_enabled:      bool,
	// private
	_has_debug_messenger:    bool,
	_debug_messenger:        vk.DebugUtilsMessengerEXT,
	_messenger_context_copy: ^runtime.Context,
}

create_context :: proc(
	instance_config: Instance_Config,
	window_config: Window_Config,
	device_config: Device_Config,
	swapchain_config: Swapchain_Config,
	command_config: Commands_Config,
	descriptor_config: Descriptor_Config,
) -> Context {
	ctx: Context

	init_ok := sdl.Init({.VIDEO} + window_config.sdl_init_flags)
	log.ensure(init_ok == 0, "Failed to initialize SDL3")

	vulkan_ok := sdl.Vulkan_LoadLibrary(nil)
	log.ensure(vulkan_ok == 0, "Failed to load the vulkan library")

	vk.load_proc_addresses_global(sdl.Vulkan_GetVkGetInstanceProcAddr())

	if instance_config.enable_validation_layers {
		ctx._messenger_context_copy = new(runtime.Context)
		ctx._messenger_context_copy^ = context
	}

	create_instance(&ctx.instance, instance_config, cast(rawptr)ctx._messenger_context_copy)

	vk.load_proc_addresses_instance(ctx.instance)

	if instance_config.enable_validation_layers {
		ctx._has_debug_messenger = true
		create_debug_messenger(
			&ctx._debug_messenger,
			ctx.instance,
			cast(rawptr)ctx._messenger_context_copy,
		)
	}

	create_window(&ctx.window, window_config, ctx.instance)

	create_devices_and_queues(&ctx, device_config, ctx.instance, ctx.window.surface)
	ctx.anisotropy_enabled = cast(bool)device_config.features.samplerAnisotropy

	ctx.swapchain = create_swapchain(ctx, swapchain_config)

	create_command_pool(&ctx, command_config)
	create_command_buffers(&ctx, command_config)

	create_descriptor_pool(&ctx, descriptor_config)

	return ctx
}

destroy_context :: proc(ctx: Context) {
	vk.DestroyCommandPool(ctx.device, ctx.command_pool, nil)
	delete(ctx.command_buffers)

	destroy_swapchain(ctx, ctx.swapchain)
	destroy_window(ctx, ctx.window)

	vk.DestroyDescriptorPool(ctx.device, ctx.descriptor_pool, nil)

	vk.DestroyDevice(ctx.device, nil)
	delete(ctx.swapchain_support.surface_formats)
	delete(ctx.swapchain_support.present_modes)

	if ctx._has_debug_messenger {
		destroy_debug_messenger(ctx._debug_messenger, ctx.instance)
	}

	vk.DestroyInstance(ctx.instance, nil)

	sdl.Quit()
}

update_swapchain_capabilities :: proc(ctx: ^Context) {
	result := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(
		ctx.physical_device,
		ctx.window.surface,
		&ctx.swapchain_support.capabilities,
	)
	log.ensuref(
		result == .SUCCESS,
		"Failed to get the physical device surface capabilities (result: %v)",
	)
}

