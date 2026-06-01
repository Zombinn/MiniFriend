// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MiniFriend",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MiniFriend",
            path: "Sources/MiniFriend",
            resources: [.process("Resources")],
            linkerSettings: [
                // 把 Info.plist 编进可执行文件（麦克风/语音识别权限说明）
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Info.plist",
                ])
            ]
        )
    ]
)
