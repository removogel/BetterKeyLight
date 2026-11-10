import Foundation
import CoreMediaIO

/// Checks whether any camera on this Mac is currently in use (by any app).
/// Reading this property does not require camera permission.
enum CameraMonitor {
    static func isAnyCameraRunning() -> Bool {
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var address = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain))

        var dataSize: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &dataSize) == 0, dataSize > 0 else {
            return false
        }
        let count = Int(dataSize) / MemoryLayout<CMIOObjectID>.size
        var devices = [CMIOObjectID](repeating: 0, count: count)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, dataSize, &used, &devices) == 0 else {
            return false
        }

        var runningAddress = CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeWildcard),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementWildcard))
        let valueSize = UInt32(MemoryLayout<UInt32>.size)

        for device in devices {
            var running: UInt32 = 0
            var usedBytes: UInt32 = 0
            let status = CMIOObjectGetPropertyData(device, &runningAddress, 0, nil, valueSize, &usedBytes, &running)
            if status == 0 && running != 0 { return true }
        }
        return false
    }
}
