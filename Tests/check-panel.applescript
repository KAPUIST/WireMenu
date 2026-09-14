-- Run against the launched app: osascript Tests/check-panel.applescript
-- Opens the menu, expands the network list when available, and closes with Esc.
-- Does not change Wi-Fi, connect to networks, or change login settings.
on findOtherButton()
    tell application "System Events" to tell process "WireMenu"
        repeat with menuRow in buttons of scroll area 1 of group 1 of window 1
            try
                if (value of attribute "AXIdentifier" of menuRow as text) is "wiremenu.other-networks" then return contents of menuRow
            end try
        end repeat
    end tell
    return missing value
end findOtherButton

tell application "System Events" to tell process "WireMenu"
    if exists window 1 then click menu bar item 1 of menu bar 1
    delay 0.3
    click menu bar item 1 of menu bar 1
    delay 1
    set menuHeaderPosition to get position of checkbox 1 of group 1 of window 1
    set headerY to item 2 of menuHeaderPosition
    set anchorPosition to position of menu bar item 1 of menu bar 1
    set anchorSize to size of menu bar item 1 of menu bar 1
    set panelPosition to position of window 1
    if (item 2 of panelPosition) < ((item 2 of anchorPosition) + (item 2 of anchorSize)) then error "Menu opened above its menu bar anchor."
    set menuDidExpand to false
    set menuRow to my findOtherButton()
    if menuRow is not missing value then
            click menuRow
            delay 0.4
            set menuDidExpand to true
            set collapseButton to my findOtherButton()
            if value of collapseButton is not "펼쳐짐" then error "Network list did not expand."
            set expandedHeaderPosition to position of checkbox 1 of group 1 of window 1
            if (item 2 of expandedHeaderPosition) is not headerY then error "Header moved in the expanded menu."
            click collapseButton
            delay 0.4
            set expandButton to my findOtherButton()
            if value of expandButton is not "접힘" then error "Network list did not collapse."
    end if
    set menuHeaderPosition to get position of checkbox 1 of group 1 of window 1
    if (item 2 of menuHeaderPosition) is not headerY then error "Header moved while expanding."
    set menuWindowPosition to get position of window 1
    set menuWindowSize to get size of window 1
    set menuQuitPosition to get position of button 2 of group 1 of window 1
    set menuQuitSize to get size of button 2 of group 1 of window 1
    set windowBottom to (item 2 of menuWindowPosition) + (item 2 of menuWindowSize)
    set quitBottom to (item 2 of menuQuitPosition) + (item 2 of menuQuitSize)
    if quitBottom > windowBottom then error "Footer is clipped."
    set frontmost to true
    key code 53
    delay 0.3
    if exists window 1 then error "Escape did not dismiss the menu."
    -- Closing an old window must not dismiss a newly opened one.
    click menu bar item 1 of menu bar 1
    click menu bar item 1 of menu bar 1
    click menu bar item 1 of menu bar 1
    delay 0.3
    if not (exists window 1) then error "Rapid reopening lost the menu."
    click menu bar item 1 of menu bar 1
    delay 0.3
    if exists window 1 then error "An animated window was left behind."
end tell
return "PASS: fixed header, visible footer, Escape dismissal. Expanded list: " & menuDidExpand
