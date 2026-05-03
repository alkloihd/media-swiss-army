# XcodeBuildMCP Status -- 2026-05-02

## Current State

- Global binary path: `/Users/rishaal/.nvm/versions/node/v22.18.0/bin/xcodebuildmcp`
- Global install command run:

```bash
npm install -g xcodebuildmcp@latest
```

- CLI help works:

```bash
xcodebuildmcp --help
```

- Tool inventory works:

```bash
xcodebuildmcp tools
```

The tool inventory reports 72 canonical tools and 104 total tools across coverage, debugging, device, logging, macOS, project-discovery, project-scaffolding, simulator, simulator-management, swift-package, UI automation, utilities, and Xcode IDE workflows.

## Codex Config

Codex user TOML:

```text
/Users/rishaal/.codex/config.toml
```

Configured entry:

```toml
[mcp_servers.XcodeBuildMCP]
command = "xcodebuildmcp"
args = ["mcp"]
```

Codex must be restarted before this MCP server is exposed as active tools in the current chat.

## Claude Code Config

Claude Code user-scope MCP command run:

```bash
claude mcp add --scope user xcodebuildmcp -- xcodebuildmcp mcp
```

Claude wrote this to:

```text
/Users/rishaal/.claude.json
```

Claude Code may need a restart or `/mcp` refresh before the server appears in a live Claude session.

Final health check:

```text
xcodebuildmcp: xcodebuildmcp mcp - ✓ Connected
```

## Xcode State

Xcode command-line tools:

```text
Xcode 16.0
Build version 16A242d
/Applications/Xcode.app/Contents/Developer
```

There is currently no `.xcodeproj` or `.xcworkspace` in this repo, so XcodeBuildMCP can be tested for server/tool availability now, but app-specific build/run testing waits until an Xcode project exists.
