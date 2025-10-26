package svk

import "core:log"
import "core:mem"
import "core:strings"

import "vendor:cgltf"

Skin :: struct {
	name:                  string,
	joints:                []^Node,
	skeleton_node:         ^Node,
	inverse_bind_matrices: Maybe([]matrix[4, 4]f32),
}

Animation :: struct {
	channels: []Animation_Channel,
	samplers: []Animation_Sampler,
}

Animation_Channel :: struct {
	target_node:    ^Node,
	sampler:        ^Animation_Sampler,
	target:         Animation_Target, // TODO: hm
	keyframe_index: uint,
}

Animation_Sampler :: struct {
	keyframes: []f32,
	values:    union {
		[][]f32,
		[][3]f32,
		[]quaternion128,
	},
	type:      Interpolation_Type,
}

Animation_Target :: enum u32 {
	translation,
	rotation,
	scale,
	weights,
}

Interpolation_Type :: enum u32 {
	linear,
	step,
	cubic_spline,
}

@(private)
load_skin :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_skin: cgltf.skin,
) -> (
	skin: Skin,
) {
	skin.name = strings.clone(string(src_skin.name))

	skin.joints = make([]^Node, len(src_skin.joints))
	for joint_node, i in src_skin.joints {
		node_index := cgltf.node_index(data, joint_node)
		skin.joints[i] = &model.nodes[node_index]
	}

	if src_skin.skeleton != nil {
		node_index := cgltf.node_index(data, src_skin.skeleton)
		skin.skeleton_node = &model.nodes[node_index]
	}

	if src_skin.inverse_bind_matrices != nil {
		skin.inverse_bind_matrices = load_inverse_bind_matrices(src_skin.inverse_bind_matrices)
	}

	return skin
}

@(private = "file")
load_inverse_bind_matrices :: proc(accessor: ^cgltf.accessor) -> []matrix[4, 4]f32 {
	data_ptr, component_size, component_count := read_accessor(accessor)
	stride := get_accessor_stride(accessor)

	matrices := make([]matrix[4, 4]f32, accessor.count)
	for i in 0 ..< accessor.count {
		current_matrix_ptr := mem.ptr_offset(cast(^matrix[4, 4]f32)data_ptr, i * stride)
		matrices[i] = current_matrix_ptr^
	}

	return matrices
}

@(private)
load_animation :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_animation: ^cgltf.animation,
) -> (
	animation: Animation,
) {
	animation.samplers = make([]Animation_Sampler, len(src_animation.samplers))
	for src_sampler, i in src_animation.samplers {
		animation.samplers[i] = load_sampler(model, data, src_sampler)
	}

	animation.channels = make([]Animation_Channel, len(src_animation.channels))
	for src_channel, i in src_animation.channels {
		animation.channels[i] = load_channel(
			model,
			data,
			src_animation,
			src_channel,
			&animation.samplers,
		)
	}

	return animation
}

@(private = "file")
load_sampler :: proc(
	model: ^Model,
	data: ^cgltf.data,
	src_sampler: cgltf.animation_sampler,
) -> (
	sampler: Animation_Sampler,
) {
	sampler.keyframes = load_keyframes_from_accessor(src_sampler.input)

	data_ptr, component_size, component_count := read_accessor(src_sampler.input)
	switch component_count {
	case 1:
		sampler.values = load_values_float_array(
			src_sampler.input,
			data_ptr,
			component_size,
			component_count,
		)
	case 3:
		sampler.values = load_values_vec3(
			src_sampler.input,
			data_ptr,
			component_size,
			component_count,
		)
	case 4:
		sampler.values = load_values_quaternion(
			src_sampler.input,
			data_ptr,
			component_size,
			component_count,
		)
	}

	sampler.type = transmute(Interpolation_Type)src_sampler.interpolation

	return sampler
}

@(private = "file")
load_channel :: proc(
	model: ^Model,
	data: ^cgltf.data,
	src_animation: ^cgltf.animation,
	src_channel: cgltf.animation_channel,
	samplers: ^[]Animation_Sampler,
) -> (
	channel: Animation_Channel,
) {
	node_index := cgltf.node_index(data, src_channel.target_node)
	channel.target_node = &model.nodes[node_index]

	sampler_index := cgltf.animation_sampler_index(src_animation, src_channel.sampler)
	channel.sampler = &samplers[sampler_index]

	log.ensuref(
		src_channel.target_path != .invalid,
		"The target path of the animation channel is invalid bro...",
	)

	channel.target = transmute(Animation_Target)(cast(u32)src_channel.target_path + 1)

	return channel
}

@(private = "file")
load_keyframes_from_accessor :: proc(accessor: ^cgltf.accessor) -> []f32 {
	data_ptr, component_size, component_count := read_accessor(accessor)
	stride := get_accessor_stride(accessor)

	log.ensure(accessor.component_type == .r_32f, "Only f32 keyframes are allowed (for now?)")

	keyframes := make([]f32, accessor.count)
	for i in 0 ..< accessor.count {
		keyframe_ptr := mem.ptr_offset(cast(^f32)data_ptr, i * stride)
		keyframes[i] = keyframe_ptr^
	}

	return keyframes
}

@(private = "file")
load_values_float_array :: proc(
	accessor: ^cgltf.accessor,
	data_ptr: rawptr,
	component_size: uint,
	component_count: uint,
) -> [][]f32 {
	stride := get_accessor_stride(accessor) / component_size
	count := accessor.count / component_count

	values := make([][]f32, count)

	for k in 0 ..< count {
		values[k] = make([]f32, component_count)
		for i in 0 ..< component_count {
			ptr := mem.ptr_offset(cast(^f32)data_ptr, (k * component_count + i))
			values[k][i] = ptr^
		}
	}

	return values
}

@(private = "file")
load_values_vec3 :: proc(
	accessor: ^cgltf.accessor,
	data_ptr: rawptr,
	component_size: uint,
	component_count: uint,
) -> [][3]f32 {
	stride := get_accessor_stride(accessor)

	values := make([][3]f32, accessor.count)
	for i in 0 ..< accessor.count {
		value_ptr := mem.ptr_offset(cast(^[3]f32)data_ptr, i * stride)
		values[i] = value_ptr^
	}

	return values
}

@(private = "file")
load_values_quaternion :: proc(
	accessor: ^cgltf.accessor,
	data_ptr: rawptr,
	component_size: uint,
	component_count: uint,
) -> []quaternion128 {
	stride := get_accessor_stride(accessor)

	values := make([]quaternion128, accessor.count)
	for i in 0 ..< accessor.count {
		value_ptr := mem.ptr_offset(cast(^quaternion128)data_ptr, i * stride)
		values[i] = value_ptr^
	}

	return values
}

