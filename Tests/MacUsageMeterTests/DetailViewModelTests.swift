import XCTest
import AppKit
@testable import MacUsageMeter

final class DetailViewModelTests: XCTestCase {

    @MainActor
    func testResolveSavePanelWindow_prefersPresentingWindow() {
        let presentingWindow = makeWindow()
        let keyWindow = makeWindow()
        let mainWindow = makeWindow()

        let resolved = resolveSavePanelWindow(
            presentingWindow: presentingWindow,
            keyWindow: keyWindow,
            mainWindow: mainWindow
        )

        XCTAssertTrue(resolved === presentingWindow)
    }

    @MainActor
    func testResolveSavePanelWindow_fallsBackToKeyWindow() {
        let keyWindow = makeWindow()
        let mainWindow = makeWindow()

        let resolved = resolveSavePanelWindow(
            presentingWindow: nil,
            keyWindow: keyWindow,
            mainWindow: mainWindow
        )

        XCTAssertTrue(resolved === keyWindow)
    }

    @MainActor
    func testResolveSavePanelWindow_fallsBackToMainWindow() {
        let mainWindow = makeWindow()

        let resolved = resolveSavePanelWindow(
            presentingWindow: nil,
            keyWindow: nil,
            mainWindow: mainWindow
        )

        XCTAssertTrue(resolved === mainWindow)
    }

    @MainActor
    private func makeWindow() -> NSWindow {
        NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 400, height: 300),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
    }
}
