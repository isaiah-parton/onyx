@echo off
sokol-shdc --input=shader.glsl --output=shader.odin --slang=glsl430:hlsl5:glsl300es --format=sokol_odin
cd demo
odin run . --define:SOKOL_USE_GL=false