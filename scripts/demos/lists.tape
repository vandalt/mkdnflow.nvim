# To-do list management demo
# Features: MkdnToggleToDo (C-Space) with status cycling,
#           upward propagation, plain list item conversion

Output scripts/demos/gif/lists${SUFFIX}.gif

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
Type@75ms "TMPFILE = $(date -u +%Y%m%d%H%M%S)"
Enter
Sleep 250ms
Type@75ms "nvim -u scripts/demos/demo_init.lua $TMPFILE.md"
Enter
Sleep 2s

# Write text
Type "i# Release Checklist"
Enter 2

Type "## Pre-release"
Enter 2
Show
Sleep 1s

# First item
Type@50ms "1. "
Sleep 250ms
Type@50ms "Run integration tests"
Sleep 400ms
Enter
Sleep 250ms

# Second item
Type@50ms "Update changelog"
Sleep 400ms
Enter
Sleep 500ms

# Third item
Type@50ms "Bump version number"
Sleep 250ms
Enter
Sleep 100ms
Enter
Sleep 75ms
Enter

# Start typing next section
Type@50ms "## De"
Type@100ms "pl"
Type@500ms "oy"
Type "m"
Sleep 500ms
Escape
Sleep 100ms

# Go up
Type@250ms "kk"
Sleep 250ms
Type "O"
Sleep 500ms
Type@50ms "Review pull requests"
Sleep 250ms
Escape
Sleep 500ms

# Finish the deployment line
Type@250ms "GA"
Sleep 250ms
Type@50ms "ent Steps"
Sleep 500ms
Enter
Sleep 250ms
Enter
Sleep 500ms

# Single sentence
Type@30ms "Follow the standard deployment process."
Sleep 400ms
Enter
Sleep 250ms
Enter
Sleep 250ms

# Staging section
Type@100ms "### "
Sleep 150ms
Type@50ms "Staging"
Sleep 300ms
Enter
Sleep 250ms
Enter
Sleep 250ms

# Start new list
Type "1. "
Sleep 250ms
Type@50ms "Deploy to staging environment"
Sleep 250ms
Enter
Type@50ms "Run smoke tests:"
Sleep 250ms
Enter
Sleep 250ms

# Sub-list
Type@50ms "Verify API health endpoints"
Sleep 250ms
Enter
Sleep 250ms
Type@40ms "Check database migrations"
Sleep 150ms
Enter
Sleep 150ms
Type@40ms "Confirm background job processing"
Sleep 250ms
Enter
Sleep 500ms
Enter
Sleep 500ms

# Back to the main list
Type@50ms "Get sign-off from QA"
Sleep 1.5s

Hide
# Quit
Escape
Type ":q!"
Enter
Sleep 250ms
Type "rm $TMPFILE.md"
Enter
