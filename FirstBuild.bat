@echo off
cd src/Vendor/Glad
zig build

cd ../GLFW
zig build

cd ../imgui
zig build

cd ../nativefiledialog
zig build

cd ../../..
zig build

copy "zig-out\bin\GameEngine.exe" .

pause