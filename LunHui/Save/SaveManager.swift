import Foundation

/// 本地存档（18.1、18.2）。save.json 存局外，run.json 存进行中的一世。
/// 写入先写临时文件再替换；成功写入 save.json 后把旧文件备份为 save.backup.json。
final class SaveManager {
    enum LoadResult {
        case ok(SaveData)
        case missing
        /// 主存档损坏；backupAvailable 表示备份能读。
        case corrupted(backupAvailable: Bool)
    }

    let dir: URL
    private let fm = FileManager.default
    private let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.dateEncodingStrategy = .secondsSince1970
        return e
    }()
    private let decoder: JSONDecoder = {
        let d = JSONDecoder()
        d.dateDecodingStrategy = .secondsSince1970
        return d
    }()

    init(directory: URL? = nil) {
        if let directory {
            dir = directory
        } else {
            let base = (try? FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                                     appropriateFor: nil, create: true)) ?? FileManager.default.temporaryDirectory
            dir = base.appendingPathComponent("LunHui", isDirectory: true)
        }
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    }

    var saveURL: URL { dir.appendingPathComponent("save.json") }
    var backupURL: URL { dir.appendingPathComponent("save.backup.json") }
    var runURL: URL { dir.appendingPathComponent("run.json") }

    // MARK: 局外存档

    func load() -> LoadResult {
        guard fm.fileExists(atPath: saveURL.path) else { return .missing }
        if let s = decodeSave(saveURL) { return .ok(migrate(s)) }
        return .corrupted(backupAvailable: decodeSave(backupURL) != nil)
    }

    func loadBackup() -> SaveData? { decodeSave(backupURL).map { migrate($0) } }

    private func decodeSave(_ url: URL) -> SaveData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? decoder.decode(SaveData.self, from: data)
    }

    /// 18.2：版本小于当前版本时依次迁移。现在只有版本 1。
    private func migrate(_ s: SaveData) -> SaveData {
        var s = s
        if s.version < SaveData.currentVersion { s.version = SaveData.currentVersion }
        return s
    }

    @discardableResult
    func save(_ s: SaveData) -> Bool {
        guard let data = try? encoder.encode(s) else { return false }
        let hadOld = fm.fileExists(atPath: saveURL.path)
        if hadOld {
            try? fm.removeItem(at: backupURL)
            try? fm.copyItem(at: saveURL, to: backupURL)
        }
        return atomicWrite(data, to: saveURL)
    }

    /// 删除全部存档（设置里的"重置存档"）。
    func resetAll() {
        for u in [saveURL, backupURL, runURL] { try? fm.removeItem(at: u) }
    }

    // MARK: 一世存档

    func loadRun() -> RunState? {
        guard let data = try? Data(contentsOf: runURL), let r = try? decoder.decode(RunState.self, from: data) else { return nil }
        // 18.2：版本不匹配又无法迁移时，丢弃这一世
        return r.version == RunState.currentVersion ? r : nil
    }

    @discardableResult
    func saveRun(_ r: RunState) -> Bool {
        guard let data = try? encoder.encode(r) else { return false }
        return atomicWrite(data, to: runURL)
    }

    func deleteRun() { try? fm.removeItem(at: runURL) }

    private func atomicWrite(_ data: Data, to url: URL) -> Bool {
        let tmp = dir.appendingPathComponent(".\(url.lastPathComponent).\(UUID().uuidString).tmp")
        do {
            try data.write(to: tmp)
            if fm.fileExists(atPath: url.path) {
                _ = try fm.replaceItemAt(url, withItemAt: tmp)
            } else {
                try fm.moveItem(at: tmp, to: url)
            }
            return true
        } catch {
            try? fm.removeItem(at: tmp)
            return false
        }
    }
}
