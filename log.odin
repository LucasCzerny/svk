package svk

import "base:runtime"
import "core:fmt"
import "core:log"
import "core:strings"

import vk "vendor:vulkan"

@(private)
vulkan_debug_callback: vk.ProcDebugUtilsMessengerCallbackEXT : proc "system" (
	message_severity: vk.DebugUtilsMessageSeverityFlagsEXT,
	message_type: vk.DebugUtilsMessageTypeFlagsEXT,
	callback_data: ^vk.DebugUtilsMessengerCallbackDataEXT,
	user_data: rawptr,
) -> b32 {
	if .VALIDATION not_in message_type {
		return false
	}

	context = (cast(^runtime.Context)user_data)^

	// TODO: use core:terminal/ansi
	red_ansi := "\033[31m"
	gray_ansi := "\033[2m"
	bold_ansi := "\033[1m"
	clear_ansi := "\033[0m"

	builder := strings.builder_make()
	defer strings.builder_destroy(&builder)

	strings.write_string(
		&builder,
		fmt.aprintfln("Vulkan Error %s%s%s", bold_ansi, callback_data.pMessageIdName, clear_ansi),
	)

	split := strings.split(string(callback_data.pMessage), "The Vulkan spec states: ")

	message_split := strings.split(split[0], " | ")
	message := message_split[len(message_split) - 1]
	message = strings.trim_right_space(message)

	strings.write_string(
		&builder,
		fmt.aprintfln("%s%sWhat: %s%s", red_ansi, bold_ansi, clear_ansi, message),
	)

	if len(split) == 2 {
		spec_states := split[1]

		strings.write_string(
			&builder,
			fmt.aprintfln("%s%sVulkan spec: %s%s", red_ansi, bold_ansi, clear_ansi, spec_states),
		)
	}

	final_message := strings.to_string(builder)

	if .ERROR in message_severity {
		log.errorf(final_message)
	} else if .WARNING in message_severity {
		log.warnf(final_message)
	} else if .INFO in message_severity {
		// log.infof(final_message)
		// also debugf because these messages are kinda useless tbh
		log.debugf(final_message)
	} else if .VERBOSE in message_severity {
		log.debugf(final_message)
	}

	return true
}

@(private = "file")
Message :: struct {
	handle:  string,
	message: string,
}

