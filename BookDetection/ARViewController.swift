import UIKit
import ARKit
import Firebase

class ARViewController: UIViewController, ARSCNViewDelegate{
    
    /*------------------------------------------*/
    /*                Properties                */
    /*------------------------------------------*/
    
    //for text searching
    static var searchString: String = "총,균,쇠"
    var searchDone: Bool = false
    
    //Cloud Vision
    //let textRecognizer = MLKit.TextRecognizer()
    lazy var functions = Functions.functions()
    
    //Scale
    var imageWidth:CGFloat!
    var imageHeight:CGFloat!
    
    // AR Scene
    @IBOutlet var sceneView: ARSCNView!
    let scene = SCNScene()
    let bubbleDepth : Float = 0.01 // the 'depth' of 3D text
    var latestPrediction : String = "…" // a variable containing the latest CoreML prediction
    
    /*------------------------------------------*/
    
    //After loaded
    //setting NotificationCenter here.
    override func viewDidLoad() {
        super.viewDidLoad()
        
        //Set up ARview
        sceneView.delegate = self
        
        sceneView.showsStatistics = true
        sceneView.scene = scene
        
        //Only for test. When releasing, comment or delete this line
        sceneView.debugOptions = [ARSCNDebugOptions.showFeaturePoints, ARSCNDebugOptions.showWorldOrigin]
        sceneView.autoenablesDefaultLighting = true // visually better
        
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
        
        let wall = SCNPlane(width: 10, height: 10)
        let wallMt = SCNMaterial()
        wallMt.transparency = 0.0
        let wallNode = SCNNode(geometry: wall)
        wallNode.opacity = 0.0
        wallNode.position = SCNVector3(0.0, 0.0, -0.2)
        self.sceneView.scene.rootNode.addChildNode(wallNode)
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
        
        Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { timer in
            
            let capture = self.sceneView.snapshot()
            self.imageWidth = capture.size.width
            self.imageHeight = capture.size.height
            let data = capture.jpegData(compressionQuality: 1.0)
            
            
            struct requestData: Encodable {
                let image: [String: Data]
                let features = [["type":"TEXT_DETECTION"]]
                let imageContext = ["languageHints": ["en","ko"]]
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
                guard let res = (result?.data as? NSArray)?[0] else {return}
                let annotation = (res as? NSDictionary)?["fullTextAnnotation"] as? [String: Any]
                guard let pages = annotation?["pages"] as? [[String: Any]] else {return}
                for page in pages {
                    var pageText = ""
                    guard let blocks = page["blocks"] as? [[String: Any]] else { continue }
                    for block in blocks {
                        var blockText = ""
                        let boudingPoly = block["boundingBox"] as? [String: Any]
                        let vertices = boudingPoly?["vertices"] as? [[String: Any]]
                        guard let paragraphs = block["paragraphs"] as? [[String: Any]] else { continue }
                        for paragraph in paragraphs {
                            var paragraphText = ""
                            guard let words = paragraph["words"] as? [[String: Any]] else { continue }
                            for word in words {
                                var wordText = ""
                                guard let symbols = word["symbols"] as? [[String: Any]] else { continue }
                                for symbol in symbols {
                                    let symbolText = symbol["text"] as? String ?? ""
                                    wordText += symbolText
                                }
                                paragraphText += wordText
                            }
                            
                            blockText += paragraphText
                        }
                        self.search(blockText: blockText, vertices: [CGPoint(x:(vertices?[0]["x"] as? Int)!,y:(vertices?[0]["y"] as? Int)!),CGPoint(x:(vertices?[1]["x"] as? Int)!,y:(vertices?[1]["y"] as? Int)!),CGPoint(x:(vertices?[2]["x"] as? Int)!,y:(vertices?[2]["y"] as? Int)!)])
                        pageText += blockText
                    }
                }
                //for page in pages {
                    
                //}
                
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
    func DrawSphereNode(p1:CGPoint) {
        
        /*Get 3D Coordinates of the points from a bounding box*/
        guard let query = self.sceneView.raycastQuery(from: p1, allowing: .estimatedPlane, alignment: .horizontal) else { return }
        guard let hitPoint = self.sceneView.session.raycast(query).first else { return }
        
        let sphere = SCNSphere(radius: 0.05)
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.green.withAlphaComponent(0.8)
        sphere.materials = [material]
        
        let node = SCNNode(geometry: sphere)
        node.position = SCNVector3(hitPoint.worldTransform.columns.3.x, hitPoint.worldTransform.columns.3.y, hitPoint.worldTransform.columns.3.z)
        let billboardConstraint = SCNBillboardConstraint()
        node.constraints = [billboardConstraint]
        self.sceneView.scene.rootNode.addChildNode(node)
    }
    
    //Create a Plane Node
    func DrawPlaneNode(p1:CGPoint, p2:CGPoint, p3:CGPoint)-> Bool{
        
        /*Get 3D Coordinates of the points from a bounding box*/
        guard let query1 = self.sceneView.raycastQuery(from: p1, allowing: .estimatedPlane, alignment: .horizontal) else { return false }
        guard let hitPoint1 = self.sceneView.session.raycast(query1).first else { return false }
        guard let query2 = self.sceneView.raycastQuery(from: p2, allowing: .estimatedPlane, alignment: .horizontal) else { return false }
        guard let hitPoint2 = self.sceneView.session.raycast(query2).first else { return false }
        guard let query3 = self.sceneView.raycastQuery(from: p3, allowing: .estimatedPlane, alignment: .horizontal) else { return false }
        guard let hitPoint3 = self.sceneView.session.raycast(query3).first else { return false }
        
        // Get a normal vector
        let v1 = SCNVector3(hitPoint1.worldTransform.columns.3.x, hitPoint1.worldTransform.columns.3.y, hitPoint1.worldTransform.columns.3.z)
        let v2 = SCNVector3(hitPoint2.worldTransform.columns.3.x, hitPoint2.worldTransform.columns.3.y, hitPoint2.worldTransform.columns.3.z)
        let v3 = SCNVector3(hitPoint3.worldTransform.columns.3.x, hitPoint3.worldTransform.columns.3.y, hitPoint3.worldTransform.columns.3.z)
        //let normalVector: SCNVector3 = normalPlane(v1: v1, v2: v2, v3: v3)
        
        // Get width and height of the plane
        let horizontalV = simd_float3(v1.x-v2.x, v1.y-v2.y, v1.z-v2.z)
        let verticalV = simd_float3(v2.x-v3.x, v2.y-v3.y, v2.z-v3.z)
        let w = CGFloat( simd_length(horizontalV) )
        let h = CGFloat( simd_length(verticalV) )
        
        /*Plane to be drawn*/
        //let plane = SCNPlane(width: w, height: h)
        let plane = SCNPlane(width: w, height: h)
        
        /*Set color of the plane*/
        let material = SCNMaterial()
        material.diffuse.contents = UIColor.green.withAlphaComponent(0.8)
        material.isDoubleSided = true
        plane.materials = [material]
        
        //Make a node
        let planeNode = SCNNode(geometry: plane)
        planeNode.position = SCNVector3((v1.x+v3.x)/2, v3.y, (v1.z+v3.z)/2)
        //planeNode.position = SCNVector3((v1.x+v2.x)/2, (v2.y+v3.y)/2, -0.1)
        let billboardConstraint = SCNBillboardConstraint()
        billboardConstraint.freeAxes = [ .X, .Y, .Z]
        planeNode.constraints = [billboardConstraint]
        
        self.sceneView.scene.rootNode.addChildNode(planeNode)

        return true
    }
    
    // Calculate a normal vector of a plane
    func normalPlane(v1:SCNVector3, v2:SCNVector3, v3:SCNVector3)-> SCNVector3{
        return SCNVector3((v1.y-v2.y)*(v1.z-v3.z)-(v1.z-v2.z)*(v1.y-v3.y), (v1.z-v2.z)*(v1.x-v3.x)-(v1.x-v2.x)*(v1.z-v3.z), (v1.x-v2.x)*(v1.y-v3.y)-(v1.y-v2.y)*(v1.x-v3.x))
    }
    
    /*---------------------------------------------*/
    
    // Search
    
    func search(blockText:String, vertices:[CGPoint]){
        
        if( ARViewController.searchString.count == 0 ) {
            return
        }
        
        if( (blockText.contains(ARViewController.searchString) || matchingRatio(text:blockText)<0.5) && !searchDone){
            var p1 = vertices[0]
            var p2 = vertices[1]
            var p3 = vertices[2]
            
            let scaleX = self.sceneView.bounds.width / imageWidth
            let scaleY = self.sceneView.bounds.height / imageHeight
            
            p1.x *= scaleX; p1.y *= scaleY
            p2.x *= scaleX; p2.y *= scaleY
            p3.x *= scaleX; p3.y *= scaleY
            
            print("P1 : \(p1) , P3 : \(p3)")
            //self.DrawSphereNode(p1: p1)
            if(self.DrawPlaneNode(p1:p1 , p2: p2, p3: p3)){
                print("FOUND IT!!")
                searchDone = true
            }
        }
    }
    
    private func matchingRatio(text: String) -> Double{
        let text = text.replacingOccurrences(of: " ", with: "").lowercased()
        
        let n = ARViewController.searchString.count, m = text.count
        var dp = [[Int]](repeating: Array(repeating: 0, count: m+1), count: n+1)
        
        for (i, _) in ARViewController.searchString.enumerated() {
            dp[i+1][0] = i+1
        }
        for (j, _) in text.enumerated() {
            dp[0][j+1] = j+1
        }
        for (i, s) in ARViewController.searchString.enumerated(){
            for (j, t) in text.enumerated(){
                if s == t {
                    dp[i+1][j+1] = dp[i][j]
                } else {
                    dp[i+1][j+1] = min(dp[i][j], dp[i+1][j], dp[i][j+1]) + 1
                }
            }
        }
            
        return Double(dp[n][m]) / Double(n)
    }
}
