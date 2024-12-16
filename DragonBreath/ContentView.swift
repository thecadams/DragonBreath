import SwiftUI
import AVKit
import AVFoundation

// App Delegate to force landscape orientation
class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, supportedInterfaceOrientationsFor window: UIWindow?) -> UIInterfaceOrientationMask {
        return .landscape
    }
}

// Audio Monitor to detect breathing
class AudioMonitor: NSObject, ObservableObject {
    private var audioRecorder: AVAudioRecorder?
    private var timer: Timer?
    @Published var isBreathing = false

    private let breathingThreshold: Float = -7.0 // Adjust this value based on testing

    override init() {
        super.init()
        setupAudioRecorder()
    }

    private func setupAudioRecorder() {
        let audioSession = AVAudioSession.sharedInstance()
        do {
            try audioSession.setCategory(.playAndRecord, mode: .default)
            try audioSession.setActive(true)
            try audioSession.overrideOutputAudioPort(.speaker)

            let url = URL(fileURLWithPath: "/dev/null", isDirectory: true)
            let settings: [String: Any] = [
                AVFormatIDKey: Int(kAudioFormatAppleLossless),
                AVSampleRateKey: 44100.0,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.min.rawValue
            ]

            audioRecorder = try AVAudioRecorder(url: url, settings: settings)
            audioRecorder?.isMeteringEnabled = true
            audioRecorder?.record()

            startMonitoring()
        } catch {
            print("Audio recording setup failed: \(error)")
        }
    }

    private func startMonitoring() {
        timer = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { [weak self] _ in
            self?.audioRecorder?.updateMeters()
            let level = self?.audioRecorder?.averagePower(forChannel: 0) ?? -160.0
            self?.isBreathing = level > self?.breathingThreshold ?? -7.0
        }
    }

    func stopMonitoring() {
        timer?.invalidate()
        timer = nil
        audioRecorder?.stop()
    }

    deinit {
        stopMonitoring()
    }
}

// Video Controller to manage playback
class VideoController: ObservableObject {
    private var player: AVPlayer
    private var loopStartTime: CMTime
    private var loopEndTime: CMTime
    private var isLooping = false

    init(player: AVPlayer) {
        self.player = player

        // Calculate the middle second of the video
        let duration = player.currentItem?.duration.seconds ?? 0
        let middlePoint = duration / 2
        self.loopStartTime = CMTime(seconds: middlePoint - 0.5, preferredTimescale: 600)
        self.loopEndTime = CMTime(seconds: middlePoint + 0.5, preferredTimescale: 600)
    }

    func startLooping() {
        guard !isLooping else { return }
        isLooping = true
        player.seek(to: loopStartTime)
        player.play()

        // Add observer for loop
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleLoopEnd),
            name: .AVPlayerItemDidPlayToEndTime,
            object: player.currentItem
        )
    }

    func stopLooping() {
        guard isLooping else { return }
        isLooping = false
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func handleLoopEnd() {
        if isLooping {
            player.seek(to: loopStartTime)
            player.play()
        }
    }
}

// Main Video Player View
struct ContentView: View {
    @StateObject private var audioMonitor = AudioMonitor()
    private let player: AVPlayer
    private var videoController: VideoController

    init() {
        // Replace this URL with your video file URL
        guard let url = Bundle.main.url(forResource: "breath", withExtension: "mp4") else {
            fatalError("Video file not found")
        }

        // Create AVPlayer with the video URL
        self.player = AVPlayer(url: url)
        self.videoController = VideoController(player: player)
    }

    var body: some View {
        GeometryReader { geometry in
            let videoWidth = geometry.size.height * 2 // Force 2:1 aspect ratio to ensure sides are off screen

            VideoPlayer(player: player)
                .disabled(true)
                .frame(width: videoWidth, height: geometry.size.height)
                .frame(width: geometry.size.width, height: geometry.size.height, alignment: .center)
                .clipped()
                .edgesIgnoringSafeArea(.all)
                .onChange(of: audioMonitor.isBreathing) {
                    if audioMonitor.isBreathing {
                        videoController.startLooping()
                    } else {
                        videoController.stopLooping()
                    }
                }
        }
        .edgesIgnoringSafeArea(.all)
    }
}
