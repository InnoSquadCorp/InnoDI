import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

spec=importlib.util.spec_from_file_location('resolution',Path(__file__).resolve().parents[1]/'collect_ci_resolution_evidence.py')
m=importlib.util.module_from_spec(spec);spec.loader.exec_module(m)

class ResolutionEvidenceTests(unittest.TestCase):
 def setUp(self):
  self.temp=tempfile.TemporaryDirectory();self.addCleanup(self.temp.cleanup);self.root=Path(self.temp.name).resolve()/'repo';self.root.mkdir();self.example=self.root/'Examples/SampleApp';self.example.mkdir(parents=True)
  for p in (self.root,self.example):(p/'Package.swift').write_text('// exact manifest')
  self.env={'GITHUB_SHA':'a'*40,'GITHUB_RUN_ID':'1','GITHUB_RUN_ATTEMPT':'1'};self.commands=[]
 def fake(self,cmd,**kwargs):
  self.commands.append(cmd)
  if cmd[0]=='git':
   if cmd[3]=='show':return (self.root/cmd[4].split(':',1)[1]).read_text()
   return self.env['GITHUB_SHA']+'\n'
  if cmd==['xcrun','swift','--version']:return 'Swift actual toolchain fixture\n'
  if cmd==['xcodebuild','-version']:return 'Xcode fixture\n'
  package=Path(cmd[cmd.index('--package-path')+1])
  if cmd[-1]=='resolve':(package/'Package.resolved').write_text(json.dumps({'version':3,'pins':[{'identity':'swift-syntax'}]}));return ''
  return '{"name":"fixture"}\n'
 def test_real_command_boundary_copies_generated_bytes_and_provenance(self):
  output=self.root.parent/'evidence';proof=m.collect(self.root,'SampleApp',output,self.env,self.fake)
  self.assertEqual((output/'root/Package.resolved').read_bytes(),(self.root/'Package.resolved').read_bytes())
  self.assertEqual(proof['candidate_sha'],self.env['GITHUB_SHA']);self.assertEqual(len(proof['packages']),2)
  self.assertEqual(sum(c[-1]=='resolve' for c in self.commands),2)
  self.assertIn('not compilation',proof['scope'])
 def test_missing_generated_lock_cannot_emit_proof(self):
  def missing(cmd,**kw):
   if cmd[-1]=='resolve':return ''
   return self.fake(cmd,**kw)
  output=self.root.parent/'missing'
  with self.assertRaises(FileNotFoundError):m.collect(self.root,'SampleApp',output,self.env,missing)
  self.assertFalse(output.exists())
 def test_failed_resolve_never_emits_success(self):
  def fail(cmd,**kw):
   if cmd[-1]=='resolve':raise RuntimeError('resolver failed')
   return self.fake(cmd,**kw)
  output=self.root.parent/'failed'
  with self.assertRaises(RuntimeError):m.collect(self.root,'SampleApp',output,self.env,fail)
  self.assertFalse(output.exists())
 def test_dirty_manifest_cannot_claim_committed_candidate(self):
  def dirty(cmd,**kw):
   if cmd[0]=='git' and cmd[3]=='show':return '// different committed manifest'
   return self.fake(cmd,**kw)
  with self.assertRaises(ValueError):m.collect(self.root,'SampleApp',self.root.parent/'dirty',self.env,dirty)
  self.assertFalse(any(c[-1]=='resolve' for c in self.commands))
 def test_later_resolution_cannot_change_earlier_input(self):
  def changed(cmd,**kw):
   result=self.fake(cmd,**kw)
   if cmd[-1]=='resolve' and str(self.example) in cmd:(self.root/'Package.swift').write_text('// changed later')
   return result
  output=self.root.parent/'changed'
  with self.assertRaises(ValueError):m.collect(self.root,'SampleApp',output,self.env,changed)
  self.assertFalse(output.exists())
 def test_stale_output_and_unknown_consumer_reject(self):
  with self.assertRaises(ValueError):m.collect(self.root,'Unknown',self.root.parent/'x',self.env,self.fake)
  with self.assertRaises(ValueError):m.collect(self.root,'SampleApp',self.root,self.env,self.fake)
 def test_wrong_candidate_rejects_before_resolve(self):
  def wrong(cmd,**kw):return 'b'*40+'\n' if cmd[0]=='git' else self.fake(cmd,**kw)
  with self.assertRaises(ValueError):m.collect(self.root,'SampleApp',self.root.parent/'x',self.env,wrong)
  self.assertEqual(self.commands,[])

if __name__=='__main__':unittest.main()
