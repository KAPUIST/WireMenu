-- Run while connected to Wi-Fi: osascript Tests/check-menu.applescript
-- Requires Accessibility permission; only opens/closes the menu, never changes a connection.
on run
    tell application "System Events" to tell process "WireMenu"
        if exists window 1 then click menu bar item 1 of menu bar 1
        click menu bar item 1 of menu bar 1
        repeat 40 times
            if exists (first button of scroll area 1 of group 1 of window 1 whose value is "연결됨") then exit repeat
            delay 0.5
        end repeat
        if not (exists (first button of scroll area 1 of group 1 of window 1 whose value is "연결됨")) then error "Initial network scan did not find the connected network."
        click menu bar item 1 of menu bar 1
        click menu bar item 1 of menu bar 1
        delay 0.1
        if not (exists (first button of scroll area 1 of group 1 of window 1 whose value is "연결됨")) then error "Connected network missing immediately after reopening."
        click menu bar item 1 of menu bar 1
    end tell
    return "PASS: known network is visible immediately after reopening."
end run
