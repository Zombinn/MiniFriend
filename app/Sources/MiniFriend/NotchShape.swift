import SwiftUI

// 灵动岛形状：顶部两角「凹进外扩」（从刘海向下张开），底部大圆角。
// 改编自 MrKai77/DynamicNotchKit (MIT)。
struct NotchShape: Shape {
    var topCornerRadius: CGFloat
    var bottomCornerRadius: CGFloat

    var animatableData: AnimatablePair<CGFloat, CGFloat> {
        get { .init(topCornerRadius, bottomCornerRadius) }
        set { topCornerRadius = newValue.first; bottomCornerRadius = newValue.second }
    }

    func path(in rect: CGRect) -> Path {
        let t = topCornerRadius
        let b = bottomCornerRadius
        var p = Path()
        p.move(to: CGPoint(x: rect.minX, y: rect.minY))
        // 左上：向内凹的小圆角
        p.addQuadCurve(to: CGPoint(x: rect.minX + t, y: rect.minY + t),
                       control: CGPoint(x: rect.minX + t, y: rect.minY))
        // 左侧下行
        p.addLine(to: CGPoint(x: rect.minX + t, y: rect.maxY - b))
        // 左下大圆角
        p.addQuadCurve(to: CGPoint(x: rect.minX + t + b, y: rect.maxY),
                       control: CGPoint(x: rect.minX + t, y: rect.maxY))
        // 底边
        p.addLine(to: CGPoint(x: rect.maxX - t - b, y: rect.maxY))
        // 右下大圆角
        p.addQuadCurve(to: CGPoint(x: rect.maxX - t, y: rect.maxY - b),
                       control: CGPoint(x: rect.maxX - t, y: rect.maxY))
        // 右侧上行
        p.addLine(to: CGPoint(x: rect.maxX - t, y: rect.minY + t))
        // 右上凹角
        p.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.minY),
                       control: CGPoint(x: rect.maxX - t, y: rect.minY))
        p.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        return p
    }
}
