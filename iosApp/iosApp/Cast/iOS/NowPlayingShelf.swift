import SwiftUI

/// The single now-playing accessory shown above the tab bar. Only one bar shows
/// at a time: a cast session takes priority over an audiobook session. Renders
/// nothing (zero space) when neither is active.
struct NowPlayingShelf: View {
    var style: NowPlayingBarStyle = .card

    #if os(iOS)
    @Environment(SiloCastController.self) private var castController
    #endif
    @Environment(AudioPlaybackStore.self) private var audioStore

    /// Single source of truth for "is a now-playing bar currently shown".
    /// Cast (when not showing the full remote) takes priority over audio.
    #if os(iOS)
    static func hasActiveAccessory(cast: SiloCastController, audio: AudioPlaybackStore) -> Bool {
        if cast.hasActiveSession && !cast.isShowingRemoteControl { return true }
        return audio.player.hasActiveSession
    }
    #else
    static func hasActiveAccessory(audio: AudioPlaybackStore) -> Bool {
        audio.player.hasActiveSession
    }
    #endif

    var body: some View {
        #if os(iOS)
        if castController.hasActiveSession && !castController.isShowingRemoteControl {
            SiloCastMiniBar(controller: castController, style: style)
                .animation(.snappy, value: castController.hasActiveSession)
                .animation(.snappy, value: castController.isShowingRemoteControl)
        } else if audioStore.player.hasActiveSession {
            AudioMiniPlayerView(style: style)
                .animation(.snappy, value: audioStore.player.hasActiveSession)
        }
        #else
        if audioStore.player.hasActiveSession {
            AudioMiniPlayerView(style: style)
                .animation(.snappy, value: audioStore.player.hasActiveSession)
        }
        #endif
    }
}

#if os(iOS)
/// Hosts `NowPlayingShelf` on a `TabView` so it rests above the tab bar.
/// iOS 26: native `tabViewBottomAccessory` (Liquid Glass, chromeless content).
/// iOS 18: a bottom `safeAreaInset` carrying the card-styled shelf.
/// The accessory is only attached while something is playing, so no empty bar
/// shows when idle.
struct NowPlayingShelfAttachment: ViewModifier {
    @Environment(SiloCastController.self) private var castController
    @Environment(AudioPlaybackStore.self) private var audioStore

    private var isActive: Bool {
        NowPlayingShelf.hasActiveAccessory(cast: castController, audio: audioStore)
    }

    func body(content: Content) -> some View {
        if #available(iOS 26.0, *) {
            if isActive {
                content.tabViewBottomAccessory {
                    NowPlayingShelf(style: .accessory)
                }
            } else {
                content
            }
        } else {
            content.safeAreaInset(edge: .bottom, spacing: 0) {
                if isActive {
                    NowPlayingShelf(style: .card)
                }
            }
        }
    }
}
#endif
