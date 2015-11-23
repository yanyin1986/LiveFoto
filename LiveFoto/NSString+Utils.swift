//
//  NSString+Utils.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/20/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import Foundation
import CoreMedia

public func NSStringFromCMTime(time : CMTime) -> String {
    return _stringFromCFString(CMTimeCopyDescription(kCFAllocatorDefault, time))
}

public func NSStringFromCMTimeRange(range : CMTimeRange) -> String {
    return _stringFromCFString(CMTimeRangeCopyDescription(kCFAllocatorDefault, range))
}

public func NSStringFromCMTimeMapping(mapping : CMTimeMapping) -> String {
    return _stringFromCFString(CMTimeMappingCopyDescription(kCFAllocatorDefault, mapping))
}

private func _stringFromCFString(str : CFString?) -> String {
    if str != nil {
        return str as String!
    } else {
        return ""
    }
}
