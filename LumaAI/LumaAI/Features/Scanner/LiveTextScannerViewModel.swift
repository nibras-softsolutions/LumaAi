import Foundation
import SwiftUI
import AVFoundation
import UIKit

public enum CameraPermissionStatus {
    case notDetermined
    case authorized
    case denied
}

@MainActor
public final class LiveTextScannerViewModel: ObservableObject {
    @Published public var permissionStatus: CameraPermissionStatus = .notDetermined
    @Published public var recognizedBlocks: [RecognizedTextBlock] = []
    @Published public var recognizedFullText: String = ""
    @Published public var selectedBlockId: UUID?
    @Published public var isTorchOn: Bool = false
    @Published public var isTorchAvailable: Bool = false
    @Published public var toastMessage: String?
    @Published public var isScanning: Bool = false
    @Published public var videoBufferSize: CGSize = CGSize(width: 1080, height: 1920)

    public let cameraService = LiveCameraService()
    private var toastDismissTask: Task<Void, Never>?
    private var isTornDown: Bool = false

    public init() {
        setupBindings()
    }

    deinit {
        toastDismissTask?.cancel()
    }

    private func setupBindings() {
        cameraService.onObservationsUpdated = { [weak self] blocks, fullText, bufferSize in
            DispatchQueue.main.async {
                guard let self = self, !self.isTornDown else { return }
                self.recognizedBlocks = blocks
                self.recognizedFullText = fullText
                self.videoBufferSize = bufferSize
            }
        }
    }

    // MARK: - Permissions & Lifecycle

    public func onAppear() {
        isTornDown = false
        setupBindings()
        checkAndRequestPermissions()
    }

    public func onDisappear() {
        stopScanning()
    }

    public func checkAndRequestPermissions() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            self.permissionStatus = .authorized
            startScanning()

        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { [weak self] granted in
                DispatchQueue.main.async {
                    guard let self = self, !self.isTornDown else { return }
                    if granted {
                        self.permissionStatus = .authorized
                        self.startScanning()
                    } else {
                        self.permissionStatus = .denied
                    }
                }
            }

        case .denied, .restricted:
            self.permissionStatus = .denied

        @unknown default:
            self.permissionStatus = .denied
        }
    }

    public func startScanning() {
        isTornDown = false
        setupBindings()

        guard !isScanning else { return }
        isScanning = true

        cameraService.configureSession { [weak self] success in
            guard let self = self, !self.isTornDown, success else { return }
            self.cameraService.startSession()
            self.isTorchAvailable = self.cameraService.isTorchAvailable
        }
    }

    public func stopScanning() {
        isTornDown = true
        isScanning = false

        if isTorchOn {
            isTorchOn = false
            cameraService.setTorch(enabled: false)
        }

        cameraService.onObservationsUpdated = nil
        cameraService.stopSession()
    }

    public func pauseScanning() {
        cameraService.pause()
    }

    public func resumeScanning() {
        if permissionStatus == .authorized && !isTornDown {
            cameraService.resume()
        }
    }

    // MARK: - Torch

    public func toggleTorch() {
        isTorchOn.toggle()
        cameraService.setTorch(enabled: isTorchOn)
        HapticFeedback.light()
    }

    // MARK: - Copy & Selection Actions

    public func copyAllText() {
        let trimmed = recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        HapticFeedback.success()
        showToast("Text copied to clipboard")
    }

    public func copyBlock(_ block: RecognizedTextBlock) {
        let trimmed = block.text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        UIPasteboard.general.string = trimmed
        HapticFeedback.light()
        showToast("Copied text block")
    }

    public func selectBlock(_ block: RecognizedTextBlock) {
        HapticFeedback.selection()
        if selectedBlockId == block.id {
            selectedBlockId = nil
        } else {
            selectedBlockId = block.id
        }
    }

    public func clearRecognizedText() {
        HapticFeedback.light()
        recognizedBlocks = []
        recognizedFullText = ""
        selectedBlockId = nil
    }

    private func showToast(_ message: String) {
        toastDismissTask?.cancel()
        toastMessage = message
        toastDismissTask = Task {
            try? await Task.sleep(nanoseconds: 2_000_000_000)
            if !Task.isCancelled {
                self.toastMessage = nil
            }
        }
    }

    public func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        if UIApplication.shared.canOpenURL(url) {
            UIApplication.shared.open(url)
        }
    }
}
