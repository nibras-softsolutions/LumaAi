import Foundation
import CoreGraphics

/// Represents a discrete block or line of text recognized from the camera feed.
public struct RecognizedTextBlock: Identifiable, Equatable, Hashable {
    public let id: UUID
    public let text: String
    /// Normalized coordinates in SwiftUI coordinate space (0,0 at top-left, 1,1 at bottom-right)
    public let normalizedRect: CGRect
    public let confidence: Float

    public init(
        id: UUID = UUID(),
        text: String,
        normalizedRect: CGRect,
        confidence: Float
    ) {
        self.id = id
        self.text = text
        self.normalizedRect = normalizedRect
        self.confidence = confidence
    }
}

