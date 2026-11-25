#if os(iOS)
import SwiftUI

@main
struct LunHuiApp: App {
    @State private var app = AppState()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
                .statusBarHidden(true)
                .onAppear {
                    if app.route == .loading {
                        Audio.shared.setup()
                        app.boot()
                        Audio.shared.enabled = app.save.settings.sound
                    }
                }
                .onChange(of: app.route) { _, r in
                    switch r {
                    case .cave, .prepare, .firstLaunch: Audio.shared.playMusic(.cave)
                    case .settlement: Audio.shared.stopMusic()
                    default: break
                    }
                }
                .onChange(of: app.save.settings.sound) { _, on in Audio.shared.enabled = on }
                .onChange(of: app.save.settings.haptics) { _, on in Haptics.shared.enabled = on }
                .onChange(of: scenePhase) { _, phase in
                    // 3.4：进入后台时立即暂停战斗并存档
                    // 4.5：run.json 只在关卡开始和过关时写，关内进度不保存
                    if phase != .active {
                        app.battleFlow?.pause()
                        app.persist()
                    }
                }
        }
    }
}

/// 根视图按 route 切换（17.2）。
struct RootView: View {
    @Environment(AppState.self) private var app

    var body: some View {
        Group {
            switch app.route {
            case .loading:
                ProgressView().tint(.lhGold).lhScreen()
            case .firstLaunch:
                FirstLaunchView()
            case .cave:
                CaveView()
            case .prepare:
                PrepareView()
            case .battle:
                BattleView().id(app.battleToken)
            case .settlement:
                SettlementView()
            case .corrupted(let backup):
                CorruptedView(backupAvailable: backup)
            case .fatal(let msg):
                ScrollView { Text("启动失败：\n\(msg)").font(.system(.body, design: .monospaced)).foregroundStyle(.red).padding() }.lhScreen()
            }
        }
        .preferredColorScheme(.dark)
    }
}

/// 存档损坏（18.1）：不能静默覆盖。
struct CorruptedView: View {
    @Environment(AppState.self) private var app
    var backupAvailable: Bool
    @State private var confirmNew = false

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "exclamationmark.triangle.fill").font(.system(size: 44)).foregroundStyle(.orange)
            Text("存档损坏").font(.title2.bold()).foregroundStyle(Color.lhText)
            Text("主存档无法读取。").foregroundStyle(Color.lhSub)
            if backupAvailable {
                Button("从备份恢复") { app.restoreBackup() }.buttonStyle(LHButtonStyle())
            }
            Button("新建存档") { confirmNew = true }.buttonStyle(LHButtonStyle(color: .red, filled: false))
        }
        .padding(30)
        .lhScreen()
        .confirmationDialog("新建存档会清空所有进度", isPresented: $confirmNew, titleVisibility: .visible) {
            Button("清空并新建", role: .destructive) { app.startFresh() }
        }
    }
}

/// 第一次进入：选本命法宝外形（13.1）。
struct FirstLaunchView: View {
    @Environment(AppState.self) private var app
    @State private var pick = "sword"

    var body: some View {
        let shapes = app.config.benming.shapes
        VStack(spacing: 22) {
            Spacer()
            Text("轮回录").font(.system(size: 44, weight: .heavy)).foregroundStyle(Color.lhGold)
            Text("择一本命法宝，伴你生生世世").foregroundStyle(Color.lhSub)
            HStack(spacing: 14) {
                ForEach(shapes, id: \.id) { s in
                    Button { pick = s.id } label: {
                        VStack(spacing: 8) {
                            Image(systemName: BenmingShapeIcon.symbol(s.id)).font(.system(size: 30, weight: .semibold))
                            Text(s.name).font(.headline)
                        }
                        .foregroundStyle(pick == s.id ? Color.black : Color.lhText)
                        .frame(width: 72, height: 92)
                        .background(pick == s.id ? Color.lhGold : Color.lhCard, in: RoundedRectangle(cornerRadius: 14))
                    }
                }
            }
            Spacer()
            Button("踏入轮回") { app.chooseBenmingShape(pick) }
                .buttonStyle(LHButtonStyle())
                .accessibilityIdentifier("first-launch-go")
                .padding(.bottom, 40)
        }
        .padding()
        .lhScreen()
    }
}

enum BenmingShapeIcon {
    static func symbol(_ id: String?) -> String {
        switch id {
        case "seal": return "seal.fill"
        case "cauldron": return "flame.fill"
        case "mirror": return "circle.hexagongrid.fill"
        default: return "bolt.horizontal.fill"
        }
    }
}
#endif
