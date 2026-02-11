# Within-buffer navigation demo
# Features: MkdnNextLink (Tab), MkdnPrevLink (S-Tab),
#           MkdnNextHeading (]]), MkdnPrevHeading ([[)

Output scripts/demos/gif/navigation${SUFFIX}.gif

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
Type "nvim -u scripts/demos/demo_init.lua scripts/demos/content/navigation.md"
Enter
Sleep 3s
Show

Sleep 1s

# Jump forward through links with Tab
Tab
Sleep 0.6s
Tab
Sleep 0.6s
Tab
Sleep 0.6s
Tab
Sleep 0.6s

# Jump back with S-Tab
Shift+Tab
Sleep 0.6s
Shift+Tab
Sleep 0.8s

# Jump to next heading with ]]
Type@250ms "]]"
Sleep 0.6s
Type@250ms "]]"
Sleep 0.6s
Type@250ms "]]"
Sleep 0.8s

# Jump back with [[
Type@250ms "[["
Sleep 0.6s
Type@250ms "[["
Sleep 2.5s

# Clean exit
Hide
Type ":qa!"
Enter
