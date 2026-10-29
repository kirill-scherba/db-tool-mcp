#!/usr/bin/env perl
# =============================================================================
# db-tool-mcp — MCP server for executing SQL queries with sandboxed Perl code
#
# Repository: github.com/kirill-scherba/db-tool-mcp
#
# Features:
#   - Execute SQL queries (SELECT, INSERT, UPDATE, DELETE, etc.)
#   - List tables, inspect table schemas
#   - Sandboxed Perl code execution for row-level filtering (Safe module)
#   - Transaction support (begin_work, commit, rollback)
#   - Bind parameters support
#   - Multiple database drivers via DBI (SQLite, MySQL, PostgreSQL, etc.)
#
# MCP protocol: JSON-RPC 2.0 over stdin/stdout
# =============================================================================

use strict;
use warnings;
use utf8;
use JSON;
use DBI;
use Safe;
use POSIX qw(strftime);

use English '-no_match_vars';

# ---------------------------------------------------------------------------
# UTF-8 encoding
# ---------------------------------------------------------------------------
binmode(STDOUT, ":utf8");
binmode(STDERR, ":utf8");

# ---------------------------------------------------------------------------
# Logging (to stderr — stdout is reserved for JSON-RPC protocol)
# ---------------------------------------------------------------------------
sub log_message {
    my ($level, $message) = @_;
    my $timestamp = strftime("%Y-%m-%d %H:%M:%S", localtime);
    print STDERR "[$timestamp] [$level] $message\n";
    STDERR->flush();
}

# ---------------------------------------------------------------------------
# JSON-RPC helpers
# ---------------------------------------------------------------------------
my $json = JSON->new;

sub respond {
    my ($id, $result) = @_;
    my $response = { jsonrpc => "2.0", id => $id, result => $result };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub respond_error {
    my ($id, $code, $message, $data) = @_;
    my $error = { code => $code, message => $message };
    $error->{data} = $data if defined $data;
    my $response = { jsonrpc => "2.0", id => $id, error => $error };
    print $json->encode($response) . "\n";
    STDOUT->flush();
}

sub send_notification {
    my ($method, $params) = @_;
    my $notification = { jsonrpc => "2.0", method => $method };
    $notification->{params} = $params if defined $params;
    print $json->encode($notification) . "\n";
    STDOUT->flush();
    log_message("INFO", "Notification: $method");
}

# ---------------------------------------------------------------------------
# Database connection (lazy — connects once and reuses)
# ---------------------------------------------------------------------------
my $dbh;
my $current_dsn;

sub ensure_db_connection {
    my ($params) = @_;
    $params //= {};

    my $db_driver   = $params->{db_driver}   || 'SQLite';
    my $db_host     = $params->{db_host}     || 'localhost';
    my $db_port     = $params->{db_port};
    my $db_name     = $params->{db_name}     || 'db.sqlite';
    my $db_user     = $params->{db_user}     // '';
    my $db_password = $params->{db_password} // '';

    my $dsn;
    if (lc($db_driver) eq 'sqlite') {
        $dsn = "dbi:SQLite:dbname=$db_name";
    } else {
        $dsn = "dbi:$db_driver:database=$db_name;host=$db_host";
        $dsn .= ";port=$db_port" if $db_port;
    }

    # Reconnect only if DSN changed or no connection
    if (!$dbh || $dsn ne $current_dsn) {
        $dbh->disconnect() if $dbh;
        $current_dsn = $dsn;
        eval {
            $dbh = DBI->connect($dsn, $db_user, $db_password, {
                RaiseError => 1,
                AutoCommit => 1,
                (lc($db_driver) eq 'sqlite' ? (sqlite_unicode => 1) : ()),
            });
        };
        if ($@ || !$dbh) {
            die "Database connection failed: $@";
        }
        log_message("INFO", "Connected to database: $dsn");
    }
}

# ---------------------------------------------------------------------------
# Tool definition (returned by tools/list)
# ---------------------------------------------------------------------------
sub get_tool_definition {
    return {
        name => "db_execute",
        description => "Execute SQL queries against any DBI-supported database.
Supports SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, PRAGMA, etc.
Always use LIMIT with SELECT queries to prevent excessive data retrieval.
IMPORTANT: Ask user permission before modifying data (INSERT, UPDATE, DELETE, etc.).",
        inputSchema => {
            type => "object",
            properties => {
                list_tables => {
                    type => "boolean",
                    description => "List all tables in the database.",
                },
                query => {
                    type => "string",
                    description => "The SQL query to execute.",
                },
                inspect_table => {
                    type => "object",
                    properties => {
                        table => {
                            type => "string",
                            description => "The name of the table to inspect.",
                        },
                    },
                    required => ["table"],
                },
                # Database connection parameters
                db_driver => {
                    type => "string",
                    description => "Database driver. Examples: SQLite, mysql, Pg, etc.",
                },
                db_host => {
                    type => "string",
                    description => "Database host (for non-SQLite drivers).",
                },
                db_port => {
                    type => "integer",
                    description => "Database port.",
                },
                db_name => {
                    type => "string",
                    description => "Database name. For SQLite: path to .db file.",
                },
                db_user => {
                    type => "string",
                    description => "Database user.",
                },
                db_password => {
                    type => "string",
                    description => "Database password.",
                },
                code => {
                    type => "string",
                    description => "Perl code executed for each row in Safe sandbox.
Use \$row variable to access the current row hashref.
Return true to include the row, false to skip it.
Example: 'length(\$row->{name}) > 5 && \$row->{id} % 2 == 1'
WARNING: Only AI assistants should generate this code. Not intended for end users.",
                },
                bind => {
                    type => "array",
                    items => { type => "string" },
                    description => "Bind parameters for parameterized queries.",
                },
                # Transaction control
                begin_work => {
                    type => "boolean",
                    description => "Begin a new database transaction (disables AutoCommit).",
                },
                commit => {
                    type => "boolean",
                    description => "Commit the current transaction.",
                },
                rollback => {
                    type => "boolean",
                    description => "Rollback the current transaction.",
                },
            },
        },
    };
}

# ---------------------------------------------------------------------------
# Action implementations
# ---------------------------------------------------------------------------

sub action_list_tables {
    my $dbh = shift;
    my @tables = $dbh->tables(undef, undef, undef, 'TABLE');
    log_message("INFO", "Listed " . scalar(@tables) . " tables.");
    return \@tables;
}

sub action_inspect_table {
    my ($dbh, $table) = @_;
    unless ($table) {
        die "Missing required parameter 'inspect_table.table'";
    }

    my $sth = $dbh->column_info(undef, undef, $table, '%');
    if (!$sth) {
        log_message("WARN", "column_info not supported, falling back to PRAGMA");
        my $quoted_table = $dbh->quote_identifier($table);
        $sth = $dbh->prepare("PRAGMA table_info($quoted_table)");
        $sth->execute();
        return $sth->fetchall_arrayref({});
    }

    my $columns = $sth->fetchall_arrayref({});
    log_message("INFO", "Inspected table '$table', found " . scalar(@$columns) . " columns.");
    return $columns;
}

sub action_execute_query {
    my ($dbh, $params) = @_;
    my $query = $params->{query};
    unless ($query) {
        die "Missing required parameter 'query'";
    }

    my $sth = $dbh->prepare($query);
    $sth->execute(@{ $params->{bind} || [] });
    log_message("INFO", "Executed query: $query");

    # -----------------------------------------------------------------------
    # Sandboxed Perl code processor (code parameter)
    # -----------------------------------------------------------------------
    my $code = $params->{code};
    my $processor;
    if ($code) {
        my $safe = Safe->new();

        # Whitelist safe modules
        my %safe_modules = (
            'MIME::Base64' => 1,
            'Digest::MD5'  => 1,
            'URI::Escape'  => 1,
        );

        # Extract and validate 'use Module;' statements
        while ($code =~ s/^\s*use\s+([\w::]+)\s*;//m) {
            my $module_name = $1;
            die "Perl Compile Error: Module '$module_name' is not allowed."
                unless $safe_modules{$module_name};
            eval "use $module_name; 1" or die "Perl Compile Error: Cannot load module '$module_name': $@";
            no strict 'refs';
            my @symbols = keys %{$module_name . '::'};
            $safe->share_from($module_name, \@symbols);
            log_message("INFO", "Loaded module '$module_name' for safe eval.");
        }

        # Compile the filter code in Safe sandbox
        $processor = $safe->reval("sub { my \$row = shift; " . $code . " }");
        die "Perl Compile Error: $@" if $@;
    }

    # -----------------------------------------------------------------------
    # Fetch and filter rows
    # -----------------------------------------------------------------------
    my @results;
    my $error_in_loop = 0;
    while (my $row = $sth->fetchrow_hashref) {
        if ($processor) {
            my $keep = eval { $processor->($row) };
            if ($@) {
                log_message("ERROR", "Runtime error in user code: $@");
                push @results, { error => "Runtime Error", details => $@ };
                $error_in_loop = 1;
                last;
            }
            push @results, $row if $keep;
        } else {
            push @results, $row;
        }
    }

    my $total_count = scalar @results;
    log_message("INFO", "Query returned $total_count rows.");

    if ($error_in_loop) {
        return {
            count => $total_count,
            data => \@results,
            warning => "Execution stopped due to a runtime error in user code."
        };
    }

    return { count => $total_count, data => \@results };
}

sub action_transaction {
    my ($dbh, $params) = @_;
    if (exists $params->{begin_work} && $params->{begin_work}) {
        $dbh->begin_work();
        log_message("INFO", "Transaction started.");
        return "Transaction started.";
    }
    if (exists $params->{commit} && $params->{commit}) {
        $dbh->commit();
        log_message("INFO", "Transaction committed.");
        return "Transaction committed.";
    }
    if (exists $params->{rollback} && $params->{rollback}) {
        $dbh->rollback();
        log_message("INFO", "Transaction rolled back.");
        return "Transaction rolled back.";
    }
    return undef;
}

sub execute_tool {
    my ($args) = @_;
    $args //= {};

    # Connect to database
    ensure_db_connection($args);

    # Handle transaction commands first
    my $tx_result = action_transaction($dbh, $args);
    if (defined $tx_result) {
        return { status => "success", data => $tx_result };
    }

    if (exists $args->{list_tables}) {
        my $tables = action_list_tables($dbh);
        return { status => "success", data => $tables };
    }
    elsif (exists $args->{inspect_table}) {
        my $columns = action_inspect_table($dbh, $args->{inspect_table}->{table});
        return { status => "success", data => $columns };
    }
    elsif (exists $args->{query}) {
        my $result = action_execute_query($dbh, $args);
        return { status => "success", data => $result };
    }
    else {
        die "No valid execute action provided. Please provide one of: list_tables, inspect_table, or query.";
    }
}

# ===========================================================================
# MCP Main Loop — Infinite loop processing JSON-RPC requests from stdin
# ===========================================================================

log_message("INFO", "db-tool-mcp server started");

# No unsolicited notification here: MCP clients expect a server to speak only when spoken to, and an
# "initialized" line with no id arriving before the first request made every proxy pair it with the next
# answer - db-tool then returned the previous query's result (29.10.2026).
LINE: while (my $line = <STDIN>) {
    chomp $line;
    next LINE unless $line && $line =~ /\S/;

    log_message("DEBUG", "Received: $line");

    my $msg = eval { $json->decode($line) };
    if ($@ || !$msg) {
        log_message("ERROR", "Invalid JSON-RPC message: $@");
        next LINE;
    }

    my $id     = $msg->{id};
    my $method = $msg->{method} // '';
    my $params = $msg->{params} // {};

    # Handle notifications (no id)
    if (!defined $id) {
        log_message("INFO", "Received notification: $method");
        next LINE;
    }

    if ($method eq 'initialize') {
        respond($id, {
            protocolVersion => '2024-11-05',
            capabilities    => { tools => {} },
            serverInfo      => {
                name    => 'db-tool-mcp',
                version => '0.1.0',
            },
        });
        log_message("INFO", "Initialized");
    }
    elsif ($method eq 'ping') {
        respond($id, {});
    }
    elsif ($method eq 'tools/list') {
        respond($id, {
            tools => [ get_tool_definition() ],
        });
        log_message("INFO", "Sent tool list");
    }
    elsif ($method eq 'tools/call') {
        my $tool_name  = $params->{name} // '';
        my $tool_args  = $params->{arguments} // {};

        if ($tool_name ne 'db_execute') {
            respond_error($id, -32601, "Method not found: tool '$tool_name' not found");
            next LINE;
        }

        log_message("INFO", "Executing tool: $tool_name");

        eval {
            my $result = execute_tool($tool_args);
            log_message("INFO", "Tool execution successful");
            respond($id, {
                content => [
                    {
                        type => "text",
                        text => $json->encode($result),
                    },
                ],
            });
        };
        if ($@) {
            my $error_msg = $@;
            chomp $error_msg;
            log_message("ERROR", "Tool execution error: $error_msg");
            respond_error($id, -32603, "Internal error: $error_msg");
        }
    }
    else {
        log_message("WARN", "Unknown method: $method");
        respond_error($id, -32601, "Method not found: $method");
    }
}

# Cleanup
$dbh->disconnect() if $dbh;
log_message("INFO", "db-tool-mcp server stopped");