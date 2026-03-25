const { describe, it } = require('node:test');
const assert = require('node:assert');
const { capitalize, reverse, wordCount } = require('../src/string');

describe('string', () => {
  it('capitalizes a string', () => {
    assert.strictEqual(capitalize('hello'), 'Hello');
  });

  it('reverses a string', () => {
    assert.strictEqual(reverse('abc'), 'cba');
  });

  // No tests for: capitalize(''), wordCount edge cases, etc.
});
