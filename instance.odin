package svk

import "core:log"

import sdl "vendor:sdl2"
import vk "vendor:vulkan"

Instance_Config :: struct {
	name:                     cstring,
	major:                    u32,
	minor:                    u32,
	patch:                    u32,
	extensions:               []cstring,
	enable_validation_layers: bool,
	i_have_a_gpu:             bool,
}

@(private)
create_instance :: proc(instance: ^vk.Instance, config: Instance_Config, context_copy: rawptr) {
	app_info := vk.ApplicationInfo {
		sType              = .APPLICATION_INFO,
		pApplicationName   = config.name,
		applicationVersion = vk.MAKE_VERSION(config.major, config.minor, config.patch),
		pEngineName        = "svk",
		engineVersion      = vk.MAKE_VERSION(0, 1, 0),
		apiVersion         = vk.API_VERSION_1_3,
	}

	temp_window := sdl.CreateWindow(
		"temp window to get instance extensions",
		0,
		0,
		800,
		600,
		sdl.WINDOW_VULKAN | sdl.WINDOW_ALLOW_HIGHDPI | sdl.WINDOW_SHOWN,
	)
	defer sdl.DestroyWindow(temp_window)

	sdl_extension_count: u32
	sdl.Vulkan_GetInstanceExtensions(temp_window, &sdl_extension_count, nil)

	sdl_extensions := make([]cstring, sdl_extension_count)
	defer delete(sdl_extensions)
	sdl.Vulkan_GetInstanceExtensions(temp_window, &sdl_extension_count, raw_data(sdl_extensions))

	log.assert(sdl_extension_count != 0, "No GLFW extensions were found")

	extensions: [dynamic]cstring
	defer delete(extensions)

	reserve(&extensions, len(config.extensions) + len(sdl_extensions))

	append(&extensions, ..config.extensions)
	append(&extensions, ..sdl_extensions)

	create_info := vk.InstanceCreateInfo {
		sType                   = .INSTANCE_CREATE_INFO,
		pApplicationInfo        = &app_info,
		enabledExtensionCount   = cast(u32)len(extensions),
		ppEnabledExtensionNames = raw_data(extensions),
	}

	validation_layer: cstring = "VK_LAYER_KHRONOS_validation"

	debug_info: vk.DebugUtilsMessengerCreateInfoEXT
	if config.enable_validation_layers {
		create_info.enabledLayerCount = 1
		create_info.ppEnabledLayerNames = &validation_layer

		debug_info = {
			sType           = .DEBUG_UTILS_MESSENGER_CREATE_INFO_EXT,
			messageSeverity = {.VERBOSE, .INFO, .WARNING, .ERROR},
			messageType     = {.GENERAL, .VALIDATION, .PERFORMANCE},
			pfnUserCallback = vulkan_debug_callback,
			pUserData       = context_copy,
		}

		create_info.pNext = &debug_info
	}

	result := vk.CreateInstance(&create_info, nil, instance)
	log.ensuref(result == .SUCCESS, "Failed to create the instance (result: %v)", result)
}

