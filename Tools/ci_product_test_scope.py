"""Exact PR leaf-product proof; runtime qualification remains a separate gate."""
import hashlib
import importlib.util
import json
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parent


def module(name):
    spec=importlib.util.spec_from_file_location(name.replace('-','_'),ROOT/(name+'.py'))
    value=importlib.util.module_from_spec(spec);spec.loader.exec_module(value);return value


def git(root,*args):
    return subprocess.check_output(['git','-C',str(root),*args],text=True,stderr=subprocess.PIPE).strip()


def prove(root,event,env):
    """Return None for uncertainty; never infer a qualified lane from extensions."""
    try:
        if env.get('GITHUB_EVENT_NAME')!='pull_request' or env.get('PRODUCT_SCOPE_ENABLED','').lower() not in ('','true'):return None
        if event.get('action') not in ('opened','synchronize','reopened','edited','labeled','unlabeled'):return None
        if event['action']=='edited' and not event.get('changes',{}).get('base'):return None
        pr=event['pull_request'];labels=pr['labels']
        if not isinstance(labels,list) or any(not isinstance(x,dict) or not isinstance(x.get('name'),str) for x in labels):return None
        author=pr['user']['login']
        if not isinstance(author,str) or not author or author.lower().endswith('[bot]') or pr['user'].get('type') not in (None,'User'):return None
        if any(x['name'].lower()=='release-validation' for x in labels):return None
        root=Path(root).resolve();candidate=git(root,'rev-parse','HEAD');base=pr['base']['sha'];head=pr['head']['sha']
        execution=module('ci_product_execution')
        if any(not execution.SHA.fullmatch(x or '') for x in (candidate,base,head)) or candidate!=env.get('GITHUB_SHA'):return None
        if candidate!=head and git(root,'show','-s','--format=%P',candidate).split()!=[base,head]:return None
        if git(root,'status','--porcelain','--untracked-files=no'):return None
        graph_path=root/'Tools/ci-product-graph.json';graph=json.loads(graph_path.read_text());execution.impact.validate(graph)
        manifest=hashlib.sha256((root/'Package.swift').read_bytes()).hexdigest()
        if graph['manifest_sha256']!=manifest:return None
        paths=execution.impact.diff_paths(root,base,head);execution.regular_source_diff(root,base,head)
        plan=execution.impact.select(graph,paths,manifest)
        if plan['mode']!='scoped-build-plan' or len(plan['affected_products'])!=1:return None
        product=plan['affected_products'][0]
        if product not in ('InnoDISwiftUI','InnoDITesting'):return None
        if product=='InnoDISwiftUI':execution.require_consumer_locks(root)
        if not paths or any(not p.startswith('Sources/'+product+'/') or not p.endswith('.swift') for p in paths):return None
        if git(root,'ls-files','--others','--exclude-standard','--','Sources','Tests','Tools/CIProductTests'):return None
        # No compiler is invoked here. The selected test job must independently
        # verify live toolchain/manifests before its result may be successful.
        qualification=module('ci_product_tests').verify_qualification(root,product)
        return {'schema':1,'product':product,'base':base,'head':head,'candidate':candidate,
                'paths':sorted(paths),'graph_sha256':hashlib.sha256(graph_path.read_bytes()).hexdigest(),
                'qualification':qualification}
    except (ValueError,KeyError,TypeError,OSError,AttributeError,subprocess.CalledProcessError):
        return None


def required_jobs(product):
    if product=='InnoDISwiftUI':return {'policy','fast-tests','examples','documentation-contracts','docc'}
    if product=='InnoDITesting':return {'policy','fast-tests'}
    raise ValueError('unsupported test product')


def validate(proof,paths):
    if not isinstance(proof,dict) or set(proof)!={'schema','product','base','head','candidate','paths','graph_sha256','qualification'} or type(proof['schema']) is not int or proof['schema']!=1:
        raise ValueError('invalid product-test proof')
    required_jobs(proof['product'])
    if proof['paths']!=sorted(paths) or not paths or any(not p.startswith('Sources/'+proof['product']+'/') or not p.endswith('.swift') for p in paths):
        raise ValueError('product-test proof omits changed inputs')
    if not isinstance(proof['qualification'],dict) or proof['qualification'].get('product')!=proof['product']:
        raise ValueError('product qualification identity differs')


def revalidate(root,event,env,proof,paths):
    validate(proof,paths)
    if prove(root,event,env)!=proof:
        raise ValueError('product-test plan no longer matches exact Git/qualification inputs')
