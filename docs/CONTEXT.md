# DB-tool-MCP — Project Context

## What is this?

An MCP (Model Context Protocol) server that executes SQL queries with sandboxed Perl code filtering.

## Key Problem Solved

AI assistants need to query databases, but standard SQL queries return ALL matching rows. For large datasets, transferring everything to the client is slow. The `code` parameter allows server-side row filtering using Perl's Safe sandbox.

## Unique Value Proposition

The only MCP server with built-in Safe sandbox for AI-generated code. No other language (Python, JS, Lua) has a built-in sandbox comparable to Perl's Safe module.

## Target Audience

- AI assistants (Cline, Claude, etc.) that need database access
- Developers who want AI to query their databases safely
- Perl enthusiasts who want to show Perl is still relevant
