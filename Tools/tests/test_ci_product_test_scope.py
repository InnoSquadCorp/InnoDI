import copy
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile
import types
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
def module(name):
 spec=importlib.util.spec_from_file_location(name.replace('-','_'),ROOT/'Tools'/(name+'.py'));m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m);return m
s=module('ci_product_test_scope');policy=module('ci-policy')
class ProductScopeTests(unittest.TestCase):
 def setUp(self):
  temp=tempfile.TemporaryDirectory();self.addCleanup(temp.cleanup);self.root=Path(temp.name);self.envgit={**os.environ,'GIT_AUTHOR_NAME':'Test','GIT_COMMITTER_NAME':'Test','GIT_AUTHOR_EMAIL':'test@example.invalid','GIT_COMMITTER_EMAIL':'test@example.invalid'}
  self.git('init','-q','-b','main');(self.root/'Tools').mkdir();shutil.copy(ROOT/'Package.swift',self.root/'Package.swift');shutil.copy(ROOT/'Tools/ci-product-graph.json',self.root/'Tools/ci-product-graph.json');self.base=self.commit()
  self.source=self.root/'Sources/InnoDITesting/Change.swift';self.source.parent.mkdir(parents=True);self.source.write_text('struct Change {}');self.head=self.commit();self.event={'action':'synchronize','pull_request':{'base':{'sha':self.base},'head':{'sha':self.head},'labels':[],'user':{'login':'author'}}};self.env={'GITHUB_SHA':self.head,'GITHUB_EVENT_NAME':'pull_request'}
  self.qual={'product':'InnoDITesting','qualification_sha256':'a'*64};original=s.module
  self.patch=mock.patch.object(s,'module',side_effect=lambda name:types.SimpleNamespace(verify_qualification=lambda *args:dict(self.qual)) if name=='ci_product_tests' else original(name));self.patch.start();self.addCleanup(self.patch.stop)
 def git(self,*args):return subprocess.check_output(['git','-C',str(self.root),'-c','commit.gpgsign=false',*args],env=self.envgit,text=True).strip()
 def commit(self):self.git('add','-A');self.git('commit','-qm','fixture');return self.git('rev-parse','HEAD')
 def test_exact_leaf_proof_revalidates_real_git(self):
  proof=s.prove(self.root,self.event,self.env);self.assertEqual(proof['product'],'InnoDITesting');s.revalidate(self.root,self.event,self.env,proof,proof['paths'])
  self.qual['qualification_sha256']='b'*64
  with self.assertRaises(ValueError):s.revalidate(self.root,self.event,self.env,proof,proof['paths'])
 def test_non_pr_bot_release_disabled_uncertain_and_dirty_stay_full(self):
  for event in ('push','merge_group','release','workflow_dispatch'):
   self.assertIsNone(s.prove(self.root,self.event,{**self.env,'GITHUB_EVENT_NAME':event}))
  for flag in ('false','unknown'):self.assertIsNone(s.prove(self.root,self.event,{**self.env,'PRODUCT_SCOPE_ENABLED':flag}))
  event=copy.deepcopy(self.event);event['pull_request']['labels']=[{'name':'release-validation'}];self.assertIsNone(s.prove(self.root,event,self.env))
  event=copy.deepcopy(self.event);event['pull_request']['user']['login']='dependabot[bot]';self.assertIsNone(s.prove(self.root,event,self.env))
  self.source.write_text('struct Dirty {}');self.assertIsNone(s.prove(self.root,self.event,self.env))
 def test_untracked_relevant_file_and_wrong_head_reject(self):
  self.assertIsNone(s.prove(self.root,self.event,{**self.env,'GITHUB_SHA':'f'*40}))
  (self.source.parent/'Injected.swift').write_text('struct Injected {}');self.assertIsNone(s.prove(self.root,self.event,self.env))
 def test_mixed_unknown_path_cannot_narrow(self):
  (self.root/'unknown.txt').write_text('unknown');head=self.commit();self.event['pull_request']['head']['sha']=head;self.env['GITHUB_SHA']=head
  self.assertIsNone(s.prove(self.root,self.event,self.env))
 def test_policy_omissions_require_proof_and_preserve_aggregate(self):
  proof=s.prove(self.root,self.event,self.env);paths=proof['paths'];plan=policy.make_plan('pull_request',self.event,paths)
  with mock.patch.object(policy,'product_scope_module',return_value=s),mock.patch.dict(os.environ,self.env,clear=True):
   scoped=policy.apply_product_tests(plan,self.root,self.event,paths);policy.validate_plan(scoped)
   self.assertEqual({j for j,v in scoped['jobs'].items() if v},{'policy','fast-tests'})
   needs={j:{'result':'success' if chosen else 'skipped'} for j,chosen in scoped['jobs'].items()};needs['ci-plan']={'result':'success'}
   policy.evaluate(scoped,needs,root=self.root,event=self.event)
   needs['fast-tests']['result']='skipped'
   with self.assertRaises(ValueError):policy.evaluate(scoped,needs,root=self.root,event=self.event)
   bad=copy.deepcopy(scoped);bad['jobs']['policy']=False
   with self.assertRaises(ValueError):policy.validate_plan(bad)
   bad=copy.deepcopy(scoped);del bad['product_test_scope']
   with self.assertRaises(ValueError):policy.validate_plan(bad)
 def test_swiftui_requires_all_consumer_pins_and_selects_relevant_examples(self):
  self.git('checkout','-q','--detach',self.base)
  lock={'version':3,'pins':[{'identity':'swift-syntax','state':{'revision':'a'*40}}]}
  for relative in ['Package.resolved']+['Examples/'+unit+'/Package.resolved' for unit in ('SampleApp','SwiftUIExample','PreviewInjectionExample')]:
   path=self.root/relative;path.parent.mkdir(parents=True,exist_ok=True);path.write_text(json.dumps(lock))
  path=self.root/'Sources/InnoDISwiftUI/Leaf.swift';path.parent.mkdir(parents=True);path.write_text('struct Before {}');base=self.commit();path.write_text('struct After {}');head=self.commit()
  self.event['pull_request']['base']['sha']=base;self.event['pull_request']['head']['sha']=head;self.env['GITHUB_SHA']=head;self.qual['product']='InnoDISwiftUI'
  proof=s.prove(self.root,self.event,self.env);self.assertEqual(proof['product'],'InnoDISwiftUI')
  plan=policy.make_plan('pull_request',self.event,proof['paths'])
  with mock.patch.object(policy,'product_scope_module',return_value=s),mock.patch.dict(os.environ,self.env,clear=True):
   scoped=policy.apply_product_tests(plan,self.root,self.event,proof['paths']);policy.validate_plan(scoped);self.assertTrue(scoped['examples_full']);self.assertTrue(scoped['jobs']['documentation-contracts'])
 def test_exact_synthetic_merge_parents_are_required(self):
  self.git('checkout','-q','-b','advanced-main',self.base);(self.root/'README.md').write_text('base-only');base=self.commit();self.git('merge','--no-ff','-m','synthetic candidate',self.head);merge=self.git('rev-parse','HEAD')
  self.event['pull_request']['base']['sha']=base;self.env['GITHUB_SHA']=merge
  self.assertEqual(s.prove(self.root,self.event,self.env)['candidate'],merge)
  self.event['pull_request']['base']['sha']=self.base;self.assertIsNone(s.prove(self.root,self.event,self.env))
 def test_malformed_or_other_bot_author_and_boolean_schema_reject(self):
  for user in ({'login':12},{'login':'automation[bot]'}, {'login':'automation','type':'Bot'}):
   event=copy.deepcopy(self.event);event['pull_request']['user']=user;self.assertIsNone(s.prove(self.root,event,self.env))
  proof=s.prove(self.root,self.event,self.env);proof['schema']=True
  with self.assertRaises(ValueError):s.validate(proof,proof['paths'])
 def test_manifest_drift_and_executable_source_force_full(self):
  self.source.chmod(0o755);head=self.commit();self.event['pull_request']['head']['sha']=head;self.env['GITHUB_SHA']=head
  self.assertIsNone(s.prove(self.root,self.event,self.env))
  self.source.chmod(0o644);(self.root/'Package.swift').write_text('// changed manifest');head=self.commit();self.event['pull_request']['head']['sha']=head;self.env['GITHUB_SHA']=head
  self.assertIsNone(s.prove(self.root,self.event,self.env))
 def test_replacement_proof_replays_even_for_release_label_or_bot(self):
  import re
  from test_ci_event_routing import expression_value
  self.assertTrue(policy.qualification_proof_changed({'changes':[{'path':'Tools/CIProductTests/InnoDITesting/qualification.json'}]}))
  self.assertFalse(policy.qualification_proof_changed({'changes':[{'path':'Sources/InnoDITesting/Leaf.swift'}]}))
  workflow=(ROOT/'.github/workflows/macro-tests.yml').read_text()
  condition=workflow.split('      - name: Qualify isolated product test packages\n',1)[1].split('        if: ',1)[1].split('\n',1)[0]
  condition=re.sub(r"hashFiles\('[^']+'\)","'present'",condition)
  values={'github.event_name':'pull_request','needs.ci-plan.outputs.qualification-proof-change':'true','needs.ci-plan.outputs.qualification-refresh':'false','github.event.pull_request.user.login':'dependabot[bot]','github.event.pull_request.labels.*.name':['release-validation']}
  self.assertTrue(expression_value(condition,values))
  self.assertFalse(expression_value(condition,{**values,'github.event_name':'push'}))
  self.assertFalse(expression_value(condition,{**values,'needs.ci-plan.outputs.qualification-proof-change':'false'}))
 def test_changed_qualification_or_bound_input_forces_real_refresh(self):
  for path in ('Tools/CIProductTests/InnoDITesting/qualification.json','Package.resolved','Tools/ci_product_api.py','Tests/InnoDISwiftUITests/Changed.swift','__diff_unavailable_full_fallback__'):
   self.assertTrue(policy.qualification_refresh_needed({'changes':[{'path':path}]}))
  self.assertFalse(policy.qualification_refresh_needed({'changes':[{'path':'Sources/InnoDITesting/Leaf.swift'}]}))
  workflow=(ROOT/'.github/workflows/macro-tests.yml').read_text()
  self.assertIn("needs.ci-plan.outputs.qualification-refresh == 'true'",workflow)
 def test_shared_and_unsupported_products_never_suppress_gates(self):
  with self.assertRaises(ValueError):s.required_jobs('InnoDI')
  self.assertEqual(s.required_jobs('InnoDISwiftUI'),{'policy','fast-tests','examples','documentation-contracts','docc'})

if __name__=='__main__':unittest.main()
