#!/usr/bin/env python3
"""Isolate typed-prewarm dispatch from runtime-cell changes using exported AST.
Usage: measure-prewarm.py EXISTING_CONSUMERS_DIR NEW_OUTPUT_DIR
Both lanes link the SAME unchanged baseline InnoDI runtime dependency package.
"""
import hashlib, json, os, pathlib, shutil, statistics, subprocess, sys
source = pathlib.Path(sys.argv[1]).resolve()
out = pathlib.Path(sys.argv[2]).resolve(); out.mkdir(parents=True, exist_ok=True)
common = (source/'Consumer-InnoDI-baseline/Sources/Consumer/Common.swift').read_text().split('func verify()')[0]
names = ['baseline', 'typed']
driver = r'''
func verify() throws {
    let counter = Counter()
    do {
        let context = BenchmarkContainer(counter: counter)
        precondition(counter.made == 0)
        try prewarmOne(context)
        precondition(counter.made == 20)
        let leaf = context.node19
        try prewarmAll(context)
        precondition(counter.made == 20 && leaf === context.node19)
    }
    precondition(counter.released == 20)
}
@main struct Run {
    static func main() throws {
        try verify()
        let clock = ContinuousClock(), samples = 10, warmups = 3
        let firstBatch = 100, warmBatch = 10000
        let warm = BenchmarkContainer(counter: Counter()); try prewarmAll(warm)
        var first: [Double] = [], one: [Double] = [], all: [Double] = []
        var checksum = 0
        for sample in (-warmups)..<samples {
            let contexts = (0..<firstBatch).map { _ in BenchmarkContainer(counter: Counter()) }
            let firstTime = try clock.measure {
                for context in contexts { try prewarmOne(context) }
            }
            let oneTime = try clock.measure {
                for _ in 0..<warmBatch { try prewarmOne(warm) }
            }
            let allTime = try clock.measure {
                for _ in 0..<warmBatch { try prewarmAll(warm) }
            }
            checksum &+= contexts.reduce(0) { $0 + $1.node19.id }
            checksum &+= warm.node19.id
            if sample >= 0 {
                first.append(milliseconds(firstTime) * 1e6 / Double(firstBatch))
                one.append(milliseconds(oneTime) * 1e6 / Double(warmBatch))
                all.append(milliseconds(allTime) * 1e6 / Double(warmBatch))
            }
        }
        let result: [String: Any] = ["oracles_passed": true, "samples": samples, "warmups": warmups,
            "nodes": 20, "first_leaf_prewarm_ns": first, "ready_leaf_prewarm_ns": one,
            "ready_all_prewarm_ns": all, "checksum": checksum, "batch_sizes": [firstBatch, warmBatch]]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
'''
metadata = {}
for name in names:
    root = out/f'Consumer-{name}'; sources = root/'Sources/Consumer'; sources.mkdir(parents=True, exist_ok=True)
    exported = source/f'Consumer-InnoDI-{"candidate" if name == "typed" else "baseline"}/Sources/Consumer/Expanded.swift'
    shutil.copy2(exported, sources/'Expanded.swift')
    def call(indices):
        prefix = 'try ' if name == 'baseline' else ''
        arguments = ', '.join(('\\.' if name == 'baseline' else '.') + f'node{i}' for i in indices)
        return prefix + f'context.prewarm({arguments})'
    adapters = '\n'.join(f'@inline(never) func prewarm{method}(_ context: BenchmarkContainer) throws {{ {call(indices)} }}' for method, indices in [('One', [19]), ('All', range(20))])
    (sources/'Main.swift').write_text(common + adapters + '\n' + driver)
    (root/'Package.swift').write_text('// swift-tools-version: 6.4\nimport PackageDescription\n' +
        f'let package = Package(name: "Prewarm{name}", dependencies: [.package(path: "{source}/Runtime-InnoDI-baseline")], targets: [.executableTarget(name: "Consumer", dependencies: [.product(name: "InnoDI", package: "Runtime-InnoDI-baseline")])])\n')
    command = ['swift', 'build', '--package-path', str(root), '-c', 'release', '-j', '4']
    with (out/f'{name}-build.log').open('w') as log:
        subprocess.run(command, check=True, stdout=log, stderr=subprocess.STDOUT)
    binary = root/'.build/release/Consumer'
    stripped = out/f'{name}.debug-stripped'; shutil.copy2(binary, stripped)
    subprocess.run(['strip', '--strip-debug', str(stripped)], check=True)
    metadata[name] = {'binary_sha256': hashlib.sha256(binary.read_bytes()).hexdigest(),
        'debug_stripped_elf_bytes': stripped.stat().st_size,
        'source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sources.glob('*.swift'))}, 'build_command': command}
records = []
for block in range(3):
    for name in (names if block % 2 == 0 else list(reversed(names))):
        text = subprocess.check_output([str(out/f'Consumer-{name}/.build/release/Consumer')], text=True)
        data = json.loads(text); assert data['oracles_passed'] and data['samples'] == 10
        records.append({'name': name, 'block': block, 'data': data})
        print(name, block, 'done', flush=True)
report = {'compiler': subprocess.check_output(['swiftc', '--version'], text=True),
    'runtime_source_sha256': {p.name: hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted((source/'Runtime-InnoDI-baseline/Sources/InnoDI').glob('*.swift'))},
    'scope': '20-provider actual exported container; identical baseline runtime; 3 blocks x10 batch means; 3 warmups each; no Apple qualification',
    'records': records, 'metadata': metadata}
(out/'raw.json').write_text(json.dumps(report, indent=2)+'\n')
summary = {}
for name in names:
    rows = [r['data'] for r in records if r['name'] == name]
    summary[name] = {}
    for metric in ['first_leaf_prewarm_ns', 'ready_leaf_prewarm_ns', 'ready_all_prewarm_ns']:
        values = [v for row in rows for v in row[metric]]
        summary[name][metric] = {'median': statistics.median(values), 'p95_batch_mean': sorted(values)[28],
            'block_medians': [statistics.median(row[metric]) for row in rows]}
(out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n'); print(json.dumps(summary, indent=2))
