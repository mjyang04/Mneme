import Foundation
import ServiceManagement

enum LoginItemController {
    static var isEnabled: Bool {
        if #available(macOS 13.0, *) {
            return SMAppService.mainApp.status == .enabled
        }
        return false
    }

    static func setEnabled(_ enabled: Bool) throws {
        guard #available(macOS 13.0, *) else {
            throw LoginItemError.unsupported
        }
        if enabled {
            try SMAppService.mainApp.register()
        } else {
            try SMAppService.mainApp.unregister()
        }
    }
}

enum LoginItemError: LocalizedError {
    case unsupported

    var errorDescription: String? {
        "当前 macOS 版本不支持 SMAppService 登录项"
    }
}
