import UIKit
import ARKit
import Firebase

class ARViewController: UIViewController, ARSCNViewDelegate{
    
    /*------------------------------------------*/
    /*                Properties                */
    /*------------------------------------------*/
    
    //for text searching
    var searchString: String = "게임"
    
    //Cloud Vision
    //let textRecognizer = MLKit.TextRecognizer()
    lazy var functions = Functions.functions()
    
    // AR Scene
    @IBOutlet var sceneView: ARSCNView!
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    /*------------------------------------------*/
    
    //After loaded
    //setting NotificationCenter here.
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Set up ARview
        sceneView.delegate = self
        
        //sceneView.showStatistics = true
        let scene = SCNScene()
        sceneView.scene = scene
        
        //Only for test. When releasing, comment or delete this line
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        //sceneView.autoenablesDefaultLighting = true // visually better
        
        // Authentication ( Reauired for using Cloud Vision Text Recognition )
        
        /*Auth.auth().createUser(withEmail: "abcde@abcde.com", password: "1q2w3e4r" ) { authResult, error in
            if error != nil {
                debugPrint(error!.localizedDescription)
                debugPrint(error.debugDescription)
            }
        }*/
        Auth.auth().signIn(withEmail: "abcde@abcde.com", password: "1q2w3e4r") { [weak self] authResult, error in
            if error != nil {
                debugPrint(error!.localizedDescription)
                debugPrint(error.debugDescription)
            }
        }
        
        // Send request to the Cloud Vision periodically
        cloudOCR()
    }
    
    //ViewWillAppear
    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        // Configure AR Tracking
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = .horizontal
        
        // Run ARView's session
        sceneView.session.run(configuration)
    }
    
    //viewWIllDisappear
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        sceneView.session.pause()
    }
    
    override func didReceiveMemoryWarning() {
        super.didReceiveMemoryWarning()
        // The original developer commented to release any cached data here
    }
    
    /* Cloud OCR */
    /* Send Requests Cloud OCR and Draw Boxes as the results */
    func cloudOCR() {
        Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { timer in
            
            let data = self.sceneView.snapshot().jpegData(compressionQuality: 1.0)
            
            struct requestData: Encodable {
                let image: [String: Data]
                let features = [["type":"TEXT_DETECTION"]]
                let imageContext = ["languageHints": ["en","kr"]]
                init(imageData:Data) {
                    image = ["content": imageData]
                }
            }
            
            let encoder = JSONEncoder()
            let encodedData = try! encoder.encode(requestData(imageData:data!))
            let string = String(data: encodedData, encoding: .utf8)!
            
            //Send a request to the Cloud Vision API
            self.functions.httpsCallable("annotateImage").call(string) { (result, error) in
                //ERROR
                if let error = error as NSError? {
                    if error.domain == FunctionsErrorDomain {
                        let code = FunctionsErrorCode(rawValue: error.code)
                        let message = error.localizedDescription
                        let details = error.userInfo[FunctionsErrorDetailsKey]
                        debugPrint(code!, message, details ?? "")
                    }
                }
                //SUCCESS
                print("RESULT \(result?.data)")
            }
            
        }//End of Timer
    }
    
    /*------------------------------------------*/
    /*               Visualization              */
    /*------------------------------------------*/
    
    // Not sure what this is for. Assumes this function is called by ARSession at every frame.
    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        /*DispatchQueue.main.async {
            // ??
        }*/
    }
    
    // Full screen
    override var prefersStatusBarHidden: Bool {
        return true
    }
    
    //Create a Bubble Node
    func createNewBubbleParentNode(_ text : String) -> SCNNode {
        // The original developer advises to use less polygons, letters, smoothness, etc.
        
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = SCNBillboardAxis.Y
        
        // BUBBLE TEXT
        let bubble = SCNText(string: text, extrusionDepth: CGFloat(bubbleDepth))
        let font = UIFont(name: "Futura", size:0.15)
        bubble.font = font
        bubble.firstMaterial?.diffuse.contents = UIColor.orange
        bubble.firstMaterial?.specular.contents = UIColor.white
        bubble.firstMaterial?.isDoubleSided = true
        // bubble.flatness // setting this too low can cause crashes.
        bubble.chamferRadius = CGFloat(bubbleDepth)
        
        // BUBBLE NODE
        let (minBound, maxBound) = bubble.boundingBox
        let bubbleNode = SCNNode(geometry: bubble)
        // Centre Node - to Centre-Botoom point
        bubbleNode.pivot = SCNMatrix4MakeTranslation( (maxBound.x - minBound.x)/2, minBound.y, bubbleDepth/2)
        // Reduce default text size
        bubbleNode.scale = SCNVector3Make(0.2, 0.2, 0.2)
        
        // CENTRE POINT NODE
        let sphere = SCNSphere(radius:  0.005)
        sphere.firstMaterial?.diffuse.contents = UIColor.cyan
        let sphereNode = SCNNode(geometry: sphere)
        
        // BUBBLE PARENT NODE
        let bubbleNodeParent = SCNNode()
        bubbleNodeParent.addChildNode(bubbleNode)
        bubbleNodeParent.addChildNode(sphereNode)
        bubbleNodeParent.constraints = [billboardConstraint]
        
        return bubbleNodeParent
    }
}
