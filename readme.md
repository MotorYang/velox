Spec-SwiftTerminal: macOS Native Minimalist Terminal with SSH & SFTP本项目是一款专为 macOS 设计的 100% 纯 Swift 原生、极简沉浸式终端工具。它旨在提供媲美 Ghostty / Alacritty 的极致渲染性能与毛玻璃视觉，并在无任何 C 语言桥接（无 libssh2 依赖）的纯安全 Swift 环境下，通过底层异步网络框架实现无缝嵌入的 SSH 与 SFTP 传输功能。这份文档作为 Codex / LLM 编程智能体的上下文输入（System Prompt / Architecture Spec），定义了整个项目的技术栈、数据流、UI/UX 动线及核心组件的实现蓝图。🛠️ 1. 技术栈选型 (Technical Stack)为了确保 100% 纯 Swift 闭环与极致的原生性能，拒绝引入任何 C 动态链接库：开发语言： Swift 5.10+ / Swift 6 (开启严格并发安全检查)UI 框架： SwiftUI (声明式现代 UI) + AppKit (用于高吞吐量窗口事件、底层键位映射)终端渲染引擎： SwiftTerm (100% Swift 编写的 VT100/Xterm 状态机解析与像素渲染控件)网络与安全传输底座： SwiftNIO (Apple 官方高性能非阻塞事件驱动网络框架)SSH / SFTP 协议栈： Citadel (基于 SwiftNIO SSH 封装的现代化纯 Swift 异步 SSH/SFTP 客户端库)本地数据存储： SwiftData (用于持久化保存服务器节点、分组与历史会话)安全凭证存储： macOS Native Keychain (用于加密存储 SSH 密码与私钥)SPM (Swift Package Manager) 依赖声明dependencies: [
    .package(url: "[https://github.com/krzyzanowskim/OpenSwiftTerm.git](https://github.com/krzyzanowskim/OpenSwiftTerm.git)", from: "1.0.0"), // 终端渲染与解析
    .package(url: "[https://github.com/orlandos-nl/Citadel.git](https://github.com/orlandos-nl/Citadel.git)", from: "0.5.0")       // 纯 Swift SSH/SFTP 传输
]
📡 2. 核心数据流架构 (Data Flow Architecture)由于没有传统的 C 指针阻塞调用，整个数据流必须构建在 Swift 的 async/await 与 Task 异步流之上。终端 I/O 穿透桥接拓扑+------------------+                   +---------------------+
|                  | --- (onInput) --> |                     |
|  SwiftTerm View  |                   |  Citadel SSH Shell  | ---> [ 远程 Linux 主机 ]
|  (屏幕输入缓冲区)  | <-- (feedBuffer) -|  (Async Read Loop)  | <--- (TCP Socket 字节流)
|                  |                   |                     |
+------------------+                   +---------------------+
关键数据流步骤说明：用户输入阶段： 当用户在 SwiftTerm 的 UI 视图中输入文字或按下快捷键时，触发 TerminalViewDelegate 的 send(source:data:) 回调。异步写入阶段： 回调拦截到 ArraySlice<UInt8> 字节流，开启一个非阻塞 Task，异步调用 Citadel 的 SSHShell.write(_:)。远端回显接收阶段： 建立连接时，开启一个常驻 Task 去监听 SSHShell.stdout 异步字节流管道（AsyncStream）。屏幕刷新阶段： 异步流一收到远端数据，立即通过 MainActor（主线程）分发，调用 terminalView.feed(byteArray:) 刷新屏幕。🎨 3. UI/UX 规划：极简单窗口与隐形交互应用不采用繁琐的左右布局，界面整体聚焦于终端本身，附加功能（SSH/SFTP）通过层叠动画按需唤醒。视觉层次结构 (ZStack Layering)+------------------------------------------------------------------------------------+
|   [•][•][•]  MyTerminal (无缝一体化标题栏 - borderlessWindow)                           |
+------------------------------------------------------------------------------------+
|                                                                                    |
|  user@mac ~ % ssh root@192.168.1.100                                                |
|  root@ubuntu:~# _                                                                  |
|                                                                                    |
|         +---------------------------------------------+   +---------------------+  |
|         | [🔍 搜索或输入 IP...] (Cmd + P 唤醒)            |   | 📁 SFTP (Cmd+Shift+F)|  |
|         +---------------------------------------------+   |---------------------|  |
|         | 🖥️ 生产环境 - 阿里云 (192.168.1.100)         |   | /var/www/html/      |  |
|         | 🖥️ 测试环境 - 腾讯云 (10.0.0.1)             |   |  📄 index.html      |  |
|         +---------------------------------------------+   |  📄 app.js          |  |
|                                                           |  📁 assets/         |  |
|                                                           |                     |  |
|  [💡 拖拽 Mac 文件到窗口任意处即可自动通过 SFTP 上传]              | [ ⏬ 隐藏抽屉 ]      |  |
+------------------------------------------------------------------------------------+
1. 视效与窗口属性 (Visual Design & Materials)毛玻璃窗口： 主窗体样式设置 fullSizeContentView，背景采用 macOS 原生的 .ultraThinMaterial（超薄磨砂玻璃材质）。标题栏： 消除传统灰色标题栏，红绿灯直接悬浮于终端黑屏内。字体与排版： 默认使用系统等宽字体（SF Mono），支持读取用户系统安装的电力线字体（Fira Code、JetBrains Mono）以防 Zsh 主题乱码。2. 隐藏功能 1：SSH 节点 Spotlight 搜索框 (Cmd + P 唤醒)交互动线： 处于终端任何界面，按下 Cmd + P，屏幕中央平滑缩放滑出一个深色高斯模糊的搜索框。特性： 用户可通过键盘上下键和回车键，快速在保存的服务器列表、历史会话中筛选并一键连接。3. 隐藏功能 2：SFTP 暗色右滑抽屉 (Cmd + Shift + F 唤醒)交互动线： 按下快捷键，右侧边缘向左滑出 280px 的半透明面板，显示当前 SSH 连接远程服务器的目录。拖拽上传（Drag & Drop）： 监听 SwiftUI 窗口全局的 .onDrop 事件。用户只要从 Mac 桌面的 Finder 拖拽任何文件，悬停并释放到终端窗口上：应用在终端顶部弹出一个悬浮气泡进度条。调用 SFTPClient.writeFile 在后台实现无感知闪传，传输完毕气泡淡出。💻 4. 核心骨架实现方案 (Core Implementation Blueprint)以下为项目的核心 Swift 类定义，供 Codex 作为生成完整实现的参考骨架：A. 终端连接管理器 (TerminalSessionManager)负责维持 Citadel SSH 物理会话，并将数据与本地/远程进行桥接。import Foundation
import Combine
import Citadel
import SwiftNIO

/// 管理单个 SSH 连接和配套 SFTP 会话的并发控制器
@MainActor
class TerminalSessionManager: ObservableObject {
    @Published var isConnected = false
    @Published var currentRemotePath = "/"
    @Published var remoteFiles: [SFTPFile] = []
    @Published var uploadProgress: Double = 0.0
    @Published var showUploadIndicator = false
    
    private var client: CitadelClient?
    private var shell: SSHShell?
    private var sftp: SFTPClient?
    private var cancellables = Set<AnyCancellable>()
    
    /// 纯 Swift 异步建立连接
    func connect(host: String, port: Int = 22, user: String, auth: SSHAuthentication) async throws {
        // 1. 初始化 Citadel 客户端 (基于 SwiftNIO)
        self.client = try await CitadelClient.connect(
            host: host,
            port: port,
            username: user,
            authentication: auth
        )
        
        // 2. 激活 SSH 交互式 Shell 通道
        self.shell = try await client?.enableShell()
        
        // 3. 激活 SFTP 子协议服务
        self.sftp = try await client?.startSftp()
        
        self.isConnected = true
        
        // 4. 读取远程初始路径下的文件列表
        try await fetchRemoteFiles(at: "/")
    }
    
    /// 读取远程 SFTP 路径下的文件
    func fetchRemoteFiles(at path: String) async throws {
        guard let sftp = sftp else { return }
        let files = try await sftp.listDirectory(atPath: path)
        self.currentRemotePath = path
        self.remoteFiles = files
    }
    
    /// 异步上传本地文件到当前远程 SFTP 目录
    func uploadFile(localURL: URL) async throws {
        guard let sftp = sftp else { return }
        let fileName = localURL.lastPathComponent
        let destinationPath = "\(currentRemotePath)/\(fileName)"
        
        let fileData = try Data(contentsOf: localURL)
        
        await MainActor.run {
            self.showUploadIndicator = true
            self.uploadProgress = 0.1
        }
        
        // 纯 Swift 写入远程流
        try await sftp.writeFile(named: fileName, atPath: destinationPath, data: fileData)
        
        await MainActor.run {
            self.uploadProgress = 1.0
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
                self.showUploadIndicator = false
            }
        }
        
        // 刷新列表
        try await fetchRemoteFiles(at: currentRemotePath)
    }
    
    /// 暴露给 SwiftTerm 监听的读取流闭包
    func startReadingRemoteOutput(onDataReceived: @escaping ([UInt8]) -> Void) {
        guard let shell = shell else { return }
        Task {
            do {
                for try await buffer in shell.stdout {
                    onDataReceived(buffer.bytes)
                }
            } catch {
                print("SSH 读取流异常中断: \(error)")
            }
        }
    }
    
    /// 暴露给 SwiftTerm 调用的写入流
    func sendInputToRemote(bytes: ArraySlice<UInt8>) {
        guard let shell = shell else { return }
        Task {
            try? await shell.write(bytes)
        }
    }
}
B. 终端渲染视图桥接 (SwiftUI Component Bridge)由于 SwiftTerm 的原生控件是基于 AppKit 编写的 TerminalView，我们需要将其包裹进 SwiftUI 容器 NSViewRepresentable。import SwiftUI
import SwiftTerm

struct TerminalViewBridge: NSViewRepresentable {
    @ObservedObject var sessionManager: TerminalSessionManager
    
    class Coordinator: NSObject, TerminalViewDelegate {
        var parent: TerminalViewBridge
        
        init(_ parent: TerminalViewBridge) {
            self.parent = parent
        }
        
        // 当用户在终端中进行键盘输入时，触发此回调并将其穿透发送给 SSH 物理信道
        func send(source: TerminalView, data: ArraySlice<UInt8>) {
            parent.sessionManager.sendInputToRemote(bytes: data)
        }
        
        // 处理视口滚动、窗口大小改变、剪贴板读写等回调
        func scrolled(source: TerminalView, position: Double) {}
        func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {}
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }
    
    func makeNSView(context: Context) -> TerminalView {
        let view = TerminalView()
        view.terminalDelegate = context.coordinator
        
        // 终端基础配置
        view.feed(text: "正在等待 SSH 连接建立...\r\n")
        
        // 绑定高频读取通道：一旦有 SSH 物理信道数据传入，立即写入 SwiftTerm 缓存刷新屏幕
        sessionManager.startReadingRemoteOutput { bytes in
            view.feed(byteArray: bytes)
        }
        
        return view
    }
    
    func updateNSView(_ nsView: TerminalView, context: Context) {
        // 处理终端主题、字体大小和视口尺寸缩放的动态响应
    }
}
🤖 5. 给 Codex 的开发引导守则 (Codex Copilot Instructions)请你在为我编写此项目时，严格遵守以下关于 SwiftUI 与 Swift 语言层面的最佳实践，避免产生编译器无法通过的「幻觉代码」：拒绝 C 互操作： 不要生成带有 import libssh2、libssh2_session_init 或任何操作不安全 C 指针（如 UnsafePointer）的代码。我们必须使用 100% 纯 Swift 的 Citadel。Swift 6 并发安全： 注意主线程（UI 线程）隔离。由于 TerminalSessionManager 被标记为 @MainActor，任何在后台运行的网络 Socket 数据接收任务必须使用 Task 包裹，或通过非隔离上下文运行完毕后再回调回主线程刷新 UI。SwiftUI 动画与材质： 隐藏抽屉面板的侧滑请使用内置的 .transition(.move(edge: .trailing)) 配合 withAnimation(.spring()) 保证高帧率。Drag & Drop： 实现拖拽上传时，使用 SwiftUI 的 .onDrop(of: [.fileURL], isTargeted: $isTargeted) 捕获 NSItemProvider 中的文件路径，不要使用已被废弃的老旧 API。Keychain 存储： 涉及到密码和密钥存储，请编写一个干净的 KeychainManager 工具类（基于 AppKit 原生 SecItem 系列方法封装），保证安全隐私。
