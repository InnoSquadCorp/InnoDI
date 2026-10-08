"""Exercise the actual native admission expressions, including their negative paths."""
from pathlib import Path
import re
import unittest

ROOT = Path(__file__).resolve().parents[2]


def condition(source, job):
    block = source.split('\n  ' + job + ':\n', 1)[1]
    block = re.split(r'\n  [\w-]+:\n', block, maxsplit=1)[0]
    found = re.search(r'^    if: (.+)(?:\n|$)', block, re.M)
    value = found[1]
    if value == '>-':
        value = ' '.join(re.match(r'(?:      .*\n)+', block[found.end():])[0].split())
    return value.removeprefix('${{ ').removesuffix(' }}')


class GitHubString(str):
    # GitHub compares strings case-insensitively. Use its documented semantics
    # for these string-only predicates, not Python's default string equality.
    def __eq__(self, other):
        if not isinstance(other, str):
            return NotImplemented
        return self.lower() == other.lower()

    def __ne__(self, other):
        equal = self.__eq__(other)
        return NotImplemented if equal is NotImplemented else not equal


def expression_value(expression, values):
    values = {'vars.INNO_JOB_CANCELLATION': '', 'github.run_attempt': 1, **values}
    for key in sorted(values, key=len, reverse=True):
        value = repr(values[key])
        expression = expression.replace(key, 'string(' + value + ')' if isinstance(values[key], str) else value)
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    expression = re.sub(r'\bfalse\b', 'False', expression)
    expression = re.sub(r'\btrue\b', 'True', expression)
    expression = re.sub(r'!(?!=)', ' not ', expression).replace('always()', 'True')
    return eval(expression.strip(), {'__builtins__': {}, 'string': GitHubString,
                                    'format': lambda value, *args: value.format(*args),
                                    'contains': lambda values, item: any(str(value).lower() == item.lower() for value in values),
                                    'startsWith': lambda value, prefix: value.lower().startswith(prefix.lower())})


def evaluate(expression, values):
    return bool(expression_value(expression, values))


class PRMetadataAdmissionTests(unittest.TestCase):
    def test_metadata_queues_and_revalidates_a_fixed_required_context(self):
        source = (ROOT / '.github/workflows/macro-tests.yml').read_text()
        title = source.split('run-name: >-\n', 1)[1].split('\non:', 1)[0].strip()[3:-3]
        concurrency = source.split('  group: macro-tests-${{ ', 1)[1].split(' }}', 1)[0]
        required = source.split('  ci-required:\n', 1)[1]
        self.assertIn('    name: CI Required\n', required)
        cancel = source.split('  cancel-in-progress: ${{ ', 1)[1].split(' }}', 1)[0]
        queue = source.split('  queue: ${{ ', 1)[1].split(' }}', 1)[0]
        gate = required.split('      - name: Verify prior validation for metadata\n', 1)[1]
        gate_condition = gate.split('        if: ${{ ', 1)[1].split(' }}', 1)[0]
        for action, label, base, ignored in [
                ('opened', '', '', False), ('synchronize', '', '', False), ('reopened', '', '', False),
                ('labeled', 'release-validation', '', False), ('unlabeled', 'release-validation', '', False),
                ('labeled', 'Release-Validation', '', False), ('unlabeled', 'RELEASE-VALIDATION', '', False),
                ('labeled', 'documentation', '', True), ('unlabeled', 'bug', '', True),
                ('labeled', '', '', False), ('edited', '', '', True),
                ('edited', '', {'ref': {'from': 'develop'}}, False)]:
            values = {'github.event_name': 'pull_request', 'github.event.action': action,
                      'github.event.label.name': label, 'github.event.changes.base': base,
                      'github.event.pull_request.number': 45, 'github.event.pull_request.head.sha': 'a' * 40,
                      'github.event.pull_request.base.sha': 'b' * 40, 'github.workflow_sha': 'c' * 40,
                      'github.event.pull_request.labels.*.name': [], 'github.sha': 'c' * 40, 'github.run_id': 123, 'github.ref': 'refs/pull/45/merge', 'inputs.dependabot_merge_pr': ''}
            with self.subTest(action=action, label=label, base=base):
                self.assertEqual(evaluate(condition(source, 'ci-plan'), values), not ignored)
                self.assertTrue(evaluate(condition(source, 'ci-required'), values))
                self.assertEqual(evaluate(gate_condition, values), ignored)
                self.assertFalse(evaluate(cancel, values))
                self.assertEqual(evaluate(cancel, {**values, 'vars.INNO_JOB_CANCELLATION': 'disabled'}), not ignored)
                self.assertEqual(expression_value(queue, values), 'max' if ignored else 'single')
                self.assertEqual(expression_value(title, values).startswith('CI metadata-only v1 '), ignored)
                self.assertEqual(expression_value(concurrency, values), values['github.ref'])
        for event in ['push', 'merge_group', 'workflow_dispatch']:
            values.update({'github.event_name': event, 'github.event.action': 'edited', 'github.event.changes.base': ''})
            self.assertTrue(evaluate(condition(source, 'ci-plan'), values))
            self.assertEqual(expression_value(queue, values), 'single')
            self.assertTrue(evaluate(cancel, values))
            self.assertTrue(evaluate(condition(source, 'ci-required'), values))

    def test_metadata_runs_allocate_no_other_runner(self):
        source = (ROOT / '.github/workflows/macro-tests.yml').read_text()
        # Every other entrypoint depends on the skipped plan. The only jobs
        # using always() are independently guarded against a skipped plan.
        jobs = re.split(r'\n  ([\w-]+):\n', source.split('\njobs:\n', 1)[1])
        for job, block in zip(jobs[1::2], jobs[2::2]):
            if job in {'ci-plan', 'ci-required'}:
                continue
            if job == 'append-perf-history':
                self.assertIn("needs.ci-plan.result == 'success'", condition(source, job))
            else:
                self.assertIn('    needs: ci-plan\n', block)


class CoordinatorAdmissionTests(unittest.TestCase):
    def test_main_ci_notifications_are_filtered_without_losing_pr_invalidations(self):
        source = (ROOT / '.github/workflows/dependabot-auto-merge.yml').read_text()
        expr = condition(source, 'inspect')
        trusted = {'github.repository': 'InnoSquadCorp/InnoDI', 'github.ref': 'refs/heads/main',
                   'github.workflow_ref': 'InnoSquadCorp/InnoDI/.github/workflows/dependabot-auto-merge.yml@refs/heads/main'}
        for event in ['push', 'schedule', 'workflow_dispatch', 'pull_request_target', 'workflow_run']:
            for path in ['.github/workflows/macro-tests.yml', '.github/workflows/dependabot-ready.yml', '.github/workflows/dependabot-review-notice.yml']:
                for original in ['pull_request', 'push', 'workflow_dispatch', 'merge_group', 'pull_request_target']:
                    values = {**trusted, 'github.event_name': event, 'github.event.workflow_run.path': path,
                              'github.event.workflow_run.event': original}
                    expected = not (event == 'workflow_run' and path.endswith('/macro-tests.yml') and original != 'pull_request')
                    self.assertEqual(evaluate(expr, values), expected)
                    for key in trusted:
                        self.assertFalse(evaluate(expr, {**values, key: 'untrusted'}))

    def test_empty_ready_targets_do_not_suppress_post_merge_recovery(self):
        source = (ROOT / '.github/workflows/dependabot-auto-merge.yml').read_text()
        expr = condition(source, 'ready-plan')
        for result in ['success', 'failure', 'cancelled', 'skipped']:
            for event in ['pull_request_target', 'workflow_run', 'push', 'schedule', 'workflow_dispatch']:
                for targets in ['', '[]', '[45]']:
                    actual = evaluate(expr, {'needs.inspect.result': result, 'github.event_name': event,
                                             'needs.inspect.outputs.prs': targets})
                    self.assertEqual(actual, result == 'success' and event != 'pull_request_target' and targets == '[45]')
        recovery = condition(source, 'post-merge-plan')
        self.assertNotIn('needs.inspect.outputs.prs', recovery)
        for event in ['push', 'schedule', 'workflow_dispatch']:
            self.assertIn("github.event_name == '" + event + "'", recovery)


class DocsAdmissionTests(unittest.TestCase):
    def test_only_eligible_deployment_jobs_enter_the_pages_queue(self):
        source = (ROOT / '.github/workflows/docs.yml').read_text()
        # The default concurrency queue replaces an existing pending item.
        # No-op workflow_run notices must never participate in that queue.
        self.assertNotIn('\nconcurrency:', source)
        deploy = source.split('  deploy-pages:\n', 1)[1]
        self.assertIn('    needs: docc\n', deploy)
        self.assertIn('    concurrency:\n      group: pages\n      cancel-in-progress: false', deploy)
        self.assertEqual(source.count('group: pages'), 1)
        self.assertIn('    branches: [main]\n', source)
        base = {'github.repository': 'InnoSquadCorp/InnoDI',
                'github.event.workflow_run.repository.full_name': 'InnoSquadCorp/InnoDI',
                'github.event.workflow_run.path': '.github/workflows/macro-tests.yml',
                'github.event.workflow_run.head_branch': 'main',
                'github.event.workflow_run.conclusion': 'success',
                'github.event.workflow_run.event': 'push',
                'github.event.workflow_run.display_title': 'CI validation / push / refs/heads/main'}
        admission = condition(source, 'docc')
        self.assertTrue(evaluate(admission, base))
        recovery = {**base, 'github.event.workflow_run.event': 'workflow_dispatch',
                    'github.event.workflow_run.display_title': 'CI / Dependabot merge #50'}
        self.assertTrue(evaluate(admission, recovery))
        for field, value in (
                ('event', 'pull_request'), ('event', 'merge_group'), ('event', 'workflow_dispatch'),
                ('conclusion', 'failure'), ('conclusion', 'cancelled'), ('conclusion', 'skipped'),
                ('head_branch', 'topic'), ('path', '.github/workflows/foreign.yml'),
                ('repository.full_name', 'other/repository')):
            self.assertFalse(evaluate(admission, {**base, 'github.event.workflow_run.' + field: value}))
