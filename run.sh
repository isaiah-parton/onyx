#!/bin/bash
sokol-shdc --input=onyx/shader.glsl --output=onyx/shader.odin --slang=glsl430:hlsl5:glsl300es --format=sokol_odin

cd demo
~/odin/odin run . --collection:extra="/home/shazam/Code/odin/odin-extra"
cd ..
