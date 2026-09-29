; The Windows installer: Wake-<version>-windows-x64-setup.exe.
;
;   makensis /DVERSION=0.2.3 /DBINARY=path\to\wake.exe /DOUTDIR=dist desktop\packaging\windows\wake.nsi
;
; Per-user (no admin prompt), into %LOCALAPPDATA%\Programs\Wake. The in-app
; updater runs it with /S: it closes Wake if it's still running, replaces the
; files, and the updater starts Wake again. If WebView2 is missing (older
; Windows 10) and MicrosoftEdgeWebview2Setup.exe sits beside this script, the
; installer runs Microsoft's bootstrapper for it.

Unicode true
SetCompressor /SOLID lzma
RequestExecutionLevel user

!ifndef VERSION
  !error "Pass /DVERSION=x.y.z"
!endif
!ifndef BINARY
  !define BINARY "..\..\host\target\release\wake.exe"
!endif
!ifndef OUTDIR
  !define OUTDIR "..\..\dist"
!endif

!include "MUI2.nsh"
!include "LogicLib.nsh"
!include "FileFunc.nsh"

!define PRODUCT "Wake"
!define UNINSTALL_KEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Wake"
!define WEBVIEW2_KEY "SOFTWARE\WOW6432Node\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"
!define WEBVIEW2_USER_KEY "Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}"

Name "${PRODUCT}"
OutFile "${OUTDIR}\Wake-${VERSION}-windows-x64-setup.exe"
InstallDir "$LOCALAPPDATA\Programs\Wake"
InstallDirRegKey HKCU "Software\Wake" "InstallDir"
BrandingText "Wake ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "Wake"
VIAddVersionKey "FileDescription" "Wake Setup"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "LegalCopyright" "Amirali Beigi"

!define MUI_ICON "..\icons\wake.ico"
!define MUI_UNICON "..\icons\wake.ico"
!define MUI_ABORTWARNING
!define MUI_FINISHPAGE_RUN "$INSTDIR\Wake.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Open Wake"

!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH
!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_LANGUAGE "English"

; Wake keeps its files open while it runs.
!macro CloseWake UN
  Function ${UN}CloseWake
    nsExec::ExecToStack 'cmd /c tasklist /FI "IMAGENAME eq Wake.exe" /NH | find /I "Wake.exe"'
    Pop $0
    Pop $1
    ${If} $0 == 0
      ${IfNot} ${Silent}
        MessageBox MB_OKCANCEL|MB_ICONINFORMATION "Wake is open. Choose OK to quit it and continue." IDOK +2
        Abort
      ${EndIf}
      nsExec::Exec 'taskkill /IM Wake.exe /F'
      Pop $0
      Sleep 1500
    ${EndIf}
  FunctionEnd
!macroend
!insertmacro CloseWake ""
!insertmacro CloseWake "un."

Function EnsureWebView2
  ReadRegStr $0 HKLM "${WEBVIEW2_KEY}" "pv"
  ${If} $0 == ""
  ${OrIf} $0 == "0.0.0.0"
    ReadRegStr $0 HKCU "${WEBVIEW2_USER_KEY}" "pv"
  ${EndIf}
  ${If} $0 == ""
  ${OrIf} $0 == "0.0.0.0"
!if /FileExists "MicrosoftEdgeWebview2Setup.exe"
    DetailPrint "Installing Microsoft Edge WebView2…"
    File "/oname=$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe" "MicrosoftEdgeWebview2Setup.exe"
    ExecWait '"$PLUGINSDIR\MicrosoftEdgeWebview2Setup.exe" /silent /install' $1
!else
    ${IfNot} ${Silent}
      MessageBox MB_ICONEXCLAMATION "Wake needs Microsoft Edge WebView2. Install it from https://developer.microsoft.com/microsoft-edge/webview2/ and then open Wake."
    ${EndIf}
!endif
  ${EndIf}
FunctionEnd

Section "Wake"
  InitPluginsDir
  Call CloseWake
  Call EnsureWebView2

  SetOutPath "$INSTDIR"
  File "/oname=Wake.exe" "${BINARY}"
  WriteUninstaller "$INSTDIR\Uninstall.exe"

  CreateShortcut "$SMPROGRAMS\Wake.lnk" "$INSTDIR\Wake.exe"

  WriteRegStr HKCU "Software\Wake" "InstallDir" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayName" "Wake"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "Publisher" "Amirali Beigi"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "DisplayIcon" "$INSTDIR\Wake.exe"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKCU "${UNINSTALL_KEY}" "UninstallString" '"$INSTDIR\Uninstall.exe"'
  WriteRegStr HKCU "${UNINSTALL_KEY}" "QuietUninstallString" '"$INSTDIR\Uninstall.exe" /S'
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoModify" 1
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "NoRepair" 1
  ${GetSize} "$INSTDIR" "/S=0K" $0 $1 $2
  IntFmt $0 "0x%08X" $0
  WriteRegDWORD HKCU "${UNINSTALL_KEY}" "EstimatedSize" "$0"
SectionEnd

; Removes the program. Your threads, history and site data stay in
; %APPDATA%\Wake, so reinstalling picks up where you left off.
Section "Uninstall"
  Call un.CloseWake
  Delete "$INSTDIR\Wake.exe"
  Delete "$INSTDIR\Uninstall.exe"
  RMDir "$INSTDIR"
  Delete "$SMPROGRAMS\Wake.lnk"
  DeleteRegKey HKCU "${UNINSTALL_KEY}"
  DeleteRegKey HKCU "Software\Wake"
SectionEnd
