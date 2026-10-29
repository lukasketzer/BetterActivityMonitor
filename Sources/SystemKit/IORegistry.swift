import Foundation
import IOKit

enum IORegistry {
    /// Calls `body` with the properties of every service matching `className`.
    static func forEachService(matching className: String, fullProperties: Bool = true,
                               _ body: (io_object_t, [String: Any]) -> Void) {
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(kIOMainPortDefault, IOServiceMatching(className), &iterator) == KERN_SUCCESS else { return }
        defer { IOObjectRelease(iterator) }
        while case let service = IOIteratorNext(iterator), service != 0 {
            if !fullProperties {
                body(service, [:])
            } else if let props = properties(of: service) {
                body(service, props)
            }
            IOObjectRelease(service)
        }
    }

    static func properties(of entry: io_object_t) -> [String: Any]? {
        var props: Unmanaged<CFMutableDictionary>?
        guard IORegistryEntryCreateCFProperties(entry, &props, kCFAllocatorDefault, 0) == KERN_SUCCESS,
              let dict = props?.takeRetainedValue() as? [String: Any] else { return nil }
        return dict
    }

    static func property(_ key: String, of entry: io_object_t) -> Any? {
        IORegistryEntryCreateCFProperty(entry, key as CFString, kCFAllocatorDefault, 0)?.takeRetainedValue()
    }

    /// Searches the entry's descendants for the first value of `key`.
    static func childProperty(_ key: String, of entry: io_object_t) -> Any? {
        IORegistryEntrySearchCFProperty(entry, kIOServicePlane, key as CFString, kCFAllocatorDefault,
                                        IOOptionBits(kIORegistryIterateRecursively))
    }
}

extension Dictionary where Key == String, Value == Any {
    func number(_ key: String) -> Double? { (self[key] as? NSNumber)?.doubleValue }
    func uint64(_ key: String) -> UInt64? { (self[key] as? NSNumber)?.uint64Value }
    func int(_ key: String) -> Int? { (self[key] as? NSNumber)?.intValue }
}
