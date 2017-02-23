//
//  SceneKitOperation.swift
//  Pods
//
//  Created by Skye Book on 2/23/17.
//
//

import SceneKit
import GLKit

public class SceneKitOperation: ImageProcessingOperation {
    public let targets = TargetContainer()
    public let sources = SourceContainer()
    public var maximumInputs: UInt = 1
    
    public let renderer = SCNRenderer(context: sharedImageProcessingContext.context, options: nil)
    public var textureTargetMaterial: SCNMaterial?
    
    private var outputSize: CGSize
    
    private var sceneKitFramebuffer: Framebuffer?
    
    private var displayLink: CADisplayLink?
    private var renderSinceLastDisplayLink: Bool = false
    
    public init(outputSize: CGSize, renderStaleBuffers: Bool = false) {
        self.outputSize = outputSize
        
//        if renderStaleBuffers {
//            displayLink = CADisplayLink(target: self, selector: #selector(displayLinkFired(_:)))
//            
//            //displayLink?.paused = true
//            displayLink?.add(to: RunLoop.main, forMode: RunLoopMode.commonModes)
//        }
    }
    
//    @objc private func displayLinkFired(_ displayLink: CADisplayLink) {
//        let nextDisplayTime = displayLink.timestamp + displayLink.duration
//        
//        //log.debug("ITEM TIME: \(itemTime)")
//        
//        if videoOutput.hasNewPixelBuffer(forItemTime: itemTime) {
//            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: itemTime, itemTimeForDisplay: nil) {
//                delegates.invoke {$0.pixelBufferAvailable(pixelBuffer: pixelBuffer, repeatedBuffer: false, sampleTime: itemTime)}
//                firstFrameBlitted = true
//                
//                lastSampleBufferTime = itemTime
//            }
//        }
//        else if let lastSampleBufferTime = lastSampleBufferTime {
//            
//            let needsRefresh = delegates.some {$0.shouldContinueVendingLastFrame()}
//            guard needsRefresh else {
//                return
//            }
//            
//            // copy the pixel buffer down here so that we don't do it needlessly if no clients want a refresh
//            // With a pixel buffer from the previous sample time, send it to clients interested in the previous frame
//            if let pixelBuffer = videoOutput.copyPixelBuffer(forItemTime: lastSampleBufferTime, itemTimeForDisplay: nil) {
//                delegates.filterAndInvoke({ (delegate) -> Bool in
//                    return delegate.shouldContinueVendingLastFrame()
//                }, invocation: { (delegate) in
//                    delegate.pixelBufferAvailable(pixelBuffer: pixelBuffer, repeatedBuffer: true, sampleTime: lastSampleBufferTime)
//                })
//                //delegatesNeedingRefresh.forEach{$0.pixelBufferAvailable(pixelBuffer: pixelBuffer, repeatedBuffer: true, sampleTime: lastSampleBufferTime)}
//            }
//        }
//        
//    }
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        // We tend to get an error on the first frame
        var error = glGetError()
        guard error == GLenum(GL_NO_ERROR) else {
            print("SOME BAD SHIT HAPPENED HERE")
            return
        }
        
        guard let textureTargetMaterial = textureTargetMaterial else {
            print("no texture :(")
            return
        }
        // If we already have a framebuffer from a previous render, unlock it (we obtain two locks at the end of this function)
        sceneKitFramebuffer?.unlock()
        sceneKitFramebuffer = nil
        
        // Request a texture to copy the framebuffer to
        //let tempImageTexture = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: .portrait, size: framebuffer.size, textureOnly: true)
        
        // Create a texture info with this texture
        let textureInfo = InjectedTextureInfo(texture: framebuffer.texture, width: GLuint(framebuffer.size.width), height: GLuint(framebuffer.size.height))
        
        print("SceneKitOperation has texture \(framebuffer.texture)")
        
        // Attach the texture to the SceneKit scene
        textureTargetMaterial.diffuse.contents = textureInfo
        textureTargetMaterial.isDoubleSided = true
        
        // Get a framebuffer to draw into
        sceneKitFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation: .portrait, size: GLSize(width: GLint(outputSize.width), height: GLint(outputSize.height)))
        
        error = glGetError()
        guard error == GLenum(GL_NO_ERROR) else {
            print("SOME BAD SHIT HAPPENED HERE")
            return
        }
        
        guard let sceneKitFramebuffer = sceneKitFramebuffer,
            let sceneKitFramebufferID = sceneKitFramebuffer.framebuffer else {
            print("ERROR: No framebuffer")
            return
        }
        
        // Do some setup on the framebuffer
        glBindFramebuffer(GLenum(GL_FRAMEBUFFER), sceneKitFramebufferID)
        glViewport(0, 0, GLsizei(outputSize.width), GLsizei(outputSize.height))
        clearFramebufferWithColor(Color.green)
        
        error = glGetError()
        guard error == GLenum(GL_NO_ERROR) else {
            print("SOME BAD SHIT HAPPENED HERE")
            return
        }
        
        // Render to the framebuffer
        renderer.render(atTime: 0)
        
        // Unlock the framebuffer of the movie source
        framebuffer.unlock()
        
        // Lock for us to use internally
        sceneKitFramebuffer.lock()
        
        // Lock for the target to use
        sceneKitFramebuffer.lock()
        updateTargetsWithFramebuffer(sceneKitFramebuffer)
        
        renderSinceLastDisplayLink = true
    }
    
    // Called when targets are added to a source so they can immediately get some content on screen while waiting for the next render
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        // not needed?
        sharedImageProcessingContext.runOperationAsynchronously{
            guard let sceneKitFramebuffer = self.sceneKitFramebuffer else {
                return
            }
            
            sceneKitFramebuffer.lock()
            target.newFramebufferAvailable(sceneKitFramebuffer, fromSourceIndex:atIndex)
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
