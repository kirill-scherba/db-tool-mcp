# db-tool-mcp Examples

## MCP Configuration

### Cline (VS Code)

Add to `/home/kirill/.local/share/code-server/User/globalStorage/saoudrizwan.claude-dev/settings/cline_mcp_settings.json`:

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

### Claude Desktop

Add to `~/Library/Application Support/Claude/claude_desktop_config.json`:

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

## Usage Scenarios

### 1. Basic SELECT

Ask your AI assistant:

> "Show all tables in my database /path/to/project.db"

The AI will call:
```json
{
  "list_tables": true,
  "db_name": "/path/to/project.db"
}
```

### 2. Filtered Query with `code`

> "Find users with names longer than 5 characters"

The AI generates:
```json
{
  "query": "SELECT * FROM users",
  "db_name": "/path/to/project.db",
  "code": "length($row->{name}) > 5"
}
```

### 3. Complex Filtering

> "Find products that cost less than $50, have more than 3 tags, and were created this year"

The AI generates:
```json
{
  "query": "SELECT * FROM products",
  "db_name": "/path/to/shop.db",
  "code": "$row->{price} < 50 && scalar(split(',', $row->{tags})) >= 3 && $row->{created_at} gt '2026-01-01'"
}
```

### 4. Transactions

> "Start a transaction, add a user Alice, then commit"

Sequence:
1. `{ "begin_work": true, "db_name": "/path/to/db.db" }`
2. `{ "query": "INSERT INTO users (name) VALUES (?)", "bind": ["Alice"], "db_name": "/path/to/db.db" }`
3. `{ "commit": true, "db_name": "/path/to/db.db" }`

### 5. Connect to MySQL

> "Show tables in my MySQL database"

```json
{
  "list_tables": true,
  "db_driver": "mysql",
  "db_host": "localhost",
  "db_name": "myapp",
  "db_user": "root",
  "db_password": "secret"
}