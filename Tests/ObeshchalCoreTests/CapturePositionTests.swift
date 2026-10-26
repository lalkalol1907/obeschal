import CoreGraphics
import Testing
import ObeshchalCore

@Test func allNineCapturePositionsUseMacScreenCoordinates() {
    let screen = CGRect(x: 100, y: 200, width: 1_000, height: 800)
    let size = CGSize(width: 200, height: 100)
    let expected: [(CapturePosition, CGFloat, CGFloat)] = [
        (.topLeft, 124, 876), (.topCenter, 500, 876), (.topRight, 876, 876),
        (.centerLeft, 124, 550), (.center, 500, 550), (.centerRight, 876, 550),
        (.bottomLeft, 124, 224), (.bottomCenter, 500, 224), (.bottomRight, 876, 224)
    ]
    #expect(expected.count == CapturePosition.allCases.count)
    for (position, x, y) in expected {
        #expect(position.frame(for: size, in: screen) == CGRect(x: x, y: y, width: 200, height: 100))
        #expect(position.id == position.rawValue)
        #expect(!position.title.isEmpty)
    }
}

@Test func capturePositionsHonorCustomInsetsAndNegativeMonitorCoordinates() {
    let screen = CGRect(x: -1_440, y: -900, width: 1_440, height: 900)
    let size = CGSize(width: 640, height: 500)
    #expect(CapturePosition.topRight.frame(for: size, in: screen) == CGRect(x: -664, y: -524, width: 640, height: 500))
    #expect(CapturePosition.bottomLeft.frame(for: size, in: screen, margin: 40) == CGRect(x: -1_400, y: -860, width: 640, height: 500))
    #expect(CapturePosition.center.frame(for: size, in: screen) == CGRect(x: -1_040, y: -700, width: 640, height: 500))
}

@Test func resizingCaptureHeightPreservesChosenVerticalAnchor() {
    let screen = CGRect(x: -1_440, y: 0, width: 1_440, height: 900)
    for position in CapturePosition.allCases {
        let original = position.frame(for: CGSize(width: 640, height: 300), in: screen)
        let resized = position.frame(for: CGSize(width: 640, height: 600), in: screen)
        #expect(original.minX == resized.minX)
        switch position {
        case .topLeft, .topCenter, .topRight:
            #expect(original.maxY == resized.maxY)
        case .centerLeft, .center, .centerRight:
            #expect(original.midY == resized.midY)
        case .bottomLeft, .bottomCenter, .bottomRight:
            #expect(original.minY == resized.minY)
        }
    }
}

@Test func captureMarginsShrinkWhenWindowNearlyFillsScreen() {
    let screen = CGRect(x: 10, y: 20, width: 500, height: 300)
    for position in CapturePosition.allCases {
        #expect(position.frame(for: CGSize(width: 480, height: 290), in: screen) == CGRect(x: 20, y: 25, width: 480, height: 290))
        #expect(position.frame(for: screen.size, in: screen) == screen)
    }
}

@Test func oversizedCapturePinsLeftAndKeepsHeaderAtTop() {
    let tinyScreen = CGRect(x: -90, y: -80, width: 30, height: 20)
    for position in CapturePosition.allCases {
        let frame = position.frame(for: CGSize(width: 50, height: 40), in: tinyScreen)
        #expect(frame == CGRect(x: -90, y: -100, width: 50, height: 40))
        #expect(frame.minX == tinyScreen.minX)
        #expect(frame.maxY == tinyScreen.maxY)
    }
    let screen = CGRect(x: 100, y: 200, width: 300, height: 300)
    #expect(CapturePosition.bottomRight.frame(for: CGSize(width: 350, height: 100), in: screen) == CGRect(x: 100, y: 224, width: 350, height: 100))
    #expect(CapturePosition.bottomRight.frame(for: CGSize(width: 100, height: 350), in: screen) == CGRect(x: 276, y: 150, width: 100, height: 350))
}
