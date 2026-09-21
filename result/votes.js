// The vote-tallying logic, on its own.
//
// Kept in a separate file so it can be imported without side effects.
// Requiring server.js runs everything at its top level -- which includes
// creating a Postgres pool and starting a retry loop that tries to connect
// 1000 times at one-second intervals. A test that imported it would hang for
// roughly sixteen minutes rather than fail.
//
// That is the general rule: `require` executes the whole file. Anything that
// connects, listens, or reads the environment at module scope becomes a side
// effect of importing.

function collectVotesFromResult(result) {
  var votes = {a: 0, b: 0};

  result.rows.forEach(function (row) {
    votes[row.vote] = parseInt(row.count);
  });

  return votes;
}

module.exports = { collectVotesFromResult: collectVotesFromResult };
