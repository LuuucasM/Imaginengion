other possible optimizations:
- instead of each ssbo having their own transfer buffer, the renderer has its own single "master" transfer buffer, and we reuse it for all the different ssbos
- Unify copy pass into one copy pass where all the ssbos do their own UploadToGPUBuffer