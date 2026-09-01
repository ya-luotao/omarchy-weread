# WeRead for Omarchy

微信读书 reading stats as a native [Omarchy](https://omarchy.org) shell plugin (Omarchy 4 "Quattro" or later), powered by the official [WeRead agent API](https://github.com/Tencent/WeChatReading).

- **Bar widget** — an open-book glyph in the bar. A dot on the spine appears once you've read today; the tooltip carries 今天 / 本周 reading time.
- **Panel** — this week's total, reading days and daily average (with week-over-week trend), seven daily bars, and the books the time actually went to.
- **Disk cache** — the last good response lives in `~/.local/state/omarchy/weread/weekly.json`, so the bar never starts blank.

## Setup

The plugin talks to the WeRead API gateway (`i.weread.qq.com/api/agent/gateway`) and needs an API key bound to your account:

1. Get your key at [weread.qq.com/r/weread-skills](https://weread.qq.com/r/weread-skills) (format `wrk-…`)
2. Provide it either way:

```bash
# a) environment variable (picked up if the shell process sees it)
export WEREAD_API_KEY=wrk-xxxxxxxx

# b) key file (recommended for a long-running shell)
mkdir -p ~/.config/omarchy/weread
echo -n wrk-xxxxxxxx > ~/.config/omarchy/weread/api-key
chmod 600 ~/.config/omarchy/weread/api-key
```

## Install

```bash
omarchy plugin add https://github.com/ya-luotao/omarchy-weread.git --enable
```

## Usage

- Left-click the book → panel: week summary, daily bars, top books
- Middle-click (or `R` in the panel) → refresh now
- `Esc` closes the panel

From scripts:

```bash
omarchy-shell luotao.weread status    # {"ok":true,"todaySeconds":1200,...}
omarchy-shell luotao.weread refresh
```

### Settings

```bash
omarchy bar set luotao.weread refreshMinutes 30   # poll less often (default 15)
```

## How it works

`tools/weread-api` is a thin bash wrapper around the gateway: it injects `skill_version`, resolves the key from env or the key file, POSTs, and caches successful responses under `$XDG_STATE_HOME/omarchy/weread/`. The QML widget calls it with `/readdata/detail` (`mode=weekly`) and renders the result; all durations from the API are **seconds**.

## License

[MIT](./LICENSE)
