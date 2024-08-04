#version 430 core
@header package ui
@header import sg "extra:sokol-odin/sokol/gfx"

@vs vs
uniform Uniform {
    vec2 texSize;
    vec2 origin;
    float scale;
};

in vec2 pos;
in vec2 uv;
in vec4 col;
in float z;

out vec2 texCoord;
out vec4 color;

void main() {
    vec2 diff = (pos - origin);
    vec2 scaledPos = origin + diff * scale;
    gl_Position = vec4(vec2(-1.0, 1.0) + (scaledPos / texSize) * vec2(2.0, -2.0), z, 1.0);
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
    frag_color = color * vec4(1.0, 1.0, 1.0, texture(sampler2D(u_Texture, u_Sampler), texCoord));
}
@end

@program ui vs fs