# db-tool-mcp — Installation Guide for AI Assistants

## Prerequisites

- **Perl** 5.14+ (check with `perl -v`)
- **Perl modules**: `JSON`, `DBI`, `DBD::SQLite` (or `DBD::mysql`/`DBD::Pg` for other databases)

### Install Perl modules

**Arch Linux:**
```bash
sudo pacman -S perl-json perl-dbi perl-dbd-sqlite
```

**Debian/Ubuntu:**
```bash
sudo apt install libjson-perl libdbi-perl libdbd-sqlite3-perl
```

**macOS (Homebrew):**
```bash
brew install perl
sudo cpan JSON DBI DBD::SQLite
```

**Any system with cpan:**
```bash
sudo cpan JSON DBI DBD::SQLite
```

## Quick Start

Clone and run:

```bash
git clone https://github.com/kirill-scherba/db-tool-mcp.git
cd db-tool-mcp
chmod +x db-tool-mcp.pl
```

## MCP Configuration

Add to your `cline_mcp_settings.json`:

```json
{
  "mcpServers": {
    "db-tool": {
      "command": "perl",
      "args": ["/absolute/path/to/db-tool-mcp/db-tool-mcp.pl"],
      "env": {},
      "disabled": false,
      "autoApprove": []
    }
  }
}
```

## Verification

After configuration, you can test by asking:

> "List all tables in my SQLite database at /path/to/database.db"

The AI assistant will call the `db_execute` tool with `{"list_tables": true, "db_name": "/path/to/database.db"}`.

## Available Tool

### `db_execute`

Executes SQL queries against any DBI-supported database.

**Key parameters:**
- `query` — SQL query to execute (SELECT, INSERT, UPDATE, DELETE, etc.)
- `db_name` — path to SQLite .db file (or database name for other drivers)
- `list_tables` — boolean, list all tables
- `inspect_table` — object with `table` field, inspect table schema
- `code` — Perl code to filter rows (executed in Safe sandbox for each row)
- `bind` — array of bind parameters for parameterized queries
- `begin_work` / `commit` / `rollback` — transaction control
- `db_driver`, `db_host`, `db_port`, `db_user`, `db_password` — for MySQL/PostgreSQL

**Important:** Always ask user permission before modifying data (INSERT, UPDATE, DELETE, etc.). Use LIMIT with SELECT to prevent excessive data retrieval.

See full README at https://github.com/kirill-scherba/db-tool-mcp