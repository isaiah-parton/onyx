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

out vec2 tex_coord;
out vec4 diffuse_color;

void main() {
    gl_Position = mat * vec4(pos, 1.0);
    tex_coord = uv;
    diffuse_color = col;
}
@end

@fs fs
uniform frag_uniforms {
    int gradient_mode;
    vec4 gradient_colors[2];
    vec2 gradient_start;
    vec2 gradient_end;
};

uniform texture2D u_texture;
uniform sampler u_sampler;

in vec2 tex_coord;
in vec4 diffuse_color;

out vec4 frag_color;

void main() {
    frag_color = diffuse_color * texture(sampler2D(u_texture, u_sampler), tex_coord);
    switch (gradient_mode) {

        // None
        case 0:
        break;

        // Linear gradient
        case 1:
        frag_color *= vec4(1.0, 0.0, 1.0, 1.0); //diffuse_color * gradient_color0 + (gradient_color1 - gradient_color0)

        // Radial gradient
        case 2:
        frag_color *= vec4(1.0, 0.0, 1.0, 1.0);
    }
    if (frag_color.a < 0.001) {
      discard;
    }
}
@end

@program ui vs fs
