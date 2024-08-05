#version 430 core
@header package onyx
@header import sg "extra:sokol-odin/sokol/gfx"

@vs vs
uniform Uniform {
    mat4 mat;
};

in vec3 pos;
in vec2 uv;
in vec4 col;
in int tex;

out vec2 tex_coord;
out vec4 diffuse_color;
out int tex_index;

void main() {
    gl_Position = vec4(pos, 1.0) * mat;
    tex_coord = uv;
    diffuse_color = col;
    tex_index = int(tex);
}
@end

@fs fs
uniform texture2D u_textures[8];
uniform sampler u_sampler;

in vec2 tex_coord;
in vec4 diffuse_color;
flat in int tex_index;

out vec4 frag_color;

void main() {
    frag_color = diffuse_color * texture(sampler2D(u_textures[tex_index], u_sampler), tex_coord);
}
@end

@program ui vs fs
