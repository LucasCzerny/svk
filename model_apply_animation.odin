package svk

import "core:log"
import "core:math/linalg"

apply_animation :: proc(animation: Animation, time: f32) {
	for channel in animation.channels {
		apply_animation_channel(channel, time)
	}
}

apply_animation_channel :: proc(channel: Animation_Channel, time: f32) {
	channel := channel

	sampler := channel.sampler

	next_keyframe_index := channel.keyframe_index + 1
	next_keyframe := sampler.keyframes[next_keyframe_index]

	if time > next_keyframe {
		channel.keyframe_index += 1
		next_keyframe_index += 1

		next_keyframe = sampler.keyframes[next_keyframe_index]
	}

	previous_keyframe_index := channel.keyframe_index
	previous_keyframe := sampler.keyframes[previous_keyframe_index]

	if next_keyframe < time {
		channel.keyframe_index += 1
		previous_keyframe = next_keyframe
		next_keyframe =
			sampler.keyframes[next_keyframe_index] if next_keyframe_index != len(sampler.keyframes) else sampler.keyframes[len(sampler.keyframes) - 1]
	}

	factor := (time - previous_keyframe) / (next_keyframe - previous_keyframe)

	switch channel.target {
	case .translation:
		interpolate_translation(
			channel.target_node,
			sampler,
			previous_keyframe_index,
			next_keyframe_index,
			factor,
		)
	case .rotation:
		interpolate_rotation(
			channel.target_node,
			sampler,
			previous_keyframe_index,
			next_keyframe_index,
			factor,
		)
	case .scale:
		interpolate_scale(
			channel.target_node,
			sampler,
			previous_keyframe_index,
			next_keyframe_index,
			factor,
		)
	case .weights:
		interpolate_morph_weights(
			channel.target_node,
			sampler,
			previous_keyframe_index,
			next_keyframe_index,
			factor,
		)
	}
}

@(private = "file")
interpolate_translation :: proc(
	target_node: ^Node,
	sampler: ^Animation_Sampler,
	previous_index, next_index: uint,
	factor: f32,
) {
	values := &sampler.values.([][3]f32)
	previous := values[previous_index]
	next := values[next_index]

	switch sampler.type {
	case .linear:
		target_node.translation = linear_interpolation(previous, next, factor)
	case .step:
		target_node.translation = previous
	case .cubic_spline:
		target_node.translation = cubic_spline_interpolation(previous, next, factor)
	}
}

@(private = "file")
interpolate_rotation :: proc(
	target_node: ^Node,
	sampler: ^Animation_Sampler,
	previous_index, next_index: uint,
	factor: f32,
) {
	values := &sampler.values.([]quaternion128)
	previous := values[previous_index]
	next := values[next_index]

	log.ensure(
		sampler.type == .linear,
		"Rotation can only be interpreted with the .linear interpolation type (it will use slerp)",
	)

	target_node.rotation = linalg.quaternion_slerp_f32(previous, next, factor)
}

@(private = "file")
interpolate_scale :: proc(
	target_node: ^Node,
	sampler: ^Animation_Sampler,
	previous_index, next_index: uint,
	factor: f32,
) {
	values := &sampler.values.([][3]f32)
	previous := values[previous_index]
	next := values[next_index]

	switch sampler.type {
	case .linear:
		target_node.scale = linear_interpolation(previous, next, factor)
	case .step:
		target_node.scale = previous
	case .cubic_spline:
		target_node.scale = cubic_spline_interpolation(previous, next, factor)
	}
}

@(private = "file")
interpolate_morph_weights :: proc(
	target_node: ^Node,
	sampler: ^Animation_Sampler,
	previous_index, next_index: uint,
	factor: f32,
) {
	values := &sampler.values.([][]f32)
	previous := values[previous_index]
	next := values[next_index]

	mesh, has_mesh := target_node.mesh.?
	log.assertf(
		has_mesh,
		"Can't interpolate the weights on node %s if it doesn't have a mesh",
		target_node.name,
	)

	switch sampler.type {
	case .linear:
		mesh.morph_weights = linear_interpolation(previous, next, factor)
	case .step:
		mesh.morph_weights = previous
	case .cubic_spline:
		mesh.morph_weights = cubic_spline_interpolation(previous, next, factor)
	}
}

@(private = "file")
linear_interpolation :: proc {
	linear_interpolation_float_array,
	linear_interpolation_vec3,
}

@(private = "file")
linear_interpolation_float_array :: proc(previous, next: []f32, factor: f32) -> (result: []f32) {
	nr_weights := len(previous)
	result = make([]f32, nr_weights)

	for i in 0 ..< nr_weights {
		result[i] = previous[i] * (1 - factor) + next[i] * factor
	}

	return result
}

@(private = "file")
linear_interpolation_vec3 :: proc(previous, next: [3]f32, factor: f32) -> [3]f32 {
	return previous * (1 - factor) + next * factor
}

@(private = "file")
cubic_spline_interpolation :: proc {
	cubic_spline_interpolation_float_array,
	cubic_spline_interpolation_vec3,
}

@(private = "file")
cubic_spline_interpolation_float_array :: proc(previous, next: []f32, factor: f32) -> []f32 {
	log.panic("Cubic spline interpolation is not implemented yet")
}


@(private = "file")
cubic_spline_interpolation_vec3 :: proc(previous, next: [3]f32, factor: f32) -> [3]f32 {
	log.panic("Cubic spline interpolation is not implemented yet")
}

