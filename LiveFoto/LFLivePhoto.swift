//
//  LFLivePhoto.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/25/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import Foundation
import Photos

enum LFLivePhotoError : ErrorType {
    case NoError
    case NoAuth
    case Dumplicate
    case Other
}

class LFLivePhoto: NSObject {
    
    private var imageURL : NSURL
    private var videoURL : NSURL
    private var saved : Bool = false
    
    init(imageURL : NSURL, videoURL : NSURL) {
        self.imageURL = imageURL
        self.videoURL = videoURL
    }
    
    func saveToLibrary(resultBlock : (errorType : LFLivePhotoError ) -> Void) {
        let auth = PHPhotoLibrary.authorizationStatus()
        let isSaved = self.saved
        let imageURL = self.imageURL
        let videoURL = self.videoURL
        
        let callback = ({ (status : PHAuthorizationStatus) -> Void in
            if status == .Denied {
                resultBlock(errorType: .NoAuth)
            } else if isSaved {
                resultBlock(errorType: .Dumplicate)
            } else {
                PHPhotoLibrary.sharedPhotoLibrary().performChanges({ () -> Void in
                    let request = PHAssetCreationRequest.creationRequestForAsset()
                    request.addResourceWithType(PHAssetResourceType(rawValue: 9)!, fileURL: videoURL, options: nil)
                    request.addResourceWithType(.Photo, fileURL: imageURL, options: nil)
                    }, completionHandler: { (result : Bool, error : NSError?) -> Void in
                        if result {
                            NSLog("save to camera roll as live phot")
                            resultBlock(errorType: .NoError)
                        } else {
                            if error != nil {
                                NSLog("something wrong when saving : %@", error!)
                            }
                            resultBlock(errorType: .Other)
                        }
                })
            }
        })
        
        if auth == .NotDetermined {
            PHPhotoLibrary.requestAuthorization({ (status) -> Void in
                callback(status)
            })
        } else {
            callback(auth)
        }
        
        
        
        
    }
}
