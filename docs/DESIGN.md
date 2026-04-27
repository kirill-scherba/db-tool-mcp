# Design & Architecture

## Why Perl?

Perl's `Safe` module is the **only built-in sandbox** among all major dynamic languages:

| Language | Sandbox | Status |
|----------|---------|--------|
| **Perl** | `Safe->new()` in core | ✅ Built-in since 1994 |
| Python | Restricted mode removed in 3.x | ❌ Need external libs |
| JavaScript | `vm` module is leaky | ❌ Not secure |
| Lua | No built-in sandbox | ❌ Must write manually |

This makes Perl the ideal choice for server-side AI-generated code execution.

## Architecture

```
┌──────────────────────────────────────────────────────┐
│                     MCP Client (AI)                   │
│  initialize → tools/list → tools/call → tools/call   │
└──────────────────────────┬───────────────────────────┘
                           │ JSON-RPC 2.0
                           │ stdin/stdout
┌──────────────────────────▼───────────────────────────┐
│                  db-tool-mcp (Perl)                    │
│                                                       │
│  ┌──────────────┐   ┌──────────────┐                  │
│  │  MCP Loop    │──→│  Dispatcher  │──→ Database (DBI)│
│  │ while <STDIN>│   │              │    + Safe sandbox│
│  └──────────────┘   └──────────────┘                  │
└──────────────────────────────────────────────────────┘
```

## The `code` Parameter

The killer feature. AI passes Perl code that executes **for each row** in a sandbox:

```json
{
  "query": "SELECT * FROM users",
  "code": "length($row->{name}) > 5"
}
```

```
SQL → rows → for each row: eval $code in Safe → true? keep. false? skip.
```

## Protocol

Implements MCP (Model Context Protocol) via JSON-RPC 2.0:
- `initialize` — handshake
- `tools/list` — returns db_execute tool schema
- `tools/call` — executes queries

## Connections

- Lazy connection: connects once, reuses for all requests
- Multi-DB: SQLite, MySQL, PostgreSQL via DBI
- Transaction support: begin_work, commit, rollback