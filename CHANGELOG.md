# Changelog

## 0.1.3

- Reuse intermediate textures and shared workspaces while preserving delivered output buffers.
- Fuse eligible final outputs and adjacent convolutions with matching inputs without changing the shader weights or sampling rules.
- Check pipeline caches before loading GLSL and compile only enabled shader paths; fall back to original passes if optional fusion cannot compile.
- Add resource reuse/reset coverage and validate CLI resource bundles during release packaging.
- Document version-pinned Swift package dependencies.
