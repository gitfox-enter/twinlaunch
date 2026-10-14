Option Explicit

Dim fso, sh
Dim root, desktop
Dim i, made
Dim src, resolved, baseName, lnkPath, tmp
Dim lnk

Set fso = CreateObject("Scripting.FileSystemObject")
Set sh  = CreateObject("WScript.Shell")

If WScript.Arguments.Count = 0 Then
    WScript.Echo "Usage: pass one or more .exe / .lnk paths as arguments."
    WScript.Quit 1
End If

root    = sh.ExpandEnvironmentStrings("%SystemRoot%")
desktop = sh.SpecialFolders("Desktop")
made    = 0

For i = 0 To WScript.Arguments.Count - 1
    src = WScript.Arguments(i)
    If fso.FileExists(src) Then
        resolved = src
        If LCase(fso.GetExtensionName(src)) = "lnk" Then
            tmp = sh.CreateShortcut(src).TargetPath
            If tmp <> "" Then resolved = tmp
        End If
        resolved = sh.ExpandEnvironmentStrings(resolved)
        If LCase(fso.GetExtensionName(resolved)) = "exe" Then
            baseName = fso.GetBaseName(src)
            lnkPath  = desktop & "\" & baseName & " (User10).lnk"
            Set lnk = sh.CreateShortcut(lnkPath)
            lnk.TargetPath       = root & "\System32\cmd.exe"
            lnk.Arguments        = "/c runas /savecred /user:10 """ & resolved & """ || pause"
            lnk.WorkingDirectory = fso.GetParentFolderName(resolved)
            lnk.IconLocation     = resolved & ",0"
            lnk.Description      = "Launch as local user 10"
            lnk.Save
            WScript.Echo "[OK]   " & baseName & " (User10).lnk"
            made = made + 1
        Else
            WScript.Echo "[SKIP] not an exe: " & src
        End If
    Else
        WScript.Echo "[SKIP] not found: " & src
    End If
Next

WScript.Echo ""
WScript.Echo "Created " & made & " shortcut(s) on Desktop."
