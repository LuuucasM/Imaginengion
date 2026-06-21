- zig build --watch -fincremental -Dno-bin
- zig build --watch --error-style verbose_clear -fincremental -Dno-bin
- commands for building shaders while the the build system has an bug with outputing errors:
- Vertex Shader:
	- zig build-obj -fno-llvm -fno-lld -ofmt=spirv -target spirv64-vulkan -mcpu baseline --name SDFVertShader -femit-bin=SDFVertShader.spv --dep IM -Mroot=assets/shaders/SDFVertShader.zig -MIM=src/Imaginengion/ImagineShaders.zig
- Fragment Shaders:
	- zig build-obj -ODebug -target spirv64-vulkan -mcpu baseline+variable_pointers --dep IM "-Mroot=src\Imaginengion\EngineAssets\shaders\SDFFragShaderOverlay.zig" "-MIM=src\Imaginengion\ImagineShaders.zig" --name SDFFragShaderOverlay
	- zig build-obj -ODebug -target spirv64-vulkan -mcpu baseline+variable_pointers --dep IM "-Mroot=src\Imaginengion\EngineAssets\shaders\SDFFragShaderGame.zig" "-MIM=src\Imaginengion\ImagineShaders.zig" --name SDFFragShaderGame



zig build-obj -ODebug -target spirv64-vulkan -mcpu baseline+variable_pointers "-Mroot=src\IndexArray.zig"  --name IndexArray