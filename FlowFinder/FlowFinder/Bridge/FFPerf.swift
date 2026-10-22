import Foundation
import os.signpost

/// Debug 构建的轻量 signpost；Release 下 begin/end 均为空操作。
enum FFPerf {
    private static let log = OSLog(subsystem: "com.flowfinder.native",
                                   category: .pointsOfInterest)

    static func begin(_ name: StaticString) -> OSSignpostID? {
        #if DEBUG
        let id = OSSignpostID(log: log)
        os_signpost(.begin, log: log, name: name, signpostID: id)
        return id
        #else
        return nil
        #endif
    }

    static func end(_ name: StaticString, _ id: OSSignpostID?) {
        #if DEBUG
        if let id {
            os_signpost(.end, log: log, name: name, signpostID: id)
        }
        #endif
    }
}
