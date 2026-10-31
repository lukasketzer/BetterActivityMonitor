import Foundation
import IOKit

final class DiskSampler {
    private var previous: [String: (read: UInt64, write: UInt64, readOps: UInt64, writeOps: UInt64)] = [:]
    private var previousTime: Date?
    private var volumes: [Volume] = []
    private var volumesLoaded: Date?
    private var bsdNames: [UInt64: String] = [:]

    /// The recursive registry search for the BSD name is slow; registry IDs are stable.
    private func bsdName(of service: io_object_t) -> String? {
        var id: UInt64 = 0
        IORegistryEntryGetRegistryEntryID(service, &id)
        if let name = bsdNames[id] { return name }
        let name = IORegistry.childProperty("BSD Name", of: service) as? String
        bsdNames[id] = name
        return name
    }

    func sample() -> DiskStats {
        let now = Date()
        let dt = previousTime.map { max(now.timeIntervalSince($0), 0.001) }
        var devices: [DiskDevice] = []

        IORegistry.forEachService(matching: "IOBlockStorageDriver", fullProperties: false) { service, _ in
            guard let stats = IORegistry.property("Statistics", of: service) as? [String: Any],
                  let bsd = bsdName(of: service) else { return }
            let read = stats.uint64("Bytes (Read)") ?? 0
            let write = stats.uint64("Bytes (Write)") ?? 0
            let readOps = stats.uint64("Operations (Read)") ?? 0
            let writeOps = stats.uint64("Operations (Write)") ?? 0
            var device = DiskDevice(bsdName: bsd, bytesRead: read, bytesWritten: write,
                                    readsPerSecond: 0, writesPerSecond: 0, readRate: 0, writeRate: 0)
            if let dt, let prev = previous[bsd], read >= prev.read, write >= prev.write {
                device.readRate = Double(read - prev.read) / dt
                device.writeRate = Double(write - prev.write) / dt
                device.readsPerSecond = Double(readOps &- prev.readOps) / dt
                device.writesPerSecond = Double(writeOps &- prev.writeOps) / dt
            }
            previous[bsd] = (read, write, readOps, writeOps)
            devices.append(device)
        }
        previousTime = now

        // Volumes change rarely and statfs on network mounts can be slow.
        if volumesLoaded.map({ now.timeIntervalSince($0) > 30 }) ?? true {
            volumes = Self.readVolumes()
            volumesLoaded = now
        }

        return DiskStats(
            devices: devices.sorted { $0.bsdName < $1.bsdName },
            volumes: volumes,
            readRate: devices.reduce(0) { $0 + $1.readRate },
            writeRate: devices.reduce(0) { $0 + $1.writeRate },
            totalRead: devices.reduce(0) { $0 + $1.bytesRead },
            totalWritten: devices.reduce(0) { $0 + $1.bytesWritten }
        )
    }

    static func readVolumes() -> [Volume] {
        let keys: [URLResourceKey] = [.volumeNameKey, .volumeTotalCapacityKey, .volumeAvailableCapacityKey,
                                      .volumeAvailableCapacityForImportantUsageKey, .volumeIsInternalKey,
                                      .volumeIsRemovableKey, .volumeLocalizedFormatDescriptionKey]
        let urls = FileManager.default.mountedVolumeURLs(includingResourceValuesForKeys: keys,
                                                         options: [.skipHiddenVolumes]) ?? []
        return urls.compactMap { url in
            guard let v = try? url.resourceValues(forKeys: Set(keys)), let total = v.volumeTotalCapacity, total > 0 else { return nil }
            let important = v.volumeAvailableCapacityForImportantUsage.map { UInt64(max($0, 0)) }
            let available = important ?? UInt64(max(v.volumeAvailableCapacity ?? 0, 0))
            return Volume(name: v.volumeName ?? url.lastPathComponent, path: url.path,
                          format: v.volumeLocalizedFormatDescription ?? "",
                          total: UInt64(total), available: available,
                          isInternal: v.volumeIsInternal ?? false, isRemovable: v.volumeIsRemovable ?? false)
        }
    }
}
