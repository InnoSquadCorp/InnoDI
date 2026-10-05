#!/usr/bin/env python3
"""Preregistered final composite-v2 run: 15 paired processes x2 samples/version.
Thirty warmups in EVERY process; resample whole paired blocks, not timing rows.
Run only frozen already-built test runners and keep the machine build-idle.
Usage: measure-final-macro.py BASELINE_RUNNER CANDIDATE_RUNNER NEW_OUTPUT_DIR
"""
import hashlib, json, os, pathlib, platform, random, statistics, subprocess, sys
baseline, candidate, out = map(lambda value: pathlib.Path(value).resolve(), sys.argv[1:])
out.mkdir(parents=True, exist_ok=True)
if any(out.iterdir()):
    raise RuntimeError('Use a new empty evidence directory; never overwrite a measured run')
runners = {'baseline': baseline, 'candidate': candidate}
env = os.environ.copy(); env['INNODI_MACRO_BENCH_ITERATIONS'] = '2'
env['SWIFT_VERSION'] = subprocess.check_output(['swiftc', '--version'], text=True).strip().replace('\n', '; ')
metadata = {'scope': 'debug in-process composite-v2 macro expansion, not package build or application runtime',
    'compiler': env['SWIFT_VERSION'], 'platform': platform.platform(),
    'blocks': 15, 'measured_rows_per_process': 2, 'warmups_per_process': 30,
    'order': 'alternating baseline/candidate then candidate/baseline in chronological paired blocks',
    'resampling_unit': 'whole chronological pair of processes, each retaining both measured rows',
    'seed': 6725, 'draws': 10000, 'descriptive_upper_ratio_gate': 1.05,
    'limitations': 'shared VM; block independence and external temporal effects not guaranteed; not a population confidence guarantee',
    'runner_sha256': {name: hashlib.sha256(path.read_bytes()).hexdigest() for name, path in runners.items()}}
(out/'protocol.json').write_text(json.dumps(metadata, indent=2)+'\n')
records = []
for block in range(15):
    for name in (['baseline', 'candidate'] if block % 2 == 0 else ['candidate', 'baseline']):
        path = out/f'{name}-block{block}.json'; env['INNODI_MACRO_BENCH_OUTPUT'] = str(path)
        command = [str(runners[name]), '--testing-library', 'swift-testing', '--filter', 'MacroPerformanceBenchmark.measureExpansion']
        with (out/f'{name}-block{block}.log').open('w') as log:
            subprocess.run(command, env=env, stdout=log, stderr=subprocess.STDOUT, check=True)
        data = json.loads(path.read_text())
        assert data['workload_verified'] and data['warmup_iterations'] == 30 and len(data['samples_ms']) == 2
        records.append({'block': block, 'name': name, 'samples_ms': data['samples_ms']})
        (out/'raw.json').write_text(json.dumps({'protocol': metadata, 'records': records}, indent=2)+'\n')
        print(name, block, data['samples_ms'], flush=True)
by_name = {name: sorted((r for r in records if r['name'] == name), key=lambda r:r['block']) for name in runners}
values = {name: [v for r in rows for v in r['samples_ms']] for name, rows in by_name.items()}
rng = random.Random(6725); ratios = []
for _ in range(10000):
    indices = [rng.randrange(15) for _ in range(15)]
    sampled = {name: [v for index in indices for v in by_name[name][index]['samples_ms']] for name in runners}
    ratios.append(statistics.median(sampled['candidate']) / statistics.median(sampled['baseline']))
ratios.sort()
summary = {'median_ms': {name: statistics.median(v) for name, v in values.items()},
    'median_ratio': statistics.median(values['candidate']) / statistics.median(values['baseline']),
    'descriptive_block_interval': [ratios[250], ratios[9749]],
    'block_medians_ms': {name: [statistics.median(r['samples_ms']) for r in rows] for name, rows in by_name.items()},
    'defined_local_gate_pass': ratios[9749] <= 1.05,
    'not_population_confidence_guarantee': True}
(out/'summary.json').write_text(json.dumps(summary, indent=2)+'\n'); print(json.dumps(summary, indent=2))
