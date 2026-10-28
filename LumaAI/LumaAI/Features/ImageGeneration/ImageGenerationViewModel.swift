import Foundation
import SwiftUI
import Combine

@MainActor
public final class ImageGenerationViewModel: ObservableObject {
    @Published public var prompt: String = ""
    @Published public var selectedAspectRatio: String = "1:1"
    @Published public var isGenerating: Bool = false
    @Published public var generatedImage: ImageGenerateResponse?
    @Published public var errorMessage: String?

    public let aspectRatios: [(id: String, name: String, icon: String)] = [
        ("1:1", "Square", "square"),
        ("16:9", "Landscape", "rectangle.ratio.16.to.9"),
        ("9:16", "Portrait", "rectangle.portrait"),
        ("4:3", "Standard", "rectangle.ratio.4.to.3")
    ]

    private let apiClient: APIClientProtocol

    public init(apiClient: APIClientProtocol) {
        self.apiClient = apiClient
    }

    public func generate() async {
        let cleanPrompt = prompt.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanPrompt.isEmpty, !isGenerating else { return }

        isGenerating = true
        errorMessage = nil

        do {
            let response = try await apiClient.generateImage(prompt: cleanPrompt, aspectRatio: selectedAspectRatio)
            self.generatedImage = response
        } catch {
            self.errorMessage = error.localizedDescription
        }

        self.isGenerating = false
    }
}
