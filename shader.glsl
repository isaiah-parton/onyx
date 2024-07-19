#version 430 core
@header package ui
@header import sg "../sokol-odin/sokol/gfx"

@vs vs
uniform tex {
    vec2 texSize;
};

in vec2 pos;
in vec2 uv;
in vec4 col;

out vec2 texCoord;
out vec4 color;

void main() {
    gl_Position = vec4(vec2(-1.0, 1.0) + (pos.xy / texSize) * vec2(1.0, -1.0), 0.0, 1.0);
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
    frag_color = color;
}
@end

@program ui vs fs