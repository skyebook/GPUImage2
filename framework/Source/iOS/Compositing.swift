//
//  Compositing.swift
//  Pods
//
//  Created by Skye Book on 1/20/17.
//
//

import AVFoundation

public class GPUImageCompositionInstruction: AVMutableVideoCompositionInstruction {
    let trackID: CMPersistentTrackID
    let shaders: [BasicOperation]
    
//    override public var passthroughTrackID: CMPersistentTrackID {
//        get {
//            return self.trackID
//        }
//    }
    
    override public var requiredSourceTrackIDs: [NSValue] {
        get {
            return [NSNumber(value: Int(self.trackID))]
        }
    }
    
    override public var containsTweening: Bool {
        get {
            return false
        }
    }
    
    
    public init(trackID: CMPersistentTrackID, shaders: [BasicOperation]){
        print("Creating instruction")
        self.trackID = trackID
        self.shaders = shaders
        
        super.init()
        
        //self.enablePostProcessing = false
    }
    
    required public init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) hasitun not been implemented")
    }
    
}

public class Compositing: NSObject, AVVideoCompositing, ImageConsumer {
    
    // Required ImageConsumer protocol properties
    public let sources = SourceContainer()
    public let maximumInputs:UInt = 1
    
    var renderFramebuffer: Framebuffer?
    //    var pixelBuffer: CVPixelBuffer?
    //    var pixelBufferPool: CVPixelBufferPool?
    
    var colorSwizzlingShader: ShaderProgram?
    
    // WRITE FORMAT
    public var requiredPixelBufferAttributesForRenderContext: [String : Any] = [
        kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: Int32(kCVPixelFormatType_32BGRA)),
        kCVPixelBufferOpenGLESCompatibilityKey as String : NSNumber(value: true),
        kCVPixelBufferOpenGLCompatibilityKey as String : NSNumber(value: true)
    ]
    
    // READ FORMAT
    public var sourcePixelBufferAttributes: [String :Any]? = [
        kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
        kCVPixelBufferOpenGLESCompatibilityKey as String : NSNumber(value: true),
        kCVPixelBufferOpenGLCompatibilityKey as String : NSNumber(value: true)
    ]
    
    // Default to serial
    //let queue = DispatchQueue(label: "UnclipCustomCompositorQueue")
    
    let pixelBufferInput = PixelBufferInput()
    
    public override init() {
        print("intializing compositor")
        //if sharedImageProcessingContext.supportsTextureCaches() {
            //colorSwizzlingShader = sharedImageProcessingContext.passthroughShader
        //} else {
            colorSwizzlingShader = crashOnShaderCompileFailure("MovieOutput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(1), fragmentShader:ColorSwizzlingFragmentShader)}
        //}
        
        super.init()
    }
    
    public func renderContextChanged(_ newRenderContext: AVVideoCompositionRenderContext) {
        print("HELLO FROM renderContextChanged")
        DispatchQueue.main.async {
//            let pixelBufferAttributes = [
//                kCVPixelBufferPixelFormatTypeKey as String : NSNumber(value: Int32(kCVPixelFormatType_420YpCbCr8BiPlanarFullRange)),
//                kCVPixelBufferOpenGLESCompatibilityKey as String : NSNumber(value: true),
//                kCVPixelBufferWidthKey as String: NSNumber(value: Int(newRenderContext.size.width)),
//                kCVPixelBufferHeightKey as String: NSNumber(value: Int(newRenderContext.size.height))
//            ]
            
            //CVPixelBufferPoolCreate(kCFAllocatorDefault, nil, pixelBufferAttributes as CFDictionary, &self.pixelBufferPool)
            
            let glSize = GLSize(width: Int32(newRenderContext.size.width), height: Int32(newRenderContext.size.height))
            //self.renderFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:glSize)
        }
    }
    
    var currentlyAppliedInstruction: GPUImageCompositionInstruction?
    var pendingRequests: [NSDictionary :AVAsynchronousVideoCompositionRequest] = [:]
    
    public func startRequest(_ asyncVideoCompositionRequest: AVAsynchronousVideoCompositionRequest) {
        guard let trackIDsValue = asyncVideoCompositionRequest.videoCompositionInstruction.requiredSourceTrackIDs,
            let trackID = trackIDsValue[0] as? CMPersistentTrackID else {
                print("no track ID found in the composition instruction's requiredSourceTrackIDs")
                return
        }
        
        guard let instruction = asyncVideoCompositionRequest.videoCompositionInstruction as? GPUImageCompositionInstruction else {
            asyncVideoCompositionRequest.finish(with: NSError(domain: "GPUImage", code: 1, userInfo: [NSLocalizedDescriptionKey: "No GPUImageCompositionInstruction present"]))
            return
        }
        
        //autoreleasepool {
            print("HELLO FROM startRequest")
            
            
            DispatchQueue.main.async {
                autoreleasepool {
                
                
                if self.currentlyAppliedInstruction != instruction {
                    self.pixelBufferInput.removeAllTargets()
                    self.removeSourceAtIndex(0)
                    
                    // We're basically doing this:
                    //pixelBufferInput --> SaturationAdjustment() --> BrightnessAdjustment() --> self
                    
                    //self.pixelBufferInput --> self
                    
                    // Chain the shaders in order on to the input pixel buffer
                    
                    var lastShader: BasicOperation?
                    instruction.shaders.forEach({ (shader) in
                        if let lastShader = lastShader {
                            lastShader --> shader
                        }
                        else {
                            self.pixelBufferInput --> shader
                        }
                        
                        lastShader = shader
                    })
                    
                    if let lastShader = lastShader {
                        lastShader --> self
                    }
                    else {
                        print("WARNING: Rendering through OpenGL without any shaders")
                        self.pixelBufferInput --> self
                    }
                    
                    self.currentlyAppliedInstruction = instruction
                    print("New GPUImageCompositionInstruction loaded with \(instruction.shaders.count) shader(s)")
                }
                
                
                
                //            // TODO: Do the stuff here
                //            guard let pixelBufferPool = self.pixelBufferPool else {
                //                print("hey what the fuck?")
                //                return
                //            }
                //
                //            // Create pixelbuffer to render into
                //            let result = CVPixelBufferPoolCreatePixelBuffer(kCFAllocatorDefault, pixelBufferPool, &self.pixelBuffer)
                //            guard result == kCVReturnSuccess else {
                //                print("failed to create pixel buffer from pool")
                //                return
                //            }
            
            
            
                guard let sourceBuffer = asyncVideoCompositionRequest.sourceFrame(byTrackID: trackID) else {
                    print("no source buffer found for passthrough track ID")
                    return
                }
                
                if let cf = CMTimeCopyAsDictionary(asyncVideoCompositionRequest.compositionTime, nil),
                    let timeDictionary = cf as? [AnyHashable : Any] {
                    
                    print("time: \(asyncVideoCompositionRequest.compositionTime.value)")
                    
                    self.pendingRequests[timeDictionary as NSDictionary] = asyncVideoCompositionRequest
                }
                
                
                // The pixel buffer is now processing the video. As the ImageConsumer, we will have the output returned to us via newFramebufferAvailable
                self.pixelBufferInput.process(movieFrame: sourceBuffer, withSampleTime: asyncVideoCompositionRequest.compositionTime)
                
            }
        }
    }
    
    private func renderIntoPixelBuffer(_ pixelBuffer:CVPixelBuffer, framebuffer:Framebuffer) {
        // Sanity check
        guard let colorSwizzlingShader = colorSwizzlingShader else {
            print("colorSwizzlingShader not initialized")
            return
        }
        
        
        let size = CVImageBufferGetEncodedSize(pixelBuffer)
        let glSize = GLSize(width: Int32(size.width), height: Int32(size.height))
        
        // initialize the GPUImage framebuffer
        
        if renderFramebuffer == nil {
            
            print("CREATING RENDER FRAMEBUFFER")
            
            
            var cachedTextureRef:CVOpenGLESTexture? = nil
            //let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, self.pixelBuffer!, nil, GLenum(GL_TEXTURE_2D), GL_RGBA, glSize.width, glSize.height, GLenum(GL_BGRA), GLenum(GL_UNSIGNED_BYTE), 0, &cachedTextureRef)
            
            var cachedTexture: GLuint?
            if let ctr = cachedTextureRef {
                cachedTexture = CVOpenGLESTextureGetName(ctr)
            }
            
            renderFramebuffer = try! Framebuffer(context: sharedImageProcessingContext, orientation: .portrait, size: glSize, textureOnly: false, overriddenTexture: cachedTexture)
        }
        
        
        
        // Simulator doesn't support texture caching
        //if !sharedImageProcessingContext.supportsTextureCaches() {
            renderFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:framebuffer.orientation, size:glSize)
            renderFramebuffer?.lock()
        //}
        
        guard let renderFramebuffer = renderFramebuffer else {
            print("Framebuffer not initialized")
            return
        }
        
        renderFramebuffer.activateFramebufferForRendering()
        clearFramebufferWithColor(Color.blue)
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        renderQuadWithShader(colorSwizzlingShader, uniformSettings:ShaderUniformSettings(), vertices:standardImageVertices, inputTextures:[framebuffer.texturePropertiesForOutputRotation(.noRotation)])
        
        //if sharedImageProcessingContext.supportsTextureCaches() {
            //glFinish()
        //} else {
            glReadPixels(0, 0, renderFramebuffer.size.width, renderFramebuffer.size.height, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddress(pixelBuffer))
            renderFramebuffer.unlock()
        //}
        
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue: CVOptionFlags(0)))
    }
    
    // MARK: - ImageConsumer
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        // sup
        guard let timestamp = framebuffer.timingStyle.timestamp else {
            print("ERROR: No timestamp attached to GPUImage framebuffer")
            return
        }
        let cmTime = timestampToCMTime(timestamp: timestamp)
        
        //autoreleasepool { () in
            
        //}
        
        autoreleasepool {
            if let cf = CMTimeCopyAsDictionary(cmTime, nil),
                let timeDictionary = cf as? [AnyHashable : Any] {
                
                if let request = self.pendingRequests[timeDictionary as NSDictionary] {
                    if let buffer = request.renderContext.newPixelBuffer() {
                        print("got gl framebuffer back, rendering into pixel buffer")
                        renderIntoPixelBuffer(buffer, framebuffer: framebuffer)
                        print("finishing render for timestamp value \(timestamp.value)")
                        request.finish(withComposedVideoFrame: buffer)
                        self.pendingRequests.removeValue(forKey: timeDictionary as NSDictionary)
                    }
                }
                else {
                    print("Could not find pending request")
                }
            }
        }
        
    }
    
    func timestampToCMTime(timestamp: Timestamp) -> CMTime {
        return CMTime(value: timestamp.value, timescale: timestamp.timescale, flags: CMTimeFlags(rawValue: timestamp.flags.rawValue), epoch: timestamp.epoch)
    }
}
