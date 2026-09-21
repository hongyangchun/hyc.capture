# hyc.capture — Cap Quick for Omarchy

Quick capture to [Capacities](https://capacities.io) daily notes.

**Super+N** → centered input card → type → **Enter** → appended to today's daily note.

## Features

- Fullscreen layer-shell overlay, follows the active Omarchy theme
- Multi-line (Shift+Enter for newline), clipboard hint with Tab-to-fill
- Offline queue: failed sends land in `~/.local/state/cap-quick/queue/` and are
  flushed automatically on the next successful send
- Draft restore: close with unsent text, get it back on next open
- Desktop notifications confirm send / queue status
- Token read at runtime from `~/.config/cap-quick/token` (0600) or
  `~/.hermes/.env` (`CAPACITIES_API_TOKEN`) — never stored in the repo

## Install

```sh
omarchy plugin add https://github.com/hongyangchun/hyc.capture.git --enable
```

Then bind a key in `~/.config/hypr/bindings.conf`:

```
bindd = SUPER, N, Cap Quick capture, exec, omarchy-shell shell summon hyc.capture '{}'
```

## API

Uses `POST /blocks/daily-note/append` (markdown, async, 30 req/min) from the
[Capacities API](https://developers.capacities.io). Personal token
(`cap-api-…`) generated in Capacities → Settings → Capacities API.

## License

MIT
