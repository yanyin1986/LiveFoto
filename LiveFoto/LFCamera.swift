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
    private var _recordStart : Bool = false
    private var _previousFrameTime : CMTime = kCMTimeInvalid
    private var _minFrameDuration : CMTime = kCMTimeInvalid
    private var _recordDuration : CMTime = kCMTimeIndefinite
    private var _videoRecordCallBack : ((Bool) -> Void)?
    
    private var _assetWriter : AVAssetWriter?
    private var _assetWriterVideoInput : AVAssetWriterInput?
    private var _pixelAdapter : AVAssetWriterInputPixelBufferAdaptor?
    private var _assetWriterMetadataInput : AVAssetWriterInput?
    private var _metadataAdapter : AVAssetWriterInputMetadataAdaptor?
    
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
            let uuid = NSUUID().UUIDString
            
            // for video
            let videoURL = self.videoURL(uuid: uuid)
            let assetWriter = self.assetWriter(videoURL: videoURL)
            if assetWriter == nil {
                block(false)
                return
            }
            assetWriter?.metadata = [self.metadataItem(self._uuid!)]
            
            let (assetWriterVideoInput, pixelAdapter) = self.assetWriterVideo(CGSizeMake(1980, 1080))
            let (assetWriterMetadataInput, metadataAdapter) = self.assetWriterMetadata()
            
            assetWriter?.addInput(assetWriterVideoInput)
            assetWriter?.addInput(assetWriterMetadataInput)
            
            self._assetWriter = assetWriter
            self._assetWriterVideoInput = assetWriterVideoInput
            self._assetWriterMetadataInput = assetWriterMetadataInput
            self._pixelAdapter = pixelAdapter
            self._metadataAdapter = metadataAdapter
            
            self._minFrameDuration = CMTimeMake(39, 600)
            self._recordDuration = CMTimeMakeWithSeconds(3.0, 600)
            self._recordStart = true
            
            // for image
            let imageURL = self.imageURL(uuid: uuid)
        })
    }
    
    
    private func assetWriterMetadata() -> (AVAssetWriterInput, AVAssetWriterInputMetadataAdaptor) {
        let spec = [
            kCMMetadataFormatDescriptionMetadataSpecificationKey_Identifier as String : "mdta/com.apple.quicktime.still-image-time",
            kCMMetadataFormatDescriptionMetadataSpecificationKey_DataType as String : "com.apple.metadata.datatype.int8"
        ]
        var desc : CMMetadataFormatDescription?
        CMMetadataFormatDescriptionCreateWithMetadataSpecifications(kCFAllocatorDefault, kCMMetadataFormatType_Boxed, [spec], &desc)
        let assetWriterMetadataInput = AVAssetWriterInput(mediaType: AVMediaTypeMetadata, outputSettings: nil, sourceFormatHint: desc)
        let metadataAdapter = AVAssetWriterInputMetadataAdaptor(assetWriterInput: assetWriterMetadataInput)
        return (assetWriterMetadataInput, metadataAdapter)
    }
    
    private func assetWriterVideo(videoSize : CGSize) -> (AVAssetWriterInput, AVAssetWriterInputPixelBufferAdaptor) {
        let outputSettings = [
            AVVideoCodecKey : AVVideoCodecH264,
            AVVideoWidthKey : NSNumber(double: Double(videoSize.width)),
            AVVideoHeightKey : NSNumber(double: Double(videoSize.height))
        ]
        let assetWriterVideoInput = AVAssetWriterInput(mediaType: AVMediaTypeVideo, outputSettings: outputSettings)
        let pixelAdapter = self.assetWriterVideoInputPixelBufferAdapter(videoSize, videoInput: assetWriterVideoInput)
        return (assetWriterVideoInput, pixelAdapter)
    }
    
    private func assetWriterVideoInputPixelBufferAdapter(videoSize : CGSize, videoInput : AVAssetWriterInput) -> AVAssetWriterInputPixelBufferAdaptor {
        let sourcePixelBufferAttributes = [
            kCVPixelBufferPixelFormatTypeKey as String : NSNumber(unsignedInt: kCVPixelFormatType_32BGRA),
            kCVPixelBufferWidthKey as String : NSNumber(double: Double(videoSize.width)),
            kCVPixelBufferHeightKey as String : NSNumber(double: Double(videoSize.height)),
            kCVPixelBufferOpenGLESCompatibilityKey as String : NSNumber(bool: true)
        ]
        let pixelAdapter = AVAssetWriterInputPixelBufferAdaptor(assetWriterInput: videoInput, sourcePixelBufferAttributes: sourcePixelBufferAttributes)
        return pixelAdapter
    }
    
    private func outputFileURL(uuid uuid : String, fileExtend : String) -> NSURL {
        let outputFilePath = NSTemporaryDirectory() + uuid + "." + fileExtend
        NSFileManager.defaultManager().removeItemAtPathIfExists(outputFilePath)
        return NSURL(fileURLWithPath: outputFilePath, isDirectory: false)
    }
    
    private func videoURL(uuid uuid : String) -> NSURL {
        return self.outputFileURL(uuid: uuid, fileExtend: "mov")
    }
    
    private func imageURL(uuid uuid : String) -> NSURL {
        return self.outputFileURL(uuid: uuid, fileExtend: "jpg")
    }
    
    private func assetWriter(videoURL videoURL : NSURL) -> AVAssetWriter? {
        let assetWriter : AVAssetWriter?
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
//        let w = CVPixelBufferGetWidth(cvpixelBuffer)
//        let h = CVPixelBufferGetHeight(cvpixelBuffer)
        
        if cvpixelBuffer != nil {
            if _recordStart {
                precondition(_assetWriter != nil && _assetWriterVideoInput != nil
                    && _pixelAdapter != nil , "asset input nil")
                if !_assetWriter!.startWriting() {
                   NSLog("error : %@", _assetWriter!.error!)
                }
                if CMTIME_IS_INVALID(_startTime) {
                    // first frame
                    _startTime = presentationTime
                    _assetWriter!.startSessionAtSourceTime(_startTime)
                    _metadataAdapter!.appendTimedMetadataGroup(self.avtimedMetadata(_startTime))
                    
                    if _assetWriterVideoInput!.readyForMoreMediaData {
                        _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: _startTime)
                        _previousTime = _startTime
                    }
                } else {
                    if CMTIME_IS_INVALID(_minFrameDuration) {
                        //
                        _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: presentationTime)
                    } else {
                        let frameDuration = CMTimeSubtract(presentationTime, _previousTime)
                        if frameDuration >= _minFrameDuration {
                            _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: presentationTime)
                            _previousTime = presentationTime
                        } else {
//                            NSStringFromCGAffineTransform(<#T##transform: CGAffineTransform##CGAffineTransform#>)
//                            NSLog("drop frame ", <#T##args: CVarArgType...##CVarArgType#>)
                        }
                    }
                    // stop ?
                    if CMTIME_IS_VALID(_recordDuration) {
                        let duration = CMTimeSubtract(presentationTime, _startTime)
                        if duration >= _recordDuration {
                            //
                            // TODO:
                        }
                    }
                    
                }
                
            }
            
            
            
            
            let ciimage = CIImage(CVImageBuffer: cvpixelBuffer!)
            
            if delegate != nil {
                delegate!.capture(ciimage, time: presentationTime)
            }
        }
    }
    
    private func avtimedMetadata(startTime : CMTime) -> AVTimedMetadataGroup {
        let metadataGroupItem = AVMutableMetadataItem()
        metadataGroupItem.key = "com.apple.quicktime.still-image-time"
        metadataGroupItem.keySpace = "mdta"
        metadataGroupItem.value = NSNumber(int: 0)
        metadataGroupItem.dataType = "com.apple.metadata.datatype.int8"
        
        let group = AVTimedMetadataGroup(items: [metadataGroupItem], timeRange: CMTimeRangeMake(startTime, CMTimeMake(200, 3000)))
        return group
    }
    
    /// drop frame
    func captureOutput(captureOutput: AVCaptureOutput!, didDropSampleBuffer sampleBuffer: CMSampleBuffer!, fromConnection connection: AVCaptureConnection!) {
        
    }
    
    
}
