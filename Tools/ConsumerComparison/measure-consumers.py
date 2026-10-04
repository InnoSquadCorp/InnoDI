#!/usr/bin/env python3
"""Linux, serialized release consumer measurements; keep all samples and pins."""
import hashlib,json,os,pathlib,platform,random,shutil,statistics,subprocess,sys,time
root=pathlib.Path(sys.argv[1]).resolve();out=pathlib.Path(sys.argv[2]).resolve();out.mkdir(parents=True,exist_ok=True)
names=['InnoDI-baseline','InnoDI-candidate','Factory','Swinject','Dependencies','Needle-runtime','Control']
env=os.environ.copy();env['BENCH_SAMPLES']='10';env.pop('BENCH_VALIDATE_ONLY',None)
records=[];sequence=[]
for block in range(3):
 order=names if block==0 else list(reversed(names)) if block==1 else names[3:]+names[:3]
 for name in order:
  binary=root/f'Consumer-{name}'/'.build/release/Consumer'
  result=out/f'{name}-block{block}.json';error=out/f'{name}-block{block}.stderr'
  start=time.monotonic()
  with result.open('w') as stdout,error.open('w') as stderr:
   p=subprocess.Popen([str(binary)],env=env,stdout=stdout,stderr=stderr)
   _,status,usage=os.wait4(p.pid,0);p.returncode=os.waitstatus_to_exitcode(status)
  elapsed=time.monotonic()-start
  if p.returncode: raise RuntimeError(f'{name} exited {p.returncode}: {error.read_text()}')
  data=json.loads(result.read_text());assert data['oracles_passed'] and data['samples']==10
  records.append({'name':name,'block':block,'data':data,'process_wall_s':elapsed,'peak_rss_kib':usage.ru_maxrss,'user_cpu_s':usage.ru_utime,'system_cpu_s':usage.ru_stime})
  sequence.append([name,block]);print(name,block,'done',flush=True)
metadata={}
for name in names:
 binary=root/f'Consumer-{name}'/'.build/release/Consumer';stripped=out/f'{name}.debug-stripped'
 shutil.copy2(binary,stripped);subprocess.run(['strip','--strip-debug',str(stripped)],check=True)
 validation=env|{'BENCH_VALIDATE_ONLY':'1'}
 assert subprocess.check_output([str(stripped)],env=validation,text=True).strip()=='oracles passed'
 sourceRoot=root/f'Consumer-{name}'/'Sources'
 metadata[name]={'binary_sha256':hashlib.sha256(binary.read_bytes()).hexdigest(),'binary_bytes':binary.stat().st_size,'debug_stripped_elf_bytes':stripped.stat().st_size,'elf_size_B':subprocess.check_output(['size','-B',str(binary)],text=True),'sources':{str(p.relative_to(sourceRoot)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(sourceRoot.rglob('*.swift'))}}
runtime_sources={str(p.relative_to(root)):hashlib.sha256(p.read_bytes()).hexdigest() for p in sorted(root.glob('Runtime-*/Sources/**/*.swift'))}
report={'runtime_source_sha256':runtime_sources,'schema':1,'scope':'single-thread release 20-node shared/on-demand graph; batch-mean times; no Apple package or universal library ranking','compiler':subprocess.check_output(['swiftc','--version'],text=True).strip(),'os':platform.platform(),'sequence':sequence,'records':records,'metadata':metadata,'memory_method':'Linux os.wait4 child ru_maxrss in KiB; whole benchmark process, not retained service heap','cold_definition':'fresh root plus first resolution and release after process metadata/oracle warmup, not cold process startup','first_resolution_lifetime_control':'pre-created roots explicitly retained through a point after warm timing; excludes their ARC teardown from first-resolution timing'}
(out/'raw.json').write_text(json.dumps(report,indent=2)+'\n')
summary=[]
for name in names:
 rows=[x for x in records if x['name']==name];metrics={}
 for metric in ['cold_graph_lifecycle_ms','first_resolution_ms','warm_resolution_ns']:
  values=[v for x in rows for v in x['data'][metric]];assert len(values)==30
  metrics[metric]={'median':statistics.median(values),'p95_batch_mean':sorted(values)[28],'min':min(values),'max':max(values),'block_medians':[statistics.median(x['data'][metric]) for x in rows]}
 summary.append({'name':name,'metrics':metrics,'peak_rss_kib_by_process':[x['peak_rss_kib'] for x in rows],'debug_stripped_elf_bytes':metadata[name]['debug_stripped_elf_bytes']})
(out/'summary.json').write_text(json.dumps(summary,indent=2)+'\n');print(json.dumps(summary,indent=2))
