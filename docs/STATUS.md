# Active Context — db-tool-mcp

## Current Status

Published on GitHub and submitted to Cline Marketplace (issue #1461).

## What's Been Done

- Created `db-tool-mcp.pl` — MCP server in Perl (JSON-RPC 2.0 over stdin/stdout)
- Full DBI support (SQLite, MySQL, PostgreSQL)
- Safe sandbox for `code` parameter (server-side row filtering)
- Transaction support (begin_work, commit, rollback)
- Lazy database connection (reuses across requests)
- README.md with full documentation in English
- llms-install.md for Cline Marketplace
- Logo in SVG + PNG
- Git repo pushed to github.com/kirill-scherba/db-tool-mcp

## Next Steps / Ideas

- Reddit r/perl post (user can't access Reddit — AI should prepare text)
- Hacker News post
- Memory Bank improvements
- Maybe: add more Safe-whitelisted modules
- Maybe: support for EXPLAIN and query analysis
