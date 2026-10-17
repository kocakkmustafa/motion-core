'use strict';

// Test configuration only. No real clips, consent, training or remote schemas.
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {spawnSync} = require('node:child_process');
const Ajv2020 = require('ajv/dist/2020').default;
assert.equal(require('ajv/package.json').version, '8.20.0');

const pipeline = path.resolve(__dirname, '../..');
const schema = JSON.parse(fs.readFileSync(path.join(pipeline, 'first_party_capture.schema.json'), 'utf8'));
const copy = value => JSON.parse(JSON.stringify(value));
const referenceKeys = new Set(['$ref', '$dynamicRef', '$recursiveRef']);

function localReferencesOnly(value) {
  if (value === null || typeof value !== 'object') return;
  for (const [key, item] of Object.entries(value)) {
    if (referenceKeys.has(key)) {
      assert(typeof item === 'string' && item.startsWith('#'), 'Only local fragment schema references are allowed');
    }
    localReferencesOnly(item);
  }
}

function compile(value) {
  assert.equal(value.$schema, 'https://json-schema.org/draft/2020-12/schema');
  localReferencesOnly(value);
  // Synchronous compile and no loadSchema callback: never retrieve a schema.
  return new Ajv2020({allErrors: true, strict: false, validateSchema: true}).compile(value);
}

const python = spawnSync('python3', ['-c',
  'import json,sys; sys.path.insert(0,sys.argv[1]); from test_first_party_capture import manifest; print(json.dumps(manifest()))',
  path.resolve(__dirname, '..')], {
  encoding: 'utf8', timeout: 10000, maxBuffer: 1024 * 1024,
  env: {...process.env, PYTHONDONTWRITEBYTECODE: '1'},
});
if (python.error) throw python.error;
assert.equal(python.status, 0, python.stderr);
const base = JSON.parse(python.stdout);
const validate = compile(schema);
let contractCases = 0;
function check(name, doc, accepted) {
  assert.equal(validate(doc), accepted, name + ': ' + JSON.stringify(validate.errors));
  console.log(name + ': PASS');
  contractCases++;
}

check('valid three partitions', base, true);
for (const [index, permission] of [[0, 'training'], [1, 'training'], [1, 'evaluation']]) {
  const doc = copy(base), clip = doc.clips[index];
  clip.purpose = 'demonstration';
  clip.permissions.demo_distribution = true;
  clip.permissions[permission] = false;
  check('partition ' + index + ' still requires ' + permission, doc, false);
}
const demo = copy(base);
Object.assign(demo.clips[0], {partition: 'reference', purpose: 'demonstration'});
Object.assign(demo.clips[0].permissions, {training: false, evaluation: false, demo_distribution: true});
check('demonstration-only reference remains a valid collection', demo, true);
const evaluation = copy(base);
evaluation.clips[2].permissions.training = false;
check('evaluation-only test remains legitimate', evaluation, true);
const malformed = copy(base);
malformed.clips[0].permissions.training = 'true';
check('string permission cannot authorize training', malformed, false);

let refusedReferences = 0;
for (const key of referenceKeys) {
  for (const ref of ['https://example.invalid/schema.json', 'file:///unread-schema.json', 'another-schema.json']) {
    assert.throws(() => compile({...copy(schema), [key]: ref}), /Only local fragment/);
    refusedReferences++;
  }
}
const local = {...copy(schema), $defs: {collection: {type: 'object'}}, allOf: [{$ref: '#/$defs/collection'}]};
assert.equal(compile(local)(base), true);
assert.throws(() => compile({...copy(schema), type: 3}));
console.log(contractCases + ' contract cases, ' + refusedReferences + ' external-reference refusals, local-reference and malformed-schema controls PASS');
