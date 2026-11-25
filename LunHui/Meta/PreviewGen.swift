import Foundation

/// 下一世的预览（4.1）：地图主题顺序、秘境词缀、3 个灵根。
enum PreviewGen {
    static func make(_ cfg: GameConfig, rng: inout SeededRandom) -> RunPreview {
        var themes = cfg.themes.themes.map(\.id)
        rng.shuffle(&themes)
        return RunPreview(themeOrder: themes, dungeonAffixes: rollAffixes(cfg, rng: &rng),
                          lingGenChoices: rollLingGen(cfg, rng: &rng),
                          lingGenRerollUsed: false, affixRerollUsed: false)
    }

    static func rollLingGen(_ cfg: GameConfig, rng: inout SeededRandom) -> [LingGen] {
        var out: [LingGen] = []
        for _ in 0..<cfg.linggen.choices { out.append(LingGen.roll(cfg, &rng, excluding: out)) }
        return out
    }

    /// 9.3：固定生成 3 条，不重复，至少 1 条增益类。
    /// 自定：第 1 条一定是增益类，因为第 10 劫以下只有前 2 条生效，这样低劫数也保证有增益。
    static func rollAffixes(_ cfg: GameConfig, rng: inout SeededRandom) -> [String] {
        let all = cfg.dungeonAffixes.affixes
        let buffs = all.filter { $0.isBuff }
        guard let first = rng.pick(buffs) else { return [] }
        var out = [first.id]
        var rest = all.filter { $0.id != first.id }
        rng.shuffle(&rest)
        for a in rest where out.count < cfg.dungeonAffixes.previewCount { out.append(a.id) }
        return out
    }
}
