using System;
using System.Data.Common;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Threading;
using Newtonsoft.Json;
using Npgsql;
using StackExchange.Redis;

namespace Worker
{
    public class Program
    {
        private static volatile bool shutdownRequested = false;

        public static int Main(string[] args)
        {
            // Kubernetes sends SIGTERM before SIGKILL when a pod is terminated. Handling it
            // lets the current vote finish its INSERT rather than being lost in the window
            // between LPOP (which removes it from Redis) and the write to Postgres.
            using var sigTerm = PosixSignalRegistration.Create(PosixSignal.SIGTERM, RequestShutdown);
            using var sigInt = PosixSignalRegistration.Create(PosixSignal.SIGINT, RequestShutdown);

            try
            {
                var connectionString = BuildPostgresConnectionString();
                var pgsql = OpenDbConnection(connectionString);
                var redisConn = OpenRedisConnection();
                var redis = redisConn.GetDatabase();

                // Keep alive is not implemented in Npgsql yet. This workaround was recommended:
                // https://github.com/npgsql/npgsql/issues/1214#issuecomment-235828359
                var keepAliveCommand = pgsql.CreateCommand();
                keepAliveCommand.CommandText = "SELECT 1";

                var definition = new { vote = "", voter_id = "" };
                while (!shutdownRequested)
                {
                    // Slow down to prevent CPU spike, only query each 100ms
                    Thread.Sleep(100);

                    // Reconnect redis if down
                    if (redisConn == null || !redisConn.IsConnected) {
                        Console.WriteLine("Reconnecting Redis");
                        redisConn = OpenRedisConnection();
                        redis = redisConn.GetDatabase();
                    }
                    string json = redis.ListLeftPopAsync("votes").Result;
                    if (json != null)
                    {
                        var vote = JsonConvert.DeserializeAnonymousType(json, definition);
                        Console.WriteLine($"Processing vote for '{vote.vote}' by '{vote.voter_id}'");

                        // Reconnect DB if down. The vote has already been popped off the queue
                        // by this point, so it must still be written after reconnecting --
                        // otherwise it is silently dropped.
                        if (!pgsql.State.Equals(System.Data.ConnectionState.Open))
                        {
                            Console.WriteLine("Reconnecting DB");
                            pgsql = OpenDbConnection(connectionString);
                            keepAliveCommand = pgsql.CreateCommand();
                            keepAliveCommand.CommandText = "SELECT 1";
                        }

                        UpdateVote(pgsql, vote.voter_id, vote.vote);
                    }
                    else
                    {
                        keepAliveCommand.ExecuteNonQuery();
                    }
                }

                Console.WriteLine("Shutdown complete, no vote in flight");
                pgsql.Close();
                redisConn.Close();
                return 0;
            }
            catch (Exception ex)
            {
                Console.Error.WriteLine(ex.ToString());
                return 1;
            }
        }

        private static void RequestShutdown(PosixSignalContext context)
        {
            // Cancel the default terminate-immediately behaviour so the main loop can finish
            // whatever it is holding and exit on its own terms.
            context.Cancel = true;
            shutdownRequested = true;
            Console.WriteLine($"{context.Signal} received, draining in-flight vote before exit");
        }

        // Host, port, database and username are plain configuration (ConfigMap); the password
        // is a Secret. Defaults match docker-compose so local runs need no configuration.
        // internal, not private, so the test project can reach it via
        // InternalsVisibleTo. Deliberately not public -- this is not API, it is
        // just testable.
        internal static string BuildPostgresConnectionString()
        {
            var builder = new NpgsqlConnectionStringBuilder
            {
                Host = GetEnv("POSTGRES_HOST", "db"),
                Port = int.Parse(GetEnv("POSTGRES_PORT", "5432")),
                Username = GetEnv("POSTGRES_USER", "postgres"),
                Password = GetEnv("POSTGRES_PASSWORD", "postgres"),
                Database = GetEnv("POSTGRES_DB", "postgres"),
            };

            return builder.ConnectionString;
        }

        internal static string GetEnv(string name, string fallback)
        {
            var value = Environment.GetEnvironmentVariable(name);
            return string.IsNullOrEmpty(value) ? fallback : value;
        }

        private static NpgsqlConnection OpenDbConnection(string connectionString)
        {
            NpgsqlConnection connection;

            while (true)
            {
                try
                {
                    connection = new NpgsqlConnection(connectionString);
                    connection.Open();
                    break;
                }
                catch (SocketException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
                catch (DbException)
                {
                    Console.Error.WriteLine("Waiting for db");
                    Thread.Sleep(1000);
                }
            }

            Console.Error.WriteLine("Connected to db");

            var command = connection.CreateCommand();
            command.CommandText = @"CREATE TABLE IF NOT EXISTS votes (
                                        id VARCHAR(255) NOT NULL UNIQUE,
                                        vote VARCHAR(255) NOT NULL
                                    )";
            command.ExecuteNonQuery();

            return connection;
        }

        private static ConnectionMultiplexer OpenRedisConnection()
        {
            var host = GetEnv("REDIS_HOST", "redis");
            var port = int.Parse(GetEnv("REDIS_PORT", "6379"));
            var password = Environment.GetEnvironmentVariable("REDIS_PASSWORD");

            var options = new ConfigurationOptions
            {
                // Throw on a failed connect so the retry loop below keeps waiting for Redis
                // to come up, instead of handing back a multiplexer that is not connected.
                AbortOnConnectFail = true,
                ConnectTimeout = 5000,
            };
            options.EndPoints.Add(host, port);

            if (!string.IsNullOrEmpty(password))
            {
                options.Password = password;
            }

            while (true)
            {
                try
                {
                    Console.Error.WriteLine($"Connecting to redis at {host}:{port}");
                    return ConnectionMultiplexer.Connect(options);
                }
                catch (RedisConnectionException)
                {
                    Console.Error.WriteLine("Waiting for redis");
                    Thread.Sleep(1000);
                }
            }
        }

        private static void UpdateVote(NpgsqlConnection connection, string voterId, string vote)
        {
            var command = connection.CreateCommand();
            try
            {
                command.CommandText = "INSERT INTO votes (id, vote) VALUES (@id, @vote)";
                command.Parameters.AddWithValue("@id", voterId);
                command.Parameters.AddWithValue("@vote", vote);
                command.ExecuteNonQuery();
            }
            catch (DbException)
            {
                command.CommandText = "UPDATE votes SET vote = @vote WHERE id = @id";
                command.ExecuteNonQuery();
            }
            finally
            {
                command.Dispose();
            }
        }
    }
}
