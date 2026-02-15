# Section folding demo
# Features: MkdnFoldSection (leader-f), MkdnUnfoldSection (leader-F),
#           custom foldtext with object counts

Output scripts/demos/gif/folding${SUFFIX}.gif

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
Type "nvim -u scripts/demos/demo_init.lua scripts/demos/content/folding.md"
Enter
Sleep 3s
Show

Sleep 1s

# Move to "API Layer" heading (line 3)
Type "3G"
Sleep 750ms

# Fold the section
Enter
Sleep 1.25s

# Move to "Data Layer" heading
Type "j"
Sleep 750ms

# Fold that section too
Enter
Sleep 1.25s

# Move to "Deployment" heading
Type "j"
Sleep 500ms

# Fold it
Enter
Sleep 1.2s

# Move back to first fold and unfold it
Type@250ms "kk"
Sleep 1s
Enter
Sleep 1.25s

# Unfold the next one
Type@250ms "]]"
Sleep 0.5s
Enter
Sleep 2.5s

# Clean exit
Hide
Type ":qa!"
Enter
