//
//  CGGeometry+Utils.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/25/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import Foundation
import UIKit

public var CG_M_PI : CGFloat {
    get {
        return CGFloat(M_PI)
    }
}

public var CG_M_PI_2 : CGFloat {
    get {
        return CGFloat(M_PI_2)
    }
}

extension CGSize {
    public var min : CGFloat {
        return self.width > self.height ? self.height : self.width
    }
    
    public var max : CGFloat {
        return self.width > self.height ? self.width : self.height
    }
}

extension CGRect {
    public var center : CGPoint {
        get {
            return CGPointMake(midX, midY)
        }
    }
    
    public var minSide : CGFloat {
        get {
            return self.size.min
        }
    }
    
    public var maxSide : CGFloat {
        get {
            return self.size.max
        }
    }
}
