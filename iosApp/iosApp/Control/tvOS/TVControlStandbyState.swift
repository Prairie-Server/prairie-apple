#if os(tvOS)
import Foundation

struct TVControlStandbyState: Equatable {
    var controllerName: String?
    var serverName: String?

    var controllerLabel: String {
        if let controllerName, !controllerName.isEmpty {
            return controllerName
        }
        return "iPhone"
    }
}
#endif
