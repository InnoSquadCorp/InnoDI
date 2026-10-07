import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import types
import unittest
from unittest import mock

spec=importlib.util.spec_from_file_location('runner',Path(__file__).resolve().parents[1]/'run_ci_product_tests.py');r=importlib.util.module_from_spec(spec);spec.loader.exec_module(r)
class ScopedRuntimeTests(unittest.TestCase):
 def setUp(self):
  t=tempfile.TemporaryDirectory();self.addCleanup(t.cleanup);self.root=Path(t.name);(self.root/'build').mkdir();self.env={'RUNNER_TEMP':str(self.root)};self.receipt=self.root/'receipt.json';self.proof={'product':'InnoDITesting','candidate':'a'*40};self.plan={'product_test_scope':self.proof};self.calls=[];self.closure={'first_party_modules':['InnoDITesting']}
  self.tests=types.SimpleNamespace(SWIFT=['xcrun','swift'],TEST_FLAGS=['--no-parallel','-Xswiftc','-warnings-as-errors'],prepare=lambda *a:{'test_arguments':['--package-path',str(self.root/'consumer'),'--force-resolved-versions']},inspect=lambda *a:{'verified':True},verify_build_closure=lambda *a:self.closure)
  p=mock.patch.object(r,'proof_for',return_value=self.proof);p.start();self.addCleanup(p.stop)
  p=mock.patch.object(r,'module',side_effect=lambda name:self.tests if name=='ci_product_tests' else types.SimpleNamespace(verify=lambda *a,**kw:{'baseline_match':True}));p.start();self.addCleanup(p.stop)
 def fake_run(self,cmd,**kw):
  self.calls.append(cmd);self.assertTrue(kw['check'])
 def execute(self):return r.execute(self.root,self.plan,{},self.env,self.receipt,self.fake_run)
 def test_selected_package_commands_and_api_receipt(self):
  self.execute();command=self.calls[0];self.assertIn('--package-path',command);self.assertIn('--force-resolved-versions',command);self.assertNotIn('--filter',command)
  self.assertEqual(r.verify_api(self.root,self.plan,{},self.env,self.receipt),{'baseline_match':True})
 def test_failed_test_cannot_write_success(self):
  def fail(*a,**kw):raise subprocess.CalledProcessError(1,a[0])
  with self.assertRaises(subprocess.CalledProcessError):r.execute(self.root,self.plan,{},self.env,self.receipt,fail)
  self.assertFalse(self.receipt.exists())
 def test_unrelated_compile_closure_rejects_even_successful_command(self):
  def reject(*a):raise ValueError('unrelated product built')
  self.tests.verify_build_closure=reject
  with self.assertRaises(ValueError):self.execute()
  self.assertFalse(self.receipt.exists())
 def test_stale_receipt_and_forged_command_are_rejected(self):
  self.execute()
  with self.assertRaises(ValueError):self.execute()
  data=json.loads(self.receipt.read_text());data['command']=['true'];self.receipt.write_text(json.dumps(data))
  with self.assertRaises(ValueError):r.verify_api(self.root,self.plan,{},self.env,self.receipt)
 def test_scratch_escape_or_missing_receipt_cannot_pass_api(self):
  with self.assertRaises(FileNotFoundError):r.verify_api(self.root,self.plan,{},self.env,self.receipt)
  self.execute();data=json.loads(self.receipt.read_text());data['scratch']='/tmp/unrelated';self.receipt.write_text(json.dumps(data))
  with self.assertRaises(ValueError):r.verify_api(self.root,self.plan,{},self.env,self.receipt)

if __name__=='__main__':unittest.main()
