; main.nsi
;
; This script will install and configure Cypress.
; It also sets up an uninstaller so that the user 
; can remove the application completely if desired.

;--------------------------------

; Use the lzma compression algorithm for maximum compression
SetCompressor /solid lzma

;--------------------------------
; Include files

!include "LogicLib.nsh"
!include "MUI2.nsh"
!include "scheduletask.nsh"

;--------------------------------

; Only install on Windows XP or more recent (option not supported yet)
;TargetMinimalOS 5.1

; Make sure the product name is defined
!ifndef PRODUCT_NAME
  !error "Must provide the name of the product. i.e. /DPRODUCT_NAME=Cypress"
!endif

; Make sure the version number is defined
!ifndef VERSION
  !error "Must provide installer version. i.e. /DVERSION=<ver_num>"
!endif

; Make sure the size required for the product is defined
!ifndef PRODUCT_SIZE
  !error "Must provide the size of product (in KB). i.e. /DPRODUCT_SIZE=105100"
!endif

; Make sure the version of the measures bundle is provided
!ifndef MEASURES_VERSION
  !error "Must provide version for the measures bundle. i.e. /DMEASURES_VERSION=1.4.2"
!endif

; default to 64-bit architecture
!ifndef BUILDARCH
  !define BUILDARCH 64
!endif
!echo "BUILDARCH = ${BUILDARCH}"

; The file to write
!if ${BUILDARCH} = 32
OutFile "${PRODUCT_NAME}-${VERSION}-i386.exe"
!else
OutFile "${PRODUCT_NAME}-${VERSION}-x86_64.exe"
!endif

; Registry key to check for directory (so if you install again, it will
; overwrite the old one automatically)
InstallDirRegKey HKLM "Software\${PRODUCT_NAME}" "Install_Dir"

; Request application privileges for Windows Vista
RequestExecutionLevel admin

; Install types we support: full, minimal, custom (provided automatically)
InstType "Full"
InstType "Minimal"

; License settings
LicenseForceSelection checkbox "I accept"
;LicenseText
LicenseData license.txt

;--------------------------------
; Some useful defines
!define env_allusers 'HKLM "SYSTEM\CurrentControlSet\Control\Session Manager\Environment"'
!if ${BUILDARCH} = 32
  !define ruby_key 'HKLM "software\RubyInstaller\MRI\1.9.2" "InstallLocation"'
!else
  !define ruby_key 'HKLM "software\Wow6432Node\RubyInstaller\MRI\1.9.2" "InstallLocation"'
!endif

; The name of the installer
Name "${PRODUCT_NAME}"

;--------------------------------
; Some useful macros

; This macro sets an environment variable temporarily for the installer and sub-processes
!macro SetInstallerEnvVar Name Value
  System::Call 'Kernel32::SetEnvironmentVariableA(t, t) i("${Name}", "${Value}").r0'
  StrCmp $0 0 0 +2
    MessageBox MB_OK "Failed to set environment variable '${Name}'"
!macroend

; This macro adds an environment variable to the registry for all users
!macro AddEnvVarToReg Name Value
  WriteRegExpandStr ${env_allusers} '${Name}' '${Value}'
  ; Make sure Windows knows about the change
  SendMessage ${HWND_BROADCAST} ${WM_WININICHANGE} 0 "STR:Environment" /TIMEOUT=5000
!macroend

; This macro adds an environment variable to the registry for all users, and
; adds it to the environment of the installer and sub-processes
!macro EnvVarEverywhere Name Value
  !insertmacro AddEnvVarToReg '${Name}' '${Value}'
  !insertmacro SetInstallerEnvVar '${Name}' '${Value}'
!macroend

!macro SetRubyDir
  StrCpy $rubydir "$systemdrive\Ruby192"
  push $0
  ReadRegStr $0 ${ruby_key}
  StrCmp $0 "" +2
  StrCpy $rubydir $0
  pop $0
!macroend

!macro CheckRubyInstalled Yes No
  !insertmacro SetRubyDir
  IfFileExists "$rubydir\bin\ruby.exe" ${Yes} ${No}
!macroend

; Usage:
; ${Trim} $trimmedString $originalString
!define Trim "!insertmacro Trim"
!macro Trim ResultVar String
  Push "${String}"
  Call Trim
  Pop "${ResultVar}"
!macroend

;--------------------------------
;Interface Settings

!define MUI_HEADERIMAGE
!define MUI_HEADERIMAGE_BITMAP ${PRODUCT_NAME}MiniLogo.bmp
!define MUI_ABORTWARNING
XPStyle on

Var Dialog
var systemdrive ;Set the primary drive letter for the system
var rubydir    ; The root directory of the ruby install to use
var mongodir   ; The root directory of the mongodb install
var redisdir   ; The root directory of the redis install

;--------------------------------
; Pages

!insertmacro MUI_PAGE_WELCOME
;Page license
!insertmacro MUI_PAGE_LICENSE license.txt
;Page components
!insertmacro MUI_PAGE_COMPONENTS
;Page directory
!insertmacro MUI_PAGE_DIRECTORY

Page custom ProxySettingsPage ProxySettingsLeave

;Page instfiles
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_WELCOME
;UninstPage uninstConfirm
!insertmacro MUI_UNPAGE_CONFIRM
UnInstPage custom un.ProxySettingsPage
;UninstPage instfiles
!insertmacro MUI_UNPAGE_INSTFILES
!insertmacro MUI_UNPAGE_FINISH

;--------------------------------
; Languages

!insertmacro MUI_LANGUAGE "English"

;=============================================================================
; INSTALLER SECTIONS
;
; The order of the sections determines the order that they will be listed in
; the Components page.
;=============================================================================

;-----------------------------------------------------------------------------
; Uninstaller
;
; Creates and registers an uninstaller for application removal.
;-----------------------------------------------------------------------------
Section "Create Uninstaller" sec_uninstall

  SectionIn RO
  
  SetOutPath $INSTDIR

  ; Write the installation path into the registry
  WriteRegStr HKLM SOFTWARE\${PRODUCT_NAME} "Install_Dir" "$INSTDIR"
  
  ; Write the uninstall keys for Windows
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "DisplayName" "${PRODUCT_NAME}"
  WriteRegStr HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoModify" 1
  WriteRegDWORD HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}" "NoRepair" 1
  WriteUninstaller "uninstall.exe"
  
SectionEnd

;-----------------------------------------------------------------------------
; Start Menu Shortcuts
;
; Registers a Start Menu shortcut for the application uninstaller and other
; scrpits needed to launch a web browser into the web application.
;-----------------------------------------------------------------------------
Section "Start Menu Shortcuts" sec_startmenu

  SectionIn 1 2 3

  SetOutPath $INSTDIR

  ; Create an Internet shortcut for the web app
  WriteINIStr "$INSTDIR\${PRODUCT_NAME}.URL" "InternetShortcut" "URL" "http://localhost:3000/"

  CreateDirectory "$SMPROGRAMS\${PRODUCT_NAME}"
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\Uninstall.lnk" "$INSTDIR\uninstall.exe" "" "$INSTDIR\uninstall.exe" 0
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME}.lnk" "$INSTDIR\${PRODUCT_NAME}.URL" "" "" ""
  CreateShortCut "$SMPROGRAMS\${PRODUCT_NAME}\${PRODUCT_NAME} Web Server.lnk" "$INSTDIR\${PRODUCT_NAME}\script\webserver.bat"
  
SectionEnd

SectionGroup "Required 3rd party software"
;-----------------------------------------------------------------------------
; Ruby
;
; Runs the Ruby install program and waits for it to finish.
; TODO: Need to record somehow whether we actually install this so that the
;       uninstaller can remove it.
;-----------------------------------------------------------------------------
Section "Install Ruby" sec_ruby

  SectionIn 1 3                  ; enabled in Full and Custom installs
  AddSize 18534                  ; additional size in kB above installer

  ;Check if ruby exists
  !insertmacro CheckRubyInstalled 0 installruby
  
  ;Ruby was found
  MessageBox MB_ICONQUESTION|MB_YESNO "A current ruby installation was found.  Do you want to install it again?$\n$\n\
      Current install location: $0" /SD IDNO IDNO rubydone
  
  ;Ruby not found
  installruby:	
  SetOutPath $INSTDIR\depinstallers ; temporary directory

  File "rubyinstaller-1.9.2-p290.exe"
  ExecWait '"$INSTDIR\depinstallers\rubyinstaller-1.9.2-p290.exe" /verysilent /tasks="assocfiles,modpath"'
  Delete "$INSTDIR\depinstallers\rubyinstaller-1.9.2-p290.exe"

  ;Make sure ruby was installed
  !insertmacro CheckRubyInstalled rubydone 0
  MessageBox MB_ICONEXCLAMATION|MB_RETRYCANCEL 'We could not verify that ruby was properly installed' \
  IDRETRY installruby

  rubydone:
  Push "$rubydir\bin"
  Call AddToPath
SectionEnd

;-----------------------------------------------------------------------------
; Bundler
;
; Installs the bundler gem for user later in the install.
;-----------------------------------------------------------------------------
Section "Install Bundler" sec_bundler

  SectionIn 1 3                  ; enabled in Full and Custom installs
  AddSize 3922                   ; additional size in kB above installer

  ClearErrors
  ExecWait '"$rubydir\bin\gem.bat" install bundler'
  IfErrors 0 +2
    MessageBox MB_ICONEXCLAMATION|MB_OK "Failed to install the bundler gem."

  ;some logging gems require version >1.8.0 of RubyGems to install properly
  ExecWait '"$rubydir\bin\gem.bat" update --system'

SectionEnd

;-----------------------------------------------------------------------------
; MongoDB
;
; Installs and registers mongodb to runs as a native Windows service.  Since
; this program is distributed as a zip file, it is unpackaged and included
; directly in the installer. The service is also started so that we
; can use MongoDB later in the installer.
;-----------------------------------------------------------------------------
Section "Install MongoDB" sec_mongodb

  SectionIn 1 3                  ; enabled in Full and Custom installs

  SetOutPath "$systemdrive\mongodb-2.0.1"

  File /r mongodb-2.0.1\*.*

  ; Create a data directory for mongodb
  SetOutPath $systemdrive\data\db

  ; Install the mongodb service
  ExecWait '"$mongodir\bin\mongod" --logpath $systemdrive\data\logs --logappend --dbpath $systemdrive\data\db --directoryperdb --install'

  ; Start the mongodb service
  ExecWait 'net.exe start "Mongo DB"'

SectionEnd

;-----------------------------------------------------------------------------
; Redis
;
; Installs the redis server.  This program is distributed as a zip file, so
; it is unpackage and included directly in the installer.  
;-----------------------------------------------------------------------------
Section "Install Redis" sec_redis

  SectionIn 1 3                  ; enabled in Full and Custom installs

  SetOutPath "$redisdir"
  File /r redis-2.4.0\*.*

SectionEnd

SectionGroupEnd
; end "Third party software"

;-----------------------------------------------------------------------------
; Web Application
;
; This section copies the Web Application onto the system.  This
; also installs a scheduled task with a boot trigger that will start a web
; server so that the application can be accessed when the system is booted.
;-----------------------------------------------------------------------------
Section "${PRODUCT_NAME} Web Application" sec_webserver

  SectionIn RO
  AddSize ${PRODUCT_SIZE}        ; current size of cloned repo (in kB)

  ; Define an environment variable for the database to use
  ;  !insertmacro EnvVarEverywhere 'DB_NAME' 'cypress_production'

  ; Set output path to the installation directory.
  SetOutPath $INSTDIR
  File /r ${PRODUCT_NAME}

  SetOutPath "$INSTDIR\${PRODUCT_NAME}"
  ExecWait 'bundle.bat install --local'

  SetOutPath "$INSTDIR\${PRODUCT_NAME}\script"

  ; Install the batch file that starts the workers.
  File "run-resque.bat"

  ; Create/Install a batch file that starts the web server with all prerequisites.
  ClearErrors
  FileOpen $0 "webserver.bat" w
  IfErrors done
  FileWrite $0 "@ECHO OFF$\r$\n"
  ; generate the code that starts the redis-server
  FileWrite $0 "echo Starting the redis-server to handle job queue management$\r$\n"
  FileWrite $0 "cd $redisdir\${BUILDARCH}bit$\r$\n"
  FileWrite $0 "start /b redis-server.exe redis.conf$\r$\n"

  ; generate the code that starts the resque workers up
  FileWrite $0 "SET QUEUE=*$\r$\n"
  FileWrite $0 "SET RAILS_ENV=production$\r$\n"
  FileWrite $0 "cd $INSTDIR\Cypress$\r$\n"
  FileWrite $0 "echo.$\r$\n"
  FileWrite $0 "echo Starting the resque workers to listen on the queue$\r$\n"
  FileWrite $0 "start /b bundle.bat exec rake resque:work$\r$\n"
  FileWrite $0 "echo.$\r$\n"

  ; generate code that fires up the web server
  FileWrite $0 "echo.$\r$\n"
  FileWrite $0 "echo Starting up the Cypress web server which takes a few minutes...$\r$\n"
  FileWrite $0 "echo Once you start seeing messages logged to this window, you can feel$\r$\n"
  FileWrite $0 "echo free to use the Cypress shortcut to open a browser pointed to the application.$\r$\n"
  FileWrite $0 "echo Alternatively, you can type the URL http://localhost:3000/ into an$\r$\n"
  FileWrite $0 "echo existing browser.$\r$\n"
  FileWrite $0 "echo.$\r$\n"
  FileWrite $0 "echo          -- The Cypress Team$\r$\n"
  FileWrite $0 "echo.$\r$\n"
  FileWrite $0 "ruby.exe script\rails server -p 3000 -e production$\r$\n"

  FileClose $0
  done:

SectionEnd

;-----------------------------------------------------------------------------
; Scheduled Tasks
;
; As an optional convenience, we can provide scheduled tasks to restart the 
; key components upon rebooting the system.  These components are redis-server
; (until we install 2.4.6 which can be run as a service), the resque workers
; which are stared using script\run-resque.bat and the web server itself which 
; is kicked off using script\webserver.bat
;-----------------------------------------------------------------------------
Section "${PRODUCT_NAME} Scheduled Tasks" sec_scheduledtasks

  SectionIn 1 3

  ; Install a scheduled task to start redis on system boot
  push "${PRODUCT_NAME} Redis Server"
  push "Run the redis server at startup."
  push "PT15S"
  push "$redisdir\${BUILDARCH}bit\redis-server.exe"
  push "redis.conf"
  push "$redisdir\${BUILDARCH}bit"
  push "Local Service"
  Call CreateTask
  pop $0
  DetailPrint "Result of scheduling Redis Server task: $0"

  ; Install the scheduled service to run the resque workers on startup.
  push "${PRODUCT_NAME} Resque Workers"
  push "Run the resque workers for the ${PRODUCT_NAME} application."
  push "PT45S"
  push "$INSTDIR\${PRODUCT_NAME}\script\run-resque.bat"
  push ""
  push "$INSTDIR\${PRODUCT_NAME}"
  push "Local Service"
  Call CreateTask
  pop $0
  DetailPrint "Result of scheduling resque workers task: $0"

  ; Install a scheduled task to start a web server on system boot
  push "${PRODUCT_NAME} Web Server"
  push "Run the web server that allows access to the ${PRODUCT_NAME} application."
  push "PT1M30S"
  push "$rubydir\bin\ruby.exe"
  push "script/rails server -p 3000 -e production"
  push "$INSTDIR\${PRODUCT_NAME}"
  push "System"
  Call CreateTask
  pop $0
  DetailPrint "Result of scheduling Web Server task: $0"
  SetRebootFlag true
SectionEnd

;-----------------------------------------------------------------------------
; Post-install steps
;
; This section adds the Test Deck patient records to the mongo database so that
; there is data to work with as soon as the installer finishes.
; It also runs the quality measure engine on the test deck.
;-----------------------------------------------------------------------------
Section "Post-Install steps" sec_postinstall

  SectionIn 1 3                  ; enabled in Full and Custom installs

  SetOutPath "$redisdir\${BUILDARCH}bit"
  ; start up the redis server for queue management
  ExecShell "open" "redis-server.exe" "redis.conf" SW_HIDE

  ; Set output path to the product web app's script directory
  SetOutPath $INSTDIR\${PRODUCT_NAME}\script
  ; start up the resque workers so that the initial evaluation of measures 
  ; can be performed
  ExecShell "open" "run-resque.bat" "" SW_HIDE

  SetOutPath $INSTDIR\${PRODUCT_NAME}
  ; seed with test deck (which also loads the measure definitions)
  ExecWait 'bundle.bat exec rake mpl:initialize RAILS_ENV=production'

  ; start up the web server
  SetOutPath $INSTDIR\${PRODUCT_NAME}\script
  ExecShell "open" "webserver.bat" "" SW_SHOWDEFAULT

SectionEnd


;--------------------------------
; Descriptions

  ;Language strings
  LangString DESC_sec_uninstall       ${LANG_ENGLISH} "Provides ability to uninstall ${PRODUCT_NAME}"
  LangString DESC_sec_startmenu       ${LANG_ENGLISH} "Start Menu shortcuts"
  LangString DESC_sec_ruby            ${LANG_ENGLISH} "Ruby scripting language"
  LangString DESC_sec_bundler         ${LANG_ENGLISH} "Ruby Bundler gem"
  LangString DESC_sec_mongodb         ${Lang_ENGLISH} "MongoDB database server"
  LangString DESC_sec_redis           ${LANG_ENGLISH} "Redis server"
  LangString DESC_sec_scheduledtasks  ${LANG_ENGLISH} "${PRODUCT_NAME} scheduled tasks"
  LangString DESC_sec_webserver       ${LANG_ENGLISH} "${PRODUCT_NAME} web application"
  LangString DESC_sec_postinstall     ${LANG_ENGLISH} "Initialize database with patient data and quality measures"

  LangString ProxyPage_Title          ${LANG_ENGLISH} "Proxy Server Settings"
  LangString ProxyPage_SUBTITLE       ${LANG_ENGLISH} "Specify the name of the proxy server used to access the Internet"

  ;Assign language strings to sections
  !insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_uninstall}       $(DESC_sec_uninstall)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_startmenu}       $(DESC_sec_startmenu)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_ruby}            $(DESC_sec_ruby)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_bundler}         $(DESC_sec_bundler)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_mongodb}         $(DESC_sec_mongodb)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_redis}           $(DESC_sec_redis)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_scheduledtasks}  $(DESC_sec_scheduledtasks)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_webserver}       $(DESC_sec_webserver)
    !insertmacro MUI_DESCRIPTION_TEXT ${sec_postinstall}     $(DESC_sec_postinstall)

  !insertmacro MUI_FUNCTION_DESCRIPTION_END

;=============================================================================
; UNINSTALLER SECTION
;
; This should undo everyting done by the installer.
; TODO: Need to record exactly which components were installed so that we only
;       uninstall those same components.
;=============================================================================

Section "Uninstall"
  
  ; Remove registry keys
  DeleteRegKey HKLM "Software\Microsoft\Windows\CurrentVersion\Uninstall\${PRODUCT_NAME}"
  DeleteRegKey HKLM SOFTWARE\${PRODUCT_NAME}

  ; Uninstall the resque worker scheduled task
  ExecWait 'schtasks.exe /end /tn "${PRODUCT_NAME} Resque Workers"'
  push "${PRODUCT_NAME} Resque Workers"
  Call un.DeleteTask
  pop $0
  DetailPrint "Results of deleting Resque Workers task: $0"

  ; Uninstall web application scheduled task
  ExecWait 'schtasks.exe /end /tn "${PRODUCT_NAME} Web Server"'
  push "${PRODUCT_NAME} Web Server"
  Call un.DeleteTask
  pop $0
  DetailPrint "Results of deleting Web Server task: $0"
  RMDIR /r $INSTDIR\${PRODUCT_NAME}

  ; Uninstall redis and remove scheduled task.
  ExecWait 'schtasks.exe /end /tn "${PRODUCT_NAME} Redis Server"'
  push "${PRODUCT_NAME} Redis Server"
  Call un.DeleteTask
  pop $0
  DetailPrint "Results of deleting Redis Server task: $0"
  RMDIR /r "$redisdir"

  ; Uninstall mongodb
  ExecWait '"$mongodir\bin\mongod" --remove'
  RMDIR /r "$mongodir"

  ; Uninstall the Bundler gem
  ExecWait "gem.bat uninstall -x bundler"

  ; Uninstall ruby -- Should we do a silent uninstall
  ; TODO: Did we really install it?
  MessageBox MB_ICONINFORMATION|MB_YESNO 'We installed Ruby.  Do you want us to uninstall it?' \
      /SD IDYES IDNO skiprubyuninst
    ReadRegStr $0 HKCU "SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\{BD5F3A9C-22D5-4C1D-AEA0-ED1BE83A1E67}_is1" \
        "UninstallString"
    ExecWait '$0 /silent'
  skiprubyuninst:

  ; Remove files and uninstaller
  Delete $INSTDIR\uninstall.exe
  Delete $INSTDIR\${PRODUCT_NAME}.URL

  ; Remove shortcuts, if any
  Delete "$SMPROGRAMS\${PRODUCT_NAME}\*.*"

  ; Remove directories used
  RMDir "$SMPROGRAMS\${PRODUCT_NAME}"
  RMDir "$INSTDIR\depinstallers"
  RMDir "$INSTDIR\${PRODUCT_NAME}"
  RMDir "$INSTDIR"

SectionEnd

;=============================================================================
; UTILITY FUNCTIONS
;=============================================================================

; Trim
;   Removes leading & trailing whitespace from a string
; Usave:
;   Push
;   Call Trim
;   Pop
Function Trim
  Exch $R1 ; Original string
  Push $R2

Loop:
  StrCpy $R2 "$R1" 1
  StrCmp "$R2" " " TrimLeft
  StrCmp "$R2" "$\r" TrimLeft
  StrCmp "$R2" "$\n" TrimLeft
  StrCmp "$R2" "$\t" TrimLeft
  Goto Loop2
TrimLeft:
  StrCpy $R1 "$R1" "" 1
  Goto Loop

Loop2:
  StrCpy $R2 "$R1" 1 -1
  StrCmp "$R2" " " TrimRight
  StrCmp "$R2" "$\r" TrimRight
  StrCmp "$R2" "$\n" TrimRight
  StrCmp "$R2" "$\t" TrimRight
  Goto Done
TrimRight:
  StrCpy $R1 "$R1" -1
  Goto Loop2

Done:
  Pop $R2
  Exch $R1
FunctionEnd

;--------------------------------
; Functions for Custom pages

; These are window handles of the controls in the Proxy Settings page
Var proxyTitleLabel
Var proxyServerLabel
Var proxyServerText
Var proxyPortLabel
var proxyPortText
var proxyUseProxyCheckbox

; Window handle of window a callback was invoked for
var hwnd

; Values the user entered in the Proxy Settings page
var useProxy
var proxyServer
var proxyPort
var tmp

;-------------------
; Collect proxy info
Function ProxySettingsPage
  !insertmacro MUI_HEADER_TEXT $(ProxyPage_TITLE) $(ProxyPage_SUBTITLE)
  nsDialogs::Create 1018
  Pop $Dialog
  ${If} $Dialog == error
    Abort
  ${EndIf}

  ${NSD_CreateLabel} 0 0 100% 12u "Configure Proxy to Access the Internet:"
    pop $proxyTitleLabel

  ${NSD_CreateCheckBox} 0 13u 80u 12u "Use Proxy Server"
    pop $proxyUseProxyCheckbox
    ${NSD_OnClick} $proxyUseProxyCheckbox ProxySettingsUseProxyClick
    ${NSD_SetState} $proxyUseProxyCheckbox $useProxy

  ${NSD_CreateLabel} 0 28u 80u 12u "Http Proxy Server:"
    pop $proxyServerLabel
  ${NSD_CreateText} 90u 28u 100u 12u $proxyServer
    pop $proxyServerText
    EnableWindow $proxyServerText 0 # start out disabled

  ${NSD_CreateLabel} 0 43u 80u 12u "Port:"
    pop $proxyPortLabel
  ${NSD_CreateNumber} 90u 43u 100u 12u $proxyPort
    pop $proxyPortText
    EnableWindow $proxyPortText 0 # start out disabled

  nsDialogs::Show
FunctionEnd

Function ProxySettingsLeave
  ${NSD_GetState} $proxyUseProxyCheckbox $useProxy
  ${If} $useProxy == 1
    ${NSD_GetText} $proxyServerText $tmp
    ${Trim} $proxyServer $tmp
    ${NSD_GetText} $proxyPortText $tmp
    ${Trim} $proxyPort $tmp
    
    ; Ensure that the proxy server is set
    StrCmp $proxyServer '' 0 +3
      MessageBox MB_OK|MB_ICONEXCLAMATION "Proxy server cannot be blank!"
      Abort
    push $0
    StrCpy $0 'http://$proxyServer'
    
    ; Append :port only if port is set
    StrCmp $proxyPort '' +2
      StrCpy $0 '$0:$proxyPort'

    ; This will permanently set the environment variable for future use
    !insertmacro AddEnvVarToReg 'http_proxy' $0
    !insertmacro AddEnvVarToReg 'https_proxy' $0

    ; We will also need these environment variables defined for later install tasks
    !insertmacro SetInstallerEnvVar 'http_proxy' $0
    !insertmacro SetInstallerEnvVar 'https_proxy' $0
    pop $0
  ${EndIf}
FunctionEnd

Function ProxySettingsUseProxyClick
  pop $hwnd
  ${NSD_GetState} $hwnd $0
  ${If} $0 == 1
    EnableWindow $proxyServerText 1
    EnableWindow $proxyPortText 1
  ${Else}
    EnableWindow $proxyServerText 0
    EnableWindow $proxyPortText 0
  ${EndIf}
FunctionEnd

; This function removes the environment variable we might have installed
Function un.ProxySettingsPage
  DeleteRegValue ${env_allusers} 'http_proxy'
  DeleteRegValue ${env_allusers} 'https_proxy'
  ClearErrors
FunctionEnd

; This function is called when the installer starts.  It is used to initialize some
; needed variables
Function .onInit
  StrCpy $systemdrive $WINDIR 2
  StrCpy $INSTDIR "$systemdrive\MITRE\${PRODUCT_NAME}"

  !insertmacro SetRubyDir
  StrCpy $mongodir "$systemdrive\mongodb-2.0.1"
  StrCpy $redisdir "$systemdrive\redis-2.4.0"
FunctionEnd

Function un.onInit
  StrCpy $systemdrive $WINDIR 2
  StrCpy $mongodir "$systemdrive\mongodb-2.0.1"
  StrCpy $redisdir "$systemdrive\redis-2.4.0"
FunctionEnd

; This function adds the passed directory to the path (only for installer and subprocesses)
Function AddToPath
  ; Store registers and pop params
  System::Store "S r0"

  ; Get the current path
  ReadEnvStr $R1 PATH

  ; Add the new directory to the end of the path
  StrCpy $R1 "$0;$R1"

  ; Set the new path in the environment
;  System::Call "kernel32::SetEnvironmentVariable(t 'PATH', t R1) i.R9"
  !insertmacro SetInstallerEnvVar 'PATH' $R1

  ; restore registers
  System::Store "l"
FunctionEnd
