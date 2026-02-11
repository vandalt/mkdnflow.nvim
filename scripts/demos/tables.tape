# Table workflow demo
# Features: :MkdnTable (create), Tab cell navigation in insert mode,
#           auto-formatting, MkdnTableNewRowBelow (leader-ir)

Output scripts/demos/gif/tables${SUFFIX}.gif

Set FontFamily "MonoLisaCustom Nerd Font"
Set FontSize 22
Set Width 1300
Set Height 650
Set Padding 5
Set TypingSpeed 75ms
Set CursorBlink false
Set Margin 20
Set MarginFill "${MARGIN_FILL}"
Set BorderRadius 20
Set Theme {
    "name": "Kanagawa",
    "background": "#1F1F28",
    "black": "#090618",
    "blue": "#7E9CD8",
    "brightBlack": "#727169",
    "brightBlue": "#7FB4CA",
    "brightCyan": "#7AA89F",
    "brightGreen": "#98BB6C",
    "brightPurple": "#938AA9",
    "brightRed": "#E82424",
    "brightWhite": "#DCD7BA",
    "brightYellow": "#E6C384",
    "cursorColor": "#C8C093",
    "cyan": "#6A9589",
    "foreground": "#DCD7BA",
    "green": "#76946A",
    "purple": "#957FB8",
    "red": "#C34043",
    "selectionBackground": "#2D4F67",
    "white": "#C8C093",
    "yellow": "#C0A36E"
}

Require nvim

# Launch Neovim with demo config
Hide
Type@75ms "TMPFILE=$(date -u +%Y%m%d%H%M%S)"
Enter
Sleep 250ms
Type@75ms "nvim -u scripts/demos/demo_init.lua $TMPFILE.md"
Enter
Sleep 2s

# Clear welcome screen
Type "i "
Sleep 500ms
Backspace
Escape
Sleep 1.5s
Show

Sleep 1s

# Add initial content quickly
Type@50ms "i# Feature Comparison"
Sleep 250ms
Enter
Sleep 150ms
Enter
Sleep 500ms
Type@25ms "Below is a comparison of the deployment options we're evaluating."
Sleep 250ms
Enter
Sleep 250ms
Enter
Sleep 150ms
Escape
Sleep 250ms

# Create a 3-column, 1-row table (excluding the header row)
Type ":MkdnTable 3 1"
Sleep 750ms
Enter
Sleep 1.25s

# Move into the first header cell and enter insert mode
Type "jlli"
Sleep 0.3s

# Type header data and Tab between cells
Type "Option"
Sleep 0.5s
Tab
Type "Cost"
Sleep 0.5s
Tab
Type "Status"
Sleep 0.5s

# Tab to first data row
Tab
Type "AWS ECS (Fargate)"
Sleep 0.5s
Tab
Type "~$125/mo"
Sleep 0.5s
Tab
Type "Evaluated"
Sleep 0.8s

# Exit insert mode
Escape
Sleep 0.5s

# Add a new row below
Type@250ms "\ir"
Sleep 1s

# Tab to the new row
Type "i"
Sleep 250ms
Tab
Sleep 0.3s
Type "Fly.io"
Sleep 0.5s
Tab
Type "~$40/mo"
Sleep 0.5s
Tab
Type "Proposed"
Sleep 0.8s

Escape
Sleep 500ms
Type ":MkdnTableFormat"
Sleep 750ms
Enter
Sleep 500ms

# Exit insert mode
Escape
Sleep 0.5s

# Add a new row below
Type@250ms "\ir"
Sleep 1s

# Tab to the new row
Type "i"
Sleep 250ms
Tab
Sleep 0.3s
Type "DataOcean App Platform"
Sleep 0.5s
Tab
Type "$51/mo"
Sleep 0.5s
Tab
Type "Proposed"
Sleep 0.8s

# Exit insert mode
Escape
Sleep 0.5s

# Play with alignment of first column
Type@500ms "0l"
Sleep 500ms
Type "\ar"
Sleep 1s
Type "\ac"
Sleep 1s
Type "\ax"
Sleep 2.5s

# Clean exit
Hide
Type ":qa!"
Enter
Sleep 150ms
Type "rm $TMPFILE.md"
Enter
Sleep 150ms
