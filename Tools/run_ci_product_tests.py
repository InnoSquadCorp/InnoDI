#!/usr/bin/env python3
"""Execute a qualified leaf test package and its selected semantic API gate."""
import argparse
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile


def module(name):
    spec=importlib.util.spec_from_file_location(name,Path(__file__).with_name(name+'.py'))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def proof_for(root,plan,event,env):
    proof=plan.get('product_test_scope')
    if not isinstance(proof,dict):raise ValueError('no qualified product-test plan')
    module('ci_product_test_scope').revalidate(root,event,env,proof,[change['path'] for change in plan['changes']])
    return proof


def execute(root,plan,event,env,receipt,run=subprocess.run):
    root=Path(root).resolve();receipt=Path(receipt)
    if receipt.exists():raise ValueError('stale test receipt already exists')
    proof=proof_for(root,plan,event,env);tests=module('ci_product_tests');product=proof['product']
    prepared=tests.prepare(root,product)
    scratch=Path(tempfile.mkdtemp(prefix='innodi-scoped-tests-',dir=env.get('RUNNER_TEMP')))
    command=[*tests.SWIFT,'test',*prepared['test_arguments'],'--scratch-path',str(scratch),*tests.TEST_FLAGS]
    run(command,cwd=root,check=True)
    inspected=tests.inspect(root,product)
    closure=tests.verify_build_closure(root,product,inspected,scratch,root/'build/ci-product-build-evidence')
    proof_for(root,plan,event,env)
    result={'schema':1,'proof':proof,'scratch':str(scratch),'command':command,'result':'success','build_closure':closure}
    receipt.parent.mkdir(parents=True,exist_ok=True)
    with receipt.open('x') as stream:json.dump(result,stream,sort_keys=True);stream.write('\n')
    return result


def verify_api(root,plan,event,env,receipt):
    root=Path(root).resolve();proof=proof_for(root,plan,event,env)
    result=json.loads(Path(receipt).read_text())
    if set(result)!={'schema','proof','scratch','command','result','build_closure'} or result['schema']!=1 or result['proof']!=proof or result['result']!='success':
        raise ValueError('missing/forged/stale successful scoped test receipt')
    temporary=Path(env.get('RUNNER_TEMP') or tempfile.gettempdir()).resolve();scratch=Path(result['scratch']).resolve()
    if scratch.parent!=temporary or not scratch.name.startswith('innodi-scoped-tests-'):
        raise ValueError('scratch directory escaped the current runner temporary root')
    tests=module('ci_product_tests');prepared=tests.prepare(root,proof['product'])
    expected=[*tests.SWIFT,'test',*prepared['test_arguments'],'--scratch-path',str(scratch),*tests.TEST_FLAGS]
    if result['command']!=expected:raise ValueError('scoped test command changed')
    inspected=tests.inspect(root,proof['product'])
    if tests.verify_build_closure(root,proof['product'],inspected,scratch)!=result['build_closure']:
        raise ValueError('compiled scope changed after test execution')
    checked=module('ci_product_api').verify(root,proof['product'],scratch,evidence_dir=root/'build/ci-product-api-evidence')
    proof_for(root,plan,event,env)
    (root/'build/ci-product-api-result.json').write_text(json.dumps({'proof':proof,'api':checked,'result':'success'},sort_keys=True)+'\n')
    return checked


def main():
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action',choices=('test','api'));parser.add_argument('--receipt',type=Path,default=Path('build/ci-product-test-receipt.json'))
    args=parser.parse_args();plan=json.loads(os.environ['CI_PLAN']);event=json.loads(Path(os.environ['GITHUB_EVENT_PATH']).read_text())
    action=execute if args.action=='test' else verify_api
    print(json.dumps(action(Path.cwd(),plan,event,os.environ,args.receipt),sort_keys=True))


if __name__=='__main__':main()
