package svk

import "core:log"

import "vendor:cgltf"
import vk "vendor:vulkan"

// the descriptor will contain all of the textures in the same order as in the definition of the Model_Texture_Type struct
// for more info on the enums, see model_material.odin
Material :: struct {
	descriptor:   Descriptor_Set,
	textures:     [dynamic]Image,
	samplers:     [dynamic]vk.Sampler,
	//
	data_scalar:  map[Model_Texture_Data_Scalar]f32,
	data_vec3:    map[Model_Texture_Data_Vec3][3]f32,
	data_vec4:    map[Model_Texture_Data_Vec4][4]f32,
	//
	alpha_mode:   Alpha_Mode,
	alpha_cutoff: f32,
	double_sided: b32,
}

Alpha_Mode :: enum {
	opaque,
	mask,
	blend,
}

Model_Texture_Data_Scalar :: enum {
	metallic_factor,
	roughness_factor,
	glossiness_factor,
	clearcoat_factor,
	clearcoat_roughness_factor,
	transmission_factor,
	thickness_factor,
	attenuation_distance,
	ior,
	specular_factor,
	sheen_roughness_factor,
	emissive_strength,
	iridescence_factor,
	iridescence_ior,
	iridescence_thickness_min,
	iridescence_thickness_max,
	anisotropy_strength,
	anisotropy_rotation,
	dispersion,
}

Model_Texture_Data_Vec3 :: enum {
	specular_factor,
	attenuation_color,
	specular_color_factor,
	sheen_color_factor,
}

Model_Texture_Data_Vec4 :: enum {
	base_color_factor,
}

@(private)
load_material :: proc(
	ctx: Context,
	data: ^cgltf.data,
	src_material: cgltf.material,
) -> (
	material: Material,
	err: Model_Loading_Error,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	material.textures = make([dynamic]Image)
	material.samplers = make([dynamic]vk.Sampler)

	pbr_mr := src_material.pbr_metallic_roughness
	pbr_sg := src_material.pbr_specular_glossiness

	if src_material.has_pbr_metallic_roughness {
		material.data_vec4[.base_color_factor] = pbr_mr.base_color_factor
	} else if src_material.has_pbr_specular_glossiness {
		material.data_vec4[.base_color_factor] = pbr_sg.diffuse_factor
	} else {
		return {}, .base_color_not_available
	}

	for type in options.texture_types {
		switch (type) {
		case .base_color:
			src_texture_view :=
				src_material.has_pbr_metallic_roughness ? pbr_mr.base_color_texture : pbr_sg.diffuse_texture
			append(&material.textures, load_texture(ctx, src_texture_view, true))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

		case .normal:
			if src_material.normal_texture == {} {
				return {}, .normal_not_available
			}

			append(&material.textures, load_texture(ctx, src_material.normal_texture, false))
			append(&material.samplers, create_sampler(ctx, src_material.normal_texture))

		case .pbr_metallic_roughness:
			if !src_material.has_pbr_metallic_roughness {
				return {}, .pbr_metallic_roughness_not_available
			}

			src_texture_view := pbr_mr.metallic_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.metallic_factor] = pbr_mr.metallic_factor
			material.data_scalar[.roughness_factor] = pbr_mr.roughness_factor

		case .pbr_specular_glossiness:
			if !src_material.has_pbr_metallic_roughness {
				return {}, .pbr_specular_glossiness_not_available
			}

			src_texture_view := pbr_sg.specular_glossiness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.specular_factor] = pbr_sg.specular_factor
			material.data_scalar[.glossiness_factor] = pbr_sg.glossiness_factor

		case .clearcoat:
			if !src_material.has_clearcoat {
				return {}, .clearcoat_not_available
			}

			c := src_material.clearcoat

			src_texture_view := c.clearcoat_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			src_texture_view = c.clearcoat_normal_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.clearcoat_factor] = c.clearcoat_factor
			material.data_scalar[.clearcoat_roughness_factor] = c.clearcoat_roughness_factor

		case .transmission:
			if !src_material.has_transmission {
				return {}, .transmission_not_available
			}

			t := src_material.transmission

			src_texture_view := t.transmission_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.transmission_factor] = t.transmission_factor

		case .volume:
			if !src_material.has_volume {
				return {}, .volume_not_available
			}

			v := src_material.volume

			src_texture_view := v.thickness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.thickness_factor] = v.thickness_factor
			material.data_vec3[.attenuation_color] = v.attenuation_color
			material.data_scalar[.attenuation_distance] = v.attenuation_distance

		case .ior:
			if !src_material.has_ior {
				return {}, .ior_not_available
			}

			i := src_material.ior
			material.data_scalar[.ior] = i.ior

		case .specular:
			if !src_material.has_specular {
				return {}, .specular_not_available
			}

			s := src_material.specular

			src_texture_view := s.specular_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.specular_color_factor] = s.specular_color_factor
			material.data_scalar[.specular_factor] = s.specular_factor

		case .sheen:
			if !src_material.has_sheen {
				return {}, .sheen_not_available
			}

			s := src_material.sheen

			src_texture_view := s.sheen_color_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			src_texture_view = s.sheen_roughness_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_vec3[.sheen_color_factor] = s.sheen_color_factor
			material.data_scalar[.sheen_roughness_factor] = s.sheen_roughness_factor

		case .emissive_strength:
			if !src_material.has_emissive_strength {
				return {}, .emissive_strength_not_available
			}

			e := src_material.emissive_strength
			material.data_scalar[.emissive_strength] = e.emissive_strength

		case .iridescence:
			if !src_material.has_iridescence {
				return {}, .iridescence_not_available
			}

			i := src_material.iridescence

			src_texture_view := i.iridescence_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.iridescence_factor] = i.iridescence_factor
			material.data_scalar[.iridescence_ior] = i.iridescence_ior
			material.data_scalar[.iridescence_thickness_min] = i.iridescence_thickness_min
			material.data_scalar[.iridescence_thickness_max] = i.iridescence_thickness_max

		case .anisotropy:
			if !src_material.has_anisotropy {
				return {}, .anisotropy_not_available
			}

			a := src_material.anisotropy

			src_texture_view := a.anisotropy_texture
			append(&material.textures, load_texture(ctx, src_texture_view, false))
			append(&material.samplers, create_sampler(ctx, src_texture_view))

			material.data_scalar[.anisotropy_strength] = a.anisotropy_strength
			material.data_scalar[.anisotropy_rotation] = a.anisotropy_rotation

		case .dispersion:
			if !src_material.has_dispersion {
				return {}, .dispersion_not_available
			}

			d := src_material.dispersion
			material.data_scalar[.dispersion] = d.dispersion
		}
	}

	bindings := make([]vk.DescriptorSetLayoutBinding, len(material.textures))

	for i in 0 ..< len(material.textures) {
		bindings[i] = vk.DescriptorSetLayoutBinding {
			binding         = cast(u32)i,
			descriptorType  = .COMBINED_IMAGE_SAMPLER,
			descriptorCount = 1,
			stageFlags      = options.texture_stage_flags,
		}
	}

	material.descriptor = create_descriptor_set(ctx, bindings)

	for sampler, i in material.samplers {
		update_descriptor_set(ctx, material.descriptor, sampler, material.textures[i], cast(u32)i)
	}

	return material, .none
}

@(private)
create_sampler :: proc(
	ctx: Context,
	src_texture_view: cgltf.texture_view,
) -> (
	sampler: vk.Sampler,
) {
	options := cast(^Model_Loading_Options)context.user_ptr

	src_sampler := src_texture_view.texture.sampler
	if src_sampler == nil {
		return create_default_sampler(ctx)
	}

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = filter_cgltf_to_vk(src_sampler.mag_filter),
		minFilter               = filter_cgltf_to_vk(src_sampler.min_filter),
		mipmapMode              = mipmap_mode_cgltf_to_vk(src_sampler.min_filter),
		addressModeU            = wrap_mode_cgltf_to_vk(src_sampler.wrap_s),
		addressModeV            = wrap_mode_cgltf_to_vk(src_sampler.wrap_t),
		addressModeW            = .CLAMP_TO_EDGE, // gltf spec doesn't specify this
		mipLodBias              = 0,
		anisotropyEnable        = cast(b32)options.anisotropy_enabled,
		maxAnisotropy           = options.max_sampler_anisotropy,
		compareEnable           = false,
		compareOp               = .NEVER,
		// minLod                  = f32,
		// maxLod                  = f32,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	log.ensuref(
		result == .SUCCESS,
		"Failed to create a texture image sampler (result: %v)",
		result,
	)

	return sampler
}

@(private)
create_default_sampler :: proc(ctx: Context) -> (sampler: vk.Sampler) {
	options := cast(^Model_Loading_Options)context.user_ptr

	sampler_info := vk.SamplerCreateInfo {
		sType                   = .SAMPLER_CREATE_INFO,
		magFilter               = .LINEAR,
		minFilter               = .LINEAR,
		mipmapMode              = .LINEAR,
		addressModeU            = .CLAMP_TO_EDGE,
		addressModeV            = .CLAMP_TO_EDGE,
		addressModeW            = .CLAMP_TO_EDGE,
		mipLodBias              = 0,
		anisotropyEnable        = cast(b32)options.anisotropy_enabled,
		maxAnisotropy           = options.max_sampler_anisotropy,
		compareEnable           = false,
		compareOp               = .NEVER,
		// minLod                  = f32,
		// maxLod                  = f32,
		borderColor             = .INT_OPAQUE_BLACK,
		unnormalizedCoordinates = false,
	}

	result := vk.CreateSampler(ctx.device, &sampler_info, nil, &sampler)
	log.ensuref(
		result == .SUCCESS,
		"Failed to create a texture image sampler (result: %v)",
		result,
	)

	return sampler
}

// there are no odin bindings for cgltf filters and wrap modes apparently
// also, these might not be set -> use linear filtering and clamp_to_edge

@(private = "file")
filter_cgltf_to_vk :: proc(cgltf_filter: cgltf.filter_type) -> vk.Filter {
	#partial switch (cgltf_filter) {
	case .nearest, .nearest_mipmap_nearest, .nearest_mipmap_linear:
		return .NEAREST
	case .linear, .linear_mipmap_nearest, .linear_mipmap_linear:
		return .LINEAR
	}

	log.warnf("cgltf filter %v was not found, defaulting to vulkan filter .LINEAR", cgltf_filter)

	return .LINEAR
}

@(private = "file")
mipmap_mode_cgltf_to_vk :: proc(cgltf_filter: cgltf.filter_type) -> vk.SamplerMipmapMode {
	#partial switch (cgltf_filter) {
	case .nearest_mipmap_nearest, .linear_mipmap_nearest:
		return .NEAREST
	case .nearest_mipmap_linear, .linear_mipmap_linear:
		return .LINEAR
	}

	log.warnf("cgltf filter %v was not found, defaulting to vulkan filter .LINEAR", cgltf_filter)

	return .LINEAR
}

@(private = "file")
wrap_mode_cgltf_to_vk :: proc(cgltf_wrap_mode: cgltf.wrap_mode) -> vk.SamplerAddressMode {
	#partial switch (cgltf_wrap_mode) {
	case .clamp_to_edge:
		return .CLAMP_TO_EDGE
	case .mirrored_repeat:
		return .MIRRORED_REPEAT
	case .repeat:
		return .REPEAT
	}

	log.warnf(
		"cgltf wrap_mode %v was not found, defaulting to vulkan wrap_mode .REPEAT",
		cgltf_wrap_mode,
	)

	return .REPEAT
}

