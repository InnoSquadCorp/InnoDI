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


def evaluate(expression, values):
    for key in sorted(values, key=len, reverse=True):
        expression = expression.replace(key, repr(values[key]))
    expression = expression.replace('&&', ' and ').replace('||', ' or ')
    return bool(eval(expression, {'__builtins__': {}}))


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
