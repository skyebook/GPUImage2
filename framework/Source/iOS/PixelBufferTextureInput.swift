//
//  PixelBufferTextureInput.swift
//  Pods
//
//  Created by Skye Book on 2/17/17.
//
//

//
//  PixelBufferInput.swift
//  Pods
//
//  Created by Skye Book on 1/12/17.
//
//

import AVFoundation

open class PixelBufferTextureInput: ImageSource {
    public let targets = TargetContainer()
    public var runBenchmark = false
    
    let yuvConversionShader:ShaderProgram
    var previousFrameTime: CMTime = kCMTimeZero
    var previousActualFrameTime: CFAbsoluteTime = CFAbsoluteTimeGetCurrent()
    
    var numberOfFramesCaptured: Int = 0
    var totalFrameTimeDuringCapture:Double = 0.0
    
    // MARK: -
    // MARK: Playback control
    
    public init() {
        self.yuvConversionShader = crashOnShaderCompileFailure("PixelBufferInput"){try sharedImageProcessingContext.programForVertexShader(defaultVertexShaderForInputs(2), fragmentShader:YUVConversionFullRangeFragmentShader)}
    }
    
    public func cancel() {
        self.endProcessing()
    }
    
    func endProcessing() {
        
    }
    
    public func process(pixelBuffer:CVPixelBuffer, withSampleTime:CMTime) {
        let bufferHeight = CVPixelBufferGetHeight(pixelBuffer)
        let bufferWidth = CVPixelBufferGetWidth(pixelBuffer)
        CVPixelBufferLockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        
        
        let startTime = CFAbsoluteTimeGetCurrent()
        
        CVOpenGLESTextureCacheFlush(sharedImageProcessingContext.coreVideoTextureCache, 0)
        
        let luminanceFramebuffer:Framebuffer
        let chrominanceFramebuffer:Framebuffer
        if sharedImageProcessingContext.supportsTextureCaches() {
            var luminanceTextureRef:CVOpenGLESTexture? = nil
            let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, pixelBuffer, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), 0, &luminanceTextureRef)
            let luminanceTexture = CVOpenGLESTextureGetName(luminanceTextureRef!)
            glActiveTexture(GLenum(GL_TEXTURE4))
            glBindTexture(GLenum(GL_TEXTURE_2D), luminanceTexture)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            luminanceFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true, overriddenTexture:luminanceTexture)
            
            var chrominanceTextureRef:CVOpenGLESTexture? = nil
            let _ = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, sharedImageProcessingContext.coreVideoTextureCache, pixelBuffer, nil, GLenum(GL_TEXTURE_2D), GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), 1, &chrominanceTextureRef)
            let chrominanceTexture = CVOpenGLESTextureGetName(chrominanceTextureRef!)
            glActiveTexture(GLenum(GL_TEXTURE5))
            glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceTexture)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S), GL_CLAMP_TO_EDGE)
            glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T), GL_CLAMP_TO_EDGE)
            chrominanceFramebuffer = try! Framebuffer(context:sharedImageProcessingContext, orientation:.portrait, size:GLSize(width:GLint(bufferWidth / 2), height:GLint(bufferHeight / 2)), textureOnly:true, overriddenTexture:chrominanceTexture)
        } else {
            glActiveTexture(GLenum(GL_TEXTURE4))
            luminanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:true)
            luminanceFramebuffer.lock()
            
            glBindTexture(GLenum(GL_TEXTURE_2D), luminanceFramebuffer.texture)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE, GLsizei(bufferWidth), GLsizei(bufferHeight), 0, GLenum(GL_LUMINANCE), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 0))
            
            glActiveTexture(GLenum(GL_TEXTURE5))
            chrominanceFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth / 2), height:GLint(bufferHeight / 2)), textureOnly:true)
            chrominanceFramebuffer.lock()
            glBindTexture(GLenum(GL_TEXTURE_2D), chrominanceFramebuffer.texture)
            glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_LUMINANCE_ALPHA, GLsizei(bufferWidth / 2), GLsizei(bufferHeight / 2), 0, GLenum(GL_LUMINANCE_ALPHA), GLenum(GL_UNSIGNED_BYTE), CVPixelBufferGetBaseAddressOfPlane(pixelBuffer, 1))
        }
        
        let conversionMatrix = colorConversionMatrix601FullRangeDefault
        
        // TODO: Get this color query working
        //        if let colorAttachments = CVBufferGetAttachment(movieFrame, kCVImageBufferYCbCrMatrixKey, nil) {
        //            if(CFStringCompare(colorAttachments, kCVImageBufferYCbCrMatrix_ITU_R_601_4, 0) == .EqualTo) {
        //                _preferredConversion = kColorConversion601FullRange
        //            } else {
        //                _preferredConversion = kColorConversion709
        //            }
        //        } else {
        //            _preferredConversion = kColorConversion601FullRange
        //        }
        
        
        //let movieFramebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:luminanceFramebuffer.sizeForTargetOrientation(.portrait), textureOnly:false)
        
        //let movieFramebuffer: Framebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(1920), height:GLint(1080)), textureOnly:false, minFilter: GL_LINEAR, magFilter: GL_LINEAR, wrapS: GL_CLAMP_TO_EDGE, wrapT: GL_CLAMP_TO_EDGE)
        let movieFramebuffer: Framebuffer = sharedImageProcessingContext.framebufferCache.requestFramebufferWithProperties(orientation:.portrait, size:GLSize(width:GLint(bufferWidth), height:GLint(bufferHeight)), textureOnly:false, minFilter: GL_LINEAR, magFilter: GL_LINEAR, wrapS: GL_CLAMP_TO_EDGE, wrapT: GL_CLAMP_TO_EDGE)
        
//        movieFramebuffer.texture
        
        convertYUVToRGB(shader:self.yuvConversionShader, luminanceFramebuffer:luminanceFramebuffer, chrominanceFramebuffer:chrominanceFramebuffer, resultFramebuffer:movieFramebuffer, colorConversionMatrix:conversionMatrix)
        CVPixelBufferUnlockBaseAddress(pixelBuffer, CVPixelBufferLockFlags(rawValue:CVOptionFlags(0)))
        
        movieFramebuffer.timingStyle = .videoFrame(timestamp:Timestamp(withSampleTime))
        
        //print("PIXEL BUFFER INPUT VENDING TEXTURE \(movieFramebuffer.texture)")
        
        self.updateTargetsWithFramebuffer(movieFramebuffer)
        
        if self.runBenchmark {
            let currentFrameTime = (CFAbsoluteTimeGetCurrent() - startTime)
            self.numberOfFramesCaptured += 1
            self.totalFrameTimeDuringCapture += currentFrameTime
            print("Average frame time : \(1000.0 * self.totalFrameTimeDuringCapture / Double(self.numberOfFramesCaptured)) ms")
            print("Current frame time : \(1000.0 * currentFrameTime) ms")
        }
    }
    
    public func transmitPreviousImage(to target:ImageConsumer, atIndex:UInt) {
        // Not needed for movie inputs
    }
}
