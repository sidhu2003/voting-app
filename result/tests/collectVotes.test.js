// Unit tests for the results tally.
//
// Uses node:test, which ships with Node -- no new dependency, and this project
// has no lockfile, so adding one would make builds less reproducible than they
// already are.
const test = require('node:test');
const assert = require('node:assert');

const { collectVotesFromResult } = require('../votes');

test('counts votes for both options', () => {
  const votes = collectVotesFromResult({
    rows: [ { vote: 'a', count: '7' }, { vote: 'b', count: '3' } ]
  });
  assert.deepStrictEqual(votes, { a: 7, b: 3 });
});

test('an empty table reads as zero, not undefined', () => {
  // Postgres returns no rows before anyone has voted. The dashboard must show
  // 0-0 rather than NaN or a blank -- and this is also the state right after a
  // fresh deploy, before the worker has created the table.
  assert.deepStrictEqual(collectVotesFromResult({ rows: [] }), { a: 0, b: 0 });
});

test('an option nobody voted for stays at zero', () => {
  // GROUP BY only returns rows that exist. If nobody picked 'b' there is no
  // 'b' row at all, and the missing key must not become undefined.
  const votes = collectVotesFromResult({ rows: [ { vote: 'a', count: '4' } ] });
  assert.deepStrictEqual(votes, { a: 4, b: 0 });
});

test('counts arrive as strings and must become numbers', () => {
  // node-postgres returns COUNT() as a STRING, because a bigint does not fit
  // safely in a JavaScript number. Without parseInt the browser would receive
  // "7" and "3", and string concatenation would render the total as "73".
  const votes = collectVotesFromResult({
    rows: [ { vote: 'a', count: '10' }, { vote: 'b', count: '5' } ]
  });
  assert.strictEqual(typeof votes.a, 'number');
  assert.strictEqual(votes.a + votes.b, 15);
});

test('large counts survive', () => {
  const votes = collectVotesFromResult({
    rows: [ { vote: 'a', count: '1000000' }, { vote: 'b', count: '999999' } ]
  });
  assert.deepStrictEqual(votes, { a: 1000000, b: 999999 });
});

test('an unexpected vote value does not corrupt the known ones', () => {
  // Nothing validates what `vote` contains. A stray value should be ignored
  // rather than breaking the two counters the dashboard renders.
  const votes = collectVotesFromResult({
    rows: [ { vote: 'a', count: '2' }, { vote: 'c', count: '9' }, { vote: 'b', count: '1' } ]
  });
  assert.strictEqual(votes.a, 2);
  assert.strictEqual(votes.b, 1);
});
