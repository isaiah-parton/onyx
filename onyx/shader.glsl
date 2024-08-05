#version 430 core
@header package draw
@header import sg "extra:sokol-odin/sokol/gfx"

@vs vs
uniform Uniform {
    mat4 mat;
};

in vec3 pos;
in vec2 uv;
in vec4 col;

out vec2 texCoord;
out vec4 color;

void main() {
    gl_Position = vec4(pos, 1.0) * mat;
    texCoord = uv;
    color = col;
}
@end

@fs fs
uniform texture2D   u_Texture;
uniform sampler     u_Sampler;

in      vec2        texCoord;
in      vec4        color;

out     vec4        frag_color;

void main() {
    frag_color = color * texture(sampler2D(u_Texture, u_Sampler), texCoord);
}
@end

@program ui vs fs
