import AppKit
import CoreGraphics
import CoreVideo
import Foundation
import ImageIO
import ScreenCaptureKit
import UniformTypeIdentifiers

enum ScreenshotServiceError: LocalizedError {
    case captureDenied
    case writeFailed

    var errorDescription: String? {
        switch self {
        case .captureDenied:
            return "Screen capture failed. Check macOS Screen Recording permission for CopySouL."
        case .writeFailed:
            return "The screenshot could not be written to disk."
        }
    }
}

struct ScreenshotService {
    @MainActor
    func captureScreenHidingApp() async throws -> URL {
        let visibleWindows = NSApp.windows.filter { $0.isVisible }
        visibleWindows.forEach { $0.orderOut(nil) }
        try? await Task.sleep(nanoseconds: 180_000_000)
        defer {
            visibleWindows.forEach { $0.makeKeyAndOrderFront(nil) }
        }

        let image = try await captureImageWithScreenCaptureKit()

        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("CopySouL-Screenshot-\(UUID().uuidString)")
            .appendingPathExtension("png")
        guard
            let destination = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)
        else {
            throw ScreenshotServiceError.writeFailed
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else {
            throw ScreenshotServiceError.writeFailed
        }
        return url
    }

    private func captureImageWithScreenCaptureKit() async throws -> CGImage {
        let content = try await SCShareableContent.current
        guard let display = content.displays.first else {
            throw ScreenshotServiceError.captureDenied
        }

        let ownApplications = content.applications.filter {
            $0.processID == ProcessInfo.processInfo.processIdentifier
        }
        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )
        filter.includeMenuBar = true

        let configuration = SCStreamConfiguration()
        let scale = backingScale(for: display)
        configuration.width = max(1, Int(Double(display.width) * scale))
        configuration.height = max(1, Int(Double(display.height) * scale))
        configuration.pixelFormat = kCVPixelFormatType_32BGRA

        return try await withCheckedThrowingContinuation { continuation in
            SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration) { image, error in
                if let image {
                    continuation.resume(returning: image)
                } else {
                    continuation.resume(throwing: error ?? ScreenshotServiceError.captureDenied)
                }
            }
        }
    }

    private func backingScale(for display: SCDisplay) -> Double {
        let screen = NSScreen.screens.first { screen in
            let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID
            return displayID == display.displayID
        }
        return Double(screen?.backingScaleFactor ?? NSScreen.main?.backingScaleFactor ?? 2)
    }
}

enum ScreenRecordingPermission {
    static var isGranted: Bool {
        CGPreflightScreenCaptureAccess()
    }

    @discardableResult
    static func request() -> Bool {
        CGRequestScreenCaptureAccess()
    }

    static func openSystemSettings() {
        guard let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") else {
            return
        }
        NSWorkspace.shared.open(url)
    }
}
