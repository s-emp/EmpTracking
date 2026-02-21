import Vapor

struct RegisterDeviceRequest: Content {
    let device_id: String
    let name: String
}
