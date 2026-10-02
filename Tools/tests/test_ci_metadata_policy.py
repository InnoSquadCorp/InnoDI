"""Native metadata no-ops cannot replace, green, cancel or hide real CI evidence."""
import copy
import importlib.util
from pathlib import Path
import unittest
from unittest import mock

import test_dependabot_merge_policy as bot
import test_main_ci_reuse_policy as reuse

ROOT = Path(__file__).resolve().parents[2]
spec = importlib.util.spec_from_file_location('metadata', ROOT / 'Tools/ci-metadata-policy.py')
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)
META, SUITE, SOURCE = 9900, 9901, 'f' * 40


class MetadataAPI:
    def __init__(self, base, number, head, ancestor, current_source, *, expanded=False):
        self.base, self.head, self.current_source = base, head, current_source
        repo = base.repo
        self.run = dict(id=META, run_number=99, run_attempt=1, workflow_id=base.workflow['id'],
                        path=m.PATH, event='pull_request', head_sha=head, repository=repo, head_repository=repo,
                        pull_requests=[dict(number=number)],
                        status='completed', conclusion='success', check_suite_id=SUITE,
                        display_title=f'CI metadata-only v1 pr:{number} head:{head} base:{ancestor} action:labeled source:{SOURCE}')
        self.commit = dict(sha=SOURCE, parents=[dict(sha=ancestor), dict(sha=head)])
        self.blob = '9' * 40
        self.expected_blob = self.blob
        self.jobs, self.checks = [], []
        names = m.INVENTORIES[-1 if expanded else 0]
        for i, name in enumerate(sorted(names)):
            job = dict(id=20000+i, name=name, run_id=META, run_attempt=1, head_sha=head,
                       status='completed', conclusion='skipped', steps=[],
                       check_run_url=f'https://api.github.com/repos/{bot.p.REPOSITORY}/check-runs/{30000+i}')
            self.jobs.append(job)
            self.checks.append(dict(id=30000+i, name=name, app=dict(id=15368), check_suite=dict(id=SUITE),
                                    head_sha=head, status='completed', conclusion='skipped',
                                    details_url=f'https://github.com/{bot.p.REPOSITORY}/actions/runs/{META}/job/{job["id"]}'))
        self.base.runs.append(self.run)
        self.finish_mutation = None
        self.run_reads = 0

    def get(self, route):
        if route.endswith(f'actions/runs/{META}'):
            self.run_reads += 1
            result = copy.deepcopy(self.run)
            if self.run_reads % 2 == 0 and self.finish_mutation:
                self.finish_mutation(result)
            return result
        if route.endswith('git/commits/' + SOURCE):
            return copy.deepcopy(self.commit)
        if '/contents/' + m.PATH + '?ref=' in route:
            return dict(sha=self.blob if route.endswith(SOURCE) else self.expected_blob)
        return self.base.get(route)

    def pages(self, route, key=None):
        if f'check-suites/{SUITE}/' in route:
            return copy.deepcopy(self.checks)
        if f'actions/runs/{META}/attempts/1/jobs' in route:
            return copy.deepcopy(self.jobs)
        result = self.base.pages(route, key)
        if f'commits/{self.head}/check-runs?' in route:
            result += copy.deepcopy(self.checks)
        return result

    def graphql(self, query, variables):
        return self.base.graphql(query, variables)


def reuse_api(expanded=False):
    t = reuse.Transcript()
    return MetadataAPI(t, reuse.NUMBER, reuse.HEAD, reuse.BASE, reuse.MAIN, expanded=expanded)


class MetadataProofTests(unittest.TestCase):
    def test_latest_real_ci_is_preserved_for_main_reuse_and_bot_readiness(self):
        for expanded in (False, True):
            api = reuse_api(expanded)
            proof = reuse.p.prove(api, api.base.event, reuse.CONTEXT, now=api.base.now)
            self.assertEqual(proof['run'], reuse.RUN)
            b = MetadataAPI(bot.Transcript(), bot.NUMBER, bot.HEAD, bot.BASE, bot.MERGE, expanded=expanded)
            self.assertEqual(bot.p.proof(b, bot.NUMBER)['run'], bot.RUN)
            self.assertEqual(b.base.mutations, [])

    def test_a_failed_pending_or_cancelled_real_run_cannot_be_hidden_by_metadata(self):
        for status, conclusion in [('completed', 'failure'), ('in_progress', None), ('completed', 'cancelled')]:
            api = reuse_api()
            api.base.run.update(status=status, conclusion=conclusion)
            with self.assertRaises(ValueError):
                reuse.p.prove(api, api.base.event, reuse.CONTEXT, now=api.base.now)
            b = MetadataAPI(bot.Transcript(), bot.NUMBER, bot.HEAD, bot.BASE, bot.MERGE)
            b.base.run.update(status=status, conclusion=conclusion)
            with self.assertRaises(ValueError):
                bot.p.proof(b, bot.NUMBER)

    def test_title_alone_or_incomplete_native_provenance_is_never_exempted(self):
        mutations = [
            lambda a: a.run.update(display_title=m.PREFIX + 'forged'),
            lambda a: a.run.update(workflow_id=999), lambda a: a.run.update(event='workflow_dispatch'),
            lambda a: a.run.update(head_sha='0' * 40), lambda a: a.run.update(repository={'id': 999}),
            lambda a: a.run.update(status='in_progress'), lambda a: a.run.update(conclusion='cancelled'),
            lambda a: a.run.update(check_suite_id=0), lambda a: a.run.update(run_attempt=0),
            lambda a: a.commit['parents'][0].update(sha='0' * 40),
            lambda a: setattr(a, 'blob', '0' * 40), lambda a: setattr(a, 'expected_blob', ''),
            lambda a: a.jobs.pop(), lambda a: a.jobs.append(copy.deepcopy(a.jobs[0])),
            lambda a: a.jobs[0].update(name='CI Required'), lambda a: a.jobs[0].update(conclusion='success'),
            lambda a: a.jobs[0].update(steps=[{'name': 'executed'}]),
            lambda a: a.jobs[0].update(check_run_url='https://example.invalid/123'),
            lambda a: a.jobs[0].update(run_id=0), lambda a: a.jobs[0].update(run_attempt=2),
            lambda a: a.checks[0]['app'].update(id=999), lambda a: a.checks[0].update(head_sha='0'*40),
            lambda a: a.checks[0].update(conclusion='success'), lambda a: a.checks[0].update(details_url='wrong'),
            lambda a: a.checks.append(copy.deepcopy(a.checks[0])),
            lambda a: setattr(a, 'finish_mutation', lambda r: r.update(run_attempt=2)),
        ]
        for index, mutate in enumerate(mutations):
            api = reuse_api()
            mutate(api)
            with self.subTest(index=index), self.assertRaises(ValueError):
                reuse.p.prove(api, api.base.event, reuse.CONTEXT, now=api.base.now)

    def test_metadata_alone_is_not_full_ci(self):
        api = reuse_api()
        api.base.runs = [api.run]
        with self.assertRaisesRegex(ValueError, 'missing exact-head CI'):
            reuse.p.prove(api, api.base.event, reuse.CONTEXT, now=api.base.now)

    def test_newer_real_validation_supersedes_obsolete_metadata_definition(self):
        api = reuse_api()
        api.run['run_number'] = 29
        api.blob = '0' * 40
        self.assertEqual(reuse.p.prove(api, api.base.event, reuse.CONTEXT, now=api.base.now)['run'], reuse.RUN)
        self.assertEqual(api.run_reads, 0)
        b = MetadataAPI(bot.Transcript(), bot.NUMBER, bot.HEAD, bot.BASE, bot.MERGE)
        b.run['run_number'] = 29
        b.blob = '0' * 40
        self.assertEqual(bot.p.proof(b, bot.NUMBER)['run'], bot.RUN)
        self.assertEqual(b.run_reads, 0)
        b.base.run.update(status='completed', conclusion='failure')
        with self.assertRaises(ValueError):
            bot.p.proof(b, bot.NUMBER)

    def test_pending_metadata_is_a_controlled_block_not_a_failed_coordinator(self):
        b = MetadataAPI(bot.Transcript(), bot.NUMBER, bot.HEAD, bot.BASE, bot.MERGE)
        b.run.update(status='in_progress', conclusion=None)
        with mock.patch.dict(bot.os.environ, bot.TRUSTED):
            result = bot.p.coordinate(b, bot.NUMBER, True, dict(id=bot.RUN, run_attempt=1))
        self.assertIn('blocked:', result)
        self.assertEqual(b.base.mutations, [])
