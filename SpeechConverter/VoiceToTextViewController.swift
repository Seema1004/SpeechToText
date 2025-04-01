//
//  ViewController.swift
//  SpeechConverter
//
//  Created by Seema Sharma on 3/31/25.
//

import UIKit
import Speech
import AVFoundation

class VoiceToTextViewController: UIViewController, SFSpeechRecognizerDelegate, AVSpeechSynthesizerDelegate {
    
    @IBOutlet weak var chatTable: UITableView!
    @IBOutlet weak var textView: UITextView!
    @IBOutlet weak var recordButton: UIButton!
    
    //declare variables for chat between system and user
    let speechRecognizer = SFSpeechRecognizer(locale: Locale(identifier: "en_US"))!
    let audioEngine = AVAudioEngine()
    var recognitionRequest: SFSpeechAudioBufferRecognitionRequest?
    var recognitionTask: SFSpeechRecognitionTask?
    var speechSynthesizer = AVSpeechSynthesizer()
    var speechCompletion:(() -> Void)?
    var userInput: String? = nil
    
    var transcript: [(sender: String, message: String)] = []
    var isUserSpeaking = false
    //API key from chatgpt
    var chatAPIKey = ""
    
    override func viewDidLoad() {
        super.viewDidLoad()
        // Do any additional setup after loading the view.
        self.getAPIKey()
        self.configureTableView()
        self.speechSynthesizer.delegate = self
        self.configureAudioSession()
        self.requestAuthorizationForSpeech()
    }
    
    //configure Table View
    func configureTableView() {
        self.chatTable.estimatedRowHeight = 80
        self.chatTable.rowHeight = UITableView.automaticDimension
    }
    
    //Fetch the chatGPT api key from the config file
    func getAPIKey() {
        if let apikey = Bundle.main.object(forInfoDictionaryKey: "OpenAIAPIKey") as? String{
            self.chatAPIKey = apikey
        }
    }
    
    //Configure the audio session
    func configureAudioSession() {
        do {
            let audioSession = AVAudioSession.sharedInstance()
            try audioSession.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetooth])
            try audioSession.setActive(true, options: .notifyOthersOnDeactivation)
        } catch {
            print("audio session could not be initiated")
        }
    }
    
    //Request user to provide access to speech. permission key added in the plist file
    func requestAuthorizationForSpeech() {
        SFSpeechRecognizer.requestAuthorization { status in
            DispatchQueue.main.async {
                switch status {
                case .authorized:
                    self.recordButton.isEnabled = true
                case .denied,.notDetermined,.restricted:
                    self.recordButton.isEnabled = false
                    let alert = UIAlertController(title: "Access Denied", message: "Speech recognition not authorized", preferredStyle:.alert)
                    let action = UIAlertAction.init(title: "OK", style: .default)
                    alert.addAction(action)
                    self.show(alert, sender: nil)
                @unknown default:
                    print("Speech recognition not authorized")
                }
            }
        }
    }
    
    @IBAction func recordButtonTapped(_ sender: UIButton) {
        if !isUserSpeaking {
            self.isUserSpeaking = true
            recordButton.setTitle("Stop Chat", for: .normal)
            try? startRecording()
        } else {
            self.isUserSpeaking = false
            self.stopChatWithAI()
            recordButton.setTitle("Start Chat", for: .normal)
            textView.text = "Tap to start chat!!"
        }
    }
    
    //MARK: start listening to audio
    func startRecording() throws {
        
        //cancel the previous running request to start a new one
        self.recognitionTask?.cancel()
        self.recognitionTask = nil
        
        // Stop and reset audio engine if already running
        if audioEngine.isRunning {
            audioEngine.stop()
            audioEngine.inputNode.removeTap(onBus: 0)
            audioEngine.reset()
        }
        
        
        let inputNode = audioEngine.inputNode
        inputNode.removeTap(onBus: 0)
        recognitionRequest = SFSpeechAudioBufferRecognitionRequest()
        recognitionRequest?.shouldReportPartialResults = true
        
        let recordingFormat = inputNode.outputFormat(forBus: 0)
        inputNode.installTap(onBus: 0, bufferSize: 1024, format: recordingFormat) { buffer, _ in
            self.recognitionRequest?.append(buffer)
        }
        self.audioEngine.prepare()
        try self.audioEngine.start()
        textView.text = "Listening ..."
        
        // Add timeout logic - this is to check if after 10 seconds the device is able to pick any audio. if not then its the AI's turn to respond.
        DispatchQueue.main.asyncAfter(deadline: .now() + 5) {
            if self.audioEngine.isRunning {
                self.stopChatWithAI()
            }
        }
        
        recognitionTask = speechRecognizer.recognitionTask(with: recognitionRequest!, resultHandler: { result, error in
            if let requiredResult = result {
                let speechRecognized = requiredResult.bestTranscription.formattedString
                self.textView.text = speechRecognized
                if requiredResult.isFinal {
                    self.processReceivedText(speechRecognized)
                }
            }
            
            if error != nil {
                self.recordButton.setTitle("Start Chat", for: .normal)
                self.textView.text = "Tap to start chat..."
                self.isUserSpeaking = false
            }
        })
    }
    
    //Update the table and request a response from AI
    func processReceivedText(_ userInput: String) {
        transcript.append(("You", userInput))
        chatTable.reloadData()
        self.userInput = userInput
        self.requestResponseFromOpenAI(userInput)
    }
    
    //ChatGPT API call to respond to the user input
    func requestResponseFromOpenAI(_ userInput: String){
        let chatApiURL = URL(string: "https://api.openai.com/v1/chat/completions")!
        let jsonData: [String: Any] = [
            "model": "gpt-4-turbo",
            "messages": [
                ["role": "system", "content": "You are a helpful assistant."],
                ["role": "user", "content": userInput]
            ],
            "max_tokens": 30
        ]
        
        var request = URLRequest(url: chatApiURL)
        request.httpMethod = "POST"
        if chatAPIKey != "" {
            request.addValue("Bearer \(chatAPIKey)", forHTTPHeaderField: "Authorization")
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
            
            do{
                let jsonData = try JSONSerialization.data(withJSONObject: jsonData, options: [])
                request.httpBody = jsonData
            } catch {
                print("Unable to decode the json data for API request")
                return
            }
            
            let task = URLSession.shared.dataTask(with: request) { (data, response, error) in
                guard let data = data else {
                    print("No data returned by the API")
                    DispatchQueue.main.async {
                        self.textView.text = "Failed to get response"
                        self.isUserSpeaking = false
                        self.recordButton.setTitle("Start Chat", for: .normal)
                    }
                    return
                }
                
                do {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data, options: [])
                    guard let jsonDictionary = jsonResponse as? [String: Any] else {
                        return
                    }
                    print("the response data \(jsonDictionary)")
                    
                    if let choices = jsonDictionary["choices"] as? [[String: Any]],
                       let text = choices.first?["message"] as? [String: Any],
                       let responseText = text["content"] as? String {
                        DispatchQueue.main.async {
                            self.transcript.append(("AI", responseText))
                            self.chatTable.reloadData()
                            self.showResults(responseText) {
                                if self.isUserSpeaking{
                                    try? self.startRecording()
                                }
                            }
                        }
                    } else if let error = jsonDictionary["error"] as? [String:Any], let message = error["message"] as? String {
                        print("Error: \(message)")
                        DispatchQueue.main.async {
                            self.textView.text = "AI Error: \(message)"
                            self.isUserSpeaking = false
                            self.recordButton.setTitle("Start Chat", for: .normal)
                        }
                    }
                    
                } catch {
                    print("Error decoding GPT response: \(error.localizedDescription)")
                }
            }
            
            task.resume()
        } else {
            print("API key not found")
        }
    }
    
    //Stop recording
    func stopChatWithAI() {
        self.audioEngine.stop()
        recognitionRequest?.endAudio()
        self.audioEngine.reset()
        audioEngine.inputNode.removeTap(onBus: 0)
    }
    
    //load the response received from the open AI
    func showResults(_ response: String, completion: @escaping() -> Void) {
        let speechUtterance = AVSpeechUtterance(string: response)
        speechUtterance.voice = AVSpeechSynthesisVoice(language: "en_US")
        speechUtterance.volume = 1.0
        speechUtterance.rate = AVSpeechUtteranceDefaultSpeechRate
        speechUtterance.preUtteranceDelay = 0.3
        self.speechCompletion = completion
        self.speechSynthesizer.delegate = self
        speechSynthesizer.speak(speechUtterance)
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        if let completion = speechCompletion {
            speechCompletion = nil
            completion()
        }
    }
    
    func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didStart utterance: AVSpeechUtterance) {
        print("✅ Speech started")
    }
}

extension VoiceToTextViewController: UITableViewDelegate, UITableViewDataSource {
    // MARK: - Transcript TableView
    
    func numberOfSections(in tableView: UITableView) -> Int {
        return transcript.count
    }
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 1
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "ChatViewCell") ?? UITableViewCell(style: .subtitle, reuseIdentifier: "ChatViewCell")
        let message = transcript[indexPath.section]
        cell.textLabel?.text = message.sender
        cell.detailTextLabel?.text = message.message
        cell.textLabel?.textColor = .black
        cell.detailTextLabel?.textColor = .darkGray
        cell.detailTextLabel?.numberOfLines = 0
        
        //add more colors to the cell
        cell.contentView.layer.cornerRadius = 10
        cell.contentView.layer.masksToBounds = true
        cell.selectionStyle = .none
        cell.contentView.backgroundColor = .white
        return cell
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return UITableView.automaticDimension
    }
}

