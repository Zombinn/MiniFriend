import SwiftUI

// 像素角色头像。单张 sprite + 程序化运动动画（无需多帧）：
//   待机 = 缓慢呼吸上下浮动；说话 = 快速弹跳 + 轻微挤压；思考 = 小幅抖动。
// 之后可换成多帧 sprite（眨眼/张嘴）做更精细的动态。
struct PixelAvatar: View {
    let size: CGFloat
    let speaking: Bool
    let thinking: Bool
    var resource: String = "avatar_head"     // 收起用头部版；展开传 "avatar_pixel" 全身版

    private var image: NSImage? {
        guard let url = Bundle.module.url(forResource: resource, withExtension: "png")
        else { return nil }
        return NSImage(contentsOf: url)
    }

    var body: some View {
        TimelineView(.animation) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            let (dy, sx, sy) = motion(t)
            sprite
                .frame(width: size, height: size)
                .scaleEffect(x: sx, y: sy, anchor: .bottom)
                .offset(y: dy)
        }
        .frame(width: size, height: size)
    }

    @ViewBuilder private var sprite: some View {
        if let img = image {
            Image(nsImage: img)
                .interpolation(.none)          // 保持像素硬边
                .resizable()
                .aspectRatio(contentMode: .fit)
        } else {
            RoundedRectangle(cornerRadius: 4).fill(.cyan)
        }
    }

    // 返回 (垂直偏移, x 缩放, y 缩放)
    private func motion(_ t: TimeInterval) -> (CGFloat, CGFloat, CGFloat) {
        if speaking {
            // 快速弹跳 + 挤压拉伸（说话感）
            let b = sin(t * 16)
            let dy = -abs(b) * 2.0
            let squash = b * 0.06
            return (dy, 1 - squash, 1 + squash)
        }
        if thinking {
            // 小幅左右/上下抖动
            let dy = sin(t * 6) * 0.8
            return (dy, 1, 1)
        }
        // 待机缓慢呼吸
        let breathe = sin(t * 1.8)
        return (breathe * 1.0, 1, 1 + breathe * 0.015)
    }
}
