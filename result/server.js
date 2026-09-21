var express = require('express'),
    async = require('async'),
    path = require('path'),
    { Pool } = require('pg'),
    cookieParser = require('cookie-parser'),
    { collectVotesFromResult } = require('./votes'),
    app = express(),
    server = require('http').Server(app),
    io = require('socket.io')(server);

var port = process.env.PORT || 4000;

io.on('connection', function (socket) {

  socket.emit('message', { text : 'Welcome!' });

  socket.on('subscribe', function (data) {
    socket.join(data.channel);
  });
});

// Connection details come from the environment: hostname/port/database/user from a
// ConfigMap, password from a Secret. Defaults match docker-compose for local runs.
var pool = new Pool({
  host:     process.env.POSTGRES_HOST     || 'db',
  port:     parseInt(process.env.POSTGRES_PORT || '5432', 10),
  user:     process.env.POSTGRES_USER     || 'postgres',
  password: process.env.POSTGRES_PASSWORD || 'postgres',
  database: process.env.POSTGRES_DB       || 'postgres'
});

async.retry(
  {times: 1000, interval: 1000},
  function(callback) {
    pool.connect(function(err, client, done) {
      if (err) {
        console.error("Waiting for db");
      }
      callback(err, client);
    });
  },
  function(err, client) {
    if (err) {
      return console.error("Giving up");
    }
    console.log("Connected to db");
    getVotes(client);
  }
);

function getVotes(client) {
  client.query('SELECT vote, COUNT(id) AS count FROM votes GROUP BY vote', [], function(err, result) {
    if (err) {
      console.error("Error performing query: " + err);
    } else {
      var votes = collectVotesFromResult(result);
      io.sockets.emit("scores", JSON.stringify(votes));
    }

    setTimeout(function() {getVotes(client) }, 1000);
  });
}

app.use(cookieParser());
app.use(express.urlencoded());
app.use(express.static(__dirname + '/views'));

app.get('/', function (req, res) {
  res.sendFile(path.resolve(__dirname + '/views/index.html'));
});

// Only start listening when run directly. Without this guard, importing the
// file from a test would bind the port and connect to Postgres as a side
// effect of `require`, so the tests could never run without a live database.
if (require.main === module) {
  server.listen(port, function () {
    var port = server.address().port;
    console.log('App running on port ' + port);
  });
}
