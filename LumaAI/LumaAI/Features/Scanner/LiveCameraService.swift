import Foundation
import AVFoundation
import Vision
import UIKit

/// Background AVFoundation & Apple Vision pipeline for real-time camera text recognition.
public final class LiveCameraService: NSObject, ObservableObject, AVCaptureVideoDataOutputSampleBufferDelegate {
    public let captureSession = AVCaptureSession()

    private let sessionQueue = DispatchQueue(label: "com.lumaai.camera.session.queue")
    private let ocrQueue = DispatchQueue(label: "com.lumaai.camera.ocr.queue", qos: .userInitiated)

    private var videoDevice: AVCaptureDevice?
    private var videoInput: AVCaptureDeviceInput?
    private var videoOutput: AVCaptureVideoDataOutput?

    private var isConfigured = false
    private var isProcessing = false
    private var isStopped = false
    private var lastProcessedTimestamp: CFTimeInterval = 0
    private let minProcessInterval: CFTimeInterval = 0.25 // Throttled to ~4 FPS to save battery & CPU

    private var simulatorTimer: Timer?

    #if targetEnvironment(simulator)
    public let isSimulator = true
    #else
    public let isSimulator = false
    #endif

    /// Callback delivering recognized blocks, formatted full text, and the camera buffer size for coordinate mapping.
    public var onObservationsUpdated: (([RecognizedTextBlock], String, CGSize) -> Void)?

    public override init() {
        super.init()
    }

    deinit {
        // Safe deallocation: Capture AVCaptureSession strongly by value without forming
        // any weak self references to an object currently in deinit (which crashes objc_fatal).
        let session = self.captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
        simulatorTimer?.invalidate()
    }

    // MARK: - Session Configuration

    public func configureSession(completion: @escaping (Bool) -> Void) {
        if isSimulator {
            DispatchQueue.main.async {
                completion(true)
            }
            return
        }

        sessionQueue.async { [weak self] in
            guard let self = self else { return }
            if self.isConfigured {
                DispatchQueue.main.async { completion(true) }
                return
            }

            self.captureSession.beginConfiguration()
            self.captureSession.sessionPreset = .high

            // Locate standard back camera
            guard let camera = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
                print("[LumaAI] LiveCameraService: No back camera available.")
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }
            self.videoDevice = camera

            do {
                let input = try AVCaptureDeviceInput(device: camera)
                if self.captureSession.canAddInput(input) {
                    self.captureSession.addInput(input)
                    self.videoInput = input
                } else {
                    print("[LumaAI] LiveCameraService: Could not add video input.")
                    self.captureSession.commitConfiguration()
                    DispatchQueue.main.async { completion(false) }
                    return
                }
            } catch {
                print("[LumaAI] LiveCameraService: Error creating device input: \(error.localizedDescription)")
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }

            let output = AVCaptureVideoDataOutput()
            output.alwaysDiscardsLateVideoFrames = true
            output.videoSettings = [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA)
            ]
            output.setSampleBufferDelegate(self, queue: self.ocrQueue)

            if self.captureSession.canAddOutput(output) {
                self.captureSession.addOutput(output)
                self.videoOutput = output

                if let connection = output.connection(with: .video) {
                    if connection.isVideoOrientationSupported {
                        connection.videoOrientation = .portrait
                    }
                }
            } else {
                print("[LumaAI] LiveCameraService: Could not add video output.")
                self.captureSession.commitConfiguration()
                DispatchQueue.main.async { completion(false) }
                return
            }

            self.captureSession.commitConfiguration()
            self.isConfigured = true

            DispatchQueue.main.async {
                completion(true)
            }
        }
    }

    // MARK: - Session Control

    public func startSession() {
        isStopped = false

        if isSimulator {
            startSimulatorDemoFeed()
            return
        }

        let session = self.captureSession
        sessionQueue.async {
            guard !session.isRunning else { return }
            session.startRunning()
        }
    }

    public func stopSession() {
        isStopped = true
        onObservationsUpdated = nil
        simulatorTimer?.invalidate()
        simulatorTimer = nil

        // Turn off torch if active
        if let device = videoDevice, device.hasTorch {
            do {
                try device.lockForConfiguration()
                if device.isTorchActive {
                    device.torchMode = .off
                }
                device.unlockForConfiguration()
            } catch {
                // Ignore configuration error during teardown
            }
        }

        let session = self.captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    public func pause() {
        isStopped = true
        let session = self.captureSession
        sessionQueue.async {
            if session.isRunning {
                session.stopRunning()
            }
        }
    }

    public func resume() {
        isStopped = false
        if isSimulator {
            startSimulatorDemoFeed()
            return
        }

        let session = self.captureSession
        sessionQueue.async {
            if !session.isRunning {
                session.startRunning()
            }
        }
    }

    // MARK: - Torch Control

    public var isTorchAvailable: Bool {
        guard let device = videoDevice else { return false }
        return device.hasTorch && device.isTorchAvailable
    }

    public func setTorch(enabled: Bool) {
        guard let device = videoDevice, isTorchAvailable else { return }
        sessionQueue.async {
            do {
                try device.lockForConfiguration()
                device.torchMode = enabled ? .on : .off
                device.unlockForConfiguration()
            } catch {
                print("[LumaAI] LiveCameraService: Torch error: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - AVCaptureVideoDataOutputSampleBufferDelegate

    public func captureOutput(
        _ output: AVCaptureOutput,
        didOutput sampleBuffer: CMSampleBuffer,
        from connection: AVCaptureConnection
    ) {
        // Discard frames if stopped, if another OCR request is in flight, or throttled
        guard !isStopped else { return }
        let now = CACurrentMediaTime()
        guard !isProcessing, (now - lastProcessedTimestamp) >= minProcessInterval else {
            return
        }

        guard let pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer) else {
            return
        }

        isProcessing = true
        lastProcessedTimestamp = now

        let bufferWidth = CGFloat(CVPixelBufferGetWidth(pixelBuffer))
        let bufferHeight = CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        let bufferSize = CGSize(width: bufferWidth, height: bufferHeight)

        let request = VNRecognizeTextRequest { [weak self] request, error in
            defer { self?.isProcessing = false }

            guard let self = self, !self.isStopped else { return }

            if let error = error {
                print("[LumaAI] LiveCameraService: Vision error: \(error.localizedDescription)")
                return
            }

            guard let observations = request.results as? [VNRecognizedTextObservation], !observations.isEmpty else {
                DispatchQueue.main.async { [weak self] in
                    guard let self = self, !self.isStopped else { return }
                    self.onObservationsUpdated?([], "", bufferSize)
                }
                return
            }

            self.processObservations(observations, bufferSize: bufferSize)
        }

        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true

        // Because connection.videoOrientation is configured as .portrait,
        // the CVPixelBuffer is already oriented upright. Using orientation .up
        // ensures text is recognized horizontally and bounding boxes match physical coordinates.
        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            isProcessing = false
            print("[LumaAI] LiveCameraService: Request handler error: \(error.localizedDescription)")
        }
    }

    // MARK: - Geometry & Reading Order Parsing

    private func processObservations(_ observations: [VNRecognizedTextObservation], bufferSize: CGSize) {
        guard !isStopped else { return }

        var blocks: [RecognizedTextBlock] = []

        for obs in observations {
            guard let candidate = obs.topCandidates(1).first else { continue }
            let text = candidate.string.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }

            // In Vision coordinates, (0,0) is bottom-left.
            // In UIKit/SwiftUI coordinates, (0,0) is top-left.
            // Converting normalized coordinates:
            // minX remains minX (left edge)
            // minY in top-left space is (1.0 - maxY) (top edge of text)
            // width is box.width
            // height is box.height
            let box = obs.boundingBox
            let normalizedRect = CGRect(
                x: box.minX,
                y: 1.0 - box.maxY,
                width: box.width,
                height: box.height
            )

            blocks.append(
                RecognizedTextBlock(
                    text: text,
                    normalizedRect: normalizedRect,
                    confidence: candidate.confidence
                )
            )
        }

        // Sort observations into a natural reading order (top-to-bottom, left-to-right)
        let sortedBlocks = sortBlocksInReadingOrder(blocks)

        // Assemble formatted full text
        let fullText = assembleFormattedText(from: sortedBlocks)

        DispatchQueue.main.async { [weak self] in
            guard let self = self, !self.isStopped else { return }
            self.onObservationsUpdated?(sortedBlocks, fullText, bufferSize)
        }
    }

    /// Clusters recognized text blocks that belong to the same visual line, sorting top-to-bottom and left-to-right.
    private func sortBlocksInReadingOrder(_ blocks: [RecognizedTextBlock]) -> [RecognizedTextBlock] {
        guard !blocks.isEmpty else { return [] }

        // Sort primarily by vertical position (top of screen to bottom)
        let sortedByY = blocks.sorted { $0.normalizedRect.minY < $1.normalizedRect.minY }

        var lines: [[RecognizedTextBlock]] = []
        let verticalLineThreshold: CGFloat = 0.02 // Normalized vertical distance for same line

        for block in sortedByY {
            if let lastLineIndex = lines.indices.last {
                let lineRepresentative = lines[lastLineIndex][0]
                if abs(block.normalizedRect.midY - lineRepresentative.normalizedRect.midY) < verticalLineThreshold {
                    lines[lastLineIndex].append(block)
                    continue
                }
            }
            lines.append([block])
        }

        // Sort items horizontally within each line (left to right)
        var result: [RecognizedTextBlock] = []
        for var line in lines {
            line.sort { $0.normalizedRect.minX < $1.normalizedRect.minX }
            result.append(contentsOf: line)
        }

        return result
    }

    /// Assembles individual blocks into clean, deduplicated multi-line text preserving paragraphs and reading order.
    private func assembleFormattedText(from blocks: [RecognizedTextBlock]) -> String {
        guard !blocks.isEmpty else { return "" }

        var lines: [[String]] = []
        var lastMidY: CGFloat?
        let lineThreshold: CGFloat = 0.02

        for block in blocks {
            let midY = block.normalizedRect.midY
            if let prevY = lastMidY, abs(midY - prevY) < lineThreshold {
                if let lastIndex = lines.indices.last {
                    lines[lastIndex].append(block.text)
                }
            } else {
                lines.append([block.text])
                lastMidY = midY
            }
        }

        // Join words in line with spaces, deduplicate adjacent identical lines
        var cleanedLines: [String] = []
        for lineWords in lines {
            let lineString = lineWords.joined(separator: " ").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !lineString.isEmpty else { continue }
            if cleanedLines.last != lineString {
                cleanedLines.append(lineString)
            }
        }

        return cleanedLines.joined(separator: "\n")
    }

    // MARK: - Simulator Fallback

    private func startSimulatorDemoFeed() {
        guard !isStopped else { return }

        // Realistic horizontal text blocks matching physical Vision OCR dimensions
        let demoBlocks = [
            RecognizedTextBlock(
                text: "Luma AI Intelligent Document Scanner",
                normalizedRect: CGRect(x: 0.10, y: 0.26, width: 0.80, height: 0.035),
                confidence: 0.98
            ),
            RecognizedTextBlock(
                text: "Real-time on-device Vision OCR engine",
                normalizedRect: CGRect(x: 0.12, y: 0.32, width: 0.76, height: 0.030),
                confidence: 0.95
            ),
            RecognizedTextBlock(
                text: "Extracting insights directly from your environment",
                normalizedRect: CGRect(x: 0.08, y: 0.38, width: 0.84, height: 0.035),
                confidence: 0.92
            )
        ]

        let fullText = demoBlocks.map { $0.text }.joined(separator: "\n")
        let bufferSize = CGSize(width: 1080, height: 1920)

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            guard let self = self, !self.isStopped else { return }
            self.onObservationsUpdated?(demoBlocks, fullText, bufferSize)
        }
    }
}
