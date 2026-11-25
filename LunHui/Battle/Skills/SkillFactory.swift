import Foundation

/// 按 id 创建功法行为（7.5、7.6）。新功法在这里注册。
enum SkillFactory {
    static let types: [String: SkillBase.Type] = [
        "yujian": YuJianSkill.self,
        "jianzhen": JianZhenSkill.self,
        "jianqi": JianQiSkill.self,
        "feijianyu": FeiJianYuSkill.self,
        "lingdan": LingDanSkill.self,
        "luoxing": LuoXingSkill.self,
        "lingzhen": LingZhenSkill.self,
        "lingbao": LingBaoSkill.self,
        "bengshan": BengShanSkill.self,
        "tiebu": TieBuSkill.self,
        "zhenta": ZhenTaSkill.self,
        "chongzhuang": ChongZhuangSkill.self,
        "huanling": HuanLingSkill.self,
        "lingque": LingQueSkill.self,
        "bimang": BiMangSkill.self,
        "xuangui": XuanGuiSkill.self,
        "shihun": ShiHunSkill.self,
        "xuehe": XueHeSkill.self,
        "mohuo": MoHuoSkill.self,
        "xinmozhan": XinMoZhanSkill.self,
        "leiyin": LeiYinSkill.self,
        "huoyun": HuoYunSkill.self,
        "xuanguang": XuanGuangSkill.self,
        "fengren": FengRenSkill.self,
    ]

    static func make(id: String, slot: Int, level: Int, element: Element, cfg: GameConfig) -> SkillBase? {
        guard let def = cfg.skills.def(id), let t = types[id] else { return nil }
        return t.init(def: def, slot: slot, level: level, element: element, cfg: cfg)
    }
}
