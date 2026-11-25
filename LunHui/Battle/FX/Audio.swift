#if os(iOS)
import AVFoundation

/// 音效和背景音乐（3.1、M8）。
/// 音效：AVAudioEngine + 一组 AVAudioPlayerNode，启动时把 CAF 预加载成缓冲区。
/// 同一个音效有最短间隔，满屏命中时不会叠成噪音。背景音乐：AVAudioPlayer 循环播放，切换时淡入淡出。
final class Audio {
    static let shared = Audio()

    enum Music: String {
        case cave = "bgm_cave", battle = "bgm_battle", boss = "bgm_boss"
    }

    var enabled = true {
        didSet {
            if !enabled { stopMusic() } else if let m = wantedMusic { wantedMusic = nil; playMusic(m) }
        }
    }

    private let engine = AVAudioEngine()
    private var players: [AVAudioPlayerNode] = []
    private var next = 0
    private var buffers: [String: AVAudioPCMBuffer] = [:]
    private var lastPlayed: [String: CFTimeInterval] = [:]
    private var music: AVAudioPlayer?
    private var musicName: Music?
    private var wantedMusic: Music?
    private var ready = false

    /// 每个音效的最短间隔（秒）和音量。
    private let rules: [String: (gap: Double, volume: Float)] = [
        "hit": (0.045, 0.35), "crit": (0.06, 0.5), "kill": (0.04, 0.45), "sword": (0.07, 0.3),
        "spell": (0.08, 0.35), "boom": (0.1, 0.55), "thunder": (0.09, 0.5), "pickup": (0.05, 0.3),
        "levelup": (0.2, 0.8), "drop_low": (0.08, 0.5), "drop_xian": (0.1, 0.8), "drop_shen": (0.2, 1),
        "drop_hundun": (0.3, 1), "boss": (0.5, 1), "victory": (0.5, 1), "death": (0.5, 0.9),
        "click": (0.03, 0.5), "ultimate": (0.3, 1),
    ]

    private init() {}

    /// 启动时调用一次。
    func setup() {
        guard !ready else { return }
        ready = true
        let session = AVAudioSession.sharedInstance()
        // ambient：遵守静音键，和其他 App 的声音混音
        try? session.setCategory(.ambient, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        var format: AVAudioFormat?
        for name in rules.keys {
            guard let url = Bundle.main.url(forResource: name, withExtension: "caf"),
                  let file = try? AVAudioFile(forReading: url),
                  let buf = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)) else { continue }
            try? file.read(into: buf)
            buffers[name] = buf
            format = format ?? file.processingFormat
        }
        guard let format else { return }
        for _ in 0..<14 {
            let p = AVAudioPlayerNode()
            engine.attach(p)
            engine.connect(p, to: engine.mainMixerNode, format: format)
            players.append(p)
        }
        engine.mainMixerNode.outputVolume = 0.9
        try? engine.start()
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { [weak self] _ in
            self?.restart()
        }
        NotificationCenter.default.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] n in
            guard let raw = n.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
                  AVAudioSession.InterruptionType(rawValue: raw) == .ended else { return }
            self?.restart()
        }
    }

    private func restart() {
        try? AVAudioSession.sharedInstance().setActive(true)
        if !engine.isRunning { try? engine.start() }
        if enabled, let m = musicName, music?.isPlaying != true { music?.play(); _ = m }
    }

    func play(_ name: String) {
        guard enabled, ready, let buf = buffers[name], !players.isEmpty else { return }
        let rule = rules[name] ?? (0.05, 0.6)
        let now = CACurrentMediaTime()
        if let last = lastPlayed[name], now - last < rule.gap { return }
        lastPlayed[name] = now
        if !engine.isRunning { try? engine.start() }
        guard engine.isRunning else { return }
        let p = players[next]
        next = (next + 1) % players.count
        p.volume = rule.volume
        p.scheduleBuffer(buf, at: nil, options: .interrupts)
        if !p.isPlaying { p.play() }
    }

    // MARK: 背景音乐

    func playMusic(_ m: Music) {
        guard enabled else {
            wantedMusic = m
            return
        }
        guard musicName != m || music?.isPlaying != true else { return }
        let old = music
        old?.setVolume(0, fadeDuration: 0.6)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.65) { old?.stop() }
        guard let url = Bundle.main.url(forResource: m.rawValue, withExtension: "caf"),
              let p = try? AVAudioPlayer(contentsOf: url) else { return }
        p.numberOfLoops = -1
        p.volume = 0
        p.prepareToPlay()
        p.play()
        p.setVolume(m == .cave ? 0.45 : 0.5, fadeDuration: 0.8)
        music = p
        musicName = m
    }

    func stopMusic() {
        music?.setVolume(0, fadeDuration: 0.4)
        let old = music
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) { old?.stop() }
        music = nil
        wantedMusic = musicName
        musicName = nil
    }
}
#endif
