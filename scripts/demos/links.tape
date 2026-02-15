# Link lifecycle demo
# Features: MkdnEnter (create link from word), MkdnEnter (follow link),
#           MkdnGoBack (BS), MkdnDestroyLink (M-CR)

Output scripts/demos/gif/links${SUFFIX}.gif

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
Type "nvim -u scripts/demos/demo_init.lua scripts/demos/content/links.md"
Enter
Sleep 3s
Show

Sleep 1.5s

# Move to the word "caching" on line 15 and create a link from it
Type "13G"
Sleep 500ms
Type@150ms "wwwww"
Sleep 250ms
Enter
Sleep 1s

# Follow the link
Enter
Sleep 1s

# Add some content
Type "o"
Sleep 150ms
Enter
Sleep 150ms
Type "(Fill this in later...)"
Sleep 500ms

# Navigate back
Escape
Sleep 500ms
Backspace
Sleep 1.5s

# Jump two links back
Shift+Tab
Sleep 500ms
Shift+Tab
Sleep 750ms

# Follow security audit link
Enter
Sleep 1.5s

# Add a note for Jake
Type "o"
Sleep 150ms
Enter
Sleep 250ms
Type@50ms "@Jake pls get to this ASAP"
Sleep 500ms

# Go back
Escape
Sleep 100ms
Backspace
Sleep 750ms

# Move to another link and destroy it
Tab
Sleep 750ms
Alt+Enter
Sleep 2.5s

# Clean exit
Hide
Escape
Type ":qa!"
Enter
