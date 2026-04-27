# db-tool-mcp

> **Execute SQL queries with sandboxed Perl code filtering — the only MCP server with built-in Safe sandbox for row-level data processing.**

[![Perl](https://img.shields.io/badge/perl-5.40+-blue.svg)](https://www.perl.org/)
[![MCP](https://img.shields.io/badge/MCP-2024--11--05-green.svg)](https://modelcontextprotocol.io)
[![License](https://img.shields.io/badge/license-MIT-purple.svg)](LICENSE)

## Features

- **SQL queries** — SELECT, INSERT, UPDATE, DELETE, CREATE TABLE, PRAGMA, and more
- **Sandboxed Perl code (`code` parameter)** — filter and transform rows **on the server side** using Perl's built-in `Safe` module. The code runs in an isolated environment — no other language offers this out of the box.
- **List tables** — show all tables in the database
- **Inspect tables** — show column names, types, and metadata
- **Transactions** — `begin_work`, `commit`, `rollback`
- **Bind parameters** — safe parameterized queries
- **Multiple database engines** — SQLite, MySQL, PostgreSQL, and any DBI-supported driver
- **Lazy connection** — connects once, reuses across requests
- **Zero external dependencies** for the core sandbox — `perl`, `JSON`, `DBI`, and `DBD::*` are all you need

## Why Perl?

| Feature | Perl | Python | JavaScript | Lua |
|---------|------|--------|------------|-----|
| Built-in sandbox | ✅ `Safe` module in core | ❌ No built-in sandbox | ❌ `vm` module is leaky | ❌ No built-in sandbox |
| Row-level filtering | ✅ `code` parameter | ❌ Must install extra libs | ❌ Must write own sandbox | ❌ Must write own sandbox |
| Executable | One file, zero build | Needs venv | Needs npm install | Needs luarocks |
| DBI support | ✅ SQLite, MySQL, Pg, etc. | ✅ (separate drivers) | ✅ (separate libs) | ✅ (separate libs) |

**Perl's `Safe` module is the only built-in, production-tested sandbox among all major dynamic languages.** It has been part of Perl since 1994 and is audited for security.

## Installation

### Prerequisites

```bash
# Perl modules
sudo cpan JSON DBI
# Or on Arch Linux:
sudo pacman -S perl-json perl-dbi perl-dbd-sqlite

# For other database drivers (MySQL, PostgreSQL):
sudo cpan DBD::mysql DBD::Pg
```

### Setup

1. Clone the repository:
```bash
git clone https://github.com/kirill-scherba/db-tool-mcp.git
cd db-tool-mcp
chmod +x db-tool-mcp.pl
```

2. Add to your MCP settings file (usually `cline_mcp_settings.json` for Cline, or `claude_desktop_config.json` for Claude Desktop app):

```json
{
  "mcpServers": {
    "db-tool": {
      "command": "perl",
      "args": ["/path/to/db-tool-mcp/db-tool-mcp.pl"],
      "env": {},
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

## Usage

### Basic SQL Query

```json
{
  "query": "SELECT * FROM users LIMIT 10",
  "db_name": "/path/to/database.db"
}
```

### List Tables

```json
{
  "list_tables": true,
  "db_name": "/path/to/database.db"
}
```

### Inspect Table Schema

```json
{
  "inspect_table": { "table": "users" },
  "db_name": "/path/to/database.db"
}
```

### Sandboxed Perl Code Filtering (`code` — the killer feature)

The `code` parameter allows AI assistants to pass Perl code that runs **for each row** in a sandboxed environment. This offloads filtering to the database server, reducing data transfer.

```json
{
  "query": "SELECT * FROM users",
  "db_name": "/path/to/database.db",
  "code": "length($row->{name}) > 5 && $row->{id} % 2 == 1"
}
```

**How it works:**

```
Client (AI)                        MCP Server (Perl)
     │                                    │
     │  tools/call                         │
     │  { query, code }                    │
     │──────────────────────────────────>  │
     │                                    │
     │                        execute SQL
     │                        fetch rows one by one
     │                        for each row:
     │                          eval $code in Safe sandbox
     │                          if true  → keep
     │                          if false → skip
     │                                    │
     │  { count: 3, data: [...] }          │
     │<──────────────────────────────────  │
```

**More `code` examples:**

```perl
# Filter by string length
length($row->{name}) > 5

# Case-insensitive regex match
lc($row->{email}) =~ /\@company\.com$/

# Numeric comparison
$row->{price} < 500 && $row->{rating} > 4.0

# Array/list size (if the column is a delimited string)
scalar(split(',', $row->{tags})) >= 3

# Date comparison
$row->{created_at} gt '2026-01-01'

# String transformation
ucfirst(lc($row->{name}))
```

### Transactions

```json
{
  "begin_work": true,
  "db_name": "/path/to/database.db"
}

{
  "query": "INSERT INTO users (name) VALUES (?)",
  "bind": ["Alice"],
  "db_name": "/path/to/database.db"
}

{
  "commit": true,
  "db_name": "/path/to/database.db"
}
```

### Using Different Database Engines

```json
{
  "query": "SELECT * FROM products",
  "db_driver": "mysql",
  "db_host": "localhost",
  "db_port": 3306,
  "db_name": "shop",
  "db_user": "root",
  "db_password": "secret"
}
```

## Quick Test

```bash
cd /path/to/db-tool-mcp

# Create a test database
sqlite3 test.db "CREATE TABLE IF NOT EXISTS test (id INTEGER PRIMARY KEY, name TEXT); INSERT INTO test VALUES (1, 'Alice'), (2, 'Bob'), (3, 'Charlie');"

# Test the server with a single request
echo '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{}}}' | perl db-tool-mcp.pl 2>/dev/null

# Or run a full test sequence
printf '{"jsonrpc":"2.0","id":1,"method":"initialize"}
{"jsonrpc":"2.0","id":2,"method":"tools/list"}
{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"db_execute","arguments":{"query":"SELECT * FROM test","db_name":"test.db"}}}
' | perl db-tool-mcp.pl 2>/dev/null
```

## Architecture

```
┌──────────────────────────────────────────────────────────┐
│                      MCP Client (AI)                      │
│  ┌──────────┐  ┌──────────┐  ┌──────────┐  ┌──────────┐ │
│  │initialize│  │tools/list│  │tools/call│  │tools/call│ │
│  └────┬─────┘  └────┬─────┘  └────┬─────┘  └────┬─────┘ │
│       │             │             │             │        │
│       ▼             ▼             ▼             ▼        │
│              JSON-RPC 2.0 over stdin/stdout              │
└──────────────────────────┬───────────────────────────────┘
                           │
┌──────────────────────────▼───────────────────────────────┐
│                   db-tool-mcp (Perl)                      │
│                                                           │
│  ┌──────────┐   ┌──────────────┐   ┌──────────────────┐  │
│  │ MCP Main │──>│  Request      │──>│  Database        │  │
│  │ Loop     │   │  Dispatcher   │   │  (DBI -> SQLite) │  │
│  │          │   │              │   │                  │  │
│  │ while    │   │ • list_tables│   │  + Safe sandbox  │  │
│  │ <STDIN>  │   │ • inspect    │   │  for code param  │  │
│  │          │   │ • query +code│   │                  │  │
│  │          │   │ • transaction│   │                  │  │
│  └──────────┘   └──────────────┘   └──────────────────┘  │
└──────────────────────────────────────────────────────────┘
```

## Protocol

This server implements the **Model Context Protocol (MCP)** using **JSON-RPC 2.0** over stdin/stdout.

| Method | Description |
|--------|-------------|
| `initialize` | Handshake with protocol version and capabilities |
| `ping` | Health check |
| `tools/list` | Returns the `db_execute` tool definition with full JSON Schema |
| `tools/call` | Executes `db_execute` with provided arguments |

All logging goes to **stderr**, leaving **stdout** clean for JSON-RPC messages.

## Security

- The `code` parameter runs inside Perl's `Safe` compartment, which restricts file operations, system calls, and other dangerous operations
- Only whitelisted Perl modules are allowed (`MIME::Base64`, `Digest::MD5`, `URI::Escape`)
- The code parameter is designed for **AI assistant use only** — the AI generates the Perl code, not the end user

## Contributing

Contributions are welcome! Feel free to open issues or submit pull requests.

## License

MIT © Kirill Scherba

---

*Built with 🐪 — because only Perl has `Safe` in its core.*