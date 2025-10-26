package svk

import "core:log"
import "core:mem"

import "vendor:cgltf"

@(private)
read_accessor :: proc(
	accessor: ^cgltf.accessor,
) -> (
	data: rawptr,
	component_size: uint,
	component_count: uint,
) {
	src_buffer_view := accessor.buffer_view
	src_buffer := src_buffer_view.buffer

	data_start := mem.ptr_offset(
		cast(^u8)src_buffer.data,
		accessor.offset + src_buffer_view.offset,
	)

	// don't remove these comments. the formatting is horrendous
	// odinfmt: disable
	return data_start,
		get_accessor_component_size(accessor.component_type),
		get_accessor_component_count(accessor.type)
	// odinfmt: enable
}

@(private)
copy_accessor_data_to_buffer :: proc(ctx: Context, accessor: ^cgltf.accessor, buffer: ^Buffer) {
	data_ptr, component_size, component_count := read_accessor(accessor)
	total_size := component_size * component_count * accessor.count

	log.assertf(
		cast(uint)buffer.size == total_size,
		"The buffer size doesn't match the accessor size (buffer.size = %d, accessor size = %d)",
		buffer.size,
		total_size,
	)

	copy_to_buffer(ctx, buffer, data_ptr)
}

@(private)
get_accessor_stride :: proc(accessor: ^cgltf.accessor) -> uint {
	stride := accessor.stride
	if stride == 0 {
		stride = get_accessor_type_size(accessor.type)
	}

	return stride
}

@(private)
get_accessor_component_size :: proc(component_type: cgltf.component_type) -> uint {
	switch component_type {
	case .invalid:
		break
	case .r_8, .r_8u:
		return 1
	case .r_16, .r_16u:
		return 2
	case .r_32f, .r_32u:
		return 4
	}

	log.panic("Invalid component size")
}

@(private)
get_accessor_component_count :: proc(type: cgltf.type) -> uint {
	switch type {
	case .invalid:
		break
	case .scalar:
		return 1
	case .vec2:
		return 2
	case .vec3:
		return 3
	case .vec4:
		return 4
	case .mat2:
		return 4
	case .mat3:
		return 9
	case .mat4:
		return 16
	}

	log.panic("Invalid component count")
}

@(private)
get_accessor_type_size :: proc(type: cgltf.type) -> uint {
	switch type {
	case .invalid:
		break
	case .scalar:
		return 4
	case .vec2:
		return 8
	case .vec3:
		return 12
	case .vec4:
		return 16
	case .mat2:
		return 2 * 8
	case .mat3:
		return 3 * 12
	case .mat4:
		return 3 * 16
	}

	log.panic("Invalid accessor type")
}

