import Foundation
import ScreenSaver
import GLKit

struct PixelData {
    var r: UInt8
    var g: UInt8
    var b: UInt8
    var a: UInt8
}

class MondriantScreenSaverView : ScreenSaverView {
    
    var openGLInitialized: Bool = false
    var view: NSOpenGLView! = nil
    var shader: (GLuint, GLuint, GLuint) = (0, 0, 0)
    var vbo: GLuint = 0
    var tex: GLuint = 0
    var texLoc: GLint = 0
    var imageIndex: Int = 0
    
    var settings: AntSettings = AntSettings()
    var variances: AntVariances = AntVariances()
    var pixels: [PixelData]! = nil
    var ants: [Ant] = [Ant]()
    
    var simulationFinished: Bool = false
    var simulationFinishedTime: NSDate! = nil
    var time: Float = 0.0
    
    @IBOutlet weak var configPanel: NSPanel! = nil
    
    @IBOutlet weak var bg_colorWell: NSColorWell! = nil
    @IBOutlet weak var speedSlider: NSSlider! = nil
    @IBOutlet weak var paddingSlider: NSSlider! = nil
    @IBOutlet weak var split_dt_startField: NSTextField! = nil
    @IBOutlet weak var split_dt_factorField: NSTextField! = nil
    @IBOutlet weak var split_dt_minField: NSTextField! = nil
    @IBOutlet weak var split_dt_maxField: NSTextField! = nil
    @IBOutlet weak var split_rate_startField: NSTextField! = nil
    @IBOutlet weak var split_rate_factorField: NSTextField! = nil
    @IBOutlet weak var end_pause_timeField: NSTextField! = nil
    @IBOutlet weak var colored_pathButton: NSButton! = nil

    @IBOutlet weak var split_dt_startSlider: NSSlider! = nil
    @IBOutlet weak var split_dt_factorSlider: NSSlider! = nil
    @IBOutlet weak var split_dt_minSlider: NSSlider! = nil
    @IBOutlet weak var split_dt_maxSlider: NSSlider! = nil
    @IBOutlet weak var split_rate_startSlider: NSSlider! = nil
    @IBOutlet weak var split_rate_factorSlider: NSSlider! = nil
    
    
    override init(frame: NSRect, isPreview: Bool) {
        super.init(frame: frame, isPreview: isPreview)
        loadSettingsAndVariances(frame)
        setAnimationTimeInterval(1.0/30.0)
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        loadSettingsAndVariances(frame)
    }
    
    deinit {
        deinitOpenGL()
        view.removeFromSuperview()
    }
    
    func initOpenGL(#w: Int, h:Int) {
        // OpenGL Context
        let attributes: [Int] = [Int(NSOpenGLPFAAccelerated), 0]
        let attr_ptr = UnsafePointer<NSOpenGLPixelFormatAttribute>(attributes)
        let format = NSOpenGLPixelFormat(attributes: attr_ptr)
        view = NSOpenGLView(frame: frame, pixelFormat: format)!
        self.addSubview(view)
        view.openGLContext.makeCurrentContext()
        glEnable(GLenum(GL_BLEND))
        glBlendFunc(GLenum(GL_SRC_ALPHA), GLenum(GL_ONE_MINUS_SRC_ALPHA))
        glClearColor(Float(Ant.s.bg_color.r)/255.0,
                     Float(Ant.s.bg_color.g)/255.0,
                     Float(Ant.s.bg_color.b)/255.0,
                     Float(Ant.s.bg_color.a)/255.0)
        check_gl_error()
        // VBO
        glGenBuffers(1, &vbo)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        var vertices: [Float] = [-1.0, -1.0, 0.0, 0.0,
                                 -1.0,  1.0, 0.0, 1.0,
                                  1.0, -1.0, 1.0, 0.0,
                                  1.0,  1.0, 1.0, 1.0]
        glBufferData(GLenum(GL_ARRAY_BUFFER), Int(16*sizeof(GLfloat)),
                     &vertices, GLenum(GL_STATIC_DRAW))
        let first_slot = UnsafePointer<Int>(bitPattern: 0)
        glVertexAttribPointer(0, 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                              GLsizei(4*sizeof(GLfloat)), first_slot)
        glEnableVertexAttribArray(0)
        check_gl_error()
        // Texture
        glGenTextures(1, &tex)
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glTexImage2D(GLenum(GL_TEXTURE_2D), 0, GL_RGBA, GLsizei(w), GLsizei(h),
                     0, GLenum(GL_RGBA), GLenum(GL_UNSIGNED_BYTE), pixels)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MIN_FILTER),
                        GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_MAG_FILTER),
                        GL_NEAREST)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_S),
                        GL_CLAMP_TO_EDGE)
        glTexParameteri(GLenum(GL_TEXTURE_2D), GLenum(GL_TEXTURE_WRAP_T),
                        GL_CLAMP_TO_EDGE)
        check_gl_error()
        // Shaders
        let vertex_shader = "attribute vec4 vx_tx;\nvarying vec2 tx;\nvoid ma" +
            "in(void) {\ntx=vx_tx.zw;\ngl_Position=vec4(vx_tx.xy,0.0,1.0);\n}"
        let fragment_shader = "uniform sampler2D Tex;\nvarying vec2 tx;\n" +
            "void main(void) {\ngl_FragColor=texture2D(Tex,tx);\n}"
        shader = compileShaderProgram(vertex_shader,fragment_shader,["vx_tx"])
        glUseProgram(shader.0)
        texLoc = glGetUniformLocation(shader.0, "Tex")
        check_gl_error()
    }
    
    func deinitOpenGL() {
        if (openGLInitialized) {
            view.openGLContext.makeCurrentContext()
            glDeleteTextures(1, &tex)
            glDeleteBuffers(1, &vbo)
            glDeleteShader(shader.2)
            glDeleteShader(shader.1)
            glDeleteProgram(shader.0)
        }
    }
    
    override func startAnimation() {
        super.startAnimation()
        animateOneFrame()
    }
    
    override func stopAnimation() {
        deinitOpenGL()
        openGLInitialized = false
        super.stopAnimation()
    }
    
    override func drawRect(rect: NSRect) {
        super.drawRect(rect)
    }
    
    override func animateOneFrame() {
        
        // initialize opengl and ants
        if (!openGLInitialized) {
            time = 0
            let w = Int(frame.width)
            let h = Int(frame.height)
            settings.w = w
            settings.h = h
            Ant.s.copyAssignment(settings)
            pixels = [PixelData](count: w*h, repeatedValue: Ant.s.bg_color)
            ants = [Ant(x: w/2, y: h/2, dx: 0, dy: -1, time: time)]
            initOpenGL(w:w, h:h)
            openGLInitialized = true
            simulationFinished = false
            srand48(Int(arc4random()))
        }
        
        // update image
        assert(pixels != nil)
        for i in 1...Ant.s.speed {
            // simulation step
            if (!simulationFinished) {
                var ant_index = 0
                var ant_count = ants.count
                while (ant_index < ant_count) {
                    switch ants[ant_index].step(time, pixels: pixels) {
                    case .Halt:
                        ants.removeAtIndex(ant_index)
                        ant_count -= 1
                    case .Move:
                        ants[ant_index].draw(&pixels)
                        ant_index += 1
                    case .Split(let new_ant):
                        ants.append(new_ant)
                        ant_index += 1
                    }
                }
            }
            time += 1.0
            // check if simulation is finished
            if (ants.count == 0 && !simulationFinished) {
                time = 0.0
                simulationFinished = true
                simulationFinishedTime = NSDate()
                outputPng(imageIndex % 10)
                imageIndex += 1
            }
            // check if finished and end pause time over
            if (ants.count == 0 && simulationFinished) {
                let time_since_end = -simulationFinishedTime.timeIntervalSinceNow
                if (time_since_end > Double(settings.end_pause_time)) {
                    // reset simulation
                    time = 0.0
                    let w = settings.w
                    let h = settings.h
                    for i in 0..<(w*h) {
                        pixels[i] = settings.bg_color
                    }
                    randomizeAntSettings()
                    ants.append(Ant(x: w/2, y: h/2, dx: 0, dy: -1, time: time))
                    simulationFinished = false
                    break;
                }
            }
        }
        
        // draw image
        view.openGLContext.makeCurrentContext()
        glClear(GLbitfield(GL_COLOR_BUFFER_BIT))
        glTexSubImage2D(GLenum(GL_TEXTURE_2D), 0, 0, 0, GLsizei(settings.w),
                        GLsizei(settings.h), GLenum(GL_RGBA),
                        GLenum(GL_UNSIGNED_BYTE), pixels)
        glUniform1i(texLoc, 0)
        glActiveTexture(GLenum(GL_TEXTURE0))
        glBindTexture(GLenum(GL_TEXTURE_2D), tex)
        glBindBuffer(GLenum(GL_ARRAY_BUFFER), vbo)
        let first_slot = UnsafePointer<Int>(bitPattern: 0)
        glVertexAttribPointer(0, 4, GLenum(GL_FLOAT), GLboolean(GL_FALSE),
                              GLsizei(4*sizeof(GLfloat)), first_slot)
        glEnableVertexAttribArray(0)
        glDrawArrays(GLenum(GL_TRIANGLE_STRIP), 0, 4)
        glFlush()
        needsDisplay = true
    }
    
    override func hasConfigureSheet() -> Bool {
        return true
    }
    
    override func configureSheet() -> NSWindow? {
        if (configPanel == nil) {
            let bundle = NSBundle(forClass: MondriantScreenSaverView.self)
            let nibLoaded = bundle.loadNibNamed("MondriantConfigureSheet",
                                                owner: self,
                                                topLevelObjects: nil)
            if (!nibLoaded) {
                NSLog("Could not load nib named \(bundle.bundlePath).")
            }
            if (configPanel == nil) {
                NSLog("Could not create configuration panel.")
            }
        }
        updateConfigureSheet()
        return configPanel;
    }
    
    @IBAction func closeConfigureSheet(sender: NSButton) {
        updateSettingsAndVariancesFromConfigureSheet()
        let defaults = ScreenSaverDefaults.defaultsForModuleWithName(
            "com.michael-white.mondriant-screensaver") as! ScreenSaverDefaults
        let s = NSKeyedArchiver.archivedDataWithRootObject(settings)
        defaults.setObject(s, forKey: "AntSettings")
        let v = NSKeyedArchiver.archivedDataWithRootObject(variances)
        defaults.setObject(v, forKey: "AntVariances")
        configPanel.sheetParent!.endSheet(configPanel)
        defaults.synchronize()
    }
    
    @IBAction func cancelConfigureSheet(sender: NSButton) {
        configPanel.sheetParent!.endSheet(configPanel)
    }
    
    func updateSettingsAndVariancesFromConfigureSheet() {
        settings.bg_color.r = UInt8(bg_colorWell.color.redComponent*255.0)
        settings.bg_color.g = UInt8(bg_colorWell.color.greenComponent*255.0)
        settings.bg_color.b = UInt8(bg_colorWell.color.blueComponent*255.0)
        settings.bg_color.a = UInt8(bg_colorWell.color.alphaComponent*255.0)

        settings.speed = speedSlider.integerValue
        settings.padding = paddingSlider.integerValue
        settings.split_dt_start = split_dt_startField.floatValue
        settings.split_dt_factor = split_dt_factorField.floatValue
        settings.split_dt_min = split_dt_minField.floatValue
        settings.split_dt_max = split_dt_maxField.floatValue
        settings.split_rate_start = split_rate_startField.floatValue
        settings.split_rate_factor = split_rate_factorField.floatValue
        settings.end_pause_time = end_pause_timeField.floatValue
        settings.colored_path = (colored_pathButton.state == NSOnState)
        settings.validate()

        variances.split_dt_start = split_dt_startSlider.integerValue
        variances.split_dt_factor = split_dt_factorSlider.integerValue
        variances.split_dt_min = split_dt_minSlider.integerValue
        variances.split_dt_max = split_dt_maxSlider.integerValue
        variances.split_rate_start = split_rate_startSlider.integerValue
        variances.split_rate_factor = split_rate_factorSlider.integerValue
        variances.validate()
    }

    func loadSettingsAndVariances(frame: NSRect) {
        let defaults = ScreenSaverDefaults.defaultsForModuleWithName(
            "com.michael-white.mondriant-screensaver") as! ScreenSaverDefaults
        let s_option: AnyObject? = defaults.objectForKey("AntSettings")
        if (s_option == nil) {
            settings = AntSettings()
        } else {
            let s = s_option! as! NSData
            settings = NSKeyedUnarchiver.unarchiveObjectWithData(s) as!
                AntSettings
        }
        settings.validate()
        let v_option: AnyObject? = defaults.objectForKey("AntVariances")
        if (v_option == nil) {
            variances = AntVariances()
        } else {
            let v = v_option! as! NSData
            variances = NSKeyedUnarchiver.unarchiveObjectWithData(v) as!
                AntVariances
        }
        variances.validate()
    }
    
    func updateConfigureSheet() {
        let r = CGFloat(settings.bg_color.r) / 255.0
        let g = CGFloat(settings.bg_color.g) / 255.0
        let b = CGFloat(settings.bg_color.b) / 255.0
        let a = CGFloat(settings.bg_color.a) / 255.0
        let bg_color = NSColor(calibratedRed: r, green: g, blue: b, alpha: a)
        bg_colorWell.color = bg_color
        speedSlider.integerValue = settings.speed
        paddingSlider.integerValue = settings.padding
        
        split_dt_startField.stringValue = roundedFloatString(
            settings.split_dt_start)
        split_dt_factorField.stringValue = roundedFloatString(
            settings.split_dt_factor)
        split_dt_minField.stringValue = roundedFloatString(
            settings.split_dt_min)
        split_dt_maxField.stringValue = roundedFloatString(
            settings.split_dt_max)
        split_rate_startField.stringValue = roundedFloatString(
            settings.split_rate_start)
        split_rate_factorField.stringValue = roundedFloatString(
            settings.split_rate_factor)
        end_pause_timeField.stringValue = roundedFloatString(
            settings.end_pause_time)
        
        split_dt_startSlider.integerValue = variances.split_dt_start
        split_dt_factorSlider.integerValue = variances.split_dt_factor
        split_dt_minSlider.integerValue = variances.split_dt_min
        split_dt_maxSlider.integerValue = variances.split_dt_max
        split_rate_startSlider.integerValue = variances.split_rate_start
        split_rate_factorSlider.integerValue = variances.split_rate_factor
    }
    
    func randomizeAntSettings() {
        
        let c2 = settings.split_dt_start
        let v2 = c2 * Float(variances.split_dt_start) * 0.1
        Ant.s.split_dt_start = sampleTriangularDistribution(c2, v2)
        let c3 = settings.split_dt_factor
        let v3 = 2.0 * abs(c3 - 1.0) * Float(variances.split_dt_factor) * 0.1
        Ant.s.split_dt_factor = sampleTriangularDistribution(c3, v3)
        
        let c4 = settings.split_dt_min
        let v4 = c4 * Float(variances.split_dt_min) * 0.1
        Ant.s.split_dt_min = sampleTriangularDistribution(c4, v4)
        
        let c5 = clampMin(settings.split_dt_max - settings.split_dt_min, 0.0)
        let v5 = c5 * Float(variances.split_dt_max) * 0.1
        Ant.s.split_dt_max = Ant.s.split_dt_min +
            sampleTriangularDistribution(c5, v5)
        
        let c6 = settings.split_rate_start
        let v6 = c6 * Float(variances.split_rate_start) * 0.1
        Ant.s.split_rate_start = sampleTriangularDistribution(c6, v6)
        let c7 = settings.split_rate_factor
        let v7 = 2.0 * abs(c7 - 1.0) * Float(variances.split_rate_factor) * 0.1
        Ant.s.split_rate_factor = sampleTriangularDistribution(c7, v7)

        Ant.s.color_start = Float(drand48()) * 6.28 / Ant.s.color_freq
        
        Ant.s.validate()
    }
    
    @IBAction func resetSettingsAndVariances(sender: NSButton) {
        settings = AntSettings()
        variances = AntVariances()
        updateConfigureSheet()
    }
    
    func outputPng(index: Int) {
        let dir = NSSearchPathDirectory.ApplicationSupportDirectory
        let mask = NSSearchPathDomainMask.UserDomainMask
        if let searchPath = NSSearchPathForDirectoriesInDomains(dir, mask, true) {
            if (searchPath.count > 0) {
                let asPath = searchPath[0] as! String
                let dirPath = asPath + "/Mondriant"
                if (!NSFileManager.defaultManager().fileExistsAtPath(dirPath)) {
                    let err = NSErrorPointer()
                    if (!NSFileManager.defaultManager().createDirectoryAtPath(dirPath,
                        withIntermediateDirectories: false, attributes: nil, error: err)) {
                        NSLog("Couldn't make directory: ", err.debugDescription)
                    }
                }
                let pngPath = dirPath + "/" + String(index) + ".png"
                let w = settings.w
                let h = settings.h
                let provider = CGDataProviderCreateWithData(nil, pixels, w * h * 4, nil)
                let colorSpace = CGColorSpaceCreateDeviceRGB()
                let bitmapInfo = CGBitmapInfo(CGImageAlphaInfo.Last.rawValue)
                let renderingIntent = kCGRenderingIntentDefault
                let ref = CGImageCreate(w, h, 8, 32, 4 * w, colorSpace, bitmapInfo,
                                        provider, nil, true, renderingIntent);
                let image = NSImage(CGImage: ref, size: NSSize(width: w, height: h))
                image.TIFFRepresentation!.writeToFile(pngPath, atomically: true)
            }
        }
    }
}

class AntSettings : NSObject {
    
    var w: Int                   = 0     // width of the bounding box
    var h: Int                   = 0     // height of the bounding box
    var bg_color: PixelData      = PixelData(r:0, g:0, b:0, a:255) // black
    
    // configurable parameters
    var speed: Int               = 6     // how many iterations per frame
    var padding: Int             = 1     // number pixels ants look ahead
    var split_dt_start: Float    = 8.0   // starting value for split_dt
    var split_dt_factor: Float   = 1.03  // split_dt *= split_dt_factor
    var split_dt_min: Float      = 2.0   // minimum value for split_dt
    var split_dt_max: Float      = 64.0  // maximum value for split_dt
    var split_rate_start: Float  = 1.0   // starting value for split_rate
    var split_rate_factor: Float = 0.96  // split_rate *= split_rate_factor
    var end_pause_time: Float    = 5.0   // how long to pause after the end
    var color_freq: Float        = 0.005 // how fast the color changes
    var color_start: Float       = 0.0   // starting color for the ant trails
    var colored_path: Bool       = true  // whether ants leave colored paths
    
    required override init() {
        super.init()
    }
    
    init?(coder aDecoder: NSCoder) {
        bg_color.r        = UInt8(aDecoder.decodeIntegerForKey("bg_color_r"))
        bg_color.g        = UInt8(aDecoder.decodeIntegerForKey("bg_color_g"))
        bg_color.b        = UInt8(aDecoder.decodeIntegerForKey("bg_color_b"))
        bg_color.a        = UInt8(aDecoder.decodeIntegerForKey("bg_color_a"))
        
        speed             = aDecoder.decodeIntegerForKey("speed")
        padding           = aDecoder.decodeIntegerForKey("padding")
        split_dt_start    = aDecoder.decodeFloatForKey("split_dt_start")
        split_dt_factor   = aDecoder.decodeFloatForKey("split_dt_factor")
        split_dt_min      = aDecoder.decodeFloatForKey("split_dt_min")
        split_dt_max      = aDecoder.decodeFloatForKey("split_dt_max")
        split_rate_start  = aDecoder.decodeFloatForKey("split_rate_start")
        split_rate_factor = aDecoder.decodeFloatForKey("split_rate_factor")
        end_pause_time    = aDecoder.decodeFloatForKey("end_pause_time")
        color_freq        = aDecoder.decodeFloatForKey("color_freq")
        colored_path      = aDecoder.decodeBoolForKey("colored_path")
    }
    
    func copyAssignment(a: AntSettings) {
        w = a.w
        h = a.h
        bg_color = a.bg_color
        speed = a.speed
        padding = a.padding
        split_dt_start = a.split_dt_start
        split_dt_factor = a.split_dt_factor
        split_dt_min = a.split_dt_min
        split_dt_max = a.split_dt_max
        split_rate_start = a.split_rate_start
        split_rate_factor = a.split_rate_factor
        end_pause_time = a.end_pause_time
        color_freq = a.color_freq
        colored_path = a.colored_path
    }
    
    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInteger(Int(bg_color.r), forKey: "bg_color_r")
        aCoder.encodeInteger(Int(bg_color.g), forKey: "bg_color_g")
        aCoder.encodeInteger(Int(bg_color.b), forKey: "bg_color_b")
        aCoder.encodeInteger(Int(bg_color.a), forKey: "bg_color_a")
        
        aCoder.encodeInteger(speed, forKey: "speed")
        aCoder.encodeInteger(padding, forKey: "padding")
        aCoder.encodeFloat(split_dt_start, forKey: "split_dt_start")
        aCoder.encodeFloat(split_dt_factor, forKey: "split_dt_factor")
        aCoder.encodeFloat(split_dt_min, forKey: "split_dt_min")
        aCoder.encodeFloat(split_dt_max, forKey: "split_dt_max")
        aCoder.encodeFloat(split_rate_start, forKey: "split_rate_start")
        aCoder.encodeFloat(split_rate_factor, forKey: "split_rate_factor")
        aCoder.encodeFloat(end_pause_time, forKey: "end_pause_time")
        aCoder.encodeFloat(color_freq, forKey: "color_freq")
        aCoder.encodeBool(colored_path, forKey: "colored_path")
    }
    
    func validate() {
        speed               = clamp(speed, 1, 11)
        padding             = clamp(padding, 0, 10)
        split_dt_start      = clampMin(split_dt_start, 0.001)
        split_dt_factor     = clampMin(split_dt_factor, 0.001)
        split_dt_min        = clampMin(split_dt_min, 0.001)
        split_dt_max        = clampMin(split_dt_max, split_dt_min)
        split_dt_start      = clamp(split_dt_start, split_dt_min, split_dt_max)
        split_rate_start    = clampMin(split_rate_start, 0.0)
        split_rate_factor   = clampMin(split_rate_factor, 0.001)
        end_pause_time      = clampMin(end_pause_time, 0.0)
        color_freq          = clampMin(color_freq, 0.001)
    }
}

class AntVariances: NSObject {
    
    var split_dt_start: Int    = 10
    var split_dt_factor: Int   = 10
    var split_dt_min: Int      = 10
    var split_dt_max: Int      = 10
    var split_rate_start: Int  = 10
    var split_rate_factor: Int = 10
    
    override init() {
        super.init()
    }
    
    init?(coder aDecoder: NSCoder) {
        split_dt_start  = aDecoder.decodeIntegerForKey("split_dt_start")
        split_dt_factor = aDecoder.decodeIntegerForKey("split_dt_factor")
        split_dt_min    = aDecoder.decodeIntegerForKey("split_dt_min")
        split_dt_max    = aDecoder.decodeIntegerForKey("split_dt_max")
        split_rate_start = aDecoder.decodeIntegerForKey("split_rate_start")
        split_rate_factor = aDecoder.decodeIntegerForKey("split_rate_factor")
    }
    
    func encodeWithCoder(aCoder: NSCoder) {
        aCoder.encodeInteger(split_dt_start, forKey: "split_dt_start")
        aCoder.encodeInteger(split_dt_factor, forKey: "split_dt_factor")
        aCoder.encodeInteger(split_dt_min, forKey: "split_dt_min")
        aCoder.encodeInteger(split_dt_max, forKey: "split_dt_max")
        aCoder.encodeInteger(split_rate_start, forKey: "split_rate_start")
        aCoder.encodeInteger(split_rate_factor, forKey: "split_rate_factor")
    }
    
    func validate() {
        split_dt_start    = clamp(split_dt_start, 0, 10)
        split_dt_factor   = clamp(split_dt_factor, 0, 10)
        split_dt_min      = clamp(split_dt_min, 0, 10)
        split_dt_max      = clamp(split_dt_max, 0, 10)
        split_rate_start  = clamp(split_rate_start, 0, 10)
        split_rate_factor = clamp(split_rate_factor, 0, 10)
    }
}

class Ant {
    
    var x: Int            // x position
    var y: Int            // y position
    var dx: Int           // x step size
    var dy: Int           // y step size
    var split_t: Float    // time at which the next split will be forced
    var split_dt: Float   // time between forced splits
    var split_rate: Float // rate at which random splits happen
    var num_steps: Float  // how many steps have happened
    var num_splits: Float // how many splits have happened
    
    static var s: AntSettings = AntSettings()
    
    init(x: Int, y: Int, dx: Int, dy: Int, time: Float) {
        self.x = x
        self.y = y
        self.dx = dx
        self.dy = dy
        split_t = time
        split_dt = Ant.s.split_dt_start
        split_rate = Ant.s.split_rate_start
        num_steps = 0
        num_splits = 0
    }
    
    init(splitFrom: Ant) {
        x = splitFrom.x
        y = splitFrom.y
        dx = -splitFrom.dx
        dy = -splitFrom.dy
        split_t = splitFrom.split_t
        split_dt = splitFrom.split_dt
        split_rate = splitFrom.split_rate
        num_steps = splitFrom.num_steps
        num_splits = splitFrom.num_splits
    }
    
    func in_bounds(#x: Int, y: Int) -> Bool {
        return (0 <= x && x < Ant.s.w && 0 <= y && y < Ant.s.h)
    }
    
    func is_background(pixels: [PixelData], x: Int, y: Int) -> Bool {
        if (!in_bounds(x: x, y: y)) {
            return false
        }
        let p = pixels[Ant.s.w * y + x]
        return (p.r == Ant.s.bg_color.r && p.g == Ant.s.bg_color.g &&
                p.b == Ant.s.bg_color.b && p.a == Ant.s.bg_color.a)
    }
    
    func path_blocked(pixels: [PixelData]) -> Bool {
        var px = x
        var py = y
        for i in 1...Ant.s.padding {
            px += dx
            py += dy
            if (!is_background(pixels, x: px, y: py)) {
                return true
            }
        }
        return false
    }
    
    func split(time: Float) -> Ant {
        let tmp = dx
        dx = -dy
        dy = tmp
        split_t = time + split_dt + 2.0 * expf(-0.1 * split_dt * split_dt)
        if (split_dt >= Ant.s.split_dt_min && split_dt <= Ant.s.split_dt_max) {
            split_dt *= Ant.s.split_dt_factor
        }
        split_rate *= Ant.s.split_rate_factor
        num_splits += 1
        return Ant(splitFrom: self)
    }
    
    func step(time: Float, pixels: [PixelData]) -> AntStepResult {
        if (time > split_t ||
            atanf(split_rate * 0.25) * 0.6366 > Float(drand48())) {
            return AntStepResult.Split(split(time))
        }
        num_steps += 1
        x += dx
        y += dy
        if (in_bounds(x:x, y:y) &&
            is_background(pixels, x: x, y: y) &&
            is_background(pixels, x: x+dy, y: y+dx) &&
            is_background(pixels, x: x-dy, y: y-dx) &&
            !path_blocked(pixels)) {
            return AntStepResult.Move
        } else {
            return AntStepResult.Halt
        }
    }
    
    func draw(inout pixels: [PixelData]!) {
        let r: UInt8;
        let g: UInt8;
        let b: UInt8;
        if (Ant.s.colored_path) {
            let t = Ant.s.color_freq * (num_steps + Ant.s.color_start)
            r = UInt8(sinf(t              ) * 127 + 128)
            g = UInt8(sinf(t + 3.14 * 0.67) * 127 + 128)
            b = UInt8(sinf(t + 3.14 * 1.33) * 127 + 128)
        } else {
            r = 255;
            g = 255;
            b = 255;
        }
        pixels[Ant.s.w * y + x] = PixelData(r:r, g:g, b:b, a:255)
    }
}

enum AntStepResult {
    case Halt
    case Move
    case Split(Ant)
}

func check_gl_error(_ message: String = "", line: Int = __LINE__)
{
    var err: GLenum = glGetError()
    if (err != GLenum(GL_NO_ERROR)) {
        println("OpenGL error on line \(line): \(err)")
    }
}

func clamp<T: Comparable>(x: T, min: T, max: T) -> T
{
    if (x < min) {
        return min
    }
    if (x > max) {
        return max
    }
    return x
}

func clampMin<T: Comparable>(x: T, min: T) -> T
{
    if (x < min) {
        return min
    }
    return x
}

func sampleTriangularDistribution(center: Float, width: Float) -> Float
{
    let u = Float(drand48())
    if (u < 0.5) {
        return center - width * sqrtf(2.0 * u)
    } else {
        return center + width * sqrtf(2.0 - 2.0 * u)
    }
}

func roundedFloatString(x: Float) -> String
{
    var formatter = NSNumberFormatter()
    formatter.maximumSignificantDigits = 5
    return formatter.stringFromNumber(NSNumber(float: x))!
}

func compileShader(shader_source: String, vertex_shader: Bool) -> GLuint
{
    let shader_type = GLenum(vertex_shader ? GL_VERTEX_SHADER : GL_FRAGMENT_SHADER)
    var shader_handle = glCreateShader(shader_type)
    var cstr = (shader_source as NSString).UTF8String
    glShaderSource(shader_handle, 1, &cstr, nil)
    glCompileShader(shader_handle)
    var is_compiled: GLint = 0
    glGetShaderiv(shader_handle, GLenum(GL_COMPILE_STATUS), &is_compiled)
    if(is_compiled == GL_FALSE) {
        var max_len: GLint = 0
        glGetShaderiv(shader_handle, GLenum(GL_INFO_LOG_LENGTH), &max_len)
        var info_log: [GLchar] = [GLchar](count: Int(max_len), repeatedValue: 0)
        var info_log_len: GLsizei = 0
        glGetShaderInfoLog(shader_handle, max_len, &info_log_len, &info_log)
        let message_string = NSString(bytes: info_log,
                                      length: Int(info_log_len),
                                      encoding: NSASCIIStringEncoding)!
        let shader_source_string = NSString(bytes: cstr,
                                            length: Int(count(shader_source)),
                                            encoding: NSASCIIStringEncoding)!
        println("Failed to compile shader!")
        println(message_string)
        println(shader_source_string)
        assert(false)
    }
    return shader_handle
}

func compileShaderProgram(vs: String, fs: String, inputs: [String])
    -> (GLuint, GLuint, GLuint)
{
    var shader_program: GLuint = 0
    var vertex_shader = compileShader(vs, true)
    var fragment_shader = compileShader(fs, false)
    
    // create shader program and attach shaders
    shader_program = glCreateProgram()
    glAttachShader(shader_program, vertex_shader)
    glAttachShader(shader_program, fragment_shader)
    var i: GLuint = 0
    for input in inputs {
        let cstr = (input as NSString).UTF8String
        glBindAttribLocation(shader_program, i++, cstr)
        check_gl_error()
    }
    // link the shader objects
    glLinkProgram(shader_program)
    var is_linked: GLint = 0
    glGetProgramiv(shader_program, GLenum(GL_LINK_STATUS), &is_linked)
    if(is_linked == GL_FALSE) {
        var max_len: GLint = 0
        glGetProgramiv(shader_program, GLenum(GL_INFO_LOG_LENGTH), &max_len)
        var info_log: [GLchar] = [GLchar](count: Int(max_len), repeatedValue:0)
        var info_log_len: GLsizei = 0
        glGetProgramInfoLog(shader_program, max_len, &info_log_len, &info_log)
        var message_string = NSString(bytes: info_log, length:Int(info_log_len),
                                      encoding: NSASCIIStringEncoding)
        println("Failed to link shader!")
        println(message_string)
        exit(1)
    }
    return (shader_program, vertex_shader, fragment_shader)
}

