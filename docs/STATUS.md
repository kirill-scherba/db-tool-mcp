# db-tool-mcp — Project Status

## Current Status

✅ Published on GitHub. Submitted to Cline Marketplace (issue #1461).

## Changelog

### 2026-04-28

- Created `db-tool-mcp.pl` — MCP server in Perl (JSON-RPC 2.0 over stdin/stdout)
- Full DBI support (SQLite, MySQL, PostgreSQL)
- Safe sandbox for `code` parameter (server-side row filtering)
- Transaction support (begin_work, commit, rollback)
- Lazy database connection (reuses across requests)
- README.md with full documentation in English
- llms-install.md for Cline Marketplace
- Logo in SVG + PNG
- Git repo pushed to github.com/kirill-scherba/db-tool-mcp
- docs/ with CONTEXT.md, DESIGN.md, STATUS.md (Memory Bank)

## Next Steps / Ideas

- Reddit r/perl post
- Hacker News post
- Add more Safe-whitelisted modules
- Support for EXPLAIN and query analysis
