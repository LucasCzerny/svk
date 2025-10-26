package svk

import "base:builtin"
import "core:log"
import "core:math/linalg"
import "core:mem"
import "core:strings"

import "vendor:cgltf"
import vk "vendor:vulkan"

MORPH_ATTRIBUTES :: bit_set[Model_Attribute]{.position, .normal, .tangent, .tex_coord, .color}

Scene :: struct {
	name:       string,
	root_nodes: []^Node,
}

Node :: struct {
	name:            string,
	mesh:            Maybe(^Mesh),
	translation:     [3]f32,
	rotation:        quaternion128,
	scale:           [3]f32,
	local_transform: matrix[4, 4]f32,
	children:        []^Node,
	_loaded:         bool,
}

Mesh :: struct {
	name:          string,
	primitives:    []Primitive,
	morph_weights: []f32,
}

Primitive :: struct {
	vertex_buffers: map[Model_Attribute]Buffer,
	index_buffer:   Buffer,
	index_type:     vk.IndexType,
	material:       Maybe(^Material),
	morph_targets:  []map[Model_Attribute]Buffer,
}

@(private)
load_scene :: proc(model: ^Model, data: ^cgltf.data, src_scene: cgltf.scene) -> (scene: Scene) {
	scene.name = strings.clone(string(src_scene.name))

	scene.root_nodes = make([]^Node, len(src_scene.nodes))

	for root_node, i in src_scene.nodes {
		scene.root_nodes[i] = load_node(model, data, root_node)
	}

	return scene
}

@(private)
load_node :: proc(model: ^Model, data: ^cgltf.data, src_node: ^cgltf.node) -> (node: ^Node) {
	options := cast(^Model_Loading_Options)context.user_ptr

	node_index := cgltf.node_index(data, src_node)
	node = &model.nodes[node_index]

	if node._loaded {
		return node
	}

	node.name = strings.clone(string(src_node.name))

	if src_node.mesh != nil {
		mesh_index := cgltf.mesh_index(data, src_node.mesh)
		mesh := &model.meshes[mesh_index]

		node.mesh = mesh
	}

	if src_node.has_translation {
		node.translation = src_node.translation
	}
	if src_node.has_rotation {
		node.rotation = quaternion(
			x = src_node.rotation.x,
			y = src_node.rotation.y,
			z = src_node.rotation.z,
			w = src_node.rotation.w,
		)
	}
	if src_node.has_scale {
		node.scale = src_node.scale
	}

	if src_node.has_matrix {
		log.panic("has_matrix is not implemented yet")
		// node.position, node.rotation, node.scale = decompose_matrix(src_node.matrix_)
	} else if src_node.has_scale {
		node.local_transform =
			linalg.matrix4_translate(node.translation) *
			linalg.matrix4_from_quaternion(node.rotation) *
			linalg.matrix4_scale(node.scale)
	} else {
		node.local_transform = 1
	}

	if src_node.camera != nil && .load_cameras in options.features {
		camera_index := cgltf.camera_index(data, src_node.camera)
		model.cameras[camera_index].node = node
	}

	node._loaded = true

	node.children = make([]^Node, len(src_node.children))
	for child_node, i in src_node.children {
		node.children[i] = load_node(model, data, child_node)
	}

	return node
}

@(private)
load_mesh :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_mesh: cgltf.mesh,
) -> (
	mesh: Mesh,
) {
	mesh.name = strings.clone(string(src_mesh.name))

	mesh.primitives = make([]Primitive, len(src_mesh.primitives))

	for src_primitive, i in src_mesh.primitives {
		primitive := &mesh.primitives[i]
		primitive^ = load_primitive(ctx, model, data, src_primitive)
	}

	copy(mesh.morph_weights, src_mesh.weights)

	return mesh
}

@(private)
load_primitive :: proc(
	ctx: Context,
	model: ^Model,
	data: ^cgltf.data,
	src_primitive: cgltf.primitive,
) -> (
	primitive: Primitive,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	accessor := src_primitive.indices

	stride: u32
	primitive.index_type, stride = get_vk_index_type_and_stride(accessor.component_type)

	primitive.index_buffer = create_buffer(
		ctx,
		cast(vk.DeviceSize)stride,
		cast(u32)accessor.count,
		options.index_buffer_usage,
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	copy_accessor_data_to_buffer(ctx, accessor, &primitive.index_buffer)

	if src_primitive.material != nil {
		material_index := cgltf.material_index(data, src_primitive.material)
		primitive.material = &model.materials[material_index]
	}

	// load existing attributes
	for src_attribute in src_primitive.attributes {
		attribute_type := transmute(Model_Attribute)src_attribute.type

		if attribute_type not_in options.attributes {
			log.debugf("Skipping attribute %v", attribute_type)
			continue
		}

		load_attribute_to_buffer(
			ctx,
			attribute_type,
			src_attribute,
			&primitive.vertex_buffers[attribute_type],
			options.vertex_buffer_usage,
		)
	}

	for attribute_type in options.attributes {
		if primitive.vertex_buffers[attribute_type] == {} {
			can_be_filled := bit_set[Model_Attribute]{.normal, .tangent}
			log.ensuref(
				attribute_type in can_be_filled,
				"Required attribute %v is missing and can't be filled in",
				attribute_type,
			)

			log.warnf(
				"Required attribute %v is missing, but don't worry my completely untested code is going to fill it in for you",
				attribute_type,
			)

			fill_missing_attribute(ctx, &primitive, attribute_type)
		}
	}

	primitive.morph_targets = make([]map[Model_Attribute]Buffer, len(src_primitive.targets))
	for src_morph_target, i in src_primitive.targets {
		morph_target := &primitive.morph_targets[i]

		for src_attribute in src_morph_target.attributes {
			attribute_type := transmute(Model_Attribute)src_attribute.type

			if attribute_type not_in options.attributes || attribute_type not_in MORPH_ATTRIBUTES {
				log.debugf("Skipping attribute %v", attribute_type)
				continue
			}

			load_attribute_to_buffer(
				ctx,
				attribute_type,
				src_attribute,
				&morph_target[attribute_type],
				options.vertex_buffer_usage,
			)

			log.assertf(
				morph_target[attribute_type].count ==
				primitive.vertex_buffers[attribute_type].count,
				"The number of vertices in the morph target must be the same as in the base primitive (morph_target[attribute_type].count == %d vs primitive.vertex_buffers[attribute_type].count == %d)",
				morph_target[attribute_type].count,
				primitive.vertex_buffers[attribute_type].count,
			)
		}
	}

	return primitive
}

load_attribute_to_buffer :: proc(
	ctx: Context,
	attribute_type: Model_Attribute,
	src_attribute: cgltf.attribute,
	vertex_buffer: ^Buffer,
	vertex_buffer_usage: vk.BufferUsageFlags,
) {
	accessor := src_attribute.data

	vertex_buffer^ = create_buffer(
		ctx,
		cast(vk.DeviceSize)get_accessor_stride(accessor),
		cast(u32)accessor.count,
		vertex_buffer_usage,
		{.HOST_COHERENT, .DEVICE_LOCAL},
	)

	copy_accessor_data_to_buffer(ctx, accessor, vertex_buffer)
}

@(private = "file")
get_vk_index_type_and_stride :: proc(component_type: cgltf.component_type) -> (vk.IndexType, u32) {
	#partial switch (component_type) {
	case .r_8u:
		return .UINT8, 1
	case .r_16u:
		return .UINT16, 2
	case .r_32u:
		return .UINT32, 4
	}

	log.panicf("Invalid component type for the indices (%d)", component_type)
}

@(private = "file")
get_index :: proc(ptr: rawptr, index: uint, type: vk.IndexType) -> uint {
	#partial switch type {
	case .UINT16:
		u16_ptr := mem.ptr_offset(cast(^u16)ptr, index)
		return cast(uint)u16_ptr^
	case .UINT32:
		u32_ptr := mem.ptr_offset(cast(^u32)ptr, index)
		return cast(uint)u32_ptr^
	case .UINT8:
		u8_ptr := mem.ptr_offset(cast(^u8)ptr, index)
		return cast(uint)u8_ptr^
	}

	log.panic("Invalid index type")
}

@(private = "file")
fill_missing_attribute :: proc(
	ctx: Context,
	primitive: ^Primitive,
	attribute_type: Model_Attribute,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	index_buffer := &primitive.index_buffer
	map_buffer(ctx, index_buffer)

	index_count := cast(int)index_buffer.count
	indices_ptr := index_buffer.mapped_memory

	positions_buffer := &primitive.vertex_buffers[.position]
	map_buffer(ctx, positions_buffer)

	vertex_count := cast(int)positions_buffer.count
	positions := mem.slice_ptr(cast(^[3]f32)positions_buffer.mapped_memory, vertex_count)

	tex_coords_buffer := &primitive.vertex_buffers[.tex_coord]
	map_buffer(ctx, tex_coords_buffer)

	tex_coords := mem.slice_ptr(cast(^[2]f32)tex_coords_buffer.mapped_memory, vertex_count)

	normals: [][3]f32
	tangents: [][4]f32

	if attribute_type == .normal {
		normals = make([][3]f32, vertex_count)
	} else if attribute_type == .tangent {
		tangents = make([][4]f32, vertex_count)
	}

	for i := 0; i < index_count; i += 3 {
		first := get_index(indices_ptr, cast(uint)i, primitive.index_type)
		second := get_index(indices_ptr, cast(uint)i + 1, primitive.index_type)
		third := get_index(indices_ptr, cast(uint)i + 2, primitive.index_type)

		first_edge := positions[second] - positions[first]
		second_edge := positions[third] - positions[first]

		if attribute_type == .normal {
			face_normal := linalg.cross(first_edge, second_edge)
			face_normal = linalg.normalize(face_normal)

			normals[first] += face_normal
			normals[second] += face_normal
			normals[third] += face_normal
		} else if attribute_type == .tangent {
			first_delta_uv := tex_coords[second] - tex_coords[first]
			second_delta_uv := tex_coords[third] - tex_coords[first]

			r :=
				1.0 / (first_delta_uv.x * second_delta_uv.y - first_delta_uv.y * second_delta_uv.x)
			face_tangent := (first_edge * second_delta_uv.y - second_edge * first_delta_uv.y) * r

			vec4_tangent := [4]f32{face_tangent.x, face_tangent.y, face_tangent.z, 0}

			tangents[first] += vec4_tangent
			tangents[second] += vec4_tangent
			tangents[third] += vec4_tangent
		}
	}

	if attribute_type == .normal {
		for &normal in normals {
			normal = linalg.normalize(normal)
		}

		primitive.vertex_buffers[.normal] = create_buffer(
			ctx,
			cast(vk.DeviceSize)get_accessor_type_size(.vec3),
			cast(u32)vertex_count,
			options.vertex_buffer_usage,
			{.HOST_COHERENT, .DEVICE_LOCAL},
		)

		copy_to_buffer(ctx, &primitive.vertex_buffers[.normal], raw_data(normals))
	} else if attribute_type == .tangent {
		for &tangent in tangents {
			tangent = linalg.normalize(tangent)
		}

		primitive.vertex_buffers[.tangent] = create_buffer(
			ctx,
			cast(vk.DeviceSize)get_accessor_type_size(.vec4),
			cast(u32)vertex_count,
			options.vertex_buffer_usage,
			{.HOST_COHERENT, .DEVICE_LOCAL},
		)

		copy_to_buffer(ctx, &primitive.vertex_buffers[.tangent], raw_data(tangents))
	}

	unmap_buffer(ctx, tex_coords_buffer)
	unmap_buffer(ctx, positions_buffer)
	unmap_buffer(ctx, index_buffer)
}

@(private = "file")
probably_going_to_remove_this :: proc(accessor: ^cgltf.accessor) -> (rawptr, vk.IndexType) {
	// memory leak lol
	indices := make([]u32, accessor.count)

	// prevent compiler from complaining
	stride := 0
	data_ptr: rawptr = nil

	for i in 0 ..< accessor.count {
		index: u32
		switch stride {
		case 1:
			index = cast(u32)(cast([^]u8)data_ptr)[i]
		case 2:
			index = cast(u32)(cast([^]u16)data_ptr)[i]
		case 4:
			index = (cast([^]u32)data_ptr)[i]
		}

		indices[i] = index
	}

	return raw_data(indices), .UINT32
}

// utility

@(private = "file")
matrix_from_array :: proc(array: [16]f32) -> (mat: matrix[4, 4]f32) {
	for y in 0 ..< 4 {
		for x in 0 ..< 4 {
			mat[y][x] = array[x * 4 + y]
		}
	}

	return mat
}

