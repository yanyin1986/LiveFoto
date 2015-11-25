//
//  ProgressButton.swift
//  LiveFoto
//
//  Created by Leon.yan on 11/25/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import UIKit

@IBDesignable
class ProgressButton: UIButton {
    @IBInspectable var outerWidth : CGFloat = 1
    @IBInspectable var progressWidth : CGFloat = 2
    @IBInspectable var progressColor : UIColor = UIColor.redColor()
    
    private var progressValue : Float = 0
    @IBInspectable var progress : Float {
        get {
            return progressValue
        }
        set (newValue) {
            NSLog("%g", newValue)
            progressValue = newValue
            self.setNeedsDisplay()
        }
    }
    
    override func drawRect(rect: CGRect) {
        if self.selected {
            guard let context = UIGraphicsGetCurrentContext() else { return }
            let center = rect.center
            let radius = (rect.minSide - self.outerWidth) / 2.0
            
            CGContextSetFillColorWithColor(context, progressColor.CGColor)
            CGContextFillRect(context, rect)
        }
        super.drawRect(rect)
    }
    
}
