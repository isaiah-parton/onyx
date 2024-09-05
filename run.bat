@echo off

:: Build and run the demo from within it's folder
cd demo
odin run . --define:WGPU_SHARED=true --collection:extra="C:\Users\Isaiah Parton\Code\odin-extra"
cd ..
