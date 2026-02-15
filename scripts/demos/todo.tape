# To-do list management demo
# Features: MkdnToggleToDo (C-Space) with status cycling,
#           upward propagation, plain list item conversion

Output scripts/demos/gif/todo${SUFFIX}.gif

Set FontFamily "MonoLisaCustom Nerd Font"
Set FontSize 22
Set LetterSpacing 0
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
Sleep 500ms
Escape
Show

# Write text
Type@75ms "i# Sprint No. 12 Tasks"
Enter 2

Type "## Backend"
Enter 2

Type "- API endpoints"
Escape
Sleep 750ms

# Make it a list item
Ctrl+Space
Sleep 750ms

# Make a sub-item
Type@500ms "A:"
Sleep 250ms
Enter
Sleep 500ms
Type@75ms "User authentication"
Sleep 250ms

# Next item
Enter
Sleep 500ms
Type@75ms "Data validation"
Sleep 500ms
Escape
Sleep 500ms
Ctrl+Space
Sleep 500ms
Ctrl+Space
Sleep 500ms

# Next item
Type "o"
Sleep 500ms
Type "Rate limiting"
Sleep 500ms
Enter
Sleep 750ms

# Next item
Enter
Sleep 500ms
Enter
Sleep 500ms
Enter
Sleep 500ms
Enter
Sleep 750ms
Escape

# Go up 2
Type "2k"
Sleep 500ms
Ctrl+Space
Sleep 500ms
Ctrl+Space
Sleep 500ms

# Go up 2
Type "2k"
Sleep 500ms
Ctrl+Space
Sleep 500ms
Ctrl+Space
Sleep 500ms
Escape

# Go all the way to the bottom
Type@500ms "Gi"
Sleep 750ms

# New subsection
Type "## Frontend"
Sleep 250ms

# New line
Enter
Sleep 250ms
Enter
Sleep 250ms
Type@75ms "- Refactor dashboard components"
Sleep 250ms

# New line
Enter
Sleep 500ms
Type "Update unit tests"
Sleep 1s
Escape
Sleep 500ms
Type "V"
Sleep 250ms
Type "k"
Sleep 500ms
Ctrl+Space
Sleep 3s
Hide

# Quit
Escape
Type ":q!"
Enter
Sleep 250ms
Type "rm $TMPFILE.md"
Enter
