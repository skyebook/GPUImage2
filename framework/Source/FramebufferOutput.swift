//
//  FramebufferOutput.swift
//  Pods
//
//  Created by Skye Book on 2/21/17.
//
//

#if os(Linux)
#if GLES
    import COpenGLES.gles2
    #else
    import COpenGL
#endif
#else
#if GLES
    import OpenGLES
    #else
    import OpenGL.GL3
#endif
#endif

public class FramebufferOutput: ImageConsumer {
    public var newFramebufferAvailableCallback:((Framebuffer) -> ())?
    
    public let sources = SourceContainer()
    public let maximumInputs:UInt = 1
    
    //private var lastFramebuffer: Framebuffer?
    
    public init() {
        
    }
    
    public func newFramebufferAvailable(_ framebuffer:Framebuffer, fromSourceIndex:UInt) {
        // responsibility of delegate to unlock later
        newFramebufferAvailableCallback?(framebuffer)
        // TODO: Maybe extend the lifetime of the texture past this if needed
        //framebuffer.unlock()
        /*
         if let lastFramebuffer = self.lastFramebuffer {
         lastFramebuffer.unlock()
         //print("unlocked last FBO")
         }
         lastFramebuffer = framebuffer
         */
    }
}
