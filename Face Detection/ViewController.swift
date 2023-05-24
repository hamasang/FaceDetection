import AVFoundation
import UIKit
import Vision

class ViewController: UIViewController {
    
    private let captureSession = AVCaptureSession()
    private lazy var previewLayer = AVCaptureVideoPreviewLayer(session: self.captureSession)
    private let videoDataOutput = AVCaptureVideoDataOutput()
    private var faceLayers: [CAShapeLayer] = []
    private var currentRollAngle: CGFloat = 0
    private var selectedImage: UIImage?
    
    override func viewDidLoad() {
        super.viewDidLoad()
        selectedImage = UIImage(named:"pngegg.png")
        setupCamera()
        captureSession.startRunning()
    }
    
    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        self.previewLayer.frame = self.view.frame
    }
    
    private func setupCamera() {
        let deviceDiscoverySession = AVCaptureDevice.DiscoverySession(deviceTypes: [.builtInWideAngleCamera], mediaType: .video, position: .front)
        if let device = deviceDiscoverySession.devices.first {
            if let deviceInput = try? AVCaptureDeviceInput(device: device) {
                if captureSession.canAddInput(deviceInput) {
                    captureSession.addInput(deviceInput)
                    
                    setupPreview()
                }
            }
        }
    }
    
    private func setupPreview() {
        // UIView 식별자로 프리뷰 레이어를 가져옴
        guard let previewView = self.view.viewWithTag(100) else {
            return
        }
        
        // AVCaptureVideoPreviewLayer에 프리뷰 레이어 설정
        self.previewLayer.videoGravity = .resizeAspectFill
        previewView.layer.addSublayer(self.previewLayer)
        self.previewLayer.frame = previewView.frame
        
        self.videoDataOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value: kCVPixelFormatType_32BGRA)] as [String : Any]

        self.videoDataOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "camera queue"))
        self.captureSession.addOutput(self.videoDataOutput)
        
        let videoConnection = self.videoDataOutput.connection(with: .video)
        videoConnection?.videoOrientation = .portrait
    }
    
    
    // 버튼 액션
    @IBAction func btn_1(_ sender: UIButton) {
        NSLog("Btn_1 Touch!")
        selectedImage = UIImage(named: "iron_guy.png")
    }
    @IBAction func btn_2(_ sender: UIButton) {
        NSLog("Btn_2 Touch!")
        guard let currentInput = captureSession.inputs.first as? AVCaptureDeviceInput else { return }
            
        let newCameraPosition: AVCaptureDevice.Position
        let newCameraDevice: AVCaptureDevice?
        let newCameraInput: AVCaptureDeviceInput?
        
        switch currentInput.device.position {
        case .back:
            newCameraPosition = .front
            newCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newCameraPosition)
        case .front:
            newCameraPosition = .back
            newCameraDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: newCameraPosition)
        default:
            return
        }
        
        guard let newDevice = newCameraDevice else { return }
        
        do {
            newCameraInput = try AVCaptureDeviceInput(device: newDevice)
        } catch {
            return
        }
        
        // Remove current input and add new input
        captureSession.beginConfiguration()
        captureSession.removeInput(currentInput)
        if let newInput = newCameraInput, captureSession.canAddInput(newInput) {
            captureSession.addInput(newInput)
        } else {
            captureSession.addInput(currentInput)
        }
        captureSession.commitConfiguration()
        
        // Update button text
        let buttonTitle = "♻︎"
        let font = UIFont(name: "Helvetica", size: 25)!
        let attributes = [NSAttributedString.Key.font: font]
        let attributedTitle = NSAttributedString(string: buttonTitle, attributes: attributes)

        sender.setAttributedTitle(attributedTitle, for: .normal)
        sender.layer.cornerRadius = 50
        
        // Reset video orientation to current device orientation
        let connection = videoDataOutput.connection(with: .video)
        connection?.videoOrientation = UIDevice.current.orientation.videoOrientation
    }


}

extension ViewController: AVCaptureVideoDataOutputSampleBufferDelegate {
    private var rollAngle: CGFloat {
        get {
            return currentRollAngle
        }
        set {
            let angleDiff = newValue - currentRollAngle
            currentRollAngle = newValue
            
            for faceLayer in faceLayers {
                let transform = CATransform3DRotate(faceLayer.transform, angleDiff, 0, 0, 1)
                faceLayer.transform = transform
            }
        }
    }
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        guard let imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
          return
        }

        let faceDetectionRequest = VNDetectFaceLandmarksRequest(completionHandler: { (request: VNRequest, error: Error?) in
            DispatchQueue.main.async {
                self.faceLayers.forEach({ drawing in drawing.removeFromSuperlayer() })

                if let observations = request.results as? [VNFaceObservation], !observations.isEmpty {
                    self.handleFaceDetectionObservations(observations: observations)
                }
            }
        })

        let imageRequestHandler = VNImageRequestHandler(cvPixelBuffer: imageBuffer, orientation: .leftMirrored, options: [:])

        do {
            try imageRequestHandler.perform([faceDetectionRequest])
        } catch {
          print(error.localizedDescription)
        }
    }
    
    private func handleFaceDetectionObservations(observations: [VNFaceObservation]) {
        for observation in observations {
            let faceRectConverted = self.previewLayer.layerRectConverted(fromMetadataOutputRect: observation.boundingBox)
            let faceRectanglePath = CGPath(rect: faceRectConverted, transform: nil)
            
            let faceLayer = CAShapeLayer()
            
            self.faceLayers.append(faceLayer)
            self.view.layer.addSublayer(faceLayer)
            
            if let rollAngle = observation.roll {
                // Calculate the angle difference from the previous frame
                let angleDiff = CGFloat(rollAngle) - self.currentRollAngle
                self.currentRollAngle = CGFloat(rollAngle)
                
                // Apply the angle difference to the faceLayer
                let transform = CATransform3DRotate(faceLayer.transform, -angleDiff, 0, 0, 1)
                faceLayer.transform = transform
            }
            
            // FACE LANDMARKS
            if let landmarks = observation.landmarks {
                if let nose = landmarks.nose {
                    self.handleLandmark(nose, faceBoundingBox: faceRectConverted, rollAngle: self.currentRollAngle)
                }
            }
        }
    }


    private func handleLandmark(_ nose: VNFaceLandmarkRegion2D, faceBoundingBox: CGRect, rollAngle: CGFloat) {
        let landmarkPath = CGMutablePath()
        let landmarkPathPoints = nose.normalizedPoints
            .map({ nosePoint in
                CGPoint(
                    x: nosePoint.y * faceBoundingBox.height + faceBoundingBox.origin.x,
                    y: nosePoint.x * faceBoundingBox.width + faceBoundingBox.origin.y)
            })
        landmarkPath.addLines(between: landmarkPathPoints)
        landmarkPath.closeSubpath()
        let landmarkLayer = CAShapeLayer()

        self.faceLayers.append(landmarkLayer)
        self.view.layer.addSublayer(landmarkLayer)
        
        // Add image to landmark layer
        if let image = selectedImage?.rotate(radians: .pi / 2) {
            let imageLayer = CALayer()
            imageLayer.frame = faceBoundingBox
            imageLayer.contents = image.cgImage
            imageLayer.contentsGravity = .resizeAspect
            landmarkLayer.addSublayer(imageLayer)
            
            CATransaction.begin()
            CATransaction.setAnimationDuration(0.1) // Set the animation duration to 200ms (adjust as desired)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .linear)) // Use a linear animation timing function
            imageLayer.transform = CATransform3DMakeRotation(-rollAngle, 0, 0, 1) // Apply the roll angle with the animation
            CATransaction.commit()
        }
    }

}
extension UIImage {
    func rotate(radians: CGFloat) -> UIImage? {
        let rotatedSize = CGRect(origin: .zero, size: size)
            .applying(CGAffineTransform(rotationAngle: CGFloat(radians)))
            .integral.size
        UIGraphicsBeginImageContext(rotatedSize)
        if let context = UIGraphicsGetCurrentContext() {
            let origin = CGPoint(x: rotatedSize.width / 2.0, y: rotatedSize.height / 2.0)
            context.translateBy(x: origin.x, y: origin.y)
            context.rotate(by: radians)
            draw(in: CGRect(x: -origin.y, y: -origin.x, width: size.width, height: size.height))
            let rotatedImage = UIGraphicsGetImageFromCurrentImageContext()
            UIGraphicsEndImageContext()
            return rotatedImage
        }
        return nil
    }
}
extension UIDeviceOrientation {
    var videoOrientation: AVCaptureVideoOrientation {
        switch self {
        case .portrait:
            return .portrait
        case .portraitUpsideDown:
            return .portraitUpsideDown
        case .landscapeLeft:
            return .landscapeRight
        case .landscapeRight:
            return .landscapeLeft
        default:
            return .portrait
        }
    }
}
