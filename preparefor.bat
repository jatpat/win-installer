@echo off
SETLOCAL
SETLOCAL ENABLEDELAYEDEXPANSION
goto :PROLOGUE
REM ==========================================================================
REM preparefor.bat
REM
REM This batch file will prepare the NSIS build directory to build a specific
REM version of the windows installer for Cypress.
REM
REM Some of the dependencies are available in both 32- and 64-bit
REM variants.  Also, some of the dependencies are distributed as .zip files
REM rather than executable installers.  For the .zip based dependencies, we
REM unpack them in this folder and then incorporate them into the 
REM installer.
REM
REM After all of the arguments and switches are processed and the development
REM environment is verified, there are four main steps to creating an 
REM installer:
REM   1. clean - remove any residue from earlier builds so we know we are 
REM              using all and only the latest and greatest
REM   2. fetch - pull source code from github for the projects needed
REM   3. build - this is where all the prep work happens -- packaging up the
REM              required gem files, compiling gems that have to be native,
REM              massaging configuration files
REM   4. generate - invoke the NSIS software to generate the installer from
REM              the software and config information prepared in the build 
REM              step
REM 
REM Original Author: Tim Taylor <ttaylor@mitre.org>
REM Secondary:	     Tim Brown  <timbrown@mitre.org>
REM
REM TODO: 
REM   - figure out a general way to calculate the space required by each
REM     component and pass that into the nsis script for the AddSize command
REM   - be careful about uninstalling software or data we didn't install
REM
REM ==========================================================================

:USAGE
echo.
echo Usage: %0 ^<architecture^> ^<product^> ^<version^> [switches]
echo.
echo   %1 the target architecture: 32^|64
echo   %2 the product:		  Cypress
echo   %3 the version tag:	  version of the product (e.g. v1.1, develop, master)
echo.
echo Additionally you can pass the following switches on the command line
echo   --help          to show usage information
echo   --verbose       to turn echo on and see eberything that is happening
echo   --repo ^<repo^>   to specify an alternate git repository to pull from
echo                     for example https://github.com/tlabczbrown
echo.
echo   --noclean       to not delete any lingering files from a previous installation
echo   --nofetch       to not pull the tar files or source
echo   --nobuild       to avoid unpacking and compiling requisite software
echo   --nogenerate    to avoid generating the installer with NSIS
echo.
goto :EOF

:PROLOGUE
REM ====================
REM mandatory params
REM ====================
set arch=%1
set product=%2
set version=%3
set installer_dir=%CD%
set measures_ver=1.4.2

REM ====================
REM Tag or branch names of projects to bundle with the installer.  The machine
REM building the installer will need git, but clients won't any more.
REM
REM There currently are dependencies on redis and mongodb
REM
REM When it comes time to build an installer for a new version of Cypress, just 
REM update these if necessary and rebuild.
REM ====================
set measures_tag=v1.4.2
set redisdir=redis-2.4.0
set mongodbdir=mongodb-2.0.1

REM The directory to build native gems in
set gem_build_dir=%TEMP%\native_gems
REM ====================
REM Information about native gems we need to build, and include in the
REM installer.
REM ====================
REM nagive_gem_list is a semi-colon (;) separated list of the gems we need.
REM For each gem, define a variable named gem_<gem_name>_info that contains
REM the repo tag for the version we want and the git repo url separated by a
REM ';'.  For example
REM gem_bson_ext_info=1.5.1;https://github.com/mongodb/mongo-ruby-driver.git
set native_gem_list=bson_ext;json
set gem_bson_ext_info=1.5.1;https://github.com/mongodb/mongo-ruby-driver.git
set gem_json_info=v1.4.6;https://github.com/flori/json.git

set cypress_git_url=https://github.com/projectcypress

REM process all of the switches that were on the command line
set self_contained=1
set showhelp=0
set clean=1
set fetch=1
set build=1
set generate=1
set verbose=0

if "%1"=="" (goto :USAGE)
for %%A in (%*) do (

  if "%%A"=="--help"           ( set showhelp=1 )
  if "%%A"=="--verbose"        ( set verbose=1 )
  if "%%A"=="--repo"           ( set repo=1 )
  set curarg=%%A
  if "!curarg:~0,4!" == "http" ( 
    for /l %%b in (1,1,31) do if "!curarg:~-1!"==" " set curarg=!curarg:~0,-1!
    set cypress_git_url=!curarg!
  )

  if "%%A"=="--noclean"        (set clean=0)
  if "%%A"=="--nofetch"        (set fetch=0)
  if "%%A"=="--nobuild"        (set build=0)
  if "%%A"=="--nogenerate"     (set generate=0)
)

REM Check mandatory arguments provided to the script
if not "%arch%"=="32" (
  if not "%arch%"=="64" (
    echo.
    echo *** %arch% is not a known archictecture, please use 32 or 64
    echo.
    goto :USAGE
  )
)
if not "%product%"=="Cypress" (
  echo.
  echo *** %product% is not a known product, please use Cypress
  echo.
  goto :USAGE
)
set from_branch=0
if "%version%" == "develop" (
    set from_branch=1
) else if "%version%" == "master" (
    set from_branch=1
) else (
  set xversion=%version:v=X%
  if "%xversion%"=="%version%" (
    echo.
    echo *** the version should begin with v, for example v1.2.1
    echo.
    goto :USAGE
  )
)
if %verbose% == 1 (@echo on)
if %showhelp%==1 (goto :USAGE)

echo --------------------------------------------------------------------------------
echo Preparing to build a %arch%-bit %product% installer...
  if %self_contained%==1 ( 
    echo *    - as a self-contained package 
  ) else (
    echo *    - as a minimal-size package 
  )
  echo *    - for version: %version%
  echo *    - from       : %cypress_git_url%
  echo.
  echo *      params are clean=%clean%; fetch=%fetch%; build=%build%; generate=%generate%
  echo.
echo --------------------------------------------------------------------------------

REM We need unzip, tar, curl, grep, bundle and makensis on the path.  Check for 'em
set unzipcmd=
set tarcmd=
set curlcmd=
set grepcmd=
set makensiscmd=
set setcmd=

for %%e in (%PATHEXT%) do (
  for %%x in (unzip%%e) do (
    if not defined unzipcmd (set unzipcmd=%%~$PATH:x)
  )
)
if "%unzipcmd%"=="" (
  echo unzip command was not found on the path.  Please correct.
  echo If you've installed git, try adding [git_home]\bin to path.
  exit /b 1
)
for %%e in (%PATHEXT%) do (
  for %%x in (tar%%e) do (
    if not defined tarcmd (set tarcmd=%%~$PATH:x)
  )
)
if "%tarcmd%"=="" (
  echo tar command was not found on the path.  Please correct.
  echo If you've installed git, try adding [git_home]\bin to path.
  exit /b 1
)
REM for %%e in (%PATHEXT%) do (
REM   for %%x in (sed%%e) do (
REM     if not defined sedcmd (set setcmd=%%~$PATH:x)
REM  )
REM )
REM if "%sedcmd%"=="" (
REM   echo sed command was not found on the path.  Please correct.
REM   echo If you've installed RailsInstaller, try adding [RI]\Devkit\bin to path.
REM   exit /b 1
REM )
for %%e in (%PATHEXT%) do (
  for %%x in (curl%%e) do (
    if not defined curlcmd (set curlcmd=%%~$PATH:x)
  )
)
if "%curlcmd%"=="" (
  echo curl command was not found on the path.  Please correct.
  echo If you've installed git, try adding [git_home]\bin to path.
  exit /b 1
)

for %%e in (%PATHEXT%) do (
  for %%x in (grep%%e) do (
    if not defined grepcmd (set grepcmd=%%~$PATH:x)
  )
)
if "%grepcmd%"=="" (
  echo grep command was not found on the path.  Please correct.
  echo If you've installed git, try adding [git_home]\bin to path.
  exit /b 1
)
for %%e in (%PATHEXT%) do (
  for %%x in (makensis%%e) do (
    if not defined makensiscmd (set makensiscmd=%%~$PATH:x)
  )
)
if "%makensiscmd%"=="" (
  echo makensis command was not found on the path.  Please correct.
  exit /b 1
)

REM Check and make sure the rake-compiler gem is installed.
gem list --local | grep -q rake-compiler
if ERRORLEVEL 1 (
  echo The rake-compiler gem is not installed.  Please run the command:
  echo   gem install rake-compiler
  exit /b 1
)

REM We need a sane development environment to build native gems.  Look for
REM a compiler on the path, and define environment variables the RailsInstaller
REM devkit sets up.
set gcccmd=
for %%e in (%PATHEXT%) do (
  for %%x in (gcc%%e) do (
    if not defined gcccmd (set gcccmd=%%~$PATH:x)
  )
)
if "%gcccmd%"=="" (
  echo Development tools were not found on the path.
  set /P RI_DEVKIT="Enter path to ruby devkit home: "
)
if not exist %RI_DEVKIT%\mingw\bin\gcc.exe (
  echo %RI_DEVKIT% doesn't appear to contain the mingw tools.
  exit /b 1
)
path=%RI_DEVKIT%\bin;%RI_DEVKIT%\mingw\bin;%path%
set CC=gcc
set CPP=cpp
set CXX=g++

REM ==========================================================================
REM CLEAN
REM ==========================================================================
if %clean% == 1 (
  echo ------
  echo Step 1 Clean out whatever was leftover from previous builds
  echo ------

  echo ...cleaning up from previous builds
  if exist binary_gems  (rd /s /q binary_gems)
  if exist Cypress      (
    attrib -s -h Cypress\*.* /S
    REM for some strange reason, even though rd ought to be able to delete
    REM all files in subdirectories, escpecially after removing system and 
    REM hidden attributes, it takes 3 invocations to actually succeed
    rd /s /q Cypress
    rd /s /q Cypress
    rd /s /q Cypress
  )
  if exist %mongodbdir% (rd /s /q %mongodbdir%)
  if exist %redisdir%   (rd /s /q %redisdir%)
  if exist Cypress*.tgz (del Cypress*.tgz)
)

REM ==========================================================================
REM FETCH
REM ==========================================================================
if %fetch% == 1 (
  echo ------
  echo Step 2 Fetch tarballs/source of the various repos we need.
  echo ------
  if %from_branch% == 1 (
    echo ...fetching branch %version% from %cypress_git_url%
    echo git.exe clone -b %version% %cypress_git_url%/cypress.git Cypress
    git.exe clone -b %version% %cypress_git_url%/cypress.git Cypress
  ) else (
    echo ...fetching tarball from github for %product%-%version% 
    if not exist %product%-%version%.tgz (
      "%curlcmd%" -s -k -L %cypress_git_url%/tarball/%version% > %product%-%version%.tgz
    )
    REM Unpack the product and prepare it accordingly.
    mkdir %product%
    "%tarcmd%" --strip-components=1 -C %product% -xf .\%product%-%version%.tgz > nul 2> nul
    if ERRORLEVEL 1 (
      echo.
      echo *** There is a problem with the tar file %product%-%version%.tgz
      echo Please verify %version% is a valid tag for %product%
      echo.
      exit /b 1
    )
  )
)

REM ==========================================================================
REM BUILD
REM ==========================================================================
if %build% == 1 (
  echo ------
  echo Step 3 Build native gems, package requisite software
  echo ------

  echo ...building all the native gems required
  REM TODO needed to add the following in my environment in order to fetch without ssl cert errors
  REM git config --global http.sslVerify false

  mkdir binary_gems
  if not exist %gem_build_dir% (mkdir %gem_build_dir%)
  for %%g in (%native_gem_list%) do (
    for /f "tokens=1,2 delims=;" %%t in ('cmd /v:on /c @echo !gem_%%g_info!') do (
      pushd %gem_build_dir%
      echo Gem: %%g tag %%t at %%u
      if not exist %%g (
        echo ...cloning for the first time
        git.exe clone %%u %%g
        cd %%g
      ) else (
        echo ...updating existing repo for %%g
        cd %%g
        git.exe fetch origin
        git.exe checkout -f master
      )
      git.exe checkout -q -B mitre tags/%%t

      REM If we have a patch file required to build native gem, apply it
      if exist %installer_dir%\%%g.patch (
        echo ...applying MITRE custom patch for %%g
        patch -p1 -t -F 0 -b -z .mitre < %installer_dir%\%%g.patch
      )

      REM prepare for building binary gem by removing package dir
      if exist pkg (
        if exist pkg\*.gem ( del pkg\*.gem )
      )

      REM Build the platform specific binary gem
      call rake.bat native gem > nul 2> nul

      popd

      REM Copy the compiled gem to the install directory
      move %gem_build_dir%\%%g\pkg\%%g-*-x86-mingw32.gem binary_gems\
    )
  )

  if %self_contained% == 1 (
    pushd %product%
    echo ...packaging up all of the requisite gems into %product%/vendor/cache
    rm Gemfile.lock
    call bundle.bat install
    call bundle.bat install --deployment
    call bundle.bat package
    rm vendor\cache\bson_ext-1.5.1.gem
    rm vendor\cache\json-1.4.6.gem
    copy ..\binary_gems\bson_ext-1.5.1-x86-mingw32.gem vendor\cache\
    copy ..\binary_gems\json-1.4.6-x86-mingw32.gem vendor\cache\
    popd
  )

  REM Unpack redis and prepare it accordingly.
  echo ...unpacking and preparing redis into %redisdir%...
  if exist %redisdir% ( 
    echo ...removing existing %redisdir% directory 
    rd /s /q %redisdir%
  )
  rem mkdir %redisdir%
  "%unzipcmd%" .\redis-2.4.0-win32-win64.zip -d %redisdir% > nul
  echo ...configuring newly exploded %redisdir%
  REM Copy our slightly modified redis.conf file into place
  copy /Y redis.conf %redisdir%\32bit > nul
  copy /Y redis.conf %redisdir%\64bit > nul
  REM Need to package an empty log file for redis
  echo Empty log for install > %redisdir%\redis_log.txt
  REM Create database directory
  mkdir %redisdir%\db
  
  if exist %mongodbdir% ( 
    echo ...removing existing %mongodbdir% directory 
    rd /s /q %mongodbdir%
  )
  if "%arch%"=="32" (
    echo ...setting up 32bit mongodb
  
    REM Delete the redis 64bit tree
    rd /s /q %redisdir%\64bit
  
    REM Unzip 32bit mongodb
    "%unzipcmd%" .\mongodb-win32-i386-2.0.1.zip > nul
    ren mongodb-win32-i386-2.0.1 %mongodbdir%
  ) else (
    echo ...setting up 64bit mongodb
  
    REM Delete the redis 32bit tree
    rd /s /q %redisdir%\32bit
   
    REM Unzip 64bit mongodb
    "%unzipcmd%" .\mongodb-win32-x86_64-2.0.1.zip > nul
    ren mongodb-win32-x86_64-2.0.1 %mongodbdir%
  )
)

REM ==========================================================================
REM GENERATE
REM ==========================================================================
if %generate% == 1 (
  echo ------
  echo Step 4 Generate the windows installer using NSIS
  echo ------

  echo ...determining how much space will be needed for %product%
  set product_size=0
  for /f "tokens=1,2 delims=	" %%a in ('du --summarize Cypress ^| findstr Cypress') do if "%%b"=="Cypress" set product_size=%%a
  echo !product_size! bytes are required for Cypress
 
  REM Run makensis to build product installer
  echo ...constructing the commandline to invoke NSIS
  "%makensiscmd%" /DBUILDARCH=%arch% /DVERSION=%version% /DPRODUCT_NAME=%product% /DPRODUCT_SIZE=!product_size! /DMEASURES_VERSION=%measures_ver% main.nsi
  echo.
  echo --------------------------------------------------------------------------------
  if %arch%==32 (
    echo Installer is available for testing: %product%-%version%-i386.exe
  ) else (
    echo Installer is available for testing: %product%-%version%-x86_64.exe
  )
  echo --------------------------------------------------------------------------------
  echo.
)
