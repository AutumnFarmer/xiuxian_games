import Foundation

/// 伤害来源。
enum HitSource: Equatable {
    case skill(Int)      // 功法槽位
    case ultimate
    case benming
    case levelWave
    case status          // 灼烧、感电、碎裂等固定伤害
    case other
}

/// 一次玩家阵营伤害的参数（5.4）。
struct Hit {
    var mult: Double
    var element: Element?
    var school: School?
    var statusChance: Double
    var knockback: Double = 0
    var lifesteal: Double = 0
    var source: HitSource = .other
}

enum EnemyRole: UInt8 {
    case minion, elite, boss, spirit, shadow
}

enum EliteAffix: String, Codable, CaseIterable {
    case swift, split, summoner, thunder, armored
}

struct Enemy {
    var id: Int
    var role: EnemyRole
    /// 小怪、精英、雷灵：enemies.types 的下标；Boss：realmBosses 的下标。
    var typeIndex: Int
    var pos: Vec2
    var radius: Double
    var speed: Double
    var hp: Double
    var maxHp: Double
    var atk: Double
    var element: Element?
    var affixA: EliteAffix? = nil
    var affixB: EliteAffix? = nil
    /// 通用计时器：妖弓射击、精英词缀、Boss 招式。
    var timerA = 0.0
    var timerB = 0.0
    /// 爆灵：0 追击，1 引信中。
    var phase = 0
    var fuse = 0.0
    var knock = Vec2.zero
    var knockTime = 0.0
    // 元素状态（6.4）
    var flawStacks = 0
    var flawTime = 0.0
    var rootTime = 0.0
    var slowTime = 0.0
    var slowAmount = 0.0
    var burnTicks = 0
    var burnTick = 0.0
    var burnTimer = 0.0
    var stunTime = 0.0
    var freezeTime = 0.0
    var vulnTime = 0.0
    var vulnAmount = 0.0
    /// 各元素的状态标记剩余时间，用于相生判断（6.3）。
    var marks = SIMD8<Double>(repeating: 0)
    var dead = false
    /// 清场爆碎的引爆时间（4.2），< 0 表示没有排队。
    var clearAt = -1.0
    // Boss（8.6）
    var moveIndex = 0
    var seqLeft = 0
    var seqTimer = 0.0
    var seqKind = 0
    var dashLeft = 0.0
    var dashVel = Vec2.zero
    var enraged = false

    var isEliteOrBoss: Bool { role == .elite || role == .boss || role == .shadow }
    var isBossLike: Bool { role == .boss || role == .shadow }
    var canMove: Bool { rootTime <= 0 && stunTime <= 0 && freezeTime <= 0 }
    var canAct: Bool { stunTime <= 0 && freezeTime <= 0 }
    var slowFactor: Double { slowTime > 0 ? 1 - slowAmount : 1 }
    func has(_ a: EliteAffix) -> Bool { affixA == a || affixB == a }
}

enum ProjMotion: UInt8 {
    /// 直线飞行，飞完 range 消失。
    case straight
    /// 绕玩家旋转，life 到 0 消失。
    case orbit
}

enum ProjVisual: UInt8 {
    case sword, orb, slash, wind, flame, feather, arrow, fireball
}

struct Projectile {
    var id: Int
    var team: Team
    var motion: ProjMotion
    var visual: ProjVisual
    var pos: Vec2
    var vel: Vec2
    var radius: Double
    /// 剩余飞行距离（直线）。
    var range: Double
    /// 剩余存在时间（环绕）。
    var life: Double = 0
    /// 剩余穿透次数，-1 表示无限。
    var pierce: Int
    /// 已命中的敌人 id。环绕类配合 hitTimes 做"每 0.5 秒最多一次"。
    var hits: [Int] = []
    var hitTimes: [Double] = []
    var hit: Hit
    /// 敌人阵营投射物的伤害。
    var enemyDamage: Double = 0
    var element: Element?
    /// 所属功法槽位，-1 表示没有。命中时回调该功法。
    var skill: Int = -1
    /// 功法自定义数据（比如魔焰的分裂代数）。
    var tag: Int = 0
    /// 宽刃（剑气斩）：横向半宽，0 表示普通圆形判定。
    var halfWidth: Double = 0
    var orbitAngle: Double = 0
    var orbitRadius: Double = 0
    var orbitSpeed: Double = 0
    var dead = false
}

enum ZoneShape {
    case circle(Double)
    /// 内径、外径
    case ring(Double, Double)
    /// 从 pos 出发沿 dir 的长条：半宽、长度、方向
    case rect(Double, Double, Vec2)
    /// 扇形：半径、半角（弧度）、方向
    case cone(Double, Double, Vec2)
}

enum ZoneVisual: UInt8 {
    case telegraph, strikeMark, formation, cloud, residue, blood, web, aura
}

struct Zone {
    var id: Int
    var team: Team
    var shape: ZoneShape
    var pos: Vec2
    var visual: ZoneVisual
    var element: Element?
    var followPlayer = false
    /// 预警或延迟，结束时第一次结算。
    var delay: Double
    var delayTotal: Double
    /// 第一次结算后继续存在的时间；0 表示只结算一次。
    var duration: Double
    var tick: Double = 0.5
    var tickTimer: Double = 0
    var hit: Hit
    var enemyDamage: Double = 0
    /// 敌人阵营：击退玩家的距离。
    var knockback: Double = 0
    /// 蛛网：玩家在区内的减速比例。
    var slowPlayer: Double = 0
    var skill: Int = -1
    var tag: Int = 0
    /// 敌人阵营：发出这次攻击的敌人 id。它死了，没触发的预警一起消失。
    var ownerId: Int = -1
    /// 触发时让发出者一起消失（爆灵自爆）。
    var killsOwner = false
    /// 触发时把 Boss 移到这里（跃击）。
    var moveOwnerHere = false
    var triggered = false
    var dead = false

    var radiusForDisplay: Double {
        switch shape {
        case .circle(let r): return r
        case .ring(_, let o): return o
        case .rect(_, let l, _): return l
        case .cone(let r, _, _): return r
        }
    }
}

enum SummonKind: UInt8 {
    case fox, bird, python, turtle, tempFox
}

struct Summon {
    var id: Int
    var kind: SummonKind
    var skill: Int
    var pos: Vec2
    var timer: Double = 0
    var angle: Double = 0
    var life: Double = -1
    var targetId: Int = -1
    var dead = false
}

enum DropKind: UInt8 {
    case exp, lingShi, item
}

struct Drop {
    var id: Int
    var kind: DropKind
    var amount: Double
    /// 物品：RunState.stageLoot 的下标。
    var itemIndex: Int = -1
    /// 物品品质序号（0 凡品到 5 混沌品），用于表现。
    var quality: Int = 0
    var pos: Vec2
    var vel: Vec2 = .zero
    var flying = false
    var dead = false
}

/// 给表现层的一次性事件。
enum BattleEvent {
    case damage(pos: Vec2, amount: Double, crit: Bool, element: Element?, dot: Bool, targetId: Int)
    case enemyDied(id: Int, pos: Vec2, element: Element?, role: EnemyRole, radius: Double)
    case playerHurt(amount: Double)
    case playerHealed(amount: Double)
    case levelUp(level: Int)
    case nova(pos: Vec2, radius: Double, element: Element?)
    case slash(pos: Vec2, dir: Vec2, radius: Double, angle: Double, element: Element?)
    case lightning(from: Vec2, to: Vec2)
    case skyBolt(pos: Vec2, element: Element?)
    case explosion(pos: Vec2, radius: Double, element: Element?)
    case shatter(pos: Vec2)
    case itemDropped(quality: Int, pos: Vec2)
    case itemPicked(quality: Int, name: String)
    case bossIntro(name: String)
    case banner(text: String, duration: Double)
    case shake(Int)
    case haptic(Int)
    case hitStop(Double)
    case slowMo(duration: Double, scale: Double)
    case revive
    case shieldBreak(pos: Vec2)
}

/// 关卡类型（4.2）。
enum StageKind: Equatable {
    case normal, boss, tribulation, shadow
}

/// 一关的设置，由 RunController 生成。
struct StageSetup {
    var tier: Int
    var realm: Int
    var stageIndex: Int
    var kind: StageKind
    var themeElement: Element
    /// 秘境词缀（第 9 章）带来的系数，没有时为 1。
    var enemyHpMult = 1.0
    var enemyAtkMult = 1.0
    var enemySpeedMult = 1.0
    var spawnMult = 1.0
    var eliteMult = 1.0
    var minionExplode = false
}

/// 一关内的阶段。
enum StagePhase: Equatable {
    case fighting
    /// 清场爆碎中（4.2）。
    case clearing
    /// 等待掉落物飞完。
    case collecting
    case cleared
    case dead
}
