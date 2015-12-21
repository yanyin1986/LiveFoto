//
//  LFACVFile.swift
//  LiveFoto
//
//  Created by Leon.yan on 12/21/15.
//  Copyright © 2015 Tinycomic Inc. All rights reserved.
//

import Foundation
import UIKit

func int16ForBytes(bytes: UnsafePointer<Void>) -> UInt16 {
    var result = [UInt16](count: 1, repeatedValue: 0)
    memcpy(&result, bytes, 2)
    return result[0].bigEndian
}

class LFACVFile: NSObject {
    private var version : UInt16 = 0
    private var totalCurves : UInt16 = 0
    private var rgbCompositeCurvePoints : [CGPoint] = []
    private var redCurvePoints : [CGPoint] = []
    private var greenCurvePoints : [CGPoint] = []
    private var blueCurvePoints : [CGPoint] = []
    
    init(acvFilePath : String) {
        let path = NSBundle.mainBundle().pathForResource(acvFilePath, ofType: nil)
        assert(path != nil, "invalid acv file path")
        let data = NSData(contentsOfFile: path!)
        
        assert(data?.length > 0, "empty acv file")
        var rawBytes = data?.bytes
        version = int16ForBytes(rawBytes!)
        rawBytes = rawBytes?.advancedBy(2)
        totalCurves = int16ForBytes(rawBytes!)
        rawBytes = rawBytes?.advancedBy(2)
        
        var curves : [[CGPoint]] = []
        for _ in 0 ..< totalCurves {
            let pointCount = int16ForBytes(rawBytes!)
            rawBytes = rawBytes?.advancedBy(2)
            
            var points : [CGPoint] = []
            for _ in 0 ..< pointCount {
                let y = int16ForBytes(rawBytes!)
                rawBytes = rawBytes?.advancedBy(2)
                let x = int16ForBytes(rawBytes!)
                rawBytes = rawBytes?.advancedBy(2)
                
                let point = CGPointMake(CGFloat(x) / 255.0, CGFloat(y) / 255.0)
                points.append(point)
            }
            curves.append(points)
        }
        
        rgbCompositeCurvePoints = curves[0]
        redCurvePoints = curves[1]
        greenCurvePoints = curves[2]
        blueCurvePoints = curves[3]
    }
    
    private func secondDerivative(points : [CGPoint]) -> [Double] {
        if points.count <= 0 || points.count == 1 {
            return []
        }
        
        var matrix : [(Double, Double, Double)] = [(0, 1, 0)]
        var result : [Double] = [0]
        for i in 1 ..< points.count - 1 {
            let p1 = points[i - 1];
            let p2 = points[i];
            let p3 = points[i + 1];
            
            let m0 = Double((p2.x - p1.x) / 6.0)
            let m1 = Double((p3.x - p1.x) / 3.0)
            let m2 = Double((p3.x - p2.x) / 6.0)
            
            matrix[i] = (m0, m1, m2)
            result[i] = Double((p3.y - p2.y) / (p3.x - p2.x) - (p2.y - p1.y) / (p2.x - p1.x))
        }
        result.append(0) // count - 1
        matrix.append((0, 1, 0)) // count - 1
        
        // solving pass1 ( up -> down )
        for i in 1 ..< points.count {
            let (m10, m11, m12) = matrix[i]
            let (_, m01, m02) = matrix[i - 1]
            let k = m10 / m01
            matrix[i] = (0, m11 - k * m02, m12)
            result[i] = result[i] - k * result[i - 1]
        }
        
        // solving pass2 ( down -> up )
        for var i = points.count; i >= 0; i-- {
            let (m10, m11, m12) = matrix[i]
            let (m20, m21, _) = matrix[i + 1]
            let k = m12 / m21
            matrix[i] = (m10, m11 - k * m20, 0)
            result[i] = result[i] - k * result[i + 1]
        }
        
        var output : [Double] = []
        for i in 0 ..< points.count {
            let (_, m, _) = matrix[i]
            output.append(result[i] / m)
        }
        return output
    }
    
    private func splineCurve(curvePoints : [CGPoint]) -> [CGPoint] {
        let sda = self.secondDerivative(curvePoints)
        if sda.count < 1 {
            return []
        }
        
        var output : [CGPoint] = []
        for i in 0 ..< sda.count - 1 {
            let current = curvePoints[i]
            let next = curvePoints[i + 1]
            
            for x in Int(current.x) ..< Int(next.x) {
                let h : Double = Double(next.x - current.x)
                let t : Double = Double((Double(x) - Double(current.x)) / h)
                let a : Double = 1 - t
                let b : Double = t
                
                var y : Double = a * Double(current.y) + b * Double(next.y) + (h * h / 6.0) * ((a * a * a - a) * sda[i] + (b * b * b - b) * sda[i + 1])
                y = min(255.0, y)
                y = max(0.0, y)
                
                output.append(CGPointMake(CGFloat(x), CGFloat(y)))
            }
        }
        
        output.append(curvePoints[curvePoints.endIndex - 1])
        return output
    }
    
    private func getPreparedSplineCurve(curvePoints : [CGPoint]) -> [Double] {
        if curvePoints.count > 0 {
            let sortedPoints = curvePoints.sort({ (a : CGPoint, b : CGPoint) -> Bool in
                return a.x > b.x
            })
            let scaledPoints = sortedPoints.flatMap({ (p : CGPoint) -> CGPoint? in
                return CGPointMake(p.x * 255.0, p.y * 255.0)
            })
           
            var splinePoints = self.splineCurve(scaledPoints)
            let firstSplinePoint = splinePoints[0]
            if firstSplinePoint.x > 0 {
                for var i = Int(firstSplinePoint.x); i >= 0; i-- {
                    let point = CGPointMake(CGFloat(i), 0)
                    splinePoints.insert(point, atIndex: 0)
                }
            }
            
            let lastSplinePoint = splinePoints[splinePoints.endIndex - 1]
            if lastSplinePoint.x < 255 {
                for var i = Int(lastSplinePoint.x + 1); i <= 255; i++ {
                    let point = CGPointMake(CGFloat(i), 0)
                    splinePoints.append(point)
                }
            }
            
            let preparedplinePoints = splinePoints.flatMap({ (p : CGPoint) -> Double? in
                let originalPoint = CGPointMake(p.x, p.x)
                let xPow = pow(originalPoint.x - p.x, 2.0)
                let yPow = pow(originalPoint.y - p.y, 2.0)
                var distance = sqrt(xPow + yPow)
                if originalPoint.y > p.y {
                    distance = -distance
                }
                return Double(distance)
            })
            
            return preparedplinePoints
        } else {
            return []
        }
    }
    
    func generateLUT() -> NSData {
        let rgbCompositeCurve = self.getPreparedSplineCurve(rgbCompositeCurvePoints)
        let redCurve = self.getPreparedSplineCurve(redCurvePoints)
        let greenCurve = self.getPreparedSplineCurve(greenCurvePoints)
        let blueCurve = self.getPreparedSplineCurve(blueCurvePoints)
        
        assert(rgbCompositeCurve.count >= 256 && redCurve.count >= 256 && greenCurve.count >= 256 && blueCurve.count >= 256, "invalid curve")
        
        let indexs = [  0,   8,  16,  25,  33,  41,  49,  58,
                       66,  74,  82,  90,  99, 107, 115, 123,
                      132, 140, 148, 156, 165, 173, 181, 189,
                      197, 206, 214, 222, 230, 239, 247, 255]
        var colorCubeData : [Float] = []
        for i in 0 ..< 32 {
            // bgra for upload to texture
            let currentCurveIndex = indexs[i]
            let b = fmin(fmax(Double(currentCurveIndex) + blueCurve[currentCurveIndex], 0), 255)
            let g = fmin(fmax(Double(currentCurveIndex) + greenCurve[currentCurveIndex], 0), 255)
            let r = fmin(fmax(Double(currentCurveIndex) + redCurve[currentCurveIndex], 0), 255)
            colorCubeData.append(Float(b / 255.0))
            colorCubeData.append(Float(g / 255.0))
            colorCubeData.append(Float(r / 255.0))
            colorCubeData.append(1.0)
        }
        return NSData(bytes: colorCubeData, length: colorCubeData.count * sizeof(Float))
    }
}
