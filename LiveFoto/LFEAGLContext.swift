//
//  LFEAGLContext.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/19/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import UIKit
import OpenGLES

class LFEAGLContext: NSObject {
    static let shareContext = LFEAGLContext()
    var glContext : EAGLContext? {
        get {
            return _eaglContext
        }
    }
    
    private var _eaglContext : EAGLContext?
    private override init() {
        _eaglContext = EAGLContext(API: .OpenGLES2)
    }
    
}
