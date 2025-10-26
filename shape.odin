package svk

create_quad_vertex_buffer :: proc(ctx: Context) -> (buffer: Buffer) {
	// odinfmt: disable
	vertices := [4][3]f32{
		{-0.5, -0.5, 0.0},
		{ 0.5, -0.5, 0.0},
		{ 0.5,  0.5, 0.0},
		{-0.5,  0.5, 0.0},
	}
	// odinfmt: enable

	buffer = create_buffer(
		ctx,
		size_of([3]f32),
		cast(u32)len(vertices),
		{.VERTEX_BUFFER},
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &buffer, raw_data(vertices[:]))

	return buffer
}

create_quad_index_buffer :: proc(ctx: Context) -> (buffer: Buffer) {
	// odinfmt: disable
	indices := [6]u32{
		0, 1, 2,
		2, 3, 0,
	}
	// odinfmt: enable

	buffer = create_buffer(
		ctx,
		size_of(u32),
		cast(u32)len(indices),
		{.INDEX_BUFFER},
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &buffer, raw_data(indices[:]))

	return buffer
}

create_cube_vertex_buffer :: proc(ctx: Context) -> (buffer: Buffer) {
	// odinfmt: disable
	vertices := [8][3]f32{
		{-0.5, -0.5, -0.5},
		{ 0.5, -0.5, -0.5},
		{ 0.5,  0.5, -0.5},
		{-0.5,  0.5, -0.5},
		{-0.5, -0.5,  0.5},
		{ 0.5, -0.5,  0.5},
		{ 0.5,  0.5,  0.5},
		{-0.5,  0.5,  0.5},
	}
	// odinfmt: enable

	buffer = create_buffer(
		ctx,
		size_of([3]f32),
		cast(u32)len(vertices),
		{.VERTEX_BUFFER},
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &buffer, raw_data(vertices[:]))

	return buffer
}

create_cube_index_buffer :: proc(ctx: Context) -> (buffer: Buffer) {
	// odinfmt: disable
	indices := [36]u32{
		0, 1, 2, 2, 3, 0,
		4, 5, 6, 6, 7, 4,
		4, 5, 1, 1, 0, 4,
		7, 6, 2, 2, 3, 7,
		5, 6, 2, 2, 1, 5,
		4, 7, 3, 3, 0, 4,
	}
	// odinfmt: enable

	buffer = create_buffer(
		ctx,
		size_of(u32),
		cast(u32)len(indices),
		{.INDEX_BUFFER},
		{.DEVICE_LOCAL, .HOST_COHERENT},
	)

	copy_to_buffer(ctx, &buffer, raw_data(indices[:]))

	return buffer
}

