package svk

import "core:log"

import vk "vendor:vulkan"

@(private)
create_debug_messenger :: proc(
	messenger: ^vk.DebugUtilsMessengerEXT,
	instance: vk.Instance,
	context_copy: rawptr,
) {
	create_func := cast(vk.ProcCreateDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(
		instance,
		"vkCreateDebugUtilsMessengerEXT",
	)
	log.ensure(create_func != nil, "The CreateDebugUtilsMessengerEXT function was not found")

	messenger_info := vk.DebugUtilsMessengerCreateInfoEXT {
		sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
		messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
		messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
		pfnUserCallback = vulkan_debug_callback,
		pUserData       = context_copy,
	}

	result := create_func(instance, &messenger_info, nil, messenger)
	log.ensuref(result == .SUCCESS, "Failed to create the debug messenger (result: %v)", result)
}

@(private)
destroy_debug_messenger :: proc(messenger: vk.DebugUtilsMessengerEXT, instance: vk.Instance) {
	destroy_func := cast(vk.ProcDestroyDebugUtilsMessengerEXT)vk.GetInstanceProcAddr(
		instance,
		"vkDestroyDebugUtilsMessengerEXT",
	)
	log.ensure(destroy_func != nil, "The CreateDebugUtilsMessengerEXT function was not found")

	destroy_func(instance, messenger, nil)
}

