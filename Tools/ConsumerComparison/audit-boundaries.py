#!/usr/bin/env python3
"""Record actual SwiftBuild compile/link commands and source-module boundaries."""
import hashlib,json,pathlib,shlex,sys,msgpack
root=pathlib.Path(sys.argv[1]);out=pathlib.Path(sys.argv[2]);result={}
for package in sorted(root.glob('Consumer-*')):
 records={};manifests=[];links=[]
 stores=sorted(package.glob('.build/**/task-store.msgpack'), key=lambda p:p.stat().st_mtime_ns, reverse=True)
 for path in stores[:1]:
  unpacker=msgpack.Unpacker(raw=False,strict_map_key=False);unpacker.feed(path.read_bytes())
  def walk(x):
   if isinstance(x,list):
    if all(isinstance(v,str) for v in x) and '-module-name' in x and '-O' in x:
     module=x[x.index('-module-name')+1]
     if module not in records:
      filelists=[pathlib.Path(v[1:]) for v in x if v.startswith('@') and v.endswith('.SwiftFileList')]
      records[module]={'arguments':x,'swift_version':x[x.index('-swift-version')+1] if '-swift-version' in x else 'default','package_name':x[x.index('-package-name')+1] if '-package-name' in x else None,'optimization':'-O','whole_module_optimization':'-whole-module-optimization' in x,'library_evolution':'-enable-library-evolution' in x,'cross_module_optimization':'-cross-module-optimization' in x or '-enable-cmo-everything' in x,'source_files':[shlex.split(f)[0] for p in filelists for f in p.read_text().splitlines() if f.strip()]}
    else:
     for value in x:walk(value)
   elif isinstance(x,dict):
    for value in x.values():walk(value)
  for item in unpacker:walk(item)
 for path in [p.with_name('manifest.json') for p in stores[:1]]:
  data=json.loads(path.read_text());manifests.append(str(path))
  for command in data.get('commands',{}).values():
   args=command.get('args',[])
   if '-emit-executable' in args: links.append(args)
 filepaths={pathlib.Path(f) for path in [p.with_name('manifest.json') for p in stores[:1]] for command in json.loads(path.read_text()).get('commands',{}).values() for f in command.get('inputs',[]) if f.endswith('.LinkFileList')}
 filelists={str(p):p.read_text().splitlines() for p in sorted(filepaths) if p.exists()}
 for record in records.values():
  record['source_sha256']={f:hashlib.sha256(pathlib.Path(f).read_bytes()).hexdigest() for f in record['source_files']}
 result[package.name]={'modules':records,'executable_link_arguments':links,'link_file_lists':filelists,'build_manifests':manifests}
out.write_text(json.dumps(result,indent=2)+'\n')
for name,data in result.items():
 print(name, [(m,x['swift_version'],x['whole_module_optimization'],x['cross_module_optimization'],x['library_evolution']) for m,x in data['modules'].items()])
