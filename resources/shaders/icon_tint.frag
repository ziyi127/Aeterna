#version 440

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(binding = 1) uniform sampler2D src;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
};

void main()
{
    vec4 sourceColor = texture(src, qt_TexCoord0);
    fragColor = vec4(tint.rgb * sourceColor.a, sourceColor.a) * qt_Opacity;
}
