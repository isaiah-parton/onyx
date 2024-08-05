@echo off
sokol-shdc --input=draw/shader.glsl --output=draw/shader.odin --slang=glsl430:hlsl5:glsl300es --format=sokol_odin
cd demo
odin run . --define:SOKOL_USE_GL=false --collection:extra="C:\dev\odin\packages"
cd ..
