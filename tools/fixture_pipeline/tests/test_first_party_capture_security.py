"""Synthetic bookkeeping regressions; no person, real consent or trainer."""
import copy
from contextlib import contextmanager
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from test_first_party_capture import capture, clip, manifest, options, scope, synthetic_media, targets


@contextmanager
def fixture(doc=None):
    with tempfile.TemporaryDirectory() as folder:
        root = Path(folder)
        doc = copy.deepcopy(doc) if doc is not None else manifest()
        synthetic_media(doc, root)
        artifact, pipeline = root / 'artifact', root / 'pipeline'
        artifact.write_text('synthetic parameters, not a model')
        pipeline.write_text('not executable training code')
        validation = {'partition': 'validation', 'scope': scope(doc),
                      'manifest_sha256': capture.digest(doc),
                      'artifact_sha256': capture.file_sha(artifact),
                      'pipeline_sha256': capture.file_sha(pipeline)}
        yield root, doc, artifact, pipeline, validation


def freeze(root, doc, artifact, pipeline, validation, **changes):
    kw = options(doc, root) | changes
    return capture.freeze(doc, artifact, pipeline, validation, root / 'freeze.json', **kw)


def open_test(root, doc, receipt, artifact, pipeline, validation, **changes):
    kw = options(doc, root) | {'state_root': root} | changes
    marker = kw.pop('marker', root / ('test-opened-' + doc['dataset_id'] + '.json'))
    return capture.open_test(doc, receipt, artifact, pipeline, validation, marker, **kw)


class CaptureSecurityTests(unittest.TestCase):
    def test_split_permissions_cannot_be_replaced_by_demo_purpose(self):
        for index, flag in [(0, 'training'), (1, 'training'), (1, 'evaluation')]:
            with self.subTest(index=index, flag=flag):
                d = manifest(); c = d['clips'][index]; c['purpose'] = 'demonstration'
                c['permissions'].update(demo_distribution=True)
                c['permissions'][flag] = False
                with self.assertRaisesRegex(capture.IntakeError, 'permission missing: ' + flag):
                    capture.validate(d)

    def test_demo_only_reference_remains_collection_without_development(self):
        d = manifest(); c = d['clips'][0]
        c.update(partition='reference', purpose='demonstration')
        c['permissions'].update(training=False, evaluation=False, demo_distribution=True)
        self.assertEqual(capture.validate(d)['status'], 'VALID_COLLECTION')
        self.assertFalse(capture.validate(d)['independent_evaluation_ready'])
        c['permissions']['training'] = True
        self.assertTrue(capture.validate(d)['independent_evaluation_ready'])

    def test_evaluation_only_test_does_not_require_training(self):
        d = manifest(); d['clips'][-1]['permissions']['training'] = False
        self.assertTrue(capture.validate(d)['independent_evaluation_ready'])

    def mutate(self, name, root, doc):
        c = doc['clips'][-1]; video = root / c['path']; consent = root / 'permissions.txt'
        if name == 'missing_video': video.unlink()
        elif name == 'video_same_size': video.write_bytes(b'x' * c['bytes'])
        elif name == 'video_wrong_size': video.write_bytes(b'x')
        elif name == 'missing_consent': consent.unlink()
        elif name == 'consent_same_size': consent.write_bytes(b'x' * consent.stat().st_size)
        elif name == 'video_symlink':
            other = root / 'owned-original.mp4'; video.rename(other); video.symlink_to(other)
        elif name == 'consent_symlink':
            other = root / 'owned-permission.txt'; consent.rename(other); consent.symlink_to(other)
        else: raise AssertionError(name)

    def test_freeze_and_open_recheck_all_media_and_consent_before_writing(self):
        names = ['missing_video', 'video_same_size', 'video_wrong_size',
                 'missing_consent', 'consent_same_size', 'video_symlink', 'consent_symlink']
        for stage in ['freeze', 'open_test']:
            for name in names:
                with self.subTest(stage=stage, mutation=name), fixture() as data:
                    root, doc, a, p, v = data
                    receipt = freeze(*data) if stage == 'open_test' else None
                    self.mutate(name, root, doc)
                    with self.assertRaises(capture.IntakeError):
                        if stage == 'freeze': freeze(root, doc, a, p, v)
                        else: open_test(root, doc, receipt, a, p, v)
                    output = root / ('freeze.json' if stage == 'freeze' else 'test-opened-' + doc['dataset_id'] + '.json')
                    self.assertFalse(output.exists())

    def test_invalid_local_paths_do_not_reserve_freeze(self):
        for field, name in [('path', '../owned.mp4'), ('path', '/tmp/owned.mp4'),
                            ('evidence_path', '../permission.txt'), ('evidence_path', 'https://example.invalid/consent')]:
            with self.subTest(field=field, name=name), fixture() as data:
                root, doc, a, p, v = data
                if field == 'path': doc['clips'][-1][field] = name
                else: doc['clips'][-1]['permissions'][field] = name
                v['manifest_sha256'] = capture.digest(doc)
                with self.assertRaises(capture.IntakeError): freeze(root, doc, a, p, v)
                self.assertFalse((root / 'freeze.json').exists())

    def test_each_candidate_dimension_must_have_its_own_partitions(self):
        changes = [{'app': 'lissom', 'area': 'hatha'}, {'area': 'barbell'},
                   {'course_sha256': 'c' * 64}, {'lesson_id': 'another-lesson'}, {'movement_id': 'another-movement'}]
        for change in changes:
            with self.subTest(change=change):
                d = manifest(); d['clips'][1].update(change)
                self.assertFalse(capture.validate(d)['independent_evaluation_ready'])
                with fixture(d) as data:
                    with self.assertRaisesRegex(capture.IntakeError, 'scope.*not ready'): freeze(*data)
                    self.assertFalse((data[0] / 'freeze.json').exists())

    def test_mixed_complete_scopes_return_only_selected_test_and_share_marker(self):
        d = manifest()
        for index, partition in [(4, 'train'), (5, 'validation'), (6, 'test')]:
            c = clip(index, partition); c['movement_id'] = 'another-movement'; d['clips'].append(c)
        with fixture(d) as data:
            root, doc, a, p, v = data; receipt = freeze(*data)
            result = open_test(root, doc, receipt, a, p, v)
            self.assertEqual(result['test_clip_ids'], ['clip-3'])
            other_scope = {key: doc['clips'][3][key] for key in capture.SCOPE_FIELDS}
            other_v = dict(v, scope=other_scope)
            with self.assertRaises(capture.IntakeError):
                open_test(root, doc, receipt, a, p, other_v, scope=other_scope)
            second = capture.freeze(doc, a, p, other_v, root / 'second.json', **(options(doc, root) | {'scope': other_scope}))
            with self.assertRaises(FileExistsError):
                open_test(root, doc, second, a, p, other_v, scope=other_scope)

    def test_partial_extra_scope_does_not_block_a_complete_selected_candidate(self):
        d = manifest(); extra = clip(4, 'reference'); extra['movement_id'] = 'reference-only'; d['clips'].append(extra)
        with fixture(d) as data:
            root, doc, a, p, v = data
            self.assertFalse(capture.validate(doc)['independent_evaluation_ready'])
            receipt = freeze(*data)
            self.assertEqual(open_test(root, doc, receipt, a, p, v)['test_clip_ids'], ['clip-3'])

    def test_validation_scope_partition_and_legacy_receipts_cannot_bypass_open_checks(self):
        for change in ['validation_scope', 'validation_partition', 'legacy_receipt', 'receipt_scope']:
            with self.subTest(change=change), fixture() as data:
                root, doc, a, p, v = data; receipt = freeze(*data)
                if change == 'validation_scope': v['scope'] = dict(v['scope'], movement_id='other')
                elif change == 'validation_partition':
                    v['partition'] = 'train'; receipt['validation_sha256'] = capture.digest(v)
                elif change == 'legacy_receipt':
                    for key in ['receipt_version', 'scope', 'media_verification_sha256']: receipt.pop(key)
                else: receipt['scope'] = dict(receipt['scope'], lesson_id='other')
                with self.assertRaises(capture.IntakeError): open_test(root, doc, receipt, a, p, v)
                self.assertFalse((root / ('test-opened-' + doc['dataset_id'] + '.json')).exists())

    def test_direct_api_enforces_catalog_binding_and_fixed_marker(self):
        with fixture() as data:
            root, doc, a, p, v = data
            with self.assertRaisesRegex(capture.IntakeError, 'binding'): freeze(*data, catalog={'areas': []})
            receipt = freeze(*data)
            for kw in [{'catalog': {'areas': []}}, {'marker': root / 'another-marker.json'}]:
                with self.assertRaises(capture.IntakeError): open_test(root, doc, receipt, a, p, v, **kw)
            self.assertFalse((root / 'another-marker.json').exists())

    def test_probe_mode_cannot_silently_change_after_freeze(self):
        def probe(_):
            return dict(width=1280, height=720, fps=30, duration_s=6,
                        sample_rate_hz=0, rotation_deg=0, constant_frame_timing=True)
        with fixture() as data:
            root, doc, a, p, v = data; receipt = freeze(*data, probe=probe)
            with self.assertRaises(capture.IntakeError): open_test(root, doc, receipt, a, p, v)
            self.assertEqual(open_test(root, doc, receipt, a, p, v, probe=probe)['test_clip_ids'], ['clip-3'])

    def test_scope_parser_rejects_missing_extra_and_nonstring_fields(self):
        original = scope(manifest())
        cases = [None, {}, dict(original, alias='other'), dict(original, course_sha256='invalid'),
                 dict(original, movement_id=['other']), dict(original, lesson_id='')]
        for value in cases:
            with self.subTest(value=value), self.assertRaises(capture.IntakeError): capture.candidate_scope(value)

    def test_cli_requires_root_scope_and_runs_valid_freeze_open_without_training(self):
        with fixture() as data:
            root, doc, a, p, v = data
            for name, value in [('manifest.json', doc), ('validation.json', v), ('scope.json', scope(doc)), ('targets.json', targets(doc))]:
                (root / name).write_text(json.dumps(value))
            cmd = [sys.executable, capture.__file__, 'freeze', '--manifest', str(root/'manifest.json'),
                   '--targets', str(root/'targets.json'), '--artifact', str(a), '--pipeline', str(p),
                   '--validation', str(root/'validation.json'), '--out', str(root/'freeze.json')]
            for extra in [[], ['--root', str(root)], ['--scope', str(root/'scope.json')]]:
                result = subprocess.run(cmd + extra, capture_output=True, text=True)
                self.assertEqual(result.returncode, 2); self.assertEqual(json.loads(result.stdout)['status'], 'BLOCKED')
                self.assertFalse((root/'freeze.json').exists())
            result = subprocess.run(cmd + ['--root', str(root), '--scope', str(root/'scope.json')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            receipt = json.loads(result.stdout); self.assertFalse(receipt['trained_by_this_tool'])
            cmd[2] = 'open-test'; cmd[cmd.index('--out')+1] = str(root/('test-opened-'+doc['dataset_id']+'.json'))
            result = subprocess.run(cmd + ['--root', str(root), '--scope', str(root/'scope.json'), '--receipt', str(root/'freeze.json')], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stdout)
            self.assertEqual(json.loads(result.stdout)['test_clip_ids'], ['clip-3'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
