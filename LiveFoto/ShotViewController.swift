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

class ShotViewController: UIViewController, LFCameraDelegate {
    
    @IBOutlet weak var previewView : GLKView!
    @IBOutlet weak var heightConst : NSLayoutConstraint!
    
    var camera : LFCamera?
    var transformFilter : CIFilter?
    var cropFilter : CIFilter?
    var index : Double! = 0
    var crop : Bool! = false
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        previewView.context = LFEAGLContext.shareContext.glContext!
        previewView.enableSetNeedsDisplay = false
        
        camera = LFCamera(presentName: AVCaptureSessionPresetHigh)
        camera?.delegate = self
        camera?.initSession()
        
        transformFilter = CIFilter(name: "CIAffineTransform")
//        transformFilter = CIFilter(name: "CIPerspectiveTransform")
        cropFilter = CIFilter(name: "CICrop")
    }
    
    override func viewWillAppear(animated: Bool) {
        camera?.start()
    }

    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // Dispose of any resources that can be recreated.
    }
    

    // MARK: LFCameraDelegate
    func capture(image: CIImage, time: CMTime) {
        
        
        
        transformFilter?.setValue(image, forKey: kCIInputImageKey)
        var transform = CGAffineTransformTranslate(CGAffineTransformIdentity, -960, -540)
        transform = CGAffineTransformRotate(transform, CGFloat(M_PI_2 * 3))// / 1000.0 * self.index))
//        transform = CGAffineTransformTranslate(transform, 960, 540)
        
        transformFilter?.setValue(NSValue(CGAffineTransform : transform), forKey: kCIInputTransformKey)
//        transformFilter?.setValue(CIVector(x: CGFloat(previewView.drawableHeight), y: CGFloat(previewView.drawableWidth)), forKey: "inputTopLeft")
//        transformFilter?.setValue(CIVector(x: 0, y: 0), forKey: "inputBottomRight")
//        transformFilter?.setValue(CIVector(x: 0, y: CGFloat(previewView.drawableWidth)), forKey: "inputTopRight")
//        transformFilter?.setValue(CIVector(x: CGFloat(previewView.drawableHeight), y: 0), forKey: "inputBottomLeft")
        
        let ciimage : CIImage! = transformFilter?.outputImage!
        var extent : CGRect! = ciimage?.extent
//        extent.origin = CGPointZero
        
        cropFilter?.setValue(ciimage, forKey: kCIInputImageKey)
        extent.size = CGSizeMake(1080, 1080)
        extent.origin = CGPointMake(extent.origin.x  , extent.origin.y + (1920 - 1080) / 2.0)
        cropFilter?.setValue(CIVector(CGRect: extent), forKey: "inputRectangle")
        
        let cropedImage = cropFilter?.outputImage
        let cropedExtent = cropedImage?.extent as CGRect!
        
        previewView.bindDrawable()
        EAGLContext.setCurrentContext(LFEAGLContext.shareContext.glContext)
        let width = CGFloat(previewView.drawableWidth)
        let height = CGFloat(previewView.drawableHeight)
        let bounds = CGRectMake(0, 0, width, height)
        
        if crop == true {
            camera?.ciContext?.drawImage(cropedImage!, inRect:bounds, fromRect: cropedExtent)
        } else {
            camera?.ciContext?.drawImage(ciimage!, inRect:bounds, fromRect: ciimage.extent)
        }
        previewView.display()
        self.index = self.index + 1
    }
    
    @IBAction func toggle(sender : UIButton!) {
        sender.selected = !sender.selected
        crop = sender.selected
        
        if crop == true {
            heightConst.constant = self.view.bounds.size.width
        } else {
            heightConst.constant = self.view.bounds.size.height
        }
        
        self.view.setNeedsUpdateConstraints()
        self.view.layoutIfNeeded()
    }
    
    @IBAction func snap(sender : UIButton!) {
        camera?.snapStill({ (result : Bool) -> Void in
            
        })
    }
    /*
    // MARK: - Navigation

    // In a storyboard-based application, you will often want to do a little preparation before navigation
    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        // Get the new view controller using segue.destinationViewController.
        // Pass the selected object to the new view controller.
    }
    */

}
