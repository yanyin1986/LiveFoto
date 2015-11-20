//
//  NSFileManager+Utils.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/19/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import Foundation

extension NSFileManager {
    func removeItemAtPathIfExists(filePath : String) {
        if self.fileExistsAtPath(filePath) == true {
            do {
                try self.removeItemAtPath(filePath)
            } catch (_) {
                
            }
        }
    }
    
    func removeItemAtURLIfExists(fileURL : NSURL) {
        if fileURL.isFileReferenceURL() == true {
            self.removeItemAtPathIfExists(fileURL.path!)
        }
    }
}
