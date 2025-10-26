package svk

import "core:log"
import "core:mem"
import "core:path/filepath"
import "core:strings"

import "vendor:cgltf"
import vk "vendor:vulkan"

Model :: struct {
	scenes:            []Scene,
	active_scene:      ^Scene,
	nodes:             []Node,
	meshes:            []Mesh,
	materials:         []Material,
	default_material:  Material,
	cameras:           []Camera,
	skins:             []Skin,
	animations:        []Animation,
	descriptor_layout: vk.DescriptorSetLayout,
}

Model_Attribute :: enum u32 {
	invalid,
	position,
	normal,
	tangent,
	tex_coord,
	color,
	joints,
	weights,
	custom,
}

Model_Texture_Type :: enum {
	base_color,
	normal,
	pbr_metallic_roughness,
	pbr_specular_glossiness,
	clearcoat,
	transmission,
	volume,
	ior,
	specular,
	sheen,
	emissive_strength,
	iridescence,
	anisotropy,
	dispersion,
}

Model_Loading_Features :: enum {
	ignore_materials,
	load_cameras,
	load_morph_weights,
}

Model_Loading_Error :: enum {
	none,
	base_color_not_available,
	pbr_metallic_roughness_not_available,
	pbr_specular_glossiness_not_available,
	normal_not_available,
	clearcoat_not_available,
	transmission_not_available,
	volume_not_available,
	ior_not_available,
	specular_not_available,
	sheen_not_available,
	emissive_strength_not_available,
	iridescence_not_available,
	anisotropy_not_available,
	dispersion_not_available,
}

// in the model loading code, all cgltf structs are prefixed with src_ if there is a corresponding svk struct

load_model :: proc(
	ctx: Context,
	path: string,
	attributes: bit_set[Model_Attribute],
	texture_types: bit_set[Model_Texture_Type],
	features: bit_set[Model_Loading_Features] = {},
	vertex_buffer_usage: vk.BufferUsageFlags = {.VERTEX_BUFFER},
	index_buffer_usage: vk.BufferUsageFlags = {.INDEX_BUFFER},
	texture_stage_flags: vk.ShaderStageFlags = {.FRAGMENT},
) -> (
	model: Model,
	err: Model_Loading_Error,
) {
	path := strings.unsafe_string_to_cstring(path)
	options: cgltf.options

	data, result := cgltf.parse_file(options, path)
	log.ensuref(result == .success, "Failed to parse the %s file (result: %v)", path, result)

	log.ensure(data.asset.version == "2.0", "The svk model loader only supports gltf 2.x models")

	result = cgltf.load_buffers(options, data, path)
	log.ensuref(result == .success, "Failed to load the buffers for %s (result: %v)", path, result)

	defer cgltf.free(data)

	model_loading_options := Model_Loading_Options {
		model_dir           = filepath.dir(cast(string)path),
		attributes          = attributes,
		texture_types       = texture_types,
		features            = features,
		vertex_buffer_usage = vertex_buffer_usage,
		index_buffer_usage  = index_buffer_usage,
		texture_stage_flags = texture_stage_flags,
		anisotropy_enabled  = ctx.anisotropy_enabled,
	}

	if ctx.anisotropy_enabled {
		properties: vk.PhysicalDeviceProperties
		vk.GetPhysicalDeviceProperties(ctx.physical_device, &properties)

		model_loading_options.max_sampler_anisotropy = properties.limits.maxSamplerAnisotropy
	}

	// i don't wanna have to pass all of this shit around everywhere
	context.user_ptr = &model_loading_options

	if .ignore_materials not_in features {
		model.materials = make([]Material, len(data.materials))
		for src_material, i in data.materials {
			material := &model.materials[i]

			material^ = load_material(ctx, data, src_material) or_return
			model.descriptor_layout = material.descriptor.layout
		}
	}

	model.meshes = make([]Mesh, len(data.meshes))
	for src_mesh, i in data.meshes {
		model.meshes[i] = load_mesh(ctx, &model, data, src_mesh) // or_return (TODO)
	}

	model.scenes = make([]Scene, len(data.scenes))
	model.nodes = make([]Node, len(data.nodes))
	for src_scene, i in data.scenes {
		model.scenes[i] = load_scene(&model, data, src_scene)
	}

	scene_index := cgltf.scene_index(data, data.scene)
	model.active_scene = &model.scenes[scene_index]

	if .load_cameras in features {
		model.cameras = make([]Camera, len(data.cameras))
		for src_camera, i in data.cameras {
			model.cameras[i] = load_camera(ctx, &model, src_camera)
		}
	}

	model.skins = make([]Skin, len(data.skins))
	for src_skin, i in data.skins {
		model.skins[i] = load_skin(ctx, &model, data, src_skin)
	}

	model.animations = make([]Animation, len(data.animations))
	for &src_animation, i in data.animations {
		model.animations[i] = load_animation(ctx, &model, data, &src_animation)
	}

	return model, nil
}

destroy_model :: proc(ctx: Context, model: Model) {
	delete(model.scenes)
	delete(model.nodes)

	for mesh in model.meshes {
		for primitive in mesh.primitives {
			for type in Model_Attribute {
				destroy_buffer(ctx, primitive.vertex_buffers[type])
			}

			destroy_buffer(ctx, primitive.index_buffer)
		}
	}

	delete(model.meshes)

	for material in model.materials {
		destroy_descriptor_layout(ctx, material.descriptor)

		for texture in material.textures {
			destroy_image(ctx, texture)
		}

		for sampler in material.samplers {
			vk.DestroySampler(ctx.device, sampler, nil)
		}

		delete(material.data_scalar)
		delete(material.data_vec3)
		delete(material.data_vec4)
	}
}

@(private)
Model_Loading_Options :: struct {
	model_dir:              string,
	attributes:             bit_set[Model_Attribute],
	texture_types:          bit_set[Model_Texture_Type],
	features:               bit_set[Model_Loading_Features],
	vertex_buffer_usage:    vk.BufferUsageFlags,
	index_buffer_usage:     vk.BufferUsageFlags,
	texture_stage_flags:    vk.ShaderStageFlags,
	anisotropy_enabled:     bool,
	max_sampler_anisotropy: f32,
}

@(private)
load_texture :: proc(ctx: Context, src_texture_view: cgltf.texture_view, srgb: bool) -> Image {
	options := cast(^Model_Loading_Options)context.user_ptr

	src_texture := src_texture_view.texture
	src_image := src_texture.image_

	log.ensure(src_texture != nil && src_image != nil, "The texture could not be loaded")

	is_embedded := src_image.uri == ""

	if is_embedded {
		src_buffer_view := src_image.buffer_view
		src_buffer := src_buffer_view.buffer

		log.ensure(
			src_buffer_view != nil && src_buffer != nil,
			"The embedded texture could not be loaded",
		)

		data_ptr := mem.ptr_offset(cast([^]u8)src_buffer.data, src_buffer_view.offset)

		return load_image_from_bytes(ctx, data_ptr[:src_buffer_view.size], srgb)
	} else {
		full_path := filepath.join({options.model_dir, cast(string)src_image.uri})
		return load_image_from_file(ctx, full_path, srgb)
	}
}

