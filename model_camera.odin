package svk

import "core:strings"
import "vendor:cgltf"

Camera :: struct {
	name: string,
	node: ^Node,
}

@(private)
load_camera :: proc(ctx: Context, model: ^Model, src_camera: cgltf.camera) -> Camera {
	// node will be set in the load_node function
	return Camera{name = strings.clone(string(src_camera.name))}
}

