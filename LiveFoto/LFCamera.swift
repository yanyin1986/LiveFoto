//
//  LFCamera.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/19/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import UIKit
import AVFoundation
import CoreImage
import Photos

protocol LFCameraDelegate {
    func capture(image : CIImage, time : CMTime)
}

final class LFCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    private var _sessionQueue : dispatch_queue_t?
    private var _captureQueue : dispatch_queue_t?
    private var _captureSession : AVCaptureSession?
    private var _presentName : String?
    private var _previewView : UIView?
    
    private var _previousTime : CMTime = kCMTimeInvalid
    private var _startTime : CMTime = kCMTimeInvalid
    // preview
    private var _videoDataOutput : AVCaptureVideoDataOutput?
    private var _stillImageOutput : AVCaptureStillImageOutput?
    
    // UUID
    private var _uuid : String?
    
    // video writer
    private var _assetWriter : AVAssetWriter?
    private var _assetWriterVideoInput : AVAssetWriterInput?
    
    var livePhoto : Bool = true
    // cicontext
    var ciContext : CIContext?
    //
    var delegate : LFCameraDelegate?
    
    
    var previewView : UIView? {
        get {
            return _previewView;
        }
        set (newValue) {
            _previewView = newValue
        }
    }
    
    // MARK: init
    init(presentName : String) {
        _captureSession = AVCaptureSession()
        _presentName = presentName
        _sessionQueue = dispatch_queue_create("livefoto.capture.session.queue", nil)
        ciContext = CIContext(EAGLContext: LFEAGLContext.shareContext.glContext!,
            options: [kCIContextWorkingColorSpace : NSNull()])
    }
    
    func start() {
        dispatch_async((self._sessionQueue)!, { () -> Void in
            self._captureSession?.startRunning()
        })
    }
    
    func pause() {
        dispatch_async((self._sessionQueue)!, { () -> Void in
            self._captureSession?.stopRunning()
        })
    }
    
    func initSession() {
        dispatch_async((self._sessionQueue)!, {()->Void in
            // begin config
            self._captureSession?.beginConfiguration()
            
            // camera
            let videoCaptureDevice = self.device(AVMediaTypeVideo, preferPosition: .Front)
            // input
            let videoCaptureDeviceInput : AVCaptureDeviceInput
            do {
                videoCaptureDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                if self._captureSession?.canAddInput(videoCaptureDeviceInput) == true {
                    self._captureSession?.addInput(videoCaptureDeviceInput)
                }
            } catch (_) {
                
            }
            
            // video output
            let captureVideoDataOutput = AVCaptureVideoDataOutput()
            if self._captureQueue == nil {
                self._captureQueue = dispatch_queue_create("livefoto.capture.queue", nil)
            }
            captureVideoDataOutput.setSampleBufferDelegate(self, queue: self._captureQueue)
            if self._captureSession?.canAddOutput(captureVideoDataOutput) == true {
                self._captureSession?.addOutput(captureVideoDataOutput)
            }
            
            // still output
            let stillImageOutput = AVCaptureStillImageOutput()
            if self._captureSession?.canAddOutput(stillImageOutput) == true {
                self._captureSession?.addOutput(stillImageOutput)
                self._stillImageOutput = stillImageOutput
            }
            
            self._captureSession?.commitConfiguration()
        })
    }
    
    // get capture device with mediatype and preferPosition
    func device(mediaType : String, preferPosition : AVCaptureDevicePosition) -> AVCaptureDevice? {
        let devices = AVCaptureDevice.devicesWithMediaType(mediaType)
        precondition(devices.count > 0)
        var videoCaptureDevice = devices.first as! AVCaptureDevice
        if videoCaptureDevice.position != preferPosition {
            for device in devices {
                if device.position == preferPosition {
                    videoCaptureDevice = device as! AVCaptureDevice
                    break
                }
            }
        }
        return videoCaptureDevice
    }
    
    // capture a live photo
    func snapLivePhoto(block : (Bool) -> Void) {
        dispatch_async((self._sessionQueue)!, { () -> Void in
            // uuid
            self._uuid = NSUUID().UUIDString
            
            // for video
            let videoPath = (NSTemporaryDirectory() as NSString!).stringByAppendingPathComponent(self._uuid! + "mov")
            NSFileManager.defaultManager().removeItemAtPathIfExists(videoPath)
            let videoURL = NSURL(fileURLWithPath: videoPath)
            // assetWriter
            let assetWriter : AVAssetWriter?
            do {
                assetWriter = try AVAssetWriter(URL: videoURL, fileType: AVFileTypeQuickTimeMovie)
            } catch (_) {
                assetWriter = nil
            }
            
            if assetWriter == nil {
                block(false)
                return
            }
            
            assetWriter?.metadata = [self.metadataItem(self._uuid!)]
            
        })
    }
    
    private func initWriter(videoURL : NSURL) -> AVAssetWriter {
        let assetWriter : AVAssetWriter!
        do {
            assetWriter = try AVAssetWriter(URL: videoURL, fileType: AVFileTypeQuickTimeMovie)
        } catch (_) {
            assetWriter = nil
        }
        
        return assetWriter;
    }
    
    private func metadataItem(uuid : String) -> AVMetadataItem {
        let metadataItem = AVMutableMetadataItem()
        metadataItem.key = "com.apple.quicktime.content.identifier"
        metadataItem.keySpace = "mdta"
        metadataItem.value = uuid
        metadataItem.dataType = "com.apple.metadata.datatype.UTF-8"
        
        return metadataItem
    }
    
    func snapStill(block : (Bool) -> Void) {
        let connection = self._stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo)
        self._stillImageOutput?.captureStillImageAsynchronouslyFromConnection(connection, completionHandler: { (sample : CMSampleBufferRef!, error : NSError!) -> Void in
            let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample)
            //
            let url = NSTemporaryDirectory() + "/out.jpg";
            if NSFileManager.defaultManager().fileExistsAtPath(url) == true {
                do {
                    try NSFileManager.defaultManager().removeItemAtPath(url)
                } catch (_) {}
            }
            
            data.writeToFile(url, atomically: true)
        })
    }
    
    // MARK: sample buffer delegate
    
    /// not drop frame
    func captureOutput(captureOutput: AVCaptureOutput!, didOutputSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        if CMTIME_IS_INVALID(_previousTime) == false {
            
        }
        _previousTime = presentationTime;
        
        let cvpixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) as CVPixelBuffer!
        let w = CVPixelBufferGetWidth(cvpixelBuffer)
        let h = CVPixelBufferGetHeight(cvpixelBuffer)
        
        print("%d x %d", w, h)
        if cvpixelBuffer != nil {
            let ciimage = CIImage(CVImageBuffer: cvpixelBuffer!)
            
            if delegate != nil {
                delegate!.capture(ciimage, time: presentationTime)
            }
        }
    }
    
    /// drop frame
    func captureOutput(captureOutput: AVCaptureOutput!, didDropSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
    }
    
    
}
