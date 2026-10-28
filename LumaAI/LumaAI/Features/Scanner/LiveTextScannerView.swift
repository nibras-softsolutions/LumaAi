import SwiftUI
import AVFoundation

/// Full-screen live camera-to-text OCR interface with real-time text bounding boxes,
/// clipboard copy, and direct insertion into Luma AI chat.
public struct LiveTextScannerView: View {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var viewModel = LiveTextScannerViewModel()

    let onInsertText: (String) -> Void
    let onDismiss: () -> Void

    @State private var pulseIndicator = false

    public init(
        onInsertText: @escaping (String) -> Void,
        onDismiss: @escaping () -> Void
    ) {
        self.onInsertText = onInsertText
        self.onDismiss = onDismiss
    }

    public var body: some View {
        ZStack {
            // Camera feed or permission screen
            if viewModel.permissionStatus == .denied {
                permissionDeniedView
            } else {
                cameraScanningView
            }

            // Top Floating Toast Confirmation
            if let toast = viewModel.toastMessage {
                VStack {
                    HStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 15))
                            .foregroundColor(.lumaSuccess)
                        Text(toast)
                            .font(LumaTypography.captionMedium)
                            .foregroundColor(.lumaPrimaryText)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .background(Color.lumaSurface)
                    .clipShape(Capsule())
                    .overlay(Capsule().stroke(Color.lumaBorder, lineWidth: 1))
                    .shadow(color: Color.black.opacity(0.12), radius: 8, x: 0, y: 4)
                    .padding(.top, 56)
                    .transition(.move(edge: .top).combined(with: .opacity))

                    Spacer()
                }
                .zIndex(10)
            }
        }
        .onAppear {
            viewModel.onAppear()
        }
        .onDisappear {
            viewModel.onDisappear()
        }
        .onChange(of: scenePhase) { phase in
            switch phase {
            case .active:
                viewModel.resumeScanning()
            case .background, .inactive:
                viewModel.pauseScanning()
            @unknown default:
                break
            }
        }
    }

    // MARK: - Camera Scanning View

    private var cameraScanningView: some View {
        GeometryReader { geometry in
            ZStack(alignment: .bottom) {
                // Layer 1: Live Video Feed
                CameraPreviewView(
                    session: viewModel.cameraService.captureSession,
                    isSimulator: viewModel.cameraService.isSimulator
                )
                .ignoresSafeArea()

                // Simulator fallback background visualizer
                if viewModel.cameraService.isSimulator {
                    simulatorMockBackground
                }

                // Layer 2: Live Bounding Box Highlights
                textBoundingBoxesOverlay(size: geometry.size)

                // Layer 3: Central Reticle Guide (Subtle scan visualizer)
                scannerCenterReticle
                    .allowsHitTesting(false)

                // Layer 4: Top Control Bar
                VStack {
                    topControlBar
                    Spacer()
                }

                // Layer 5: Bottom Interactive OCR Panel
                bottomControlPanel
            }
        }
        .statusBarHidden(false)
    }

    // MARK: - Top Control Bar

    private var topControlBar: some View {
        HStack(spacing: 12) {
            // Close Button
            Button(action: {
                HapticFeedback.light()
                viewModel.stopScanning()
                onDismiss()
            }) {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(.white)
                    .frame(width: 40, height: 40)
                    .background(Color.black.opacity(0.45))
                    .clipShape(Circle())
            }

            Spacer()

            // Status Badge
            HStack(spacing: 6) {
                Circle()
                    .fill(Color.green)
                    .frame(width: 7, height: 7)
                    .scaleEffect(pulseIndicator ? 1.2 : 0.8)
                    .animation(.easeInOut(duration: 0.8).repeatForever(autoreverses: true), value: pulseIndicator)

                Text(viewModel.recognizedBlocks.isEmpty ? "Scanning…" : "\(viewModel.recognizedBlocks.count) lines found")
                    .font(LumaTypography.captionMedium)
                    .foregroundColor(.white)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.45))
            .clipShape(Capsule())
            .onAppear {
                pulseIndicator = true
            }

            Spacer()

            // Torch Toggle (if available)
            if viewModel.isTorchAvailable {
                Button(action: {
                    viewModel.toggleTorch()
                }) {
                    Image(systemName: viewModel.isTorchOn ? "flashlight.on.fill" : "flashlight.off.fill")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(viewModel.isTorchOn ? .yellow : .white)
                        .frame(width: 40, height: 40)
                        .background(Color.black.opacity(0.45))
                        .clipShape(Circle())
                }
            } else {
                // Spacer placeholder to balance the close button
                Color.clear
                    .frame(width: 40, height: 40)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    // MARK: - Center Reticle Guide

    private var scannerCenterReticle: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .stroke(Color.white.opacity(0.35), style: StrokeStyle(lineWidth: 1.5, dash: [8, 6]))
                .frame(maxWidth: .infinity, maxHeight: 220)
                .padding(.horizontal, 32)
                .padding(.bottom, 220)
        }
    }

    // MARK: - Text Bounding Box Highlights

    private func textBoundingBoxesOverlay(size: CGSize) -> some View {
        ZStack(alignment: .topLeading) {
            ForEach(viewModel.recognizedBlocks) { block in
                let rect = convertToScreenRect(
                    normalizedRect: block.normalizedRect,
                    viewSize: size,
                    bufferSize: viewModel.videoBufferSize
                )

                let isSelected = (viewModel.selectedBlockId == block.id)

                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .stroke(
                        isSelected ? Color.lumaAccent : Color.white.opacity(0.85),
                        lineWidth: isSelected ? 2 : 1
                    )
                    .background(
                        (isSelected ? Color.lumaAccent : Color.white)
                            .opacity(isSelected ? 0.22 : 0.10)
                    )
                    .frame(width: max(rect.width, 24), height: max(rect.height, 14))
                    .position(x: rect.midX, y: rect.midY)
                    .onTapGesture {
                        viewModel.selectBlock(block)
                    }
            }
        }
        .allowsHitTesting(true)
    }

    /// Converts normalized Vision coordinates [0...1] into camera preview coordinates,
    /// precisely compensating for `.resizeAspectFill` scaling and edge cropping.
    private func convertToScreenRect(
        normalizedRect: CGRect,
        viewSize: CGSize,
        bufferSize: CGSize
    ) -> CGRect {
        guard bufferSize.width > 0, bufferSize.height > 0, viewSize.width > 0, viewSize.height > 0 else {
            return CGRect(
                x: normalizedRect.minX * viewSize.width,
                y: normalizedRect.minY * viewSize.height,
                width: normalizedRect.width * viewSize.width,
                height: normalizedRect.height * viewSize.height
            )
        }

        // With .resizeAspectFill, the camera feed uniformly fills the screen bounds,
        // cropping the excess dimension symmetrically around the center.
        let scale = max(viewSize.width / bufferSize.width, viewSize.height / bufferSize.height)
        let scaledWidth = bufferSize.width * scale
        let scaledHeight = bufferSize.height * scale

        let offsetX = (viewSize.width - scaledWidth) / 2.0
        let offsetY = (viewSize.height - scaledHeight) / 2.0

        let screenX = normalizedRect.minX * scaledWidth + offsetX
        let screenY = normalizedRect.minY * scaledHeight + offsetY
        let screenWidth = normalizedRect.width * scaledWidth
        let screenHeight = normalizedRect.height * scaledHeight

        return CGRect(
            x: screenX,
            y: screenY,
            width: screenWidth,
            height: screenHeight
        )
    }

    // MARK: - Bottom Control Panel

    private var bottomControlPanel: some View {
        VStack(spacing: 12) {
            // Drag Indicator Handle
            RoundedRectangle(cornerRadius: 3)
                .fill(Color.lumaBorder)
                .frame(width: 36, height: 4)
                .padding(.top, 8)

            if viewModel.recognizedBlocks.isEmpty {
                // Empty state
                VStack(spacing: 8) {
                    Image(systemName: "text.viewfinder")
                        .font(.system(size: 28, weight: .light))
                        .foregroundColor(.lumaSecondaryText)
                        .padding(.top, 4)

                    Text("Point your camera at some text")
                        .font(LumaTypography.headline)
                        .foregroundColor(.lumaPrimaryText)

                    Text("Detected text will appear here automatically in real time.")
                        .font(LumaTypography.caption)
                        .foregroundColor(.lumaSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 24)
                }
                .frame(height: 110)
            } else {
                // Detected Text Content
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("RECOGNIZED TEXT")
                            .font(LumaTypography.caption)
                            .foregroundColor(.lumaSecondaryText)

                        Spacer()

                        Button(action: {
                            viewModel.clearRecognizedText()
                        }) {
                            Text("Clear")
                                .font(LumaTypography.caption)
                                .foregroundColor(.lumaSecondaryText)
                        }
                    }

                    // Scrollable Text Preview
                    ScrollView(.vertical, showsIndicators: true) {
                        Text(viewModel.recognizedFullText)
                            .font(LumaTypography.subheadline)
                            .foregroundColor(.lumaPrimaryText)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
                    }
                    .frame(height: 80)
                    .background(Color.lumaSurfaceElevated)
                    .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

                    // Individual Block Chips (tap to copy individual line)
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 6) {
                            ForEach(viewModel.recognizedBlocks) { block in
                                Button(action: {
                                    viewModel.copyBlock(block)
                                }) {
                                    HStack(spacing: 4) {
                                        Text(block.text)
                                            .font(LumaTypography.caption)
                                            .lineLimit(1)
                                        Image(systemName: "doc.on.doc")
                                            .font(.system(size: 9))
                                    }
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(viewModel.selectedBlockId == block.id ? Color.lumaAccentLight : Color.lumaSurfaceElevated)
                                    .foregroundColor(viewModel.selectedBlockId == block.id ? .lumaAccent : .lumaPrimaryText)
                                    .clipShape(Capsule())
                                    .overlay(
                                        Capsule()
                                            .stroke(viewModel.selectedBlockId == block.id ? Color.lumaAccent : Color.lumaBorder, lineWidth: 1)
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // Primary Action Buttons (Side by Side)
            HStack(spacing: 12) {
                // Button 1: Copy Text
                Button(action: {
                    viewModel.copyAllText()
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "doc.on.doc")
                            .font(.system(size: 15, weight: .medium))
                        Text("Copy Text")
                            .font(LumaTypography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.lumaSurfaceElevated)
                    .foregroundColor(.lumaPrimaryText)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(Color.lumaBorder, lineWidth: 1)
                    )
                }
                .disabled(viewModel.recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)

                // Button 2: Ask Luma
                Button(action: {
                    let text = viewModel.recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines)
                    guard !text.isEmpty else { return }
                    HapticFeedback.light()
                    // Stop camera session first before triggering dismissal/insertion
                    viewModel.stopScanning()
                    onInsertText(text)
                }) {
                    HStack(spacing: 8) {
                        Image(systemName: "sparkle")
                            .font(.system(size: 15, weight: .medium))
                        Text("Ask Luma")
                            .font(LumaTypography.bodyMedium)
                    }
                    .frame(maxWidth: .infinity)
                    .frame(height: 48)
                    .background(Color.lumaPrimaryText)
                    .foregroundColor(Color.lumaSurface)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
                }
                .disabled(viewModel.recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .opacity(viewModel.recognizedFullText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1.0)
            }
            .padding(.top, 4)

            // Privacy Footnote
            HStack(spacing: 5) {
                Image(systemName: "lock.shield.fill")
                    .font(.system(size: 11))
                    .foregroundColor(.lumaTertiaryText)
                Text("On-device OCR · Live frames are processed locally and never stored or uploaded")
                    .font(LumaTypography.caption)
                    .foregroundColor(.lumaTertiaryText)
            }
            .padding(.top, 2)
            .padding(.bottom, 6)
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 12)
        .background(
            Color.lumaSurface
                .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                .shadow(color: Color.black.opacity(0.18), radius: 16, x: 0, y: -4)
                .ignoresSafeArea(edges: .bottom)
        )
    }

    // MARK: - Simulator Mock View

    private var simulatorMockBackground: some View {
        ZStack {
            LinearGradient(
                colors: [Color(white: 0.12), Color(white: 0.22), Color(white: 0.16)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            )
            .ignoresSafeArea()

            VStack(spacing: 12) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 44, weight: .light))
                    .foregroundColor(.white.opacity(0.7))

                Text("Live Camera Feed")
                    .font(LumaTypography.headline)
                    .foregroundColor(.white)

                Text("Simulator Mode: Demo OCR data loaded for preview & testing.\nConnect a physical iPhone for live camera stream.")
                    .font(LumaTypography.caption)
                    .foregroundColor(.white.opacity(0.65))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }
            .padding(.bottom, 160)
        }
    }

    // MARK: - Permission Denied View

    private var permissionDeniedView: some View {
        ZStack {
            Color.lumaCanvas
                .ignoresSafeArea()

            VStack(spacing: 20) {
                HStack {
                    Button(action: {
                        viewModel.stopScanning()
                        onDismiss()
                    }) {
                        Image(systemName: "xmark")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundColor(.lumaPrimaryText)
                            .frame(width: 40, height: 40)
                            .background(Color.lumaSurfaceElevated)
                            .clipShape(Circle())
                    }
                    Spacer()
                }
                .padding(.horizontal, 16)
                .padding(.top, 16)

                Spacer()

                Circle()
                    .fill(Color.lumaSurfaceElevated)
                    .frame(width: 80, height: 80)
                    .overlay(
                        Image(systemName: "camera.fill")
                            .font(.system(size: 32))
                            .foregroundColor(.lumaSecondaryText)
                    )

                VStack(spacing: 8) {
                    Text("Camera Access Required")
                        .font(LumaTypography.title)
                        .foregroundColor(.lumaPrimaryText)

                    Text("Luma AI needs permission to use your camera to scan and recognize text directly from your environment.")
                        .font(LumaTypography.subheadline)
                        .foregroundColor(.lumaSecondaryText)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 32)
                }

                Button(action: {
                    HapticFeedback.light()
                    viewModel.openSettings()
                }) {
                    Text("Open Settings")
                        .font(LumaTypography.bodyMedium)
                        .frame(maxWidth: .infinity)
                        .frame(height: 50)
                        .background(Color.lumaPrimaryText)
                        .foregroundColor(Color.lumaSurface)
                        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
                }
                .padding(.horizontal, 24)
                .padding(.top, 8)

                Spacer()
            }
        }
    }
}
