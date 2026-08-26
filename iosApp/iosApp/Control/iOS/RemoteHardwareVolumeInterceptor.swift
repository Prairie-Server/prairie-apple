#if os(iOS)
import AVFoundation
import MediaPlayer
import SwiftUI

/// Converts hardware volume changes into remote volume steps while its hidden
/// `MPVolumeView` suppresses the system HUD. Extreme values are nudged to the
/// midpoint so every subsequent hardware-button press still produces a delta.
@MainActor
final class RemoteHardwareVolumeInterceptor {
    var onVolumeStep: ((Int) -> Void)?

    let volumeView = MPVolumeView(frame: CGRect(x: 0, y: 0, width: 1, height: 1))

    private(set) var isActive = false
    private var originalSystemVolume: Float?
    private var suppressUntil: Date = .distantPast
    private var claim: AetherAudioSessionOwnership.Claim?
    private var observation: NSKeyValueObservation?

    func start() {
        guard !isActive else { return }
        isActive = true

        let session = AVAudioSession.sharedInstance()
        originalSystemVolume = session.outputVolume
        if session.category != .playback {
            try? session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        }
        try? session.setActive(true)

        claim = AetherAudioSessionOwnership.Claim(isHoldingAudio: { [weak self] in
            self?.isActive ?? false
        })

        observation = session.observe(\.outputVolume, options: [.old, .new]) { [weak self] _, change in
            Task { @MainActor [weak self] in
                guard let self, Date() >= suppressUntil,
                      let old = change.oldValue, let new = change.newValue else { return }
                if new > old {
                    onVolumeStep?(1)
                } else if new < old {
                    onVolumeStep?(-1)
                }
                if new <= 0.0625 || new >= 0.9375 {
                    nudgeSystemVolume(to: 0.5)
                }
            }
        }

        if session.outputVolume <= 0.0625 || session.outputVolume >= 0.9375 {
            nudgeSystemVolume(to: 0.5)
        }
    }

    private func nudgeSystemVolume(to value: Float) {
        suppressUntil = Date().addingTimeInterval(0.5)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { [weak self] in
            guard let self else { return }
            volumeView.subviews.compactMap { $0 as? UISlider }.first?.value = value
        }
    }

    func stop() {
        guard isActive else { return }
        isActive = false
        observation?.invalidate()
        observation = nil

        if let originalSystemVolume {
            nudgeSystemVolume(to: originalSystemVolume)
            self.originalSystemVolume = nil
        }

        let claim = claim
        let canReleaseSession = claim.map {
            AetherAudioSessionOwnership.canReleaseSharedSession(excluding: $0)
        } ?? false
        self.claim = nil
        if canReleaseSession {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                try? AVAudioSession.sharedInstance().setActive(
                    false,
                    options: .notifyOthersOnDeactivation
                )
            }
        }
    }
}

struct HiddenVolumeHost: UIViewRepresentable {
    let interceptor: RemoteHardwareVolumeInterceptor

    func makeUIView(context: Context) -> MPVolumeView {
        interceptor.volumeView
    }

    func updateUIView(_ uiView: MPVolumeView, context: Context) {}
}
#endif
