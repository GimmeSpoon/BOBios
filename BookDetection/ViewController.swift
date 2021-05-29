import UIKit
import AVFoundation
import Photos
import MLKit

class ViewController: UIViewController, AVCaptureVideoDataOutputSampleBufferDelegate,
    UITextFieldDelegate{
    
    /*------------------------------------------*/
    /*                Properties                */
    /*------------------------------------------*/
    //Outlet to the main storyboard
    @IBOutlet weak var preview: UIView!
    @IBOutlet weak var searchBar: UITextField!
    @IBOutlet weak var titleBar: UILabel!
    
    //Camera caputre
    var captureSession: AVCaptureSession!
    var videoPreviewLayer: AVCaptureVideoPreviewLayer!
    private let videoOutput = AVCaptureVideoDataOutput()
    
    //for text search
    var searchString: String = "search"
    //MLKit TextRecognizer
    let textRecognizer = TextRecognizer.textRecognizer()
    
    //UI instances needed for drawing the boxes.
    var overlayView:UIView!
    let shapeLayer:CAShapeLayer = CAShapeLayer()
    
    //For scaling the coordinates of bouding boxes to the UI View
    var scaleX:CGFloat = 0.0
    var scaleY:CGFloat = 0.0
    var viewX:CGFloat = 0.0
    var viewY:CGFloat = 0.0
    
    /*------------------------------------------*/
    /*             Functions (Default)          */
    /*------------------------------------------*/
    
    //After loaded
    //setting NotificationCenter here.
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Search text field and keyboard
        searchBar.delegate = self
        NotificationCenter.default.addObserver(self, selector: #selector(kbShow), name: UIResponder.keyboardWillShowNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(kbHide), name: UIResponder.keyboardWillHideNotification, object: nil)
    }
    
    //After showing Views
    //setting AVCapture session and UI views here.
    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        
        captureSession = AVCaptureSession()
        captureSession.sessionPreset = .high
        
        //Add Overlay View
        overlayView = UIView.init(frame: self.preview.bounds)
        preview.superview?.addSubview(overlayView)
        preview.superview?.bringSubviewToFront(searchBar)
        
        //Configure Drawing Layer
        shapeLayer.lineWidth = 3
        shapeLayer.strokeColor = UIColor.red.cgColor
        shapeLayer.fillColor = UIColor.green.withAlphaComponent(0.3).cgColor
        
        overlayView.layer.addSublayer(shapeLayer)
        
        viewX = overlayView.frame.maxX
        viewY = overlayView.frame.maxY
        
        //Set AVCapture Device
        guard let backCamera = AVCaptureDevice.default(for: AVMediaType.video)
        else {
            print("Unable to access back camera!")
            return
        }
        
        //Add input to the capture session
        do {
            let input = try AVCaptureDeviceInput(device: backCamera)
            //set up the preview and output
            if captureSession.canAddInput(input){
                captureSession.addInput(input)
                setupLivePreview()
            }
            self.captureSession.startRunning()
            print("setup done")
        }
        catch let error {
            print("Error Unable to initialize back camera: \(error.localizedDescription)")
        }
    }
    
    /*------------------------------------------*/
    /*            Functions (Configure)         */
    /*------------------------------------------*/
    
    //Configure preview layer and add it as a sublayer to the UI
    func setupLivePreview() {
        videoPreviewLayer = AVCaptureVideoPreviewLayer(session: captureSession)
        videoPreviewLayer.videoGravity = .resizeAspect
        videoPreviewLayer.connection?.videoOrientation = .portrait
        preview.layer.addSublayer(self.videoPreviewLayer)
        
        //add output to the capture session
        self.addVideoOutput()
        self.videoPreviewLayer.frame = self.preview.bounds
    }
    
    //Stop capture session when collapsing the views
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        self.captureSession.stopRunning()
    }
    
    //Add and configure output to the capture session
    private func addVideoOutput() {
        self.videoOutput.videoSettings = [(kCVPixelBufferPixelFormatTypeKey as NSString) : NSNumber(value:kCVPixelFormatType_32BGRA)] as [String : Any]
        self.videoOutput.setSampleBufferDelegate(self, queue: DispatchQueue(label: "my.image.hadnling.queue"))
        self.videoOutput.alwaysDiscardsLateVideoFrames = true
        self.captureSession.addOutput(self.videoOutput)
    }
    
    /*------------------------------------------*/
    /*              Text Recognition            */
    /*------------------------------------------*/
    
    //After capturing preview, image processed here asynchronously
    func captureOutput(_ output: AVCaptureOutput, didOutput sampleBuffer: CMSampleBuffer, from connection: AVCaptureConnection) {
        
        //IMG Processing starts
        
        //Set up scale constants
        let imgbuf:CVImageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer)!
        scaleX = self.viewX / CGFloat(CVPixelBufferGetHeight(imgbuf))
        scaleY = self.viewY / CGFloat(CVPixelBufferGetWidth(imgbuf))
        //Get results from textRecognizer
        var blocks: [TextBlock]
        let image = VisionImage(buffer: sampleBuffer)
        image.orientation = imageOrientation(
            deviceOrientation: UIDeviceOrientation.portrait,
            cameraPosition: AVCaptureDevice.Position.back)
        
        do{
            blocks = try textRecognizer.results(in: image).blocks
        }
        catch{
            print("Frame Dropped")
            return
        }
        
        //Search for the text for every block and if exists, draw the bounding box
        for block in blocks {
            if( block.text.contains(searchString)){
                DispatchQueue.main.async {
                    self.drawBox(points: block.cornerPoints)
                    self.setTitle(text: block.text)
                }
            }
            else {
                DispatchQueue.main.async {
                    self.cleanUI()
                }
            }
        }
        
    }
    
    //MLKit example code. setting orientation for the textrecognizer
    func imageOrientation(
      deviceOrientation: UIDeviceOrientation,
      cameraPosition: AVCaptureDevice.Position
    ) -> UIImage.Orientation {
      switch deviceOrientation {
      case .portrait:
        return cameraPosition == .front ? .leftMirrored : .right
      case .landscapeLeft:
        return cameraPosition == .front ? .downMirrored : .up
      case .portraitUpsideDown:
        return cameraPosition == .front ? .rightMirrored : .left
      case .landscapeRight:
        return cameraPosition == .front ? .upMirrored : .down
      case .faceDown, .faceUp, .unknown:
        return .up
      }
    }
    
    /*------------------------------------------*/
    /*               Visulaization              */
    /*------------------------------------------*/
    
    //Draw bounding boxes.
    func drawBox(points:[NSValue]){
        
        shapeLayer.path = nil
        let path = UIBezierPath()
        
        path.move(to: CGPoint( x:translateX(x: CGFloat((points[0] as! CGPoint).y)),y:translateY(y: CGFloat((points[0] as! CGPoint).x))))
        path.addLine(to: CGPoint( x:translateX(x: CGFloat((points[1] as! CGPoint).y)),y:translateY(y: CGFloat((points[1] as! CGPoint).x))))
        path.addLine(to: CGPoint( x:translateX(x: CGFloat((points[2] as! CGPoint).y)),y:translateY(y: CGFloat((points[2] as! CGPoint).x))))
        path.addLine(to: CGPoint( x:translateX(x: CGFloat((points[3] as! CGPoint).y)),y:translateY(y: CGFloat((points[3] as! CGPoint).x))))
        path.addLine(to: CGPoint( x:translateX(x: CGFloat((points[0] as! CGPoint).y)),y:translateY(y: CGFloat((points[0] as! CGPoint).x))))
        
        //print("\(points[0]) , \(points[2])")
        
        self.shapeLayer.path = path.cgPath
        
    }
    
    //Change the text of the label
    func setTitle(text:String){
        self.titleBar.text = text
    }
    
    //Clean every box on the overlay view.
    func cleanUI (){
        shapeLayer.path = nil
    }
    
    //scale the coordinates
    private func translateX (x:CGFloat)-> CGFloat{ return x * self.scaleX }
    private func translateY (y:CGFloat)-> CGFloat{ return y * self.scaleY }
    
    //Keyboard actions
    @objc
    func kbShow (_ sender:Notification){
        self.view.frame.origin.y = -300
    }
    @objc
    func kbHide (_ sender:Notification){
        self.view.frame.origin.y = 0
    }
    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        searchString = searchBar.text ?? "search"
        self.view.endEditing(true)
    }
    func textFieldShouldReturn (_ textField:UITextField)->Bool{
        searchString = searchBar.text ?? "search"
        self.view.endEditing(true)
        return true
    }
}
