//
//  SceneKitOperation.swift
//  Pods
//
//  Created by Skye Book on 2/23/17.
//
//

import SceneKit
import GLKit

open class SceneKitOperation: ImageProcessingOperation {
    public let maximumInputs:UInt = 1
    public var backgroundColor = Color.green
    
    // MARK: -
    // MARK: Internal
    
    public let targets = TargetContainer()
    public let sources = SourceContainer()
    var inputFramebuffers = [UInt:Framebuffer]()
    var renderFramebuffer:Framebuffer!
    var outputFramebuffer:Framebuffer { get { return renderFramebuffer } }
    
    
    
    // SCENEKIT STUFF
    public let renderer = SCNRenderer(context: sharedImageProcessingContext.context, options: nil)
    public var textureTargetMaterial: SCNMaterial?
    private var outputSize: CGSize
    
    // MARK: -
    // MARK: Initialization and teardown
    
    public init(outputSize: CGSize) {
        self.outputSize = outputSize
    }
    
    deinit {
        debugPrint("Deallocating operation: \(self)")
    }
    
    // MARK: -
    // MARK: Rendering
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        //print("scenekit has frame with timestamp \(framebuffer.timingStyle.timestamp) from sourceIndex \(fromSourceIndex)")
        if let previousFramebuffer = inputFramebuffers[fromSourceIndex] {
            previousFramebuffer.unlock()
        }
        inputFramebuffers[fromSourceIndex] = framebuffer
        
        if (UInt(inputFramebuffers.count) >= maximumInputs) {
            renderFrame()
            
            updateTargetsWithFramebuffer(outputFramebuffer)
        }
    }
    
    private func renderFrame() {
        
        // Get a handle on the framebuffer we want to send to the SceneKit texture
        guard let framebuffer = inputFramebuffers[0] else {
            return
        }
        
        guard let textureTargetMaterial = textureTargetMaterial else {
            print("no scenekit texture :(")
            return
        }
        
        // Create a texture info with this texture
        let textureInfo = InjectedTextureInfo(texture: framebuffer.texture, width: GLuint(framebuffer.size.width), height: GLuint(framebuffer.size.height))
        
        //print("SceneKitOperation has texture \(framebuffer.texture)")
        
        //print("TEXTURE/SOURCE:\t\(framebuffer.texture)/\(sources.sources)")
        
        // Attach the texture to the SceneKit scene
        textureTargetMaterial.diffuse.contents = textureInfo
        textureTargetMaterial.isDoubleSided = true
        
        
        
        
        // Get a framebuffer to draw into
        renderFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: .portrait, size: GLSize(width: GLint(outputSize.width), height: GLint(outputSize.height)))
        
        var error = glGetError()
        guard error == GLenum(GL_NO_ERROR) else {
            print("SOME BAD SHIT HAPPENED HERE")
            return
        }
        
        
        renderFramebuffer.activateFramebufferForRendering()
        clearFramebufferWithColor(backgroundColor)
        
        error = glGetError()
        guard error == GLenum(GL_NO_ERROR) else {
            print("SOME BAD SHIT HAPPENED HERE")
            return
        }
        
        // Render to the framebuffer
        renderer.render(atTime: 0)
        
        releaseIncomingFramebuffers()
    }
    
    private func releaseIncomingFramebuffers() {
        var remainingFramebuffers = [UInt:Framebuffer]()
        // If all inputs are still images, have this output behave as one
        renderFramebuffer.timingStyle = .stillImage
        
        var latestTimestamp:Timestamp?
        for (key, framebuffer) in inputFramebuffers {
            
            // When there are multiple transient input sources, use the latest timestamp as the value to pass along
            if let timestamp = framebuffer.timingStyle.timestamp {
                if !(timestamp < (latestTimestamp ?? timestamp)) {
                    latestTimestamp = timestamp
                    renderFramebuffer.timingStyle = .videoFrame(timestamp:timestamp)
                }
                
                framebuffer.unlock()
            } else {
                remainingFramebuffers[key] = framebuffer
            }
        }
        inputFramebuffers = remainingFramebuffers
    }
    
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        sharedImageProcessingContext.runOperationAsynchronously{
            guard let renderFramebuffer = self.renderFramebuffer, (!renderFramebuffer.timingStyle.isTransient()) else { return }
            
            renderFramebuffer.lock()
            target.newFramebufferAvailable(renderFramebuffer, fromSourceIndex:atIndex)
        }
    }
}


// GLKTextureInfo is read-only, so we've made our own with a cooler name that allows access
fileprivate class InjectedTextureInfo: GLKTextureInfo {
    
    override var name: GLuint {
        get {
            return _name
        }
    }
    
    override var target: GLenum {
        get {
            return _target
        }
    }
    
    override var width: GLuint {
        get {
            return _width
        }
    }
    
    override var height: GLuint {
        get {
            return _height
        }
    }
    
    override var depth: GLuint {
        get {
            return _depth
        }
    }
    
    override var alphaState: GLKTextureInfoAlphaState {
        get {
            return _alphaState
        }
    }
    
    override var textureOrigin: GLKTextureInfoOrigin {
        get {
            return _textureOrigin
        }
    }
    
    override var containsMipmaps: Bool {
        get {
            return _containsMipmaps
        }
    }
    
    override var mimapLevelCount: GLuint {
        return _mimapLevelCount
    }
    
    override var arrayLength: GLuint {
        get {
            return _arrayLength
        }
    }
    
    var _name: GLuint
    
    var _target: GLenum
    
    var _width: GLuint
    
    var _height: GLuint
    
    var _depth: GLuint
    
    var _alphaState: GLKTextureInfoAlphaState
    
    var _textureOrigin: GLKTextureInfoOrigin
    
    var _containsMipmaps: Bool
    
    var _mimapLevelCount: GLuint
    
    var _arrayLength: GLuint
    
    
    init(texture: GLuint, width: GLuint, height: GLuint) {
        _name = texture
        
        _target = GLenum(GL_TEXTURE_2D)
        
        _width = width
        _height = height
        
        _depth = 1
        
        _alphaState = .none
        _textureOrigin = .topLeft
        _containsMipmaps = false
        _mimapLevelCount = 1
        _arrayLength = 1
        
        
    }
}
