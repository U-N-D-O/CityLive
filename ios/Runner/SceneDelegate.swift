import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
	private var didAttachCarPlayBridge = false

	override func scene(
		_ scene: UIScene,
		willConnectTo session: UISceneSession,
		options connectionOptions: UIScene.ConnectionOptions
	) {
		super.scene(scene, willConnectTo: session, options: connectionOptions)
		attachCarPlayBridgeIfNeeded()
	}

	private func attachCarPlayBridgeIfNeeded() {
		guard !didAttachCarPlayBridge,
			let controller = window?.rootViewController as? FlutterViewController
		else {
			return
		}

		didAttachCarPlayBridge = true
		NativeCarPlayBridge.attach(to: controller)
	}
}
