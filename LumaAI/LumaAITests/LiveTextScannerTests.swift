import XCTest
import CoreGraphics
import UIKit
@testable import LumaAI

@MainActor
final class LiveTextScannerTests: XCTestCase {

    func testRecognizedTextBlockProperties() {
        let id = UUID()
        let rect = CGRect(x: 0.1, y: 0.2, width: 0.8, height: 0.05)
        let block = RecognizedTextBlock(
            id: id,
            text: "Hello Luma AI",
            normalizedRect: rect,
            confidence: 0.95
        )

        XCTAssertEqual(block.id, id)
        XCTAssertEqual(block.text, "Hello Luma AI")
        XCTAssertEqual(block.normalizedRect, rect)
        XCTAssertEqual(block.confidence, 0.95)
    }

    func testViewModelInitialState() {
        let vm = LiveTextScannerViewModel()
        XCTAssertEqual(vm.permissionStatus, .notDetermined)
        XCTAssertTrue(vm.recognizedBlocks.isEmpty)
        XCTAssertEqual(vm.recognizedFullText, "")
        XCTAssertNil(vm.selectedBlockId)
        XCTAssertNil(vm.toastMessage)
        XCTAssertFalse(vm.isScanning)
        XCTAssertFalse(vm.isTorchOn)
    }

    func testViewModelCopyAllText() {
        let vm = LiveTextScannerViewModel()
        vm.recognizedFullText = "Quantum computing relies on superposition and entanglement."

        vm.copyAllText()

        XCTAssertEqual(UIPasteboard.general.string, "Quantum computing relies on superposition and entanglement.")
        XCTAssertEqual(vm.toastMessage, "Text copied to clipboard")
    }

    func testViewModelCopyIndividualBlock() {
        let vm = LiveTextScannerViewModel()
        let block = RecognizedTextBlock(
            text: "Isolated text fragment",
            normalizedRect: .zero,
            confidence: 0.99
        )

        vm.copyBlock(block)

        XCTAssertEqual(UIPasteboard.general.string, "Isolated text fragment")
        XCTAssertEqual(vm.toastMessage, "Copied text block")
    }

    func testViewModelSelectAndToggleBlock() {
        let vm = LiveTextScannerViewModel()
        let block = RecognizedTextBlock(
            text: "Clickable block",
            normalizedRect: .zero,
            confidence: 0.90
        )

        vm.selectBlock(block)
        XCTAssertEqual(vm.selectedBlockId, block.id)

        // Tapping again deselects
        vm.selectBlock(block)
        XCTAssertNil(vm.selectedBlockId)
    }

    func testViewModelClearRecognizedText() {
        let vm = LiveTextScannerViewModel()
        let block = RecognizedTextBlock(
            text: "Temporary line",
            normalizedRect: .zero,
            confidence: 0.88
        )
        vm.recognizedBlocks = [block]
        vm.recognizedFullText = "Temporary line"
        vm.selectedBlockId = block.id

        vm.clearRecognizedText()

        XCTAssertTrue(vm.recognizedBlocks.isEmpty)
        XCTAssertEqual(vm.recognizedFullText, "")
        XCTAssertNil(vm.selectedBlockId)
    }

    func testSimulatorCameraServiceFeed() async {
        let service = LiveCameraService()
        XCTAssertTrue(service.isSimulator)

        let expectation = expectation(description: "Simulator observations callback received")
        service.onObservationsUpdated = { blocks, fullText, bufferSize in
            XCTAssertFalse(blocks.isEmpty)
            XCTAssertFalse(fullText.isEmpty)
            XCTAssertGreaterThan(bufferSize.width, 0)
            XCTAssertGreaterThan(bufferSize.height, 0)
            expectation.fulfill()
        }

        service.startSession()

        await fulfillment(of: [expectation], timeout: 2.0)
    }
}

