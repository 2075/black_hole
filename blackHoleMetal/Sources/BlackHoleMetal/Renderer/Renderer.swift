import MetalKit
import simd
import AppKit

/// Main Metal renderer -- owns the compute and render pipelines, camera, and scene state.
/// Replaces the C++ Engine struct from black_hole.cpp.
final class Renderer: NSObject, MTKViewDelegate {

    // MARK: - Metal Core Objects

    private let device: MTLDevice
    private let commandQueue: MTLCommandQueue

    // MARK: - Pipelines

    private var computePipeline: MTLComputePipelineState?
    private var quadRenderPipeline: MTLRenderPipelineState?
    private var gridRenderPipeline: MTLRenderPipelineState?

    // MARK: - Buffers

    private var quadVertexBuffer: MTLBuffer?
    private var gridVertexBuffer: MTLBuffer?
    private var gridIndexBuffer: MTLBuffer?
    private var gridIndexCount: Int = 0

    /// Fixed grid resolution (matches black_hole.cpp gridSize = 25).
    private let gridSize: Int = 25

    /// Set on first frame; grid only regenerates when gravity moves objects.
    private var needsGridUpdate: Bool = true

    // MARK: - Textures (Double-Buffered)

    /// Two compute textures for double-buffering: one is displayed while the
    /// other receives the next geodesic compute result.
    private var computeTextures: [MTLTexture?] = [nil, nil]

    /// Index into `computeTextures` for the texture currently shown by the
    /// render pass.
    private var displayTextureIndex: Int = 0

    /// `true` while a compute command buffer is in-flight on the GPU.
    /// Prevents piling up redundant compute work.
    private var computeInFlight: Bool = false

    // MARK: - Dirty Flag

    /// When `false`, the previous `computeTexture` is reused and the expensive
    /// geodesic compute dispatch is skipped entirely.
    private var needsComputeUpdate: Bool = true

    // MARK: - Scene

    let camera = Camera()
    let gravitySim = GravitySim()
    var sceneObjects: [SceneObject] = makeDefaultSceneObjects()

    // MARK: - Input

    /// Handle key events forwarded from InputMTKView.
    func handleKeyDown(with event: NSEvent) {
        let chars = event.charactersIgnoringModifiers ?? "<none>"
        print("[KEY] code=\(event.keyCode) chars=\"\(chars)\" repeat=\(event.isARepeat)")

        // Arrow keys (use keyCode since arrows have no printable character)
        switch event.keyCode {
        case 126: camera.nudgeElevation(by: -camera.arrowStep); return  // up arrow
        case 125: camera.nudgeElevation(by:  camera.arrowStep); return  // down arrow
        case 123: camera.nudgeAzimuth(by: -camera.arrowStep);   return  // left arrow
        case 124: camera.nudgeAzimuth(by:  camera.arrowStep);   return  // right arrow
        default: break
        }

        guard let chars = event.charactersIgnoringModifiers?.lowercased() else { return }

        switch chars {
        case "g":
            gravitySim.isEnabled.toggle()
            needsComputeUpdate = true
            print("[INFO] Gravity turned \(gravitySim.isEnabled ? "ON" : "OFF")")

        case "c":
            guard !event.isARepeat else { return }
            randomizeColorPalette()

        case "1", "2", "3", "4", "5", "6", "7", "8", "9":
            guard !event.isARepeat else { return }
            setResolutionLevel(Int(chars)!)

        default:
            break
        }
    }

    // MARK: - Color Palette

    /// Base color for the accretion disk (randomized by 'c' key)
    private var diskBaseColor: SIMD4<Float> = SIMD4<Float>(1.0, 0.7, 0.2, 1.0)

    /// Randomize colors for scene objects and the accretion disk.
    private func randomizeColorPalette() {
        for i in 0..<sceneObjects.count {
            // Skip the black hole (black object)
            let c = sceneObjects[i].color
            if c.x == 0 && c.y == 0 && c.z == 0 { continue }

            sceneObjects[i].color = SIMD4<Float>(
                hsbComponent(Float.random(in: 0...1)),
                hsbComponent(Float.random(in: 0...1)),
                hsbComponent(Float.random(in: 0...1)),
                1.0
            )
        }

        // Randomize disk color (warm-biased for a natural thermal look)
        diskBaseColor = SIMD4<Float>(
            Float.random(in: 0.5...1.0),
            Float.random(in: 0.2...1.0),
            Float.random(in: 0.1...0.8),
            1.0
        )

        needsComputeUpdate = true
        print("[INFO] Color palette randomized – disk: (\(diskBaseColor.x), \(diskBaseColor.y), \(diskBaseColor.z))")
    }

    /// Produce a vivid color channel value from a uniform random input.
    private func hsbComponent(_ t: Float) -> Float {
        return 0.3 + t * 0.7  // range [0.3, 1.0] avoids too-dark components
    }

    // MARK: - Resolution

    /// Window resolution
    private var viewportSize: SIMD2<UInt32> = SIMD2(800, 600)

    /// Base unit for compute resolution
    private let baseComputeWidth: Int = 100
    private let baseComputeHeight: Int = 75

    /// Current resolution multiplier (1–9)
    private var resolutionLevel: Int = 2

    /// Compute shader resolution (derived from resolutionLevel)
    private var computeWidth: Int { baseComputeWidth * resolutionLevel }
    private var computeHeight: Int { baseComputeHeight * resolutionLevel }

    /// Change the compute resolution level and reallocate the texture.
    private func setResolutionLevel(_ level: Int) {
        let clamped = max(1, min(9, level))
        guard clamped != resolutionLevel else { return }
        resolutionLevel = clamped
        allocateComputeTexture()
        needsComputeUpdate = true
        print("[INFO] Resolution level \(resolutionLevel): \(computeWidth)×\(computeHeight)")
    }

    // MARK: - Depth Stencil

    private var depthStencilState: MTLDepthStencilState?

    // MARK: - Initialization

    init(device: MTLDevice, view: MTKView) {
        self.device = device
        guard let queue = device.makeCommandQueue() else {
            fatalError("Failed to create Metal command queue")
        }
        self.commandQueue = queue

        super.init()

        buildShaderLibrary()
        buildComputePipeline()
        buildQuadRenderPipeline(pixelFormat: view.colorPixelFormat)
        buildGridRenderPipeline(pixelFormat: view.colorPixelFormat,
                                depthFormat: view.depthStencilPixelFormat)
        buildDepthStencilState()
        buildQuadVertexBuffer()
        buildGridBuffers()
        allocateComputeTexture()
    }

    // MARK: - Pipeline Construction

    /// Compiled Metal shader library (from .metal source files bundled as resources).
    private var shaderLibrary: MTLLibrary?

    private func buildShaderLibrary() {
        // Load all .metal sources from the app bundle resources and compile them.
        // The shader files are copied into the bundle by Package.swift resource rules.
        let shaderNames = ["geodesic", "grid", "quad"]
        var combinedSource = "#include <metal_stdlib>\nusing namespace metal;\n\n"

        for name in shaderNames {
            guard let url = Bundle.module.url(forResource: name, withExtension: "metal") else {
                print("[Warning] Missing shader resource: \(name).metal")
                continue
            }
            guard var source = try? String(contentsOf: url, encoding: .utf8) else {
                print("[Warning] Failed to read shader: \(name).metal")
                continue
            }

            // Strip duplicate #include and using directives since we add them once at the top
            source = source.replacingOccurrences(of: "#include <metal_stdlib>", with: "")
            source = source.replacingOccurrences(of: "using namespace metal;", with: "")

            combinedSource += "// --- \(name).metal ---\n" + source + "\n"
        }

        do {
            shaderLibrary = try device.makeLibrary(source: combinedSource, options: nil)
            print("[Info] Metal shaders compiled successfully")
        } catch {
            print("[Error] Failed to compile Metal shaders: \(error)")
            shaderLibrary = device.makeDefaultLibrary()
        }
    }

    private func buildComputePipeline() {
        guard let library = shaderLibrary,
              let kernel = library.makeFunction(name: "geodesicKernel") else {
            print("[Warning] geodesicKernel function not found in shader library")
            return
        }
        do {
            computePipeline = try device.makeComputePipelineState(function: kernel)
        } catch {
            print("[Error] Failed to create compute pipeline: \(error)")
        }
    }

    private func buildQuadRenderPipeline(pixelFormat: MTLPixelFormat) {
        guard let library = shaderLibrary else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "quadVertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "quadFragmentShader")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat

        do {
            quadRenderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[Error] Failed to create quad render pipeline: \(error)")
        }
    }

    private func buildGridRenderPipeline(pixelFormat: MTLPixelFormat, depthFormat: MTLPixelFormat) {
        guard let library = shaderLibrary else { return }

        let descriptor = MTLRenderPipelineDescriptor()
        descriptor.vertexFunction = library.makeFunction(name: "gridVertexShader")
        descriptor.fragmentFunction = library.makeFunction(name: "gridFragmentShader")
        descriptor.colorAttachments[0].pixelFormat = pixelFormat
        descriptor.colorAttachments[0].isBlendingEnabled = true
        descriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        descriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
        descriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        descriptor.depthAttachmentPixelFormat = depthFormat

        do {
            gridRenderPipeline = try device.makeRenderPipelineState(descriptor: descriptor)
        } catch {
            print("[Error] Failed to create grid render pipeline: \(error)")
        }
    }

    private func buildDepthStencilState() {
        let descriptor = MTLDepthStencilDescriptor()
        descriptor.depthCompareFunction = .less
        descriptor.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: descriptor)
    }

    // MARK: - Resource Allocation

    private func buildQuadVertexBuffer() {
        // Fullscreen quad: 6 vertices (2 triangles), each with position (x,y) + texcoord (u,v)
        let quadVertices: [Float] = [
            // pos        texcoord
            -1.0,  1.0,   0.0, 1.0,   // top-left
            -1.0, -1.0,   0.0, 0.0,   // bottom-left
             1.0, -1.0,   1.0, 0.0,   // bottom-right

            -1.0,  1.0,   0.0, 1.0,   // top-left
             1.0, -1.0,   1.0, 0.0,   // bottom-right
             1.0,  1.0,   1.0, 1.0,   // top-right
        ]
        quadVertexBuffer = device.makeBuffer(
            bytes: quadVertices,
            length: quadVertices.count * MemoryLayout<Float>.size,
            options: .storageModeShared
        )
    }

    /// Allocate fixed-size grid buffers once. Index topology is constant and
    /// written here; vertex positions are updated by `updateGridVertices()`.
    private func buildGridBuffers() {
        let vertexCount = (gridSize + 1) * (gridSize + 1)
        gridVertexBuffer = device.makeBuffer(
            length: vertexCount * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )

        var indices: [UInt32] = []
        indices.reserveCapacity(gridSize * gridSize * 4)
        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let i = UInt32(z * (gridSize + 1) + x)
                indices.append(contentsOf: [i, i + 1])
                indices.append(contentsOf: [i, i + UInt32(gridSize + 1)])
            }
        }
        gridIndexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        )
        gridIndexCount = indices.count
    }

    private func allocateComputeTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: computeWidth,
            height: computeHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        computeTextures[0] = device.makeTexture(descriptor: desc)
        computeTextures[1] = device.makeTexture(descriptor: desc)
        displayTextureIndex = 0
        computeInFlight = false
    }

    // MARK: - Grid Generation (CPU)

    /// Update grid vertex positions in-place. Index topology is constant and
    /// written once by `buildGridBuffers()`.
    private func updateGridVertices() {
        guard let buffer = gridVertexBuffer else { return }
        let spacing: Float = 1e10
        let vertexCount = (gridSize + 1) * (gridSize + 1)
        let ptr = buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)

        var idx = 0
        for z in 0...gridSize {
            for x in 0...gridSize {
                let worldX = Float(x - gridSize / 2) * spacing
                let worldZ = Float(z - gridSize / 2) * spacing
                var y: Float = 0.0

                for obj in sceneObjects {
                    let objPos = SIMD3<Float>(obj.posRadius.x, obj.posRadius.y, obj.posRadius.z)
                    let r_s = 2.0 * kGravitationalConstant * Double(obj.mass) / (kSpeedOfLight * kSpeedOfLight)
                    let dx = Double(worldX - objPos.x)
                    let dz = Double(worldZ - objPos.z)
                    let dist = sqrt(dx * dx + dz * dz)

                    if dist > r_s {
                        let deltaY = 2.0 * sqrt(r_s * (dist - r_s))
                        y += Float(deltaY) - 3e10
                    } else {
                        y += 2.0 * Float(sqrt(r_s * r_s)) - 3e10
                    }
                }

                ptr[idx] = SIMD3<Float>(worldX, y, worldZ)
                idx += 1
            }
        }
    }

    // MARK: - Uniform Uploads

    /// Adaptive step count: low during interaction for snappy preview, full when static.
    private static let interactionStepCount: Int32 = 5_000
    private static let fullStepCount: Int32 = Int32(kDefaultStepCount)

    private func makeCameraUniforms() -> CameraUniforms {
        let aspect = Float(viewportSize.x) / Float(viewportSize.y)
        let steps = (camera.isMoving || camera.isDragging)
            ? Self.interactionStepCount
            : Self.fullStepCount
        return camera.uniforms(aspect: aspect, stepCount: steps)
    }

    private func makeDiskUniforms() -> DiskUniforms {
        let rs = Float(kSagASchwarzschildRadius)
        return DiskUniforms(
            innerRadius: rs * kDiskInnerFactor,
            outerRadius: rs * kDiskOuterFactor,
            diskNum: 2.0,
            thickness: kDiskThickness,
            diskColor: diskBaseColor
        )
    }

    private func makeObjectsUniforms() -> ObjectsUniforms {
        var uniforms = ObjectsUniforms()
        let count = min(sceneObjects.count, 16)
        uniforms.numObjects = Int32(count)

        // Use withUnsafeMutablePointer to write into the fixed-size tuple arrays
        withUnsafeMutablePointer(to: &uniforms.posRadius) { ptr in
            let base = UnsafeMutableRawPointer(ptr).bindMemory(to: SIMD4<Float>.self, capacity: 16)
            for i in 0..<count { base[i] = sceneObjects[i].posRadius }
        }
        withUnsafeMutablePointer(to: &uniforms.color) { ptr in
            let base = UnsafeMutableRawPointer(ptr).bindMemory(to: SIMD4<Float>.self, capacity: 16)
            for i in 0..<count { base[i] = sceneObjects[i].color }
        }
        withUnsafeMutablePointer(to: &uniforms.mass) { ptr in
            let base = UnsafeMutableRawPointer(ptr).bindMemory(to: Float.self, capacity: 16)
            for i in 0..<count { base[i] = sceneObjects[i].mass }
        }

        return uniforms
    }

    // MARK: - MTKViewDelegate

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        viewportSize = SIMD2(UInt32(size.width), UInt32(size.height))
        needsComputeUpdate = true
    }

    func draw(in view: MTKView) {
        // 1) N-body gravity update
        let gravityActive = gravitySim.isEnabled
        gravitySim.step(objects: &sceneObjects, dt: 1.0 / 60.0)

        // 2) Determine whether the compute shader needs to run this frame
        if camera.hasChanged {
            needsComputeUpdate = true
            camera.clearChanged()
        }
        if gravityActive {
            needsComputeUpdate = true
        }

        // 3) Regenerate spacetime curvature grid (skip if objects haven't moved)
        if needsGridUpdate || gravityActive {
            updateGridVertices()
            needsGridUpdate = false
        }

        // 4) Dispatch geodesic compute into the back texture (double-buffered).
        //    If a previous compute is still in-flight, skip and retry next frame.
        if needsComputeUpdate && !computeInFlight {
            dispatchCompute()
            needsComputeUpdate = false
        }

        // 5) Render pass (separate command buffer): fullscreen quad + grid overlay
        guard let renderBuffer = commandQueue.makeCommandBuffer() else { return }
        renderBuffer.label = "Render"

        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            renderBuffer.commit()
            return
        }

        guard let renderEncoder = renderBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            renderBuffer.commit()
            return
        }

        drawFullscreenQuad(encoder: renderEncoder)
        drawGrid(encoder: renderEncoder)

        renderEncoder.endEncoding()
        renderBuffer.present(drawable)
        renderBuffer.commit()

        // Clear transient movement flag so scroll/keyboard impulses don't
        // stick.  Continuous drag re-sets it every event before the next frame.
        // If movement just ended, schedule one more compute at full step count.
        if camera.isMoving {
            needsComputeUpdate = true
            camera.clearMoving()
        }

        // Pause the render loop when the scene is fully static to drop GPU
        // usage to zero.  InputMTKView unpauses on any user input.
        if !needsComputeUpdate && !computeInFlight && !gravityActive && !camera.isDragging {
            view.isPaused = true
        }
    }

    // MARK: - Compute Dispatch

    private func dispatchCompute() {
        let writeIndex = 1 - displayTextureIndex

        guard let pipeline = computePipeline,
              let texture = computeTextures[writeIndex],
              let computeBuffer = commandQueue.makeCommandBuffer() else { return }

        computeInFlight = true
        computeBuffer.label = "Geodesic Compute"

        guard let encoder = computeBuffer.makeComputeCommandEncoder() else {
            computeInFlight = false
            return
        }

        encoder.setComputePipelineState(pipeline)
        encoder.setTexture(texture, index: 0)

        // Upload uniforms
        var camUniforms = makeCameraUniforms()
        encoder.setBytes(&camUniforms, length: MemoryLayout<CameraUniforms>.size, index: 0)

        var diskUniforms = makeDiskUniforms()
        encoder.setBytes(&diskUniforms, length: MemoryLayout<DiskUniforms>.size, index: 1)

        var objUniforms = makeObjectsUniforms()
        encoder.setBytes(&objUniforms, length: MemoryLayout<ObjectsUniforms>.size, index: 2)

        // Dispatch threadgroups to cover the compute texture
        let groupSize = kWorkgroupSize
        let threadgroupsPerGrid = MTLSize(
            width: (computeWidth + groupSize - 1) / groupSize,
            height: (computeHeight + groupSize - 1) / groupSize,
            depth: 1
        )
        let threadsPerThreadgroup = MTLSize(width: groupSize, height: groupSize, depth: 1)
        encoder.dispatchThreadgroups(threadgroupsPerGrid, threadsPerThreadgroup: threadsPerThreadgroup)

        encoder.endEncoding()

        // Flip the display texture to the freshly-computed one once the GPU
        // finishes.  Dispatched to main so draw(in:) never races with the swap.
        computeBuffer.addCompletedHandler { [weak self] _ in
            DispatchQueue.main.async {
                guard let self = self else { return }
                self.displayTextureIndex = writeIndex
                self.computeInFlight = false
            }
        }

        computeBuffer.commit()
    }

    // MARK: - Render Passes

    private func drawFullscreenQuad(encoder: MTLRenderCommandEncoder) {
        guard let pipeline = quadRenderPipeline,
              let vertexBuffer = quadVertexBuffer,
              let texture = computeTextures[displayTextureIndex] else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)
        encoder.setFragmentTexture(texture, index: 0)
        encoder.drawPrimitives(type: .triangle, vertexStart: 0, vertexCount: 6)
    }

    private func drawGrid(encoder: MTLRenderCommandEncoder) {
        guard let pipeline = gridRenderPipeline,
              let vertexBuffer = gridVertexBuffer,
              let indexBuffer = gridIndexBuffer,
              gridIndexCount > 0 else { return }

        encoder.setRenderPipelineState(pipeline)
        encoder.setDepthStencilState(depthStencilState)
        encoder.setVertexBuffer(vertexBuffer, offset: 0, index: 0)

        // Upload view-projection matrix
        let view = simd_float4x4.lookAt(eye: camera.position, center: camera.target, up: SIMD3<Float>(0, 1, 0))
        let aspect = Float(viewportSize.x) / max(Float(viewportSize.y), 1)
        let proj = simd_float4x4.perspective(fovY: Float.pi / 3.0, aspect: aspect, near: 1e9, far: 1e14)
        var viewProj = proj * view

        encoder.setVertexBytes(&viewProj, length: MemoryLayout<simd_float4x4>.size, index: 1)
        encoder.drawIndexedPrimitives(
            type: .line,
            indexCount: gridIndexCount,
            indexType: .uint32,
            indexBuffer: indexBuffer,
            indexBufferOffset: 0
        )
    }
}

// MARK: - simd Matrix Helpers

extension simd_float4x4 {

    /// Creates a look-at view matrix (right-handed).
    static func lookAt(eye: SIMD3<Float>, center: SIMD3<Float>, up: SIMD3<Float>) -> simd_float4x4 {
        let f = normalize(center - eye)
        let s = normalize(cross(f, up))
        let u = cross(s, f)

        var result = matrix_identity_float4x4
        result[0][0] = s.x;  result[1][0] = s.y;  result[2][0] = s.z
        result[0][1] = u.x;  result[1][1] = u.y;  result[2][1] = u.z
        result[0][2] = -f.x; result[1][2] = -f.y; result[2][2] = -f.z
        result[3][0] = -dot(s, eye)
        result[3][1] = -dot(u, eye)
        result[3][2] =  dot(f, eye)
        return result
    }

    /// Creates a perspective projection matrix (right-handed, Metal NDC with z in [0,1]).
    static func perspective(fovY: Float, aspect: Float, near: Float, far: Float) -> simd_float4x4 {
        let yScale = 1.0 / tan(fovY * 0.5)
        let xScale = yScale / aspect
        let zRange = far - near

        var result = simd_float4x4(0)
        result[0][0] = xScale
        result[1][1] = yScale
        result[2][2] = -(far) / zRange
        result[2][3] = -1.0
        result[3][2] = -(far * near) / zRange
        return result
    }
}
