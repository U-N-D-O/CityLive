import CarPlay
import Flutter
import UIKit

final class CarPlaySceneDelegate: UIResponder, CPTemplateApplicationSceneDelegate {
  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didConnect interfaceController: CPInterfaceController
  ) {
    CarPlayStateStore.shared.interfaceController = interfaceController
  }

  func templateApplicationScene(
    _ templateApplicationScene: CPTemplateApplicationScene,
    didDisconnect interfaceController: CPInterfaceController
  ) {
    CarPlayStateStore.shared.interfaceController = nil
  }
}

enum NativeCarPlayBridge {
  static func attach(to controller: FlutterViewController) {
    let channel = FlutterMethodChannel(
      name: "nuuk_city_live/carplay",
      binaryMessenger: controller.binaryMessenger
    )

    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "updateVisiblePlaces":
        let places = call.arguments as? [[String: Any]] ?? []
        CarPlayStateStore.shared.updateVisiblePlaces(places)
        result(nil)
      case "activateNavigation":
        let destination = call.arguments as? [String: Any] ?? [:]
        CarPlayStateStore.shared.activateNavigation(destination)
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

private struct CarPlayPlace {
  let name: String
  let category: String
  let isOpen: Bool
}

private final class CarPlayStateStore {
  static let shared = CarPlayStateStore()

  weak var interfaceController: CPInterfaceController? {
    didSet { reloadTemplate() }
  }

  private var places = [CarPlayPlace]()
  private var activeDestinationName: String?

  func updateVisiblePlaces(_ rawPlaces: [[String: Any]]) {
    places = rawPlaces.compactMap { rawPlace in
      guard let name = rawPlace["name"] as? String,
        let category = rawPlace["category"] as? String
      else {
        return nil
      }

      return CarPlayPlace(
        name: name,
        category: category,
        isOpen: rawPlace["isOpen"] as? Bool ?? false
      )
    }
    reloadTemplate()
  }

  func activateNavigation(_ rawDestination: [String: Any]) {
    activeDestinationName = rawDestination["destinationName"] as? String
    reloadTemplate()
  }

  private func reloadTemplate() {
    guard let interfaceController else {
      return
    }

    let sections = [CPListSection(items: makeItems())]
    let template = CPListTemplate(title: "Nuuk City Live", sections: sections)
    interfaceController.setRootTemplate(template, animated: true)
  }

  private func makeItems() -> [CPListItem] {
    var items = [CPListItem]()

    if let activeDestinationName {
      items.append(
        CPListItem(text: "Navigating to", detailText: activeDestinationName)
      )
    }

    if places.isEmpty {
      items.append(
        CPListItem(
          text: "Open places will appear here",
          detailText: "Choose a category or destination on your phone"
        )
      )
      return items
    }

    items.append(
      contentsOf: places.map { place in
        let status = place.isOpen ? "Open" : "Closed"
        return CPListItem(
          text: place.name,
          detailText: "\(place.category) - \(status)"
        )
      }
    )

    return items
  }
}