# Screenshots

The root README references these six files. Drop them in with these exact
names and the grid fills itself in — no README edits needed.

| File | Shot |
|:---|:---|
| `01-chat.png` | Chat with a rant typed in and clarifying questions showing |
| `02-proposal.png` | A proposal card, pre-approval, with the Approve button visible |
| `03-timeline.png` | Today's timeline in History |
| `04-focus.png` | A focus session running |
| `05-week-review.png` | The week review scoreboard |
| `06-wrapped.png` | A Wrapped story card |

`icon.png` is the 1024×1024 app icon, used as the README hero.

## Capturing

From a running simulator:

```bash
xcrun simctl io booted screenshot docs/screenshots/01-chat.png
```

From a physical device: take a normal screenshot, AirDrop it over, rename it.

Optional — trim the file size before committing:

```bash
sips -Z 1200 docs/screenshots/*.png
```
