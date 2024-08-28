@echo off

:: Build and run the demo from within it's folder
cd demo
odin run . --debug --collection:extra="C:\Users\Isaiah Parton\Code\odin-extra"
cd ..
