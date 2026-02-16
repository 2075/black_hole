# OpenGL → Metal / wgpu API Call Mapping Reference

Comprehensive mapping of every OpenGL, GLFW, GLEW, and GLM call used in this project to their Metal (Swift) and wgpu (Rust) equivalents.

Source files analyzed: `black_hole.cpp`, `2D_lensing.cpp`, `CPU-geodesic.cpp`, `ray_tracing.cpp`, `geodesic.comp`, `grid.vert`, `grid.frag`

---

## 1. Initialization & Window Management

### 1.1 Window System

| OpenGL / GLFW | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glfwInit()` | `NSApplication.shared` (automatic with SwiftUI) | `EventLoop::new()` (winit) |
| `glfwCreateWindow(W, H, title, …)` | `NSWindow(…)` or SwiftUI `WindowGroup` | `WindowBuilder::new().with_title(title).with_inner_size(LogicalSize::new(W, H)).build(&event_loop)` |
| `glfwWindowHint(GLFW_CONTEXT_VERSION_MAJOR, 4)` | N/A (Metal version selected via `MTLDevice`) | N/A (backend auto-selected by wgpu) |
| `glfwWindowHint(GLFW_OPENGL_PROFILE, …)` | N/A | N/A |
| `glfwMakeContextCurrent(window)` | N/A (Metal has no context model) | `instance.create_surface(&window)` then `adapter.request_device()` |
| `glfwDestroyWindow(window)` | `window.close()` / automatic with SwiftUI | Dropped when `Window` goes out of scope |
| `glfwTerminate()` | N/A | N/A (event loop owns lifecycle) |
| `glfwWindowShouldClose(window)` | `NSApplication.shared.isRunning` / SwiftUI lifecycle | `ControlFlow::Exit` in winit event loop |
| `glfwSwapBuffers(window)` | `commandBuffer.present(drawable)` + `commandBuffer.commit()` | `surface_texture.present()` |
| `glfwPollEvents()` | RunLoop-based (automatic in SwiftUI/AppKit) | `event_loop.run(move \|event, …\| { … })` |
| `glfwGetTime()` | `CACurrentMediaTime()` or `CFAbsoluteTimeGetCurrent()` | `std::time::Instant::now()` |

**Usage:** `black_hole.cpp` lines 177–200, `CPU-geodesic.cpp` lines 118–148, `ray_tracing.cpp` lines 34–51, `2D_lensing.cpp` lines 36–56

### 1.2 Extension Loading (GLEW)

| OpenGL / GLEW | Metal | wgpu |
|---|---|---|
| `glewExperimental = GL_TRUE` | N/A | N/A |
| `glewInit()` | N/A (Metal has no extension system) | N/A (wgpu handles backend selection) |
| `glewGetErrorString(err)` | N/A | N/A |
| `glGetString(GL_VERSION)` | `device.name` | `adapter.get_info().name` |

---

## 2. Input Handling (GLFW → Native)

| GLFW | Metal (AppKit/SwiftUI) | wgpu (winit) |
|---|---|---|
| `glfwSetMouseButtonCallback(win, cb)` | `override func mouseDown(with:)` / `mouseUp(with:)` / `.onTapGesture {}` | `WindowEvent::MouseInput { state, button, … }` |
| `glfwSetCursorPosCallback(win, cb)` | `override func mouseMoved(with:)` / `mouseDragged(with:)` | `WindowEvent::CursorMoved { position, … }` or `DeviceEvent::MouseMotion { delta }` |
| `glfwSetScrollCallback(win, cb)` | `override func scrollWheel(with:)` / `.onScroll {}` | `WindowEvent::MouseWheel { delta, … }` |
| `glfwSetKeyCallback(win, cb)` | `override func keyDown(with:)` / `keyUp(with:)` | `WindowEvent::KeyboardInput { event, … }` |
| `glfwSetWindowUserPointer(win, ptr)` | Stored as class property on `NSView`/`MTKView` subclass | Stored in application state struct passed through event loop |
| `glfwGetWindowUserPointer(win)` | `self.camera` (direct property access) | `&mut app_state.camera` |
| `glfwGetCursorPos(win, &x, &y)` | `event.locationInWindow` / `NSEvent.mouseLocation` | `WindowEvent::CursorMoved { position }` |
| `GLFW_MOUSE_BUTTON_LEFT` | `.left` (NSEvent button 0) | `MouseButton::Left` |
| `GLFW_MOUSE_BUTTON_MIDDLE` | `.otherMouse` (button 2) | `MouseButton::Middle` |
| `GLFW_MOUSE_BUTTON_RIGHT` | `.right` (button 1) | `MouseButton::Right` |
| `GLFW_PRESS` / `GLFW_RELEASE` | `mouseDown` / `mouseUp` event type | `ElementState::Pressed` / `ElementState::Released` |
| `GLFW_KEY_G` | `event.keyCode` or `event.characters == "g"` | `KeyCode::KeyG` |
| `GLFW_MOD_SHIFT` | `event.modifierFlags.contains(.shift)` | `ModifiersState::SHIFT` |

**Usage:** `black_hole.cpp` lines 614–636, `CPU-geodesic.cpp` lines 433–439

---

## 3. GPU Device & Pipeline Setup

### 3.1 Device Initialization

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| OpenGL context creation (implicit) | `MTLCreateSystemDefaultDevice()` → `MTLDevice` | `wgpu::Instance::new(…)` → `instance.request_adapter(…).await` → `adapter.request_device(…).await` |
| N/A | `device.makeCommandQueue()` → `MTLCommandQueue` | Part of `Device` (queue obtained from `device.queue()`) |
| N/A | `MTKView(frame:, device:)` | `instance.create_surface(&window)` → `surface.configure(&device, &config)` |

### 3.2 Render Pipeline

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glCreateShader(GL_VERTEX_SHADER)` | `device.makeLibrary(source:, options:)` → access function by name | `device.create_shader_module(ShaderModuleDescriptor { source: ShaderSource::Wgsl(src) })` |
| `glCreateShader(GL_FRAGMENT_SHADER)` | Same library, different function name | Same module, different entry point |
| `glShaderSource(shader, 1, &src, nil)` | Source passed to `makeLibrary(source:)` | Source passed to `create_shader_module()` |
| `glCompileShader(shader)` | Compiled during `makeLibrary()` | Compiled during `create_shader_module()` or `create_render_pipeline()` |
| `glGetShaderiv(…, GL_COMPILE_STATUS, …)` | Check `makeLibrary()` error return | Check `create_shader_module()` for errors (validated at pipeline creation) |
| `glGetShaderInfoLog(…)` | Error message from `makeLibrary()` throws | wgpu validation error callback |
| `glCreateProgram()` | `MTLRenderPipelineDescriptor` | `wgpu::RenderPipelineDescriptor` |
| `glAttachShader(program, vertShader)` | `descriptor.vertexFunction = library.makeFunction(name: "vertexMain")` | `vertex: VertexState { module: &shader, entry_point: "vs_main", … }` |
| `glAttachShader(program, fragShader)` | `descriptor.fragmentFunction = library.makeFunction(name: "fragmentMain")` | `fragment: Some(FragmentState { module: &shader, entry_point: "fs_main", … })` |
| `glLinkProgram(program)` | `device.makeRenderPipelineState(descriptor:)` | `device.create_render_pipeline(&descriptor)` |
| `glGetProgramiv(…, GL_LINK_STATUS, …)` | Check `makeRenderPipelineState()` error return | Check `create_render_pipeline()` for errors |
| `glGetProgramInfoLog(…)` | Error from `makeRenderPipelineState()` | wgpu validation error |
| `glDeleteShader(shader)` | Automatic (ARC) | Automatic (Drop) |
| `glUseProgram(program)` | `renderEncoder.setRenderPipelineState(pipelineState)` | `render_pass.set_pipeline(&pipeline)` |

**Usage:** `black_hole.cpp` lines 327–419, `CPU-geodesic.cpp` lines 149–188, `ray_tracing.cpp` lines 53–92

### 3.3 Compute Pipeline (OpenGL 4.3 → Metal / wgpu)

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glCreateShader(GL_COMPUTE_SHADER)` | `library.makeFunction(name: "computeMain")` | `device.create_shader_module(…)` with `@compute` entry |
| Compile + link (same as above) | `device.makeComputePipelineState(function:)` | `device.create_compute_pipeline(&ComputePipelineDescriptor { module, entry_point: "main", … })` |
| `glUseProgram(computeProgram)` | `computeEncoder.setComputePipelineState(computePipeline)` | `compute_pass.set_pipeline(&compute_pipeline)` |
| `glDispatchCompute(gX, gY, gZ)` | `computeEncoder.dispatchThreadgroups(MTLSize(gX, gY, gZ), threadsPerThreadgroup: MTLSize(16, 16, 1))` | `compute_pass.dispatch_workgroups(gX, gY, gZ)` |
| `glMemoryBarrier(GL_SHADER_IMAGE_ACCESS_BARRIER_BIT)` | `computeEncoder.endEncoding()` (implicit barrier between encoders) | Implicit between compute pass and render pass when using same texture |
| `glBindImageTexture(0, tex, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8)` | `computeEncoder.setTexture(texture, index: 0)` | Bind via bind group: `@group(0) @binding(0) var output: texture_storage_2d<rgba8unorm, write>` |

**Usage:** `black_hole.cpp` lines 420–496

---

## 4. Buffer Management

### 4.1 Vertex Buffers

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGenBuffers(1, &vbo)` | `device.makeBuffer(bytes:, length:, options:)` | `device.create_buffer_init(&BufferInitDescriptor { contents: bytemuck::cast_slice(&data), usage: BufferUsages::VERTEX })` |
| `glBindBuffer(GL_ARRAY_BUFFER, vbo)` | N/A (buffers bound at draw time) | N/A (buffers bound at draw time) |
| `glBufferData(GL_ARRAY_BUFFER, size, data, GL_STATIC_DRAW)` | `device.makeBuffer(bytes: data, length: size, options: .storageModeShared)` | `device.create_buffer_init(…)` |
| `glBufferData(…, GL_DYNAMIC_DRAW)` | `device.makeBuffer(length:, options: .storageModeShared)` then `buffer.contents().copyMemory(from:…)` | `queue.write_buffer(&buffer, 0, bytemuck::cast_slice(&data))` |
| `glBufferSubData(target, offset, size, data)` | `buffer.contents().advanced(by: offset).copyMemory(from: data, byteCount: size)` | `queue.write_buffer(&buffer, offset, bytemuck::cast_slice(&data))` |

**Usage:** `black_hole.cpp` lines 205–224 (UBOs), 281–298 (grid VBO), 570–600 (quad VBO)

### 4.2 Uniform Buffers (UBOs)

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGenBuffers(1, &ubo)` | `device.makeBuffer(length:, options: .storageModeShared)` | `device.create_buffer(&BufferDescriptor { size, usage: BufferUsages::UNIFORM \| BufferUsages::COPY_DST, … })` |
| `glBindBuffer(GL_UNIFORM_BUFFER, ubo)` | N/A (set on encoder) | N/A (bound via bind group) |
| `glBufferData(GL_UNIFORM_BUFFER, size, nil, GL_DYNAMIC_DRAW)` | `device.makeBuffer(length: size, options: .storageModeShared)` | `device.create_buffer(&BufferDescriptor { size, usage: UNIFORM \| COPY_DST, mapped_at_creation: false })` |
| `glBindBufferBase(GL_UNIFORM_BUFFER, binding, ubo)` | `encoder.setBuffer(buffer, offset: 0, index: binding)` | Bind group entry: `BindGroupEntry { binding, resource: buffer.as_entire_binding() }` |
| `glBufferSubData(GL_UNIFORM_BUFFER, 0, size, &data)` | `buffer.contents().copyMemory(from: &data, byteCount: size)` | `queue.write_buffer(&uniform_buffer, 0, bytemuck::cast_slice(&[data]))` |

**UBO binding points used in this project:**
- binding 1 → Camera UBO (80 bytes)
- binding 2 → Disk UBO (16 bytes)
- binding 3 → Objects UBO (variable)

**Usage:** `black_hole.cpp` lines 205–224 (creation), 497–556 (upload)

### 4.3 Index Buffers

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGenBuffers(1, &ebo)` | `device.makeBuffer(bytes:, length:, options:)` | `device.create_buffer_init(…)` with `BufferUsages::INDEX` |
| `glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, ebo)` | N/A (set at draw time) | N/A (set at draw time) |
| `glBufferData(GL_ELEMENT_ARRAY_BUFFER, size, data, GL_STATIC_DRAW)` | `device.makeBuffer(bytes: data, length: size, options: .storageModeShared)` | `device.create_buffer_init(&BufferInitDescriptor { contents: bytemuck::cast_slice(&indices), usage: BufferUsages::INDEX })` |

**Usage:** `black_hole.cpp` lines 283, 291

---

## 5. Vertex Array Objects (VAO) & Vertex Layout

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGenVertexArrays(1, &vao)` | `MTLVertexDescriptor()` (configured on pipeline descriptor) | `VertexBufferLayout` in `RenderPipelineDescriptor` |
| `glBindVertexArray(vao)` | N/A (vertex format is part of pipeline state) | N/A (vertex format is part of pipeline state) |
| `glVertexAttribPointer(0, 2, GL_FLOAT, GL_FALSE, stride, offset)` | `vertexDescriptor.attributes[0].format = .float2` + `.offset = 0` + `.bufferIndex = 0`; `vertexDescriptor.layouts[0].stride = stride` | `VertexAttribute { format: VertexFormat::Float32x2, offset: 0, shader_location: 0 }` in `VertexBufferLayout { array_stride: stride, … }` |
| `glVertexAttribPointer(0, 3, GL_FLOAT, …)` | `.float3` | `VertexFormat::Float32x3` |
| `glVertexAttribPointer(1, 2, GL_FLOAT, …, (void*)(2*sizeof(float)))` | `vertexDescriptor.attributes[1].format = .float2; .offset = 8` | `VertexAttribute { format: Float32x2, offset: 8, shader_location: 1 }` |
| `glEnableVertexAttribArray(index)` | Implicit (all declared attributes are enabled) | Implicit (all declared attributes are enabled) |

**Vertex layouts in this project:**

Fullscreen quad (`black_hole.cpp`, `CPU-geodesic.cpp`, `ray_tracing.cpp`):
```
location 0: vec2 position  (offset 0, stride 16)
location 1: vec2 texcoord  (offset 8, stride 16)
```

Grid overlay (`black_hole.cpp`):
```
location 0: vec3 position  (offset 0, stride 12)
```

**Usage:** `black_hole.cpp` lines 571–581 (quad), 293–294 (grid)

---

## 6. Texture Management

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGenTextures(1, &tex)` | `device.makeTexture(descriptor:)` | `device.create_texture(&TextureDescriptor { … })` |
| `glBindTexture(GL_TEXTURE_2D, tex)` | N/A (textures set on encoder) | N/A (textures bound via bind group) |
| `glTexImage2D(GL_TEXTURE_2D, 0, GL_RGBA8, w, h, 0, GL_RGBA, GL_UNSIGNED_BYTE, nil)` | `let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba8Unorm, width: w, height: h, mipmapped: false); desc.usage = [.shaderRead, .shaderWrite]; device.makeTexture(descriptor: desc)` | `device.create_texture(&TextureDescriptor { size: Extent3d { width: w, height: h, depth_or_array_layers: 1 }, format: TextureFormat::Rgba8Unorm, usage: TextureUsages::STORAGE_BINDING \| TextureUsages::TEXTURE_BINDING, … })` |
| `glTexImage2D(…, GL_RGB, …, pixels.data())` | `texture.replace(region:, mipmapLevel: 0, withBytes: data, bytesPerRow: w * 3)` (use RGBA format, convert data) | `queue.write_texture(ImageCopyTexture { texture, … }, &pixels, ImageDataLayout { bytes_per_row: Some(w * 4), … }, size)` |
| `glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, GL_LINEAR)` | `let sampler = device.makeSamplerState(descriptor: samplerDesc)` where `samplerDesc.minFilter = .linear` | `device.create_sampler(&SamplerDescriptor { min_filter: FilterMode::Linear, … })` |
| `glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, GL_LINEAR)` | `samplerDesc.magFilter = .linear` | `mag_filter: FilterMode::Linear` |
| `glActiveTexture(GL_TEXTURE0)` | N/A (textures bound by index on encoder) | N/A (textures bound via bind group) |
| `glBindImageTexture(0, tex, 0, GL_FALSE, 0, GL_WRITE_ONLY, GL_RGBA8)` | `computeEncoder.setTexture(texture, index: 0)` (texture created with `.shaderWrite` usage) | Bind as storage texture: `@group(0) @binding(0) var output: texture_storage_2d<rgba8unorm, write>` in WGSL; bind via `BindGroupEntry` |

**Usage:** `black_hole.cpp` lines 583–598 (creation), 470–478 (resize for compute), 319–321 (bind for sampling), 487 (bind as image for compute)

---

## 7. Uniform Uploads

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glGetUniformLocation(program, "name")` | N/A (use buffer bindings, not named uniforms) | N/A (use bind groups, not named uniforms) |
| `glUniform1i(loc, value)` | `encoder.setBuffer(…)` or argument buffer | Bind group with uniform buffer or inline constant |
| `glUniformMatrix4fv(loc, 1, GL_FALSE, value_ptr(mat))` | `encoder.setBytes(&matrix, length: MemoryLayout<float4x4>.size, index: N)` | `queue.write_buffer(&uniform_buf, 0, bytemuck::cast_slice(&[matrix]))` |

**Usage:** `black_hole.cpp` lines 302–303 (viewProj uniform), 321 (texture sampler uniform)

---

## 8. Rendering State

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glViewport(x, y, w, h)` | `renderEncoder.setViewport(MTLViewport(originX: x, originY: y, width: w, height: h, znear: 0, zfar: 1))` | `render_pass.set_viewport(x, y, w, h, 0.0, 1.0)` |
| `glClearColor(r, g, b, a)` | Set on `MTLRenderPassDescriptor`: `colorAttachments[0].clearColor = MTLClearColor(red: r, green: g, blue: b, alpha: a)` | Set on `RenderPassDescriptor`: `color_attachments: [RenderPassColorAttachment { ops: Operations { load: LoadOp::Clear(Color { r, g, b, a }), store: StoreOp::Store } }]` |
| `glClear(GL_COLOR_BUFFER_BIT \| GL_DEPTH_BUFFER_BIT)` | Automatic when render pass begins with `loadAction: .clear` | Automatic when render pass begins with `LoadOp::Clear(…)` |
| `glEnable(GL_DEPTH_TEST)` | `depthStencilDescriptor.depthCompareFunction = .less; descriptor.isDepthWriteEnabled = true` → `device.makeDepthStencilState(descriptor:)` → `renderEncoder.setDepthStencilState(…)` | `depth_stencil: Some(DepthStencilState { format: TextureFormat::Depth32Float, depth_write_enabled: true, depth_compare: CompareFunction::Less, … })` in pipeline descriptor |
| `glDisable(GL_DEPTH_TEST)` | Use a pipeline state created without depth stencil, or set `depthCompareFunction = .always` with `isDepthWriteEnabled = false` | Create a separate pipeline without `depth_stencil` or with `depth_compare: CompareFunction::Always` |
| `glEnable(GL_BLEND)` | Set on pipeline descriptor: `colorAttachments[0].isBlendingEnabled = true` | Set on pipeline descriptor: `ColorTargetState { blend: Some(BlendState::ALPHA_BLENDING), … }` |
| `glDisable(GL_BLEND)` | `colorAttachments[0].isBlendingEnabled = false` | `blend: None` |
| `glBlendFunc(GL_SRC_ALPHA, GL_ONE_MINUS_SRC_ALPHA)` | `colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha; .destinationRGBBlendFactor = .oneMinusSourceAlpha` (same for alpha) | `BlendState::ALPHA_BLENDING` (or manual: `BlendComponent { src_factor: SrcAlpha, dst_factor: OneMinusSrcAlpha, operation: Add }`) |

**Note:** In Metal and wgpu, blend/depth state is baked into the pipeline object, not toggled at draw time. The project uses two rendering modes (grid with blend/no-depth, quad with no-blend/no-depth), so two separate pipeline states are needed.

**Usage:** `black_hole.cpp` lines 306–313 (grid blend/depth), 315–325 (quad draw), 601–611 (scene render), 650–651 (clear)

---

## 9. Draw Commands

| OpenGL | Metal (Swift) | wgpu (Rust) |
|---|---|---|
| `glDrawArrays(GL_TRIANGLES, 0, 6)` | `renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)` | `render_pass.draw(0..6, 0..1)` |
| `glDrawArrays(GL_TRIANGLE_STRIP, 0, 6)` | `renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 6)` | Pipeline created with `topology: PrimitiveTopology::TriangleStrip`; `render_pass.draw(0..6, 0..1)` |
| `glDrawElements(GL_LINES, count, GL_UNSIGNED_INT, 0)` | `renderEncoder.drawIndexedPrimitives(type: .line, indexCount: count, indexType: .uint32, indexBuffer: ebo, indexBufferOffset: 0)` | Pipeline created with `topology: PrimitiveTopology::LineList`; `render_pass.set_index_buffer(ebo.slice(..), IndexFormat::Uint32); render_pass.draw_indexed(0..count, 0, 0..1)` |

**Primitive topology mapping:**

| OpenGL | Metal | wgpu |
|---|---|---|
| `GL_TRIANGLES` | `.triangle` | `PrimitiveTopology::TriangleList` |
| `GL_TRIANGLE_STRIP` | `.triangleStrip` | `PrimitiveTopology::TriangleStrip` |
| `GL_TRIANGLE_FAN` | N/A (convert to triangles) | N/A (convert to triangles) |
| `GL_LINES` | `.line` | `PrimitiveTopology::LineList` |
| `GL_LINE_STRIP` | `.lineStrip` | `PrimitiveTopology::LineStrip` |
| `GL_POINTS` | `.point` | `PrimitiveTopology::PointList` |

**Usage:** `black_hole.cpp` lines 310 (grid lines), 324 (quad strip), 608 (quad triangles)

---

## 10. Legacy OpenGL (2D_lensing.cpp only)

These calls from `2D_lensing.cpp` use the fixed-function pipeline (OpenGL 1.x/2.x) and have **no direct Metal/wgpu equivalent**. They must be rewritten as modern vertex-buffer-based rendering.

| Legacy OpenGL | Replacement Strategy |
|---|---|
| `glMatrixMode(GL_PROJECTION)` | Compute projection matrix on CPU, upload as uniform |
| `glLoadIdentity()` | Use identity matrix constant |
| `glOrtho(l, r, b, t, n, f)` | `simd_float4x4` ortho projection (Metal) / `glam::Mat4::orthographic_rh(l, r, b, t, n, f)` (Rust) |
| `glMatrixMode(GL_MODELVIEW)` | Compute model-view matrix on CPU, upload as uniform |
| `glBegin(GL_TRIANGLE_FAN)` | Build vertex buffer from fan vertices, convert to triangle list |
| `glBegin(GL_POINTS)` | Build vertex buffer of point positions, render with point topology |
| `glBegin(GL_LINE_STRIP)` | Build vertex buffer of line vertices, render with line strip topology |
| `glEnd()` | Upload vertex buffer, issue draw call |
| `glVertex2f(x, y)` | Append `(x, y)` to vertex buffer array |
| `glColor3f(r, g, b)` | Add color attribute to vertex struct: `struct Vertex { float2 pos; float4 color; }` |
| `glColor4f(r, g, b, a)` | Same with alpha |
| `glPointSize(size)` | Metal: not supported per-draw (use vertex shader to enlarge points); wgpu: not supported (render as small quads) |
| `glLineWidth(width)` | Metal: not supported (always 1px); wgpu: not supported (always 1px). Workaround: screen-space line quads in geometry/vertex shader |

**Usage:** `2D_lensing.cpp` lines 60–68, 79–90, 119–148

---

## 11. Shader Language Mapping (GLSL → MSL / WGSL)

### 11.1 Shader Stage Declarations

| GLSL | Metal Shading Language (MSL) | WGSL |
|---|---|---|
| `#version 430` | N/A (version is implicit) | N/A |
| `#version 330 core` | N/A | N/A |
| `layout(local_size_x=16, local_size_y=16) in;` | `[[kernel]] void main(uint2 gid [[thread_position_in_grid]])` with dispatch specifying threadgroup size | `@compute @workgroup_size(16, 16) fn main(@builtin(global_invocation_id) gid: vec3u)` |
| `layout(location = 0) in vec2 aPos;` | `struct VertexIn { float2 pos [[attribute(0)]]; };` as parameter: `vertex VertexOut main(VertexIn in [[stage_in]])` | `struct VertexIn { @location(0) pos: vec2f };` as parameter: `@vertex fn vs_main(in: VertexIn) -> VertexOut` |
| `layout(location = 0) in vec3 aPos;` | `float3 pos [[attribute(0)]]` | `@location(0) pos: vec3f` |
| `layout(location = 1) in vec2 aTexCoord;` | `float2 texCoord [[attribute(1)]]` | `@location(1) tex_coord: vec2f` |
| `out vec2 TexCoord;` | Return struct member: `float2 texCoord [[user(texcoord)]];` | Return struct member: `@location(0) tex_coord: vec2f` |
| `in vec2 TexCoord;` (fragment) | `float2 texCoord [[user(texcoord)]]` in fragment input struct | `@location(0) tex_coord: vec2f` in fragment input struct |
| `out vec4 FragColor;` | Return `float4` from fragment function: `fragment float4 main(…)` | `@location(0)` in return struct, or return `vec4f` directly |
| `gl_Position = vec4(…)` | Return struct member: `float4 position [[position]]` | Return struct member: `@builtin(position) pos: vec4f` |

**Usage:** `geodesic.comp` lines 1–28, `grid.vert` lines 1–6, `grid.frag` lines 1–5, inline shaders in `black_hole.cpp` lines 328–345

### 11.2 Uniform / Buffer Bindings

| GLSL | MSL | WGSL |
|---|---|---|
| `layout(std140, binding = 1) uniform Camera { … } cam;` | `struct Camera { … }; kernel void main(constant Camera& cam [[buffer(1)]])` | `struct Camera { … }; @group(0) @binding(1) var<uniform> cam: Camera;` |
| `layout(std140, binding = 2) uniform Disk { … };` | `constant Disk& disk [[buffer(2)]]` | `@group(0) @binding(2) var<uniform> disk: Disk;` |
| `layout(std140, binding = 3) uniform Objects { … };` | `constant Objects& objects [[buffer(3)]]` | `@group(0) @binding(3) var<uniform> objects: Objects;` |
| `layout(binding = 0, rgba8) writeonly uniform image2D outImage;` | `texture2d<float, access::write> outImage [[texture(0)]]` | `@group(0) @binding(0) var output: texture_storage_2d<rgba8unorm, write>;` |
| `uniform mat4 viewProj;` | `constant float4x4& viewProj [[buffer(0)]]` or in a struct | `@group(0) @binding(0) var<uniform> viewProj: mat4x4f;` |
| `uniform sampler2D screenTexture;` | `texture2d<float> tex [[texture(0)]], sampler samp [[sampler(0)]]` | `@group(0) @binding(0) var tex: texture_2d<f32>; @group(0) @binding(1) var samp: sampler;` |

**Usage:** `geodesic.comp` lines 4–28 (UBO declarations)

### 11.3 Texture Operations

| GLSL | MSL | WGSL |
|---|---|---|
| `imageStore(outImage, ivec2(pix), color)` | `outImage.write(color, uint2(pix))` | `textureStore(output, vec2u(pix), color)` |
| `texture(screenTexture, TexCoord)` | `tex.sample(samp, texCoord)` | `textureSample(tex, samp, tex_coord)` |
| `gl_GlobalInvocationID.xy` | `gid` (from `[[thread_position_in_grid]]`) | `gid.xy` (from `@builtin(global_invocation_id)`) |

**Usage:** `geodesic.comp` line 176 (imageStore), inline fragment shader in `black_hole.cpp` line 344

### 11.4 Type Mapping

| GLSL | MSL | WGSL |
|---|---|---|
| `float` | `float` | `f32` |
| `double` | N/A (use `float`) | N/A (use `f32`; no native f64 in compute) |
| `int` | `int` | `i32` |
| `uint` | `uint` | `u32` |
| `bool` | `bool` | `bool` |
| `vec2` | `float2` | `vec2f` (or `vec2<f32>`) |
| `vec3` | `float3` | `vec3f` |
| `vec4` | `float4` | `vec4f` |
| `ivec2` | `int2` | `vec2i` (or `vec2<i32>`) |
| `mat4` | `float4x4` | `mat4x4f` (or `mat4x4<f32>`) |

### 11.5 Built-in Function Mapping

| GLSL | MSL | WGSL |
|---|---|---|
| `length(v)` | `length(v)` | `length(v)` |
| `normalize(v)` | `normalize(v)` | `normalize(v)` |
| `dot(a, b)` | `dot(a, b)` | `dot(a, b)` |
| `cross(a, b)` | `cross(a, b)` | `cross(a, b)` |
| `distance(a, b)` | `distance(a, b)` | `distance(a, b)` |
| `max(a, b)` | `max(a, b)` | `max(a, b)` |
| `min(a, b)` | `min(a, b)` | `min(a, b)` |
| `clamp(x, lo, hi)` | `clamp(x, lo, hi)` | `clamp(x, lo, hi)` |
| `mix(a, b, t)` | `mix(a, b, t)` | `mix(a, b, t)` |
| `sqrt(x)` | `sqrt(x)` | `sqrt(x)` |
| `sin(x)` / `cos(x)` | `sin(x)` / `cos(x)` | `sin(x)` / `cos(x)` |
| `acos(x)` | `acos(x)` | `acos(x)` |
| `atan(y, x)` | `atan2(y, x)` | `atan2(y, x)` |
| `abs(x)` | `abs(x)` | `abs(x)` |

### 11.6 Struct and Flow Control

| GLSL | MSL | WGSL |
|---|---|---|
| `struct Ray { float x; … };` | `struct Ray { float x; … };` | `struct Ray { x: f32, … };` |
| `out vec3 d1` (function param) | `thread float3& d1` (reference param) | Return a struct (WGSL has no out params): `fn geodesicRHS(ray: Ray) -> GeodesicResult` |
| `inout Ray ray` (function param) | `thread Ray& ray` | `fn rk4Step(ray: ptr<function, Ray>, dL: f32)` |
| `if / else / for` | Same syntax | Same syntax (with `var` for mutable, `let` for immutable) |

---

## 12. Math Library Mapping (GLM → simd / glam)

| GLM (C++) | simd (Swift) | glam (Rust) |
|---|---|---|
| `#include <glm/glm.hpp>` | `import simd` (built-in) | `use glam::*;` |
| `vec2(x, y)` | `SIMD2<Float>(x, y)` or `float2(x, y)` | `Vec2::new(x, y)` or `vec2(x, y)` |
| `vec3(x, y, z)` | `SIMD3<Float>(x, y, z)` or `float3(x, y, z)` | `Vec3::new(x, y, z)` or `vec3(x, y, z)` |
| `vec4(x, y, z, w)` | `SIMD4<Float>(x, y, z, w)` or `float4(x, y, z, w)` | `Vec4::new(x, y, z, w)` or `vec4(x, y, z, w)` |
| `mat4(…)` | `float4x4(…)` | `Mat4::from_cols(…)` |
| `glm::normalize(v)` | `simd_normalize(v)` | `v.normalize()` |
| `glm::cross(a, b)` | `simd_cross(a, b)` | `a.cross(b)` |
| `glm::dot(a, b)` | `simd_dot(a, b)` | `a.dot(b)` |
| `glm::length(v)` | `simd_length(v)` | `v.length()` |
| `glm::distance(a, b)` | `simd_distance(a, b)` | `a.distance(b)` |
| `glm::clamp(x, lo, hi)` | `simd_clamp(x, lo, hi)` | `x.clamp(lo, hi)` or `f32::clamp(x, lo, hi)` |
| `glm::lookAt(eye, target, up)` | Custom implementation (simd has no lookAt) | `Mat4::look_at_rh(eye, target, up)` |
| `glm::perspective(fov, aspect, near, far)` | Custom implementation (simd has no perspective) | `Mat4::perspective_rh(fov, aspect, near, far)` |
| `glm::radians(degrees)` | `degrees * .pi / 180.0` | `degrees.to_radians()` |
| `glm::value_ptr(mat)` | `withUnsafePointer(to: &mat) { … }` (for Metal buffer upload) | `mat.to_cols_array()` or `bytemuck::cast_slice(&[mat])` |

**Usage:** throughout all `.cpp` files for vector/matrix operations

---

## 13. Command Encoding Pattern (Conceptual)

### OpenGL (current — implicit state machine)

```
// Set state, draw, set state, draw...
glUseProgram(computeProgram);
glBindImageTexture(…);
glDispatchCompute(gX, gY, 1);
glMemoryBarrier(…);

glUseProgram(gridShader);
glBindVertexArray(gridVAO);
glDrawElements(GL_LINES, …);

glUseProgram(quadShader);
glBindVertexArray(quadVAO);
glDrawArrays(GL_TRIANGLES, 0, 6);

glfwSwapBuffers(window);
```

### Metal (explicit command buffer)

```swift
let commandBuffer = commandQueue.makeCommandBuffer()!

// Compute pass
let computeEncoder = commandBuffer.makeComputeCommandEncoder()!
computeEncoder.setComputePipelineState(geodesicPipeline)
computeEncoder.setTexture(outputTexture, index: 0)
computeEncoder.setBuffer(cameraBuffer, offset: 0, index: 1)
computeEncoder.setBuffer(diskBuffer, offset: 0, index: 2)
computeEncoder.setBuffer(objectsBuffer, offset: 0, index: 3)
computeEncoder.dispatchThreadgroups(
    MTLSize(width: groupsX, height: groupsY, depth: 1),
    threadsPerThreadgroup: MTLSize(width: 16, height: 16, depth: 1))
computeEncoder.endEncoding()

// Render pass (grid + quad)
let renderDesc = MTLRenderPassDescriptor()
renderDesc.colorAttachments[0].texture = drawable.texture
renderDesc.colorAttachments[0].loadAction = .clear
renderDesc.colorAttachments[0].clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 1)
let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDesc)!

// Grid sub-pass
renderEncoder.setRenderPipelineState(gridPipeline)
renderEncoder.setVertexBuffer(gridVBO, offset: 0, index: 0)
renderEncoder.setVertexBytes(&viewProj, length: MemoryLayout<float4x4>.size, index: 1)
renderEncoder.drawIndexedPrimitives(type: .line, indexCount: gridIndexCount,
    indexType: .uint32, indexBuffer: gridEBO, indexBufferOffset: 0)

// Quad sub-pass
renderEncoder.setRenderPipelineState(quadPipeline)
renderEncoder.setVertexBuffer(quadVBO, offset: 0, index: 0)
renderEncoder.setFragmentTexture(outputTexture, index: 0)
renderEncoder.setFragmentSamplerState(linearSampler, index: 0)
renderEncoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)

renderEncoder.endEncoding()
commandBuffer.present(drawable)
commandBuffer.commit()
```

### wgpu (explicit command encoder)

```rust
let mut encoder = device.create_command_encoder(&CommandEncoderDescriptor::default());

// Compute pass
{
    let mut cpass = encoder.begin_compute_pass(&ComputePassDescriptor::default());
    cpass.set_pipeline(&geodesic_pipeline);
    cpass.set_bind_group(0, &compute_bind_group, &[]);
    cpass.dispatch_workgroups(groups_x, groups_y, 1);
}

// Render pass (grid + quad)
{
    let mut rpass = encoder.begin_render_pass(&RenderPassDescriptor {
        color_attachments: &[Some(RenderPassColorAttachment {
            view: &surface_view,
            ops: Operations { load: LoadOp::Clear(Color::BLACK), store: StoreOp::Store },
            ..Default::default()
        })],
        ..Default::default()
    });

    // Grid sub-pass
    rpass.set_pipeline(&grid_pipeline);
    rpass.set_vertex_buffer(0, grid_vbo.slice(..));
    rpass.set_index_buffer(grid_ebo.slice(..), IndexFormat::Uint32);
    rpass.set_bind_group(0, &grid_bind_group, &[]);
    rpass.draw_indexed(0..grid_index_count, 0, 0..1);

    // Quad sub-pass
    rpass.set_pipeline(&quad_pipeline);
    rpass.set_vertex_buffer(0, quad_vbo.slice(..));
    rpass.set_bind_group(0, &quad_bind_group, &[]);
    rpass.draw(0..6, 0..1);
}

queue.submit(std::iter::once(encoder.finish()));
surface_texture.present();
```

---

## 14. Resource Lifecycle Summary

| Concern | OpenGL | Metal | wgpu |
|---|---|---|---|
| Object creation | `glGen*()` | `device.make*()` | `device.create_*()` |
| Object deletion | `glDelete*()` | ARC (automatic) | Drop trait (automatic) |
| Binding model | Global state (`glBind*`) | Set on command encoder per draw | Set on command encoder per draw via bind groups |
| State changes | Mutable global state (`glEnable/glDisable`) | Immutable pipeline state objects | Immutable pipeline state objects |
| Synchronization | `glMemoryBarrier()`, `glFinish()` | Command buffer ordering + `MTLFence`/`MTLEvent` | Automatic between passes; explicit via `encoder.copy_*` ordering |
| Present | `glfwSwapBuffers()` | `commandBuffer.present(drawable)` | `surface_texture.present()` |

---

## 15. Pipeline State Objects Needed

Based on the OpenGL state combinations used in this project, the following distinct pipeline state objects must be created:

| Pipeline | Topology | Blend | Depth | Shaders | Source |
|---|---|---|---|---|---|
| **Geodesic compute** | N/A (compute) | N/A | N/A | `geodesic.comp` → `.metal` / `.wgsl` | `black_hole.cpp` line 204 |
| **Fullscreen quad** | Triangle list | Off | Off | Inline vertex+fragment → `.metal` / `.wgsl` | `black_hole.cpp` lines 327–365 |
| **Grid overlay** | Line list (indexed) | Alpha blend (src_alpha, one_minus_src_alpha) | Off | `grid.vert` + `grid.frag` → `.metal` / `.wgsl` | `black_hole.cpp` lines 300–313, line 202 |

---

## 16. Bind Group / Argument Layout

### Compute shader bind group (geodesic)

| Binding | Type | GLSL | MSL | WGSL |
|---|---|---|---|---|
| 0 | Storage texture (write) | `layout(binding=0, rgba8) writeonly uniform image2D` | `texture2d<float, access::write> [[texture(0)]]` | `@group(0) @binding(0) var output: texture_storage_2d<rgba8unorm, write>` |
| 1 | Uniform buffer | `layout(std140, binding=1) uniform Camera { … }` | `constant Camera& cam [[buffer(1)]]` | `@group(0) @binding(1) var<uniform> cam: Camera` |
| 2 | Uniform buffer | `layout(std140, binding=2) uniform Disk { … }` | `constant Disk& disk [[buffer(2)]]` | `@group(0) @binding(2) var<uniform> disk: Disk` |
| 3 | Uniform buffer | `layout(std140, binding=3) uniform Objects { … }` | `constant Objects& objs [[buffer(3)]]` | `@group(0) @binding(3) var<uniform> objs: Objects` |

### Quad shader bind group

| Binding | Type | GLSL | MSL | WGSL |
|---|---|---|---|---|
| 0 | Sampled texture | `uniform sampler2D screenTexture` | `texture2d<float> tex [[texture(0)]]` | `@group(0) @binding(0) var tex: texture_2d<f32>` |
| 1 | Sampler | (implicit in GLSL sampler2D) | `sampler samp [[sampler(0)]]` | `@group(0) @binding(1) var samp: sampler` |

### Grid shader bind group

| Binding | Type | GLSL | MSL | WGSL |
|---|---|---|---|---|
| 0 | Uniform buffer | `uniform mat4 viewProj` | `constant float4x4& viewProj [[buffer(0)]]` | `@group(0) @binding(0) var<uniform> viewProj: mat4x4f` |
