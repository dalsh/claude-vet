# claude-vet

A zsh plugin that intercepts `curl | sh` commands, has Claude review the fetched script, and only executes if the review passes.

## Requirements

- [Claude Code CLI](https://claude.ai/code) installed and authenticated (`claude` in PATH)
- `curl`
- `jq`
- `zsh`

## Usage

Instead of blindly running:
```sh
curl -sSfL https://example.com/install.sh | sh -s -- -b .
```

Run:
```sh
claude-vet 'curl -sSfL https://example.com/install.sh | sh -s -- -b .'
```

Claude fetches the script, reviews it, and:
- **SAFE** → prompts to execute (`[Y/n]`, press Enter to confirm)
- **CAUTION** → prompts to confirm (`[y/N]`, must type `y`)
- **UNSAFE** → aborts with a report

## Configuration

| Variable | Default | Description |
|---|---|---|
| `CLAUDE_VET_AUTO_EXECUTE` | unset | Set to `1` to auto-execute on SAFE verdict without prompting |

## Installation

### zinit

```zsh
zinit light dalsh/claude-vet
```

### oh-my-zsh

```zsh
git clone https://github.com/dalsh/claude-vet \
  ~/.oh-my-zsh/custom/plugins/claude-vet
```

Then add `claude-vet` to your plugins list in `~/.zshrc`:
```zsh
plugins=(... claude-vet)
```

### antigen

```zsh
antigen bundle dalsh/claude-vet
```

### zplug

```zsh
zplug "dalsh/claude-vet"
```

### Manual

```zsh
git clone https://github.com/dalsh/claude-vet ~/path/of/your/choice
echo 'source ~/path/of/your/choice/claude-vet.plugin.zsh' >> ~/.zshrc
```

## Testing

Example scripts are provided in `examples/` to verify each verdict path works correctly.
Host them at a raw URL (e.g. the raw GitHub URLs once published), then pass the URL to `claude-vet`.

| File | Expected verdict | Patterns it contains |
|---|---|---|
| `examples/caution.sh` | `CAUTION` | Secondary script download, rc file modification, unnecessary sudo |
| `examples/unsafe.sh` | `UNSAFE` | Env exfiltration, base64 eval, cron persistence |
| `examples/injection.sh` | `UNSAFE` | Prompt injection attempts + SSH key exfiltration |

## Customizing the prompt

The review prompts live in `prompts/`:
- `system.txt` — trusted system instructions (security reviewer role, anti-injection rules, analysis checklist)
- `user.txt` — template for the user message containing the untrusted script content

The script uses `--json-schema` to enforce structured output from Claude, so the verdict is validated server-side.

## Security model

claude-vet defends against prompt injection (malicious scripts trying to manipulate Claude's verdict) with multiple layers:

1. **System/user message separation** — trusted instructions go via `--system-prompt-file`, untrusted script content goes via stdin as the user message
2. **Anti-injection instructions** — the system prompt explicitly tells Claude to ignore directives embedded in script content
3. **Structured output with JSON Schema** — the verdict is constrained to an `enum` of `SAFE`/`CAUTION`/`UNSAFE`, validated server-side
4. **No auto-execute by default** — even a SAFE verdict prompts for confirmation unless `CLAUDE_VET_AUTO_EXECUTE=1` is set
5. **Default-deny on failure** — unparseable responses are treated as UNSAFE

## Caveats

- Only reviews scripts fetched **at review time**. If a script itself downloads and executes a second payload at runtime, that secondary payload is not reviewed — Claude will flag this pattern as `CAUTION` or `UNSAFE`.
- Trust ultimately rests on Claude's analysis. The hardening measures raise the bar significantly but prompt injection against LLMs is an open problem — this is a safety net, not a guarantee.
