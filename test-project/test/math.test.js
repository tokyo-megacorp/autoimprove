const { describe, it } = require('node:test');
const assert = require('node:assert');
const { add, subtract, divide, multiply } = require('../src/math');

describe('math', () => {
  it('adds two numbers', () => {
    assert.strictEqual(add(2, 3), 5);
  });

  it('subtracts two numbers', () => {
    assert.strictEqual(subtract(5, 3), 2);
  });

  it('multiplies two numbers', () => {
    assert.strictEqual(multiply(3, 4), 12);
  });

  it('divides two numbers', () => {
    assert.strictEqual(divide(10, 2), 5);
  });

  // This test exposes the bug — divide by zero returns Infinity, not an error
  it('throws on divide by zero', () => {
    assert.throws(() => divide(10, 0), { message: /division by zero/i });
  });
});
