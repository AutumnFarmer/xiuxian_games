import Foundation

/// 全部配置表（19.1）。启动时一次性加载，之后只读。
final class GameConfig {
    let balance: BalanceConfig
    let stats: StatsConfig
    let elements: ElementsConfig
    let linggen: LingGenConfig
    let schools: SchoolsConfig
    let skills: SkillsConfig
    let passives: PassivesConfig
    let insight: InsightConfig
    let enemies: EnemiesConfig
    let spawn: SpawnConfig
    let bosses: BossesConfig
    let themes: ThemesConfig
    let items: ItemsConfig
    let evolutions: EvolutionsConfig
    let settlement: SettlementConfig
    let cave: CaveConfig
    let events: EventsConfig
    let benming: BenmingConfig
    let heartDemon: HeartDemonConfig
    let dungeonAffixes: DungeonAffixesConfig
    let legendaries: LegendariesConfig
    let fx: FXConfig

    private init(dir: URL?) throws {
        balance = try GameConfig.load("balance", dir)
        stats = try GameConfig.load("stats", dir)
        var el: ElementsConfig = try GameConfig.load("elements", dir)
        el.prepare()
        elements = el
        linggen = try GameConfig.load("linggen", dir)
        schools = try GameConfig.load("schools", dir)
        var sk: SkillsConfig = try GameConfig.load("skills", dir)
        sk.prepare()
        skills = sk
        passives = try GameConfig.load("passives", dir)
        insight = try GameConfig.load("insight", dir)
        enemies = try GameConfig.load("enemies", dir)
        spawn = try GameConfig.load("spawn", dir)
        bosses = try GameConfig.load("bosses", dir)
        themes = try GameConfig.load("themes", dir)
        items = try GameConfig.load("items", dir)
        evolutions = try GameConfig.load("evolutions", dir)
        settlement = try GameConfig.load("settlement", dir)
        cave = try GameConfig.load("cave", dir)
        events = try GameConfig.load("events", dir)
        benming = try GameConfig.load("benming", dir)
        heartDemon = try GameConfig.load("heartDemon", dir)
        dungeonAffixes = try GameConfig.load("dungeonAffixes", dir)
        legendaries = try GameConfig.load("legendaries", dir)
        fx = try GameConfig.load("fx", dir)
        try validate()
    }

    /// 从 App 包里加载（iOS）。
    static func loadBundled() throws -> GameConfig { try GameConfig(dir: nil) }

    /// 从指定目录加载（命令行测试用）。
    static func load(directory: URL) throws -> GameConfig { try GameConfig(dir: directory) }

    /// 神通倍率系数（7.8）。
    func evolutionsMultFactor() throws -> Double { evolutions.multFactor }

    struct ConfigError: Error, CustomStringConvertible {
        var description: String
    }

    private static func load<T: Decodable>(_ name: String, _ dir: URL?) throws -> T {
        let url: URL
        if let dir {
            url = dir.appendingPathComponent("\(name).json")
        } else if let u = Bundle.main.url(forResource: name, withExtension: "json") {
            url = u
        } else {
            throw ConfigError(description: "找不到配置表 \(name).json")
        }
        let data: Data
        do { data = try Data(contentsOf: url) } catch {
            throw ConfigError(description: "读取 \(name).json 失败：\(error)")
        }
        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch let DecodingError.keyNotFound(key, ctx) {
            throw ConfigError(description: "\(name).json 缺少字段 \(key.stringValue)，位置 \(pathText(ctx.codingPath))")
        } catch let DecodingError.typeMismatch(_, ctx) {
            throw ConfigError(description: "\(name).json 字段类型不对，位置 \(pathText(ctx.codingPath))：\(ctx.debugDescription)")
        } catch let DecodingError.valueNotFound(_, ctx) {
            throw ConfigError(description: "\(name).json 字段为空，位置 \(pathText(ctx.codingPath))")
        } catch let DecodingError.dataCorrupted(ctx) {
            throw ConfigError(description: "\(name).json 格式错误，位置 \(pathText(ctx.codingPath))：\(ctx.debugDescription)")
        }
    }

    private static func pathText(_ path: [CodingKey]) -> String {
        path.map { $0.intValue.map { "[\($0)]" } ?? $0.stringValue }.joined(separator: ".")
    }

    /// 启动校验（19.1）：id 不重复、引用存在、数值范围合理。
    private func validate() throws {
        var problems: [String] = []
        func dupCheck(_ table: String, _ ids: [String]) {
            var seen = Set<String>()
            for id in ids where !seen.insert(id).inserted { problems.append("\(table): id 重复 \(id)") }
        }
        dupCheck("skills.json", skills.skills.map(\.id))
        dupCheck("passives.json", passives.passives.map(\.id))
        dupCheck("enemies.json", enemies.types.map(\.id))
        dupCheck("bosses.json", bosses.realmBosses.map(\.id))
        dupCheck("themes.json", themes.themes.map(\.id))
        if elements.elements.count != 7 { problems.append("elements.json: 元素数量应为 7") }
        for s in skills.skills {
            if s.cooldown < 0 { problems.append("skills.json: \(s.id) 冷却为负") }
            if s.levels.count != skills.maxLevel { problems.append("skills.json: \(s.id) levels 应有 \(skills.maxLevel) 项") }
            if s.levelDesc.count != skills.maxLevel { problems.append("skills.json: \(s.id) levelDesc 应有 \(skills.maxLevel) 项") }
        }
        for sc in schools.schools {
            if skills.def(sc.startSkill) == nil { problems.append("schools.json: \(sc.id.rawValue) 的初始功法 \(sc.startSkill) 不存在") }
            if skills.pool(for: sc.id).filter({ $0.school == sc.id }).count != 4 {
                problems.append("skills.json: 流派 \(sc.id.rawValue) 应有 4 个功法")
            }
        }
        if schools.schools.count != School.allCases.count { problems.append("schools.json: 流派数量不对") }
        if enemies.realms.count != 5 { problems.append("enemies.json: realms 应有 5 项") }
        if bosses.realmBosses.count != 5 { problems.append("bosses.json: realmBosses 应有 5 项") }
        if themes.themes.count != 5 { problems.append("themes.json: 主题应有 5 个") }
        if bosses.tribulation.boltsPerSecond.count != bosses.tribulation.waves {
            problems.append("bosses.json: boltsPerSecond 的长度应等于 waves")
        }
        let minionCount = enemies.minionTypes.count
        for w in enemies.realmWeights where w.weights.count != minionCount {
            problems.append("enemies.json: realmWeights 的长度和小怪类型数不一致")
        }
        if enemies.realmWeights.count != 5 { problems.append("enemies.json: realmWeights 应有 5 项") }
        if items.qualities.count != 6 { problems.append("items.json: 品质应有 6 档") }
        if items.slots.count != ItemSlot.allCases.count { problems.append("items.json: 部位数量不对") }
        dupCheck("items.json affixes", items.affixes.map(\.id))
        for ev in evolutions.evolutions {
            if skills.def(ev.skill) == nil { problems.append("evolutions.json: \(ev.id) 引用的功法 \(ev.skill) 不存在") }
            if passives.def(ev.passive) == nil { problems.append("evolutions.json: \(ev.id) 引用的心法 \(ev.passive) 不存在") }
        }
        dupCheck("events.json", events.events.map(\.id))
        dupCheck("benming.json", benming.awakenings.map(\.id))
        dupCheck("dungeonAffixes.json", dungeonAffixes.affixes.map(\.id))
        dupCheck("legendaries.json", legendaries.legendaries.map(\.id))
        dupCheck("cave.json", cave.upgrades.map(\.id) + cave.pills.map(\.id) + cave.daoxin.points.map(\.id))
        for l in legendaries.legendaries {
            if let s = l.skill, skills.def(s) == nil { problems.append("legendaries.json: \(l.id) 引用的功法 \(s) 不存在") }
        }
        for s in skills.skills where evolutions.forSkill(s.id) == nil {
            problems.append("evolutions.json: 功法 \(s.id) 没有神通")
        }
        if fx.drops.count != items.qualities.count { problems.append("fx.json: drops 应和品质数量一致") }
        if heartDemon.bands.first?.from != 0 { problems.append("heartDemon.json: 第一档应从 0 开始") }
        if !problems.isEmpty {
            throw ConfigError(description: "配置校验失败：\n" + problems.joined(separator: "\n"))
        }
    }
}
