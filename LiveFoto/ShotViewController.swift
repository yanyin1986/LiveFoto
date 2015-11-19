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

class ShotViewController: UIViewController, LFCameraDelegate {
    
    @IBOutlet weak var previewView: GLKView!
    
    var camera : LFCamera?
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        // Do any additional setup after loading the view.
        previewView.context = LFEAGLContext.shareContext.glContext!
        
        camera = LFCamera(presentName: AVCaptureSessionPresetHigh)
        camera?.delegate = self
        camera?.initSession()
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
        previewView.bindDrawable()
        EAGLContext.setCurrentContext(LFEAGLContext.shareContext.glContext)
        let bounds = CGRectMake(0, 0, CGFloat(previewView.drawableWidth), CGFloat(previewView.drawableHeight))
        camera?.ciContext?.drawImage(image, inRect:bounds, fromRect: image.extent)
        previewView.display()
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
