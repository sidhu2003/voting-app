using System;
using Npgsql;
using Xunit;
using Worker;

namespace Worker.Tests
{
    /// <summary>
    /// Covers how the worker reads its configuration.
    ///
    /// These matter more than they look. Every incident in this project so far
    /// has been a configuration problem, not a logic problem -- a password that
    /// did not match, a ConfigMap that was never wired in. The defaults below
    /// are what the worker silently falls back to when configuration is
    /// missing, which is exactly how a pod ends up Running and doing nothing.
    /// </summary>
    [Collection("env")]
    public class GetEnvTests : IDisposable
    {
        private const string Key = "WORKER_TEST_VAR";

        public GetEnvTests()  => Environment.SetEnvironmentVariable(Key, null);
        public void Dispose() => Environment.SetEnvironmentVariable(Key, null);

        [Fact]
        public void Returns_the_value_when_set()
        {
            Environment.SetEnvironmentVariable(Key, "actual");
            Assert.Equal("actual", Program.GetEnv(Key, "fallback"));
        }

        [Fact]
        public void Falls_back_when_unset()
        {
            Assert.Equal("fallback", Program.GetEnv(Key, "fallback"));
        }

        [Fact]
        public void Treats_empty_as_unset()
        {
            // An empty value must mean "not configured", not "configured as
            // nothing". A ConfigMap key present but blank would otherwise give
            // the worker an empty hostname and an unexplainable DNS failure.
            Environment.SetEnvironmentVariable(Key, "");
            Assert.Equal("fallback", Program.GetEnv(Key, "fallback"));
        }

        [Fact]
        public void Preserves_awkward_characters()
        {
            // The Postgres password used in this project is p@ss:word/1.
            // Credentials are passed as discrete fields rather than pasted into
            // a URL, so characters that would need escaping in a connection
            // URI must survive untouched.
            Environment.SetEnvironmentVariable(Key, "p@ss:word/1");
            Assert.Equal("p@ss:word/1", Program.GetEnv(Key, "fallback"));
        }
    }

    [Collection("env")]
    public class ConnectionStringTests : IDisposable
    {
        private static readonly string[] Vars =
        {
            "POSTGRES_HOST", "POSTGRES_PORT", "POSTGRES_USER",
            "POSTGRES_PASSWORD", "POSTGRES_DB"
        };

        public ConnectionStringTests() => Clear();
        public void Dispose()          => Clear();
        private static void Clear()
        {
            foreach (var v in Vars) Environment.SetEnvironmentVariable(v, null);
        }

        [Fact]
        public void Uses_documented_defaults_when_nothing_is_set()
        {
            // These defaults are what makes an unconfigured worker sit forever
            // on "Waiting for db": it looks for a host literally named `db`,
            // which does not exist in the cluster.
            var b = new NpgsqlConnectionStringBuilder(Program.BuildPostgresConnectionString());

            Assert.Equal("db", b.Host);
            Assert.Equal(5432, b.Port);
            Assert.Equal("postgres", b.Username);
            Assert.Equal("postgres", b.Database);
        }

        [Fact]
        public void Reads_every_value_from_the_environment()
        {
            Environment.SetEnvironmentVariable("POSTGRES_HOST", "db-service");
            Environment.SetEnvironmentVariable("POSTGRES_PORT", "6543");
            Environment.SetEnvironmentVariable("POSTGRES_USER", "voteuser");
            Environment.SetEnvironmentVariable("POSTGRES_PASSWORD", "p@ss:word/1");
            Environment.SetEnvironmentVariable("POSTGRES_DB", "votesdb");

            var b = new NpgsqlConnectionStringBuilder(Program.BuildPostgresConnectionString());

            Assert.Equal("db-service", b.Host);
            Assert.Equal(6543, b.Port);
            Assert.Equal("voteuser", b.Username);
            Assert.Equal("votesdb", b.Database);
        }

        [Fact]
        public void Password_with_special_characters_round_trips()
        {
            // The whole point of building the string with
            // NpgsqlConnectionStringBuilder rather than concatenating one: a
            // password containing @ : / would corrupt a hand-built URI, and
            // the failure would look like bad credentials.
            Environment.SetEnvironmentVariable("POSTGRES_PASSWORD", "p@ss:word/1");

            var b = new NpgsqlConnectionStringBuilder(Program.BuildPostgresConnectionString());

            Assert.Equal("p@ss:word/1", b.Password);
        }

        [Fact]
        public void A_non_numeric_port_fails_loudly()
        {
            // Better to crash at startup than to run against a silently wrong
            // port. A ConfigMap with POSTGRES_PORT: "five thousand" should stop
            // the pod, not produce a confusing connection error later.
            Environment.SetEnvironmentVariable("POSTGRES_PORT", "not-a-number");

            Assert.Throws<FormatException>(() => Program.BuildPostgresConnectionString());
        }
    }
}
