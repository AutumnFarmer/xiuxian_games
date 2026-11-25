import Foundation

/// 简单对象池（3.3）。表现层的节点都从这里取，战斗中不反复创建销毁。
final class ObjectPool<T: AnyObject> {
    private var free: [T] = []
    private let make: () -> T
    private(set) var created = 0

    init(prewarm: Int = 0, make: @escaping () -> T) {
        self.make = make
        for _ in 0..<prewarm {
            free.append(make())
            created += 1
        }
    }

    func get() -> T {
        if let o = free.popLast() { return o }
        created += 1
        return make()
    }

    func put(_ o: T) { free.append(o) }

    var freeCount: Int { free.count }
}
