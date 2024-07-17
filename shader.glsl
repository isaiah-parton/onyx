@header package ui
@header import sg "../sokol-odin/sokol/gfx"

@vs vs
in vec2 pos;
in vec2 uv;
in vec4 col;
out vec2 texCoord;
out vec4 color;
uniform Projection {
    mat4 Matrix;
};

void main() {
    gl_Position = Matrix * vec4(pos.xy, 0.0, 1.0);
    texCoord = uv;
    color = col;
}
@end

@fs fs
in      vec2        texCoord;
in      vec4        color;
out     vec4        frag_color;
uniform sampler2D   Texture;

void main() {
    frag_color = texture(Texture, texCoord) * color;
}
@end

@program ui vs fs