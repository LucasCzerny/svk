package svk

import "core:log"

import vk "vendor:vulkan"

Pipeline :: struct {
	handle:      vk.Pipeline,
	layout:      vk.PipelineLayout,
	type:        Pipeline_Type,
	record_fn:   proc(
		ctx: Context,
		pipeline: Pipeline,
		command_buffer: vk.CommandBuffer,
		current_frame: u32,
	),
	render_pass: ^vk.RenderPass,
	clear_color: [3]f32,
}

@(private)
Pipeline_Type :: enum {
	graphics,
	compute,
	ray_tracing,
}

// used by all pipeline types
// TODO: change order of function arguments, too lazy rn
@(private)
create_shader_module :: proc(source: []u32, device: vk.Device) -> (module: vk.ShaderModule) {
	module_info := vk.ShaderModuleCreateInfo {
		sType    = .SHADER_MODULE_CREATE_INFO,
		codeSize = len(source) * size_of(u32),
		pCode    = raw_data(source),
	}

	result := vk.CreateShaderModule(device, &module_info, nil, &module)
	log.ensuref(result == .SUCCESS, "Failed to create a shader module (result: %v)", result)

	return
}

