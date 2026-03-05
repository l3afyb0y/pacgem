# pacgem

`pacgem` is a lightweight `pacman` wrapper for Arch Linux.

It forwards all arguments directly to `pacman`. If `pacman` exits with an error,
`pacgem` asks whether to send command context and captured output to Gemini CLI.

## Example

```bash
sudo pacgem -Syu
```

If the command fails, `pacgem` prompts:

```text
Would you like to send the error to Gemini? [y/n]
```

Choosing `y` launches Gemini CLI with `--yolo` and sends:

```text
Please fix the errors with my Arch Linux's pacman. This happened while running -Syu
[ERROR MESSAGE]:
...
```

## Installation (local PKGBUILD)

```bash
makepkg -si
```

## Notes

- `gemini-cli` is optional, but required for the handoff feature.
- In headless environments, `pacgem` falls back to running Gemini in the current terminal.
