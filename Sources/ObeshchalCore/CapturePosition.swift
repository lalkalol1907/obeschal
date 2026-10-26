import CoreGraphics
import Foundation

public enum CapturePosition: String, CaseIterable, Identifiable, Sendable {
    case topLeft, topCenter, topRight
    case centerLeft, center, centerRight
    case bottomLeft, bottomCenter, bottomRight

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .topLeft: return "Сверху слева"
        case .topCenter: return "Сверху по центру"
        case .topRight: return "Сверху справа"
        case .centerLeft: return "Слева по центру"
        case .center: return "По центру"
        case .centerRight: return "Справа по центру"
        case .bottomLeft: return "Снизу слева"
        case .bottomCenter: return "Снизу по центру"
        case .bottomRight: return "Снизу справа"
        }
    }

    public func frame(for size: CGSize, in visibleFrame: CGRect, margin: CGFloat = 24) -> CGRect {
        let horizontalInset = min(max(0, margin), max(0, visibleFrame.width - size.width) / 2)
        let verticalInset = min(max(0, margin), max(0, visibleFrame.height - size.height) / 2)
        let x: CGFloat
        if size.width > visibleFrame.width {
            x = visibleFrame.minX
        } else {
            switch self {
            case .topLeft, .centerLeft, .bottomLeft:
                x = visibleFrame.minX + horizontalInset
            case .topCenter, .center, .bottomCenter:
                x = visibleFrame.midX - size.width / 2
            case .topRight, .centerRight, .bottomRight:
                x = visibleFrame.maxX - size.width - horizontalInset
            }
        }
        let y: CGFloat
        if size.height > visibleFrame.height {
            y = visibleFrame.maxY - size.height
        } else {
            switch self {
            case .topLeft, .topCenter, .topRight:
                y = visibleFrame.maxY - size.height - verticalInset
            case .centerLeft, .center, .centerRight:
                y = visibleFrame.midY - size.height / 2
            case .bottomLeft, .bottomCenter, .bottomRight:
                y = visibleFrame.minY + verticalInset
            }
        }
        return CGRect(origin: CGPoint(x: x, y: y), size: size)
    }
}
