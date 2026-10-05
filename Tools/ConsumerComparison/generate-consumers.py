#!/usr/bin/env python3
"""Generate identical-workload sources, not measured results or DI implementations."""
import pathlib,sys
out=pathlib.Path(sys.argv[1]); competitors=pathlib.Path(sys.argv[2]).resolve()
out.mkdir(parents=True,exist_ok=True)
common='''import Foundation
import Synchronization

final class Counter: Sendable {
    private let storage = Mutex((made: 0, released: 0))
    func didMake() { storage.withLock { $0.made += 1 } }
    func didRelease() { storage.withLock { $0.released += 1 } }
    var made: Int { storage.withLock { $0.made } }
    var released: Int { storage.withLock { $0.released } }
}
final class Node: Sendable {
    let id: Int
    let parent: Node?
    private let counter: Counter
    init(id: Int, parent: Node?, counter: Counter) {
        self.id = id; self.parent = parent; self.counter = counter; counter.didMake()
    }
    deinit { counter.didRelease() }
}
func milliseconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) * 1000 + Double(duration.components.attoseconds) / 1e15
}
func verify() {
    let a = Counter(), b = Counter()
    do {
        let first = makeContext(a), second = makeContext(b)
        precondition(a.made == 0 && b.made == 0)
        let leaf = resolve(first)
        precondition(leaf === resolve(first) && a.made == 20)
        var cursor: Node? = leaf
        for id in (0..<20).reversed() { precondition(cursor?.id == id); cursor = cursor?.parent }
        precondition(cursor == nil)
        precondition(leaf !== resolve(second) && b.made == 20)
    }
    precondition(a.released == 20 && b.released == 20)
    let overriddenCounter = Counter()
    do {
        let replacement = Node(id: 118, parent: nil, counter: overriddenCounter)
        let context = makeOverriddenContext(overriddenCounter, replacement)
        let leaf = resolve(context)
        precondition(leaf.id == 19 && leaf.parent === replacement)
        precondition(overriddenCounter.made == 2)
    }
    precondition(overriddenCounter.released == 2)
}
@main struct Run {
    static func main() throws {
        verify()
        if ProcessInfo.processInfo.environment["BENCH_VALIDATE_ONLY"] == "1" {
            print("oracles passed"); return
        }
        let samples = Int(ProcessInfo.processInfo.environment["BENCH_SAMPLES"] ?? "10")!
        let warmups = 3, firstBatch = 100, constructionBatch = 500, warmBatch = 100000
        let clock = ContinuousClock()
        var checksum = 0
        var construction: [Double] = [], first: [Double] = [], warm: [Double] = []
        let warmContext = makeContext(Counter()); _ = resolve(warmContext)
        for sample in (-warmups)..<samples {
            let constructTime = clock.measure {
                for _ in 0..<constructionBatch {
                    let counter = Counter()
                    let context = makeContext(counter)
                    withExtendedLifetime(context) { checksum &+= resolve(context).id }
                }
            }
            let contexts = (0..<firstBatch).map { _ in makeContext(Counter()) }
            let firstTime = clock.measure {
                for context in contexts { checksum &+= resolve(context).id }
            }
            let warmTime = clock.measure {
                for _ in 0..<warmBatch { checksum &+= resolve(warmContext).id }
            }
            // Keep first-resolution roots alive past every timing endpoint.
            // This removes uncertainty about ARC teardown moving into that interval.
            withExtendedLifetime(contexts) {}
            if sample >= 0 {
                construction.append(milliseconds(constructTime) / Double(constructionBatch))
                first.append(milliseconds(firstTime) / Double(firstBatch))
                warm.append(milliseconds(warmTime) * 1e6 / Double(warmBatch))
            }
        }
        let report: [String: Any] = ["schema": 1, "nodes": 20, "samples": samples,
            "warmups": warmups, "cold_graph_lifecycle_ms": construction,
            "first_resolution_ms": first, "warm_resolution_ns": warm,
            "checksum": checksum, "oracles_passed": true,
            "batch_sizes": [constructionBatch, firstBatch, warmBatch]]
        let data = try JSONSerialization.data(withJSONObject: report, options: [.sortedKeys])
        print(String(decoding: data, as: UTF8.self))
    }
}
'''
factory='''import FactoryKit
final class BenchmarkContext: ManagedContainer {
    let manager = ContainerManager()
    let counter: Counter
    init(_ counter: Counter) { self.counter = counter }
'''
for i in range(20):
 parent='nil' if not i else f'self.node{i-1}()'
 factory+=f'    var node{i}: Factory<Node> {{ self {{ Node(id: {i}, parent: {parent}, counter: self.counter) }}.cached }}\n'
factory+='''}
@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContext { BenchmarkContext(counter) }
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContext {
    let context = BenchmarkContext(counter)
    context.node18.register { replacement }
    return context
}
@inline(never) func resolve(_ context: BenchmarkContext) -> Node { context.node19() }
'''
swinject='''import Swinject
struct BenchmarkContext {
    let container: Container
    let resolver: any Resolver
    init(_ counter: Counter, replacement: Node? = nil) {
        let container = Container()
'''
for i in range(20):
 parent='nil' if not i else f'r.resolve(Node.self, name: "node{i-1}")!'
 expr=f'Node(id: {i}, parent: {parent}, counter: counter)'
 if i==18: expr='replacement ?? '+expr
 swinject+=f'        container.register(Node.self, name: "node{i}") {{ r in {expr} }}.inObjectScope(.container)\n'
swinject+='''        self.container = container
        self.resolver = container.synchronize()
    }
}
@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContext { BenchmarkContext(counter) }
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContext { BenchmarkContext(counter, replacement: replacement) }
@inline(never) func resolve(_ context: BenchmarkContext) -> Node { context.resolver.resolve(Node.self, name: "node19")! }
'''
dependencies = """import Dependencies
private enum CounterKey: DependencyKey { static var liveValue: Counter { Counter() } }
extension DependencyValues {
    var counter: Counter { get { self[CounterKey.self] } set { self[CounterKey.self] = newValue } }
"""
for i in range(20):
 dependencies += f'    var node{i}: Node {{ get {{ self[Node{i}Key.self] }} set {{ self[Node{i}Key.self] = newValue }} }}\n'
dependencies += '}\n'
for i in range(20):
 parent='nil' if not i else 'previous'
 prior='' if not i else f'        @Dependency(\\.node{i-1}) var previous\n'
 dependencies += f"""private enum Node{i}Key: DependencyKey {{
    static var liveValue: Node {{
        @Dependency(\\.counter) var counter
{prior}        return Node(id: {i}, parent: {parent}, counter: counter)
    }}
}}
"""
dependencies += """struct BenchmarkContext {
    @Dependency(\\.node19) var leaf
}
@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContext {
    withDependencies {
        $0 = DependencyValues()
        $0.context = .live
        $0.counter = counter
    } operation: { BenchmarkContext() }
}
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContext {
    withDependencies {
        $0 = DependencyValues()
        $0.context = .live
        $0.counter = counter
        $0.node18 = replacement
    } operation: { BenchmarkContext() }
}
@inline(never) func resolve(_ context: BenchmarkContext) -> Node { context.leaf }
"""
needle = """import NeedleFoundation
// Runtime-only bridge adapted from the pinned repository's generated bootstrap
// template. The official generator is NOT exercised by this file. Its manual
// authoring is counted and reported separately, never hidden as generated work.
private let bootstrapRegistration: Void = {
    __DependencyProviderRegistry.instance.registerDependencyProviderFactory(for: "^->BenchmarkContext") {
        EmptyDependencyProvider(component: $0)
    }
}()
final class BenchmarkContext: BootstrapComponent {
    let counter: Counter
    let replacement: Node?
    init(_ counter: Counter, replacement: Node? = nil) {
        self.counter = counter; self.replacement = replacement
        super.init()
    }
"""
for i in range(20):
 parent='nil' if not i else f'self.node{i-1}'
 expr=f'Node(id: {i}, parent: {parent}, counter: self.counter)'
 if i==18: expr='self.replacement ?? '+expr
 needle += f'    var node{i}: Node {{ shared {{ {expr} }} }}\n'
needle += """}
@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContext {
    _ = bootstrapRegistration
    return BenchmarkContext(counter)
}
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContext {
    _ = bootstrapRegistration
    return BenchmarkContext(counter, replacement: replacement)
}
@inline(never) func resolve(_ context: BenchmarkContext) -> Node { context.node19 }
"""
control = """// Serialized-access control only; Swift lazy properties are not concurrency-safe.
final class BenchmarkContext {
    let counter: Counter
    let replacement: Node?
    init(_ counter: Counter, replacement: Node? = nil) { self.counter = counter; self.replacement = replacement }
"""
for i in range(20):
 parent='nil' if not i else f'node{i-1}'
 expr=f'Node(id: {i}, parent: {parent}, counter: counter)'
 if i==18: expr='replacement ?? '+expr
 control += f'    lazy var node{i}: Node = {expr}\n'
control += """}
@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContext { BenchmarkContext(counter) }
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContext { BenchmarkContext(counter, replacement: replacement) }
@inline(never) func resolve(_ context: BenchmarkContext) -> Node { context.node19 }
"""
inno='''@inline(never) func makeContext(_ counter: Counter) -> BenchmarkContainer { BenchmarkContainer(counter: counter) }
@inline(never) func makeOverriddenContext(_ counter: Counter, _ replacement: Node) -> BenchmarkContainer { BenchmarkContainer(counter: counter, node18: replacement) }
@inline(never) func resolve(_ context: BenchmarkContainer) -> Node { context.node19 }
'''
# The baseline and candidate need exported Expanded.swift and exact production
# runtime files copied separately, with their hashes in the evidence manifest.
for name,body,dependency,product in [('Control',control,None,None),('Factory',factory,'Factory','FactoryKit'),('Swinject',swinject,'Swinject','Swinject'),('Dependencies',dependencies,'swift-dependencies','Dependencies'),('Needle-runtime',needle,'needle','NeedleFoundation'),('InnoDI-baseline',inno,None,'InnoDI'),('InnoDI-candidate',inno,None,'InnoDI')]:
 path=out/('Consumer-'+name); app=path/'Sources/Consumer'; app.mkdir(parents=True,exist_ok=True)
 (app/'Common.swift').write_text(common);(app/'Wiring.swift').write_text(body)
 if dependency:
  deps=f'.package(path: "{competitors/dependency}")'
  targets=f'.executableTarget(name: "Consumer", dependencies: [.product(name: "{product}", package: "{dependency}")])'
 elif product is None:
  deps=''; targets='.executableTarget(name: "Consumer")'
 else:
  runtime=out/('Runtime-'+name); runtime.mkdir(parents=True,exist_ok=True)
  (runtime/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package = Package(name: "Portable'+name.replace('-','')+'", products: [.library(name: "InnoDI", targets: ["InnoDI"])], targets: [.target(name: "InnoDI")])\n')
  deps=f'.package(path: "{runtime.resolve()}")'
  targets=f'.executableTarget(name: "Consumer", dependencies: [.product(name: "InnoDI", package: "Runtime-{name}")])'
 (path/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\nlet package = Package(name: "Comparison'+name.replace('-','')+'", dependencies: ['+deps+'], targets: ['+targets+'])\n')
print(out)
