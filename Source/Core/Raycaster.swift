//
//  Raycaster.swift
//  Satin
//
//  Created by Reza Ali on 4/22/20.
//

#if os(iOS) || os(macOS)

import Metal
import MetalPerformanceShaders
import simd

public struct RaycastResult {
    public let barycentricCoordinates: simd_float3
    public let distance: Float
    public let normal: simd_float3
    public let position: simd_float3
    public let uv: simd_float2
    public let primitiveIndex: UInt32
    public let object: Object
    public let submesh: Submesh?
}

open class Raycaster {
    public var ray = Ray() {
        didSet {
            originParam.value = ray.origin
            directionParam.value = ray.direction
        }
    }
    
    public var near: Float = 0.0 {
        didSet {
            nearParam.value = near
        }
    }
    
    public var far = Float.infinity {
        didSet {
            farParam.value = far
        }
    }
    
    public var rebuildStructures: Bool = false {
        didSet {
            _rebuildStructures = rebuildStructures
        }
    }
    
    lazy var originParam: PackedFloat3Parameter = {
        PackedFloat3Parameter("origin", ray.origin)
    }()
    
    lazy var nearParam: FloatParameter = {
        FloatParameter("near", near)
    }()
    
    lazy var directionParam: PackedFloat3Parameter = {
        PackedFloat3Parameter("direction", ray.direction)
    }()
    
    lazy var farParam: FloatParameter = {
        FloatParameter("far", far)
    }()
    
    lazy var rayParams: ParameterGroup = {
        let params = ParameterGroup("Ray")
        params.append(originParam)
        params.append(nearParam)
        params.append(directionParam)
        params.append(farParam)
        return params
    }()
    
    var distanceParam = FloatParameter("distance")
    var indexParam = UInt32Parameter("index")
    var coordinatesParam = Float2Parameter("coordinates")
    
    lazy var intersectionParams: ParameterGroup = {
        let params = ParameterGroup("Intersection")
        params.append(distanceParam)
        params.append(indexParam)
        params.append(coordinatesParam)
        return params
    }()
    
    weak var context: Context?
    var commandQueue: MTLCommandQueue?
    var intersector: MPSRayIntersector?
    var accelerationStructures: [MPSTriangleAccelerationStructure] = []
    
    var _count: Int = -1 {
        didSet {
            setupRayBuffers()
            setupIntersectionBuffers()
            setupAccelerationStructures()
        }
    }
    
    var _rebuildStructures: Bool = true
    var rayBuffer: Buffer!
    var intersectionBuffer: Buffer!
    
    // Ideally you create a raycaster on start up and reuse it over and over
    public init(context: Context) {
        self.context = context
        setup()
    }
    
    public init(context: Context, _ origin: simd_float3, _ direction: simd_float3, _ near: Float = 0.0, _ far: Float = Float.infinity) {
        self.context = context
        ray = Ray(origin, direction)
        self.near = near
        self.far = far
        setup()
    }
    
    public init(context: Context, _ ray: Ray, _ near: Float = 0.0, _ far: Float = Float.infinity) {
        self.context = context
        self.ray = ray
        self.near = near
        self.far = far
        setup()
    }
    
    public init(context: Context, _ camera: Camera, _ coordinate: simd_float2, _ near: Float = 0.0, _ far: Float = Float.infinity) {
        self.context = context
        setFromCamera(camera, coordinate)
        self.near = near
        self.far = far
        setup()
    }
    
    func setup() {
        // setup command queue
        setupCommandQueue()
        
        // setup intersector
        setupIntersector()
    }
    
    func setupCommandQueue() {
        guard let context = self.context, let commandQueue = context.device.makeCommandQueue() else { fatalError("Unable to create Command Queue") }
        self.commandQueue = commandQueue
    }
    
    func setupIntersector() {
        guard let context = self.context else { fatalError("Unable to create Intersector") }
        let intersector = MPSRayIntersector(device: context.device)
        intersector.rayDataType = .originMinDistanceDirectionMaxDistance
        intersector.rayStride = MemoryLayout<MPSRayOriginMinDistanceDirectionMaxDistance>.stride
        intersector.intersectionDataType = .distancePrimitiveIndexCoordinates
        intersector.triangleIntersectionTestType = .default
        self.intersector = intersector
    }
    
    func setupAccelerationStructures() {
        guard let context = self.context else { fatalError("Unable to create Acceleration Structures") }
        var acount = accelerationStructures.count
        while acount > _count {
            _ = accelerationStructures.popLast()
            acount = accelerationStructures.count
            _rebuildStructures = true
        }
        for _ in acount ..< _count {
            accelerationStructures.append(MPSTriangleAccelerationStructure(device: context.device))
            _rebuildStructures = true
        }
    }
    
    // expects a normalize point from -1 to 1 in both x & y directions
    public func setFromCamera(_ camera: Camera, _ coordinate: simd_float2) {
        ray = Ray(camera, coordinate)
    }
    
    func setupRayBuffers() {
        guard let context = self.context else { fatalError("Unable to create Ray Buffers") }
        rayBuffer = Buffer(context: context, parameters: rayParams, count: _count)
    }
    
    func setupIntersectionBuffers() {
        guard let context = self.context else { fatalError("Unable to create Intersection Buffers") }
        intersectionBuffer = Buffer(context: context, parameters: intersectionParams, count: _count)
    }
    
    func _intersect(_ intersectables: [Any]) -> MTLCommandBuffer? {
        guard let commandBuffer = commandQueue?.makeCommandBuffer() else { return nil }
        
        commandBuffer.label = "Raycaster Command Buffer"
        
        for (index, object) in intersectables.enumerated() {
            if let mesh = object as? Mesh {
                intersect(commandBuffer, rayBuffer, intersectionBuffer, mesh, nil, index)
            }
            else if let submesh = object as? Submesh, let mesh = submesh.parent {
                intersect(commandBuffer, rayBuffer, intersectionBuffer, mesh, submesh, index)
            }
        }
        
        if _rebuildStructures {
            _rebuildStructures = false
        }
        
        return commandBuffer
    }
    
    public func intersect(_ object: Object, _ recursive: Bool = true, _ invisible: Bool = false, _ callback: @escaping (_ results: [RaycastResult]) -> ()) {
        let intersectables = getIntersectables(object, recursive, invisible)
        guard let commandBuffer = _intersect(intersectables) else { return }
        commandBuffer.addCompletedHandler { [weak self] _ in
            if let self = self {
                callback(self.getResults(intersectables))
            }
        }
        commandBuffer.commit()
    }
    
    public func intersect(_ object: Object, _ recursive: Bool = true, _ invisible: Bool = false) -> [RaycastResult] {
        let intersectables = getIntersectables(object, recursive, invisible)
        guard let commandBuffer = _intersect(intersectables) else { return [] }
        commandBuffer.commit()
        commandBuffer.waitUntilCompleted()
        return getResults(intersectables)
    }
    
    func getIntersectables(_ object: Object, _ recursive: Bool = true, _ invisible: Bool = false) -> [Any] {
        let meshes: [Mesh] = getMeshes(object, recursive, invisible)
        var intersectables: [Any] = []
        var count = 0
        for mesh in meshes {
            var times = simd_float2(repeating: -1.0)
            guard rayBoundsIntersection(ray.origin, ray.direction, mesh.localbounds, &times) else { continue }
            let submeshes = mesh.submeshes
            count += max(mesh.submeshes.count, 1)
            if !submeshes.isEmpty {
                for submesh in submeshes {
                    intersectables.append(submesh)
                }
            }
            else {
                intersectables.append(mesh)
            }
        }
        
        if count == 0 {
            return []
        }
        else if count != _count {
            _count = count
        }
        
        return intersectables
    }
    
    func getResults(_ intersectables: [Any]) -> [RaycastResult] {
        var results: [RaycastResult] = []
        for (index, object) in intersectables.enumerated() {
            if let mesh = object as? Mesh {
                if let result = calculateResult(mesh, nil, index) {
                    results.append(result)
                }
            }
            else if let submesh = object as? Submesh, let mesh = submesh.parent {
                if let result = calculateResult(mesh, submesh, index) {
                    results.append(result)
                }
            }
        }
        
        results.sort {
            $0.distance < $1.distance
        }
        return results
    }
    
    func calculateResult(_ mesh: Mesh,
                         _ submesh: Submesh?,
                         _ index: Int) -> RaycastResult?
    {
        intersectionBuffer.sync(index)
        let distance = distanceParam.value
        if distance >= 0 {
            let primitiveIndex = indexParam.value
            let index = Int(primitiveIndex) * 3
            
            var i0 = 0
            var i1 = 0
            var i2 = 0
            
            let geometry = mesh.geometry
            
            if let sub = submesh {
                i0 = Int(sub.indexData[index])
                i1 = Int(sub.indexData[index + 1])
                i2 = Int(sub.indexData[index + 2])
            }
            else if mesh.geometry.indexData.count > 0 {
                i0 = Int(geometry.indexData[index])
                i1 = Int(geometry.indexData[index + 1])
                i2 = Int(geometry.indexData[index + 2])
            }
            else {
                i0 = index
                i1 = index + 1
                i2 = index + 2
            }
            
            let a: Vertex = geometry.vertexData[i0]
            let b: Vertex = geometry.vertexData[i1]
            let c: Vertex = geometry.vertexData[i2]
            
            let coords = coordinatesParam.value
            let u: Float = coords.x
            let v: Float = coords.y
            let w: Float = 1.0 - u - v
            
            let meshWorldMatrix = mesh.worldMatrix
            
            let aP = meshWorldMatrix * a.position * u
            let bP = meshWorldMatrix * b.position * v
            let cP = meshWorldMatrix * c.position * w
            
            let aU = a.uv * u
            let bU = b.uv * v
            let cU = c.uv * w
            
            let aN = meshWorldMatrix * simd_make_float4(a.normal) * u
            let bN = meshWorldMatrix * simd_make_float4(b.normal) * v
            let cN = meshWorldMatrix * simd_make_float4(c.normal) * w
            
            let hitP = simd_make_float3(aP + bP + cP)
            let hitU = simd_make_float2(aU + bU + cU)
            let hitN = normalize(simd_make_float3(aN + bN + cN))
            
            return RaycastResult(
                barycentricCoordinates: simd_make_float3(u, v, w),
                distance: distance,
                normal: hitN,
                position: hitP,
                uv: hitU,
                primitiveIndex: primitiveIndex,
                object: mesh,
                submesh: submesh
            )
        }
        return nil
    }
    
    func intersect(_ commandBuffer: MTLCommandBuffer,
                   _ rayBuffer: Buffer,
                   _ intersectionBuffer: Buffer,
                   _ mesh: Mesh,
                   _ submesh: Submesh?,
                   _ index: Int)
    {
        let meshWorldMatrix = mesh.worldMatrix
        let meshWorldMatrixInverse = meshWorldMatrix.inverse
        
        let origin = meshWorldMatrixInverse * simd_make_float4(ray.origin.x, ray.origin.y, ray.origin.z, 1.0)
        let direction = meshWorldMatrixInverse * simd_make_float4(ray.direction)
        
        originParam.value = simd_make_float3(origin)
        directionParam.value = simd_make_float3(direction)
        rayBuffer.update(index)
        
        let geometry = mesh.geometry
        let winding: MTLWinding = geometry.windingOrder == .counterClockwise ? .clockwise : .counterClockwise
        intersector!.frontFacingWinding = winding
        intersector!.cullMode = mesh.cullMode
        
        let accelerationStructure = accelerationStructures[index]
        accelerationStructure.vertexBuffer = mesh.geometry.vertexBuffer!
        accelerationStructure.vertexStride = MemoryLayout<Vertex>.stride
        accelerationStructure.label = mesh.label + " Acceleration Structure"
        
        if let sub = submesh, let indexBuffer = sub.indexBuffer {
            accelerationStructure.indexBuffer = indexBuffer
            accelerationStructure.indexType = .uInt32
            accelerationStructure.triangleCount = sub.indexData.count / 3
        }
        else if let indexBuffer = geometry.indexBuffer {
            accelerationStructure.indexBuffer = indexBuffer
            accelerationStructure.indexType = .uInt32
            accelerationStructure.triangleCount = geometry.indexData.count / 3
        }
        else {
            accelerationStructure.triangleCount = mesh.geometry.vertexData.count / 3
        }
        
        if _rebuildStructures {
            accelerationStructure.rebuild()
        }
        
        intersector!.label = mesh.label + " Raycaster Intersector"
        intersector!.encodeIntersection(
            commandBuffer: commandBuffer,
            intersectionType: .nearest,
            rayBuffer: rayBuffer.buffer,
            rayBufferOffset: index * rayParams.stride,
            intersectionBuffer: intersectionBuffer.buffer,
            intersectionBufferOffset: index * intersectionParams.stride,
            rayCount: 1,
            accelerationStructure: accelerationStructure
        )
    }
    
    deinit {
        accelerationStructures = []
        intersector = nil
        commandQueue = nil
        context = nil
    }
}

#endif
