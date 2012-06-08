@echo off
REM ------------------------------------------------------------------------
REM A script to verify that all of the required components installed
REM and are running properly.  The things that are needed are:
REM 	mongod service
REM	redis-server
REM	resque workers
REM	database is consistent (measures, patients, patient_cache)
REM ------------------------------------------------------------------------
set fail=0
echo.
echo ...checking to see if mongo is running as a service
tasklist /nh /fi "imagename eq mongod.exe" | findstr mongod >nul
if ERRORLEVEL 1 (
  echo *** MongoDB does not appear to be running on this machine.
  set fail=1
)

echo ...verifying that the redis-server is running
tasklist /nh /fi "imagename eq redis-server.exe" | findstr redis >nul
if ERRORLEVEL 1 (
  echo *** The redis-server does not appear to be running on this machine.
  set fail=1
)
echo ...looking to see if the webserver is running on port 3000
netstat -on | findstr ":3000" >nul
if ERRORLEVEL 1 (
  echo *** The Cypress web server is not running on port 3000.
  set fail=1
)

echo ...verifying that the cypress_production database has been initialized properly
mongo cypress_production --eval db.measures.count() | findstr 78 >nul
if ERRORLEVEL 1 (
  echo *** Not all of the quality measures made it into the database.
  set fail=1
)
mongo cypress_production --eval db.records.count() | findstr 225 >nul
if ERRORLEVEL 1 (
  echo *** Not all of the test patients made it into the database.
  set fail=1
)
mongo cypress_production --eval db.patient_cache.count() | findstr /R [0-9]+ >nul
if ERRORLEVEL 1 (
  echo *** The measures have not been calculated for the test patients.
  set fail=1
)

echo.
if %fail%==0 (
  echo Looks great!
) else (
  echo Please fix these problems or call the Cypress team for help.
)
echo.