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

    // MARK: - Textures

    /// Compute shader writes geodesic ray-traced image into this texture.
    private var computeTexture: MTLTexture?

    // MARK: - Scene

    let camera = Camera()
    let gravitySim = GravitySim()
    var sceneObjects: [SceneObject] = makeDefaultSceneObjects()

    // MARK: - Input

    /// Handle key events forwarded from InputMTKView.
    func handleKeyDown(with event: NSEvent) {
        if event.charactersIgnoringModifiers == "g" {
            gravitySim.isEnabled.toggle()
            print("[INFO] Gravity turned \(gravitySim.isEnabled ? "ON" : "OFF")")
        }
    }

    // MARK: - Resolution

    /// Window resolution
    private var viewportSize: SIMD2<UInt32> = SIMD2(800, 600)

    /// Compute shader resolution (lower than viewport for interactive speed)
    private let computeWidth: Int = 200
    private let computeHeight: Int = 150

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

    private func allocateComputeTexture() {
        let desc = MTLTextureDescriptor.texture2DDescriptor(
            pixelFormat: .rgba8Unorm,
            width: computeWidth,
            height: computeHeight,
            mipmapped: false
        )
        desc.usage = [.shaderRead, .shaderWrite]
        desc.storageMode = .private
        computeTexture = device.makeTexture(descriptor: desc)
    }

    // MARK: - Grid Generation (CPU)

    /// Rebuild the spacetime curvature grid mesh on the CPU.
    /// Matches Engine::generateGrid() from black_hole.cpp.
    private func generateGrid() {
        let gridSize = 25
        let spacing: Float = 1e10

        var vertices: [SIMD3<Float>] = []
        var indices: [UInt32] = []

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

                vertices.append(SIMD3<Float>(worldX, y, worldZ))
            }
        }

        for z in 0..<gridSize {
            for x in 0..<gridSize {
                let i = UInt32(z * (gridSize + 1) + x)
                indices.append(contentsOf: [i, i + 1])
                indices.append(contentsOf: [i, i + UInt32(gridSize + 1)])
            }
        }

        gridVertexBuffer = device.makeBuffer(
            bytes: vertices,
            length: vertices.count * MemoryLayout<SIMD3<Float>>.stride,
            options: .storageModeShared
        )
        gridIndexBuffer = device.makeBuffer(
            bytes: indices,
            length: indices.count * MemoryLayout<UInt32>.size,
            options: .storageModeShared
        )
        gridIndexCount = indices.count
    }

    // MARK: - Uniform Uploads

    private func makeCameraUniforms() -> CameraUniforms {
        let aspect = Float(viewportSize.x) / Float(viewportSize.y)
        return camera.uniforms(aspect: aspect)
    }

    private func makeDiskUniforms() -> DiskUniforms {
        let rs = Float(kSagASchwarzschildRadius)
        return DiskUniforms(
            innerRadius: rs * kDiskInnerFactor,
            outerRadius: rs * kDiskOuterFactor,
            diskNum: 2.0,
            thickness: kDiskThickness
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
    }

    func draw(in view: MTKView) {
        // 1) N-body gravity update
        gravitySim.step(objects: &sceneObjects, dt: 1.0 / 60.0)

        // 2) Regenerate spacetime curvature grid
        generateGrid()

        guard let commandBuffer = commandQueue.makeCommandBuffer() else { return }

        // 3) Dispatch geodesic compute shader
        dispatchCompute(commandBuffer: commandBuffer)

        // 4) Render pass: fullscreen quad + grid overlay
        guard let drawable = view.currentDrawable,
              let renderPassDescriptor = view.currentRenderPassDescriptor else {
            commandBuffer.commit()
            return
        }

        guard let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderPassDescriptor) else {
            commandBuffer.commit()
            return
        }

        drawFullscreenQuad(encoder: renderEncoder)
        drawGrid(encoder: renderEncoder)

        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - Compute Dispatch

    private func dispatchCompute(commandBuffer: MTLCommandBuffer) {
        guard let pipeline = computePipeline,
              let texture = computeTexture,
              let encoder = commandBuffer.makeComputeCommandEncoder() else { return }

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
    }

    // MARK: - Render Passes

    private func drawFullscreenQuad(encoder: MTLRenderCommandEncoder) {
        guard let pipeline = quadRenderPipeline,
              let vertexBuffer = quadVertexBuffer,
              let texture = computeTexture else { return }

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
