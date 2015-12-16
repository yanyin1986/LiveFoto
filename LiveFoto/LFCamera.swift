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
import ImageIO
import MobileCoreServices

protocol LFCameraDelegate {
    func capture(image : CIImage, time : CMTime)
}

typealias LivePhotoCaptureProgressBlock = (progress : Float) -> Void
typealias LivePhotoCaptureResultBlock = (result : Bool, imageOutputURL : NSURL?, videoOutputURL : NSURL?) -> Void

final class LFCamera: NSObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    
    private var _sessionQueue : dispatch_queue_t?
    private var _captureQueue : dispatch_queue_t?
    
    private var _captureSession : AVCaptureSession?
    private var _presentName : String?
    private var _previewView : UIView?
    private var _currentDevice : AVCaptureDevice?
    private var _currentInput : AVCaptureInput?
    
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
    private var _videoRecordCallBack : LivePhotoCaptureResultBlock?
    private var _videoRecordProgressBlock : LivePhotoCaptureProgressBlock?
    private var _videoOutputURL : NSURL?
    private var _imageOutputURL : NSURL?
    
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
            self._currentDevice = videoCaptureDevice
            
            // input
            let videoCaptureDeviceInput : AVCaptureDeviceInput
            do {
                videoCaptureDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                self._currentInput = videoCaptureDeviceInput
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
    
    func rotate() {
        dispatch_async(self._sessionQueue!, { () -> Void in
            if self._currentDevice == nil || self._currentInput == nil {
                return
            }
            
            let currentPosition = self._currentDevice?.position
            let rotatePosition : AVCaptureDevicePosition = (currentPosition == .Front) ? .Back : .Front
            
            let videoCaptureDevice = self.device(AVMediaTypeVideo, preferPosition: rotatePosition)
            self._currentDevice = videoCaptureDevice
            
            self._captureSession?.beginConfiguration()
            self._captureSession?.removeInput(self._currentInput)
            
            // input
            let videoCaptureDeviceInput : AVCaptureDeviceInput
            do {
                videoCaptureDeviceInput = try AVCaptureDeviceInput(device: videoCaptureDevice)
                self._currentInput = videoCaptureDeviceInput
                if self._captureSession?.canAddInput(videoCaptureDeviceInput) == true {
                    self._captureSession?.addInput(videoCaptureDeviceInput)
                }
            } catch (_) {
                
            }
            
            self._captureSession?.commitConfiguration()
        })
    }
    
    func snapStill(uuid : String, imageURL : NSURL, block : (Bool) -> Void) {
        let connection = self._stillImageOutput?.connectionWithMediaType(AVMediaTypeVideo)
        self._stillImageOutput?.captureStillImageAsynchronouslyFromConnection(connection, completionHandler: { (sample : CMSampleBufferRef!, error : NSError!) -> Void in
            let data = AVCaptureStillImageOutput.jpegStillImageNSDataRepresentation(sample)
            let imageSource = CGImageSourceCreateWithData(data as CFData, nil)
            let properties = CGImageSourceCopyProperties(imageSource!, nil)
            var destinationImageProperties = properties! as Dictionary
            destinationImageProperties[kCGImagePropertyMakerAppleDictionary] = [ "17" : uuid ]
            let imageDestination = CGImageDestinationCreateWithURL(imageURL, kUTTypeJPEG, 1, nil)
            CGImageDestinationAddImageFromSource(imageDestination!, imageSource!, 0, destinationImageProperties)
            CGImageDestinationFinalize(imageDestination!)
        })
    }
    
    // capture a live photo
    func snapLivePhoto(progressBlock : LivePhotoCaptureProgressBlock, resultBlock : LivePhotoCaptureResultBlock) {
        dispatch_async((self._sessionQueue)!, { () -> Void in
            if self._recordStart {
                resultBlock(result: false, imageOutputURL: nil, videoOutputURL: nil)
                return
            }
            // uuid
            let uuid = NSUUID().UUIDString
            
            // for video
            let videoURL = self.videoURL(uuid: uuid)
            let assetWriter = self.assetWriter(videoURL: videoURL)
            if assetWriter == nil {
                resultBlock(result: false, imageOutputURL: nil, videoOutputURL: nil)
                return
            }
            assetWriter?.metadata = [self.metadataItem(uuid)]
            
            let (assetWriterVideoInput, pixelAdapter) = self.assetWriterVideo(CGSizeMake(1920, 1080))
            let (assetWriterMetadataInput, metadataAdapter) = self.assetWriterMetadata()
            
            assetWriter?.addInput(assetWriterVideoInput)
            assetWriter?.addInput(assetWriterMetadataInput)
            
            self._assetWriter = assetWriter
            self._assetWriterVideoInput = assetWriterVideoInput
            self._assetWriterMetadataInput = assetWriterMetadataInput
            self._pixelAdapter = pixelAdapter
            self._metadataAdapter = metadataAdapter
            self._videoOutputURL = videoURL
            
            self._minFrameDuration = CMTimeMake(39, 600)
            self._recordDuration = CMTimeMakeWithSeconds(3.0, 600)
            
            self._videoRecordCallBack = resultBlock
            self._videoRecordProgressBlock = progressBlock
            self._uuid = uuid
            // for image
            let imageURL = self.imageURL(uuid: uuid)
            self._imageOutputURL = imageURL
            
            let after = dispatch_time(DISPATCH_TIME_NOW, Int64(UInt64(500) * NSEC_PER_MSEC))
            dispatch_after(after, self._sessionQueue!, { () -> Void in
                self.snapStill(uuid, imageURL : imageURL, block: { (result : Bool) -> Void in
                    NSLog("photo ok")
                })
            })
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
        assetWriterVideoInput.expectsMediaDataInRealTime = true
        assetWriterVideoInput.transform = CGAffineTransformMakeRotation(CGFloat(M_PI_2))
        
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
        guard let cvpixelBuffer : CVPixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) as CVPixelBuffer! else { return }
        
        if _assetWriter != nil && _assetWriterVideoInput != nil && _pixelAdapter != nil {
            let status = _assetWriter!.status
            
            // stop ?
            if CMTIME_IS_VALID(_recordDuration) && status == .Writing {
                let duration = CMTimeSubtract(presentationTime, _startTime)
                if self._videoRecordProgressBlock != nil {
                    let durationSec = CMTimeGetSeconds(duration)
                    let totalSec = CMTimeGetSeconds(_recordDuration)
                    let progress = durationSec / totalSec
                    self._videoRecordProgressBlock!(progress : Float(progress))
                }
                if duration > _recordDuration {
                    //
                    // TODO:
                    NSLog("duration")
                    _recordStart = false
                    self.stopRecording()
                    return
                }
            }
            
            if !_recordStart {
                _recordStart = true
                if !_assetWriter!.startWriting() {
                    NSLog("error : %@", _assetWriter!.error!)
                }
                
                // first frame
                _startTime = presentationTime
                _assetWriter!.startSessionAtSourceTime(_startTime)
                _metadataAdapter!.appendTimedMetadataGroup(self.avtimedMetadata(_startTime))
                
                if _assetWriterVideoInput!.readyForMoreMediaData {
                    _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: _startTime)
                    _previousTime = _startTime
                    NSLog("---%@---[writen]", NSStringFromCMTime(presentationTime))
                }
            }
            
            if CMTIME_IS_INVALID(_minFrameDuration) {
                //
                _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: presentationTime)
                _previousTime = presentationTime
            } else {
                let frameDuration = CMTimeSubtract(presentationTime, _previousTime)
                if frameDuration >= _minFrameDuration {
                    _pixelAdapter!.appendPixelBuffer(cvpixelBuffer, withPresentationTime: presentationTime)
                    _previousTime = presentationTime
                    NSLog("---%@---[writen]", NSStringFromCMTime(presentationTime))
                }
            }
        }
    
    
        var ciimage = CIImage(CVImageBuffer: cvpixelBuffer)
        
        if _currentDevice?.position == .Front {
            var transform = CGAffineTransformMakeScale(1.0, -1.0)
            transform = CGAffineTransformTranslate(transform, 0, ciimage.extent.size.height)
            //, 0)
            ciimage = ciimage.imageByApplyingTransform(transform)
        }
        
        if delegate != nil {
            delegate!.capture(ciimage, time: presentationTime)
        }
    }
    
    func stopRecording() {
        if _assetWriterVideoInput != nil && _assetWriter != nil && _uuid != nil {
            _assetWriterVideoInput!.markAsFinished()
            _assetWriterVideoInput = nil
            _pixelAdapter = nil
            if _assetWriterMetadataInput != nil {
                _assetWriterMetadataInput!.markAsFinished()
                _assetWriterMetadataInput = nil
                _metadataAdapter = nil
            }
            
            let assetWriter = _assetWriter
            let videoRecordCallback = _videoRecordCallBack
            let imageOutputURL = _imageOutputURL
            let videoOutputURL = _videoOutputURL
            
            _uuid = nil
            _assetWriter = nil
            _videoRecordCallBack = nil
            _startTime = kCMTimeInvalid
            assetWriter!.finishWritingWithCompletionHandler({ () -> Void in
                
                if videoRecordCallback != nil {
                    videoRecordCallback!(result: assetWriter!.status == .Completed, imageOutputURL: imageOutputURL, videoOutputURL: videoOutputURL)
                }
            })
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
