//
//  ShotViewController.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/19/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import UIKit
import GLKit
import AVFoundation
import QuartzCore
import CoreImage

class ShotViewController: UIViewController, LFCameraDelegate {
    
    @IBOutlet weak var previewView : GLKView!
    @IBOutlet weak var heightConst : NSLayoutConstraint!
    @IBOutlet weak var progressButton : ProgressButton!
    @IBOutlet weak var progressBar : UIProgressView!
    
    var camera : LFCamera?
    var transformFilter : CIFilter?
//    var cropFilter : CIFilter?
    var index : Double! = 0
//    var crop : Bool! = false
    var colorFilter : CIFilter?
    var colored : Bool = false
    
    // writer
    var ciContext : CIContext?
    var colorSpace : CGColorSpace?
    var recordStart : Bool = false
    var recordStartTime : CMTime = kCMTimeInvalid
    var assetWriter : AVAssetWriter?
    var videoInput : AVAssetWriterInput?
    var pixelAdapter : AVAssetWriterInputPixelBufferAdaptor?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        ciContext = CIContext(EAGLContext: LFEAGLContext.shareContext.glContext!,
            options: [kCIContextWorkingColorSpace : NSNull()])
        colorSpace = CGColorSpaceCreateDeviceRGB()
        previewView.context = LFEAGLContext.shareContext.glContext!
        previewView.enableSetNeedsDisplay = false
        
        camera = LFCamera(presentName: AVCaptureSessionPresetHigh)
        camera?.delegate = self
        camera?.initSession()
        camera?.previewView = previewView
        
        transformFilter = CIFilter(name: "CIAffineTransform")
        colorFilter = CIFilter(name: "CIPhotoEffectChrome")
    }
    
    override func viewWillAppear(animated: Bool) {
        camera?.start()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
    }
    
    override func prefersStatusBarHidden() -> Bool {
        return true
    }
    

    // MARK: LFCameraDelegate
    func capture(image: CIImage, time: CMTime) {
        transformFilter?.setValue(image, forKey: kCIInputImageKey)
        var transform = CGAffineTransformIdentity// CGAffineTransformTranslate(CGAffineTransformIdentity, -960, -540)
        transform = CGAffineTransformRotate(transform, CGFloat(-M_PI_2))// / 1000.0 * self.index))
        
        transformFilter?.setValue(NSValue(CGAffineTransform : transform), forKey: kCIInputTransformKey)
        var ciimage : CIImage! = image.imageByApplyingTransform(transform)
        var extent : CGRect! = ciimage?.extent
//        extent.origin = CGPointZero
        
//        cropFilter?.setValue(ciimage, forKey: kCIInputImageKey)
        extent.size = CGSizeMake(1080, 1080)
        extent.origin = CGPointMake(extent.origin.x  , extent.origin.y + (1920 - 1080) / 2.0)
//        cropFilter?.setValue(CIVector(CGRect: extent), forKey: "inputRectangle")
        
//        let cropedImage = cropFilter?.outputImage
//        let cropedExtent = cropedImage?.extent as CGRect!
        
        EAGLContext.setCurrentContext(LFEAGLContext.shareContext.glContext)
        let width = CGFloat(previewView.drawableWidth)
        let height = CGFloat(previewView.drawableHeight)
        let bounds = CGRectMake(0, 0, width, height)
        
//        if crop == true {
//            camera?.ciContext?.drawImage(cropedImage!, inRect:bounds, fromRect: cropedExtent)
//        } else {
            if recordStart == true {
                if CMTIME_IS_INVALID(recordStartTime) == true {
                    recordStartTime = time
                }
                
                var renderedOutputPixelBuffer : CVPixelBuffer? = nil
                CVPixelBufferPoolCreatePixelBuffer(nil, pixelAdapter!.pixelBufferPool!, &renderedOutputPixelBuffer)
                
                ciContext?.render(image,
                    toCVPixelBuffer: renderedOutputPixelBuffer!,
                    bounds: CGRectMake(0, 0, 1980, 1080),
                    colorSpace: colorSpace)
                
                let buf = CIImage(CVPixelBuffer: renderedOutputPixelBuffer!)

                previewView.bindDrawable()
                camera?.ciContext?.drawImage(buf, inRect:bounds, fromRect:buf.extent)
                previewView.display()
                
                if (videoInput?.readyForMoreMediaData == true) {
                    let presentationTime = CMTimeSubtract(time, recordStartTime)
                    let status = pixelAdapter?.appendPixelBuffer(renderedOutputPixelBuffer!, withPresentationTime: presentationTime)
                    if status == true {
                        NSLog("append pixel succ")
                    } else {
                        NSLog("error!")
                    }
                    
                    if CMTimeGetSeconds(presentationTime) > 1.0 {
                        recordStart = false
                        videoInput?.markAsFinished()
                        assetWriter?.finishWritingWithCompletionHandler({ () -> Void in
                            NSLog("OK!")
                        })
                    }
                }
                
            } else {
                previewView.bindDrawable()
                let rect = AVMakeRectWithAspectRatioInsideRect(bounds.size, ciimage.extent)
                ciimage = ciimage.imageByCroppingToRect(rect)
                //
                if colored {
                    colorFilter?.setValue(ciimage, forKey: kCIInputImageKey)
                    ciimage = colorFilter?.outputImage
                }
                //
                camera?.ciContext?.drawImage(ciimage!, inRect:bounds, fromRect: ciimage.extent)
                previewView.display()
            }
//        }
        self.index = self.index + 1
    }
    
    @IBAction func filtered(sender: UIButton!) {
        sender.selected = !sender.selected
        colored = sender.selected
    }
    // MARK : actions
    @IBAction func toggle(sender : UIButton!) {
        sender.selected = !sender.selected
        camera?.rotate()
    }
    
    @IBAction func snap(sender : UIButton!) {
        camera?.snapStill({ (result : Bool) -> Void in
            
        })
    }
    
    @IBAction func record(sender : UIButton!) {
        camera?.snapLivePhoto({ (progress) -> Void in
            dispatch_async(dispatch_get_main_queue(), { () -> Void in
                self.progressBar.progress = progress
            })
            }, resultBlock: { (result, imageOutputURL, videoOutputURL) -> Void in
                if imageOutputURL != nil && videoOutputURL != nil {
                    dispatch_async(dispatch_get_main_queue(), { () -> Void in
                        let livePhoto = LFLivePhoto(imageURL: imageOutputURL!, videoURL: videoOutputURL!)
                        livePhoto.saveToLibrary({ (errorType) -> Void in
                            switch(errorType) {
                            case .NoError:
                                NSLog("OK")
                                break
                            default:
                                NSLog("something wrong when save")
                                break
                            }
                        })
                    })
                }
        })
    }
}
