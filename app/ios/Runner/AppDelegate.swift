import AVFoundation
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    configureAudioSession()
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Let the concentration sounds keep playing with the screen off.
  ///
  /// An app that never says otherwise gets `AVAudioSession`'s default
  /// `.soloAmbient` category, which is silenced by the ring/silent switch and
  /// stops the moment the phone locks - correct for a game, wrong for the one
  /// thing in this app whose entire job is to run while you are not looking at
  /// it. `.playback` is the category that says "this audio *is* the point", and
  /// it is what makes the `audio` background mode in Info.plist mean anything:
  /// the entitlement permits playing in the background, the category is what
  /// asks to.
  ///
  /// The category is only *set* here, never activated. Activation is what
  /// interrupts whatever else is playing, and libmpv does it when it actually
  /// starts a source - so launching the widget does not stop your music, and
  /// pressing play does.
  ///
  /// Failures are swallowed on purpose. Every one of them ends in "the sound
  /// stops when the screen locks", which is where this started; none of them is
  /// a reason for a todo list to refuse to open.
  private func configureAudioSession() {
    do {
      try AVAudioSession.sharedInstance().setCategory(.playback, mode: .default)
    } catch {
      NSLog("[todo] could not claim the playback audio session: \(error)")
    }
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
  }
}
