@echo off

:: Cross-compile shaders
sokol-shdc --input=onyx/shader.glsl --output=onyx/shader.odin --slang=glsl430:hlsl5:glsl300es --format=sokol_odin

:: Build and run the demo from within it's folder
cd demo
odin run . --define:SOKOL_USE_GL=false --collection:extra="C:\dev\odin\packages"
cd ..
