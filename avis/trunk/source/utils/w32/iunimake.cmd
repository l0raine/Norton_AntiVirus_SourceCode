: Unified file to build any project, generated by MSVC++ environment.
: This file will be called by M.CMD of every subproject.
: See IM_TEMPL.CMD for more info. 
: (IM_TEMPL.CMD used as a base to create M.CMD for every subproject).
:
: Syntax:
:     iunimake depend  [..]
:     iunimake compile [..]
:     iunimake help    [..]
:     iunimake library [..]
:     iunimake exedll  [..]
:     iunimake all     [..]
:     iunimake clean   [..]
:
:     iunimake [-a] debug/release
:
@if "%1" == "" %UTILD%\iunimake all
@if "%THIS_PROJECT_NAME%" == ""  goto SYNTAX

:-----------------------------------------------------
: Note:  following environment variables must be set (by subproject's M.CMD):
:        THIS_PROJECT_NAME  'testdll'
:        THIS_LIBRARY_NAME  'my_lib'  - if DLL project. Library name my be different from DLL name.
:                           ""        - if non-DLL project.

@SET THIS_PROJECT_MAKEFILE=%OBJD%\%THIS_PROJECT_NAME%\%THIS_PROJECT_NAME%.mk
@if not exist "%OBJD%\%THIS_PROJECT_NAME%" mkdir "%OBJD%\%THIS_PROJECT_NAME%"

@SET SAVED_LIB=%LIB%
@SET LIB=%LIB%;%VCLIB%
@SET SAVED_INCPATHS=%INCPATHS%
@if  NOT "%LANGTYPE%" == "DBCS" goto next
@SET DBCS_FLAG=/DDBCS
@SET INCPATHS=%INCPATHS% %DBCS_FLAG%

:next
:
@%UTILD%\textattr RGI
@SET DEBUG_OR_RELEASE=debug
@if "%BLDDEBUG%" == ""  SET   DEBUG_OR_RELEASE=release
@if "%1" == "debug"     SET   DEBUG_OR_RELEASE=debug
@if "%2" == "debug"     SET   DEBUG_OR_RELEASE=debug
@if "%1" == "release"   SET   DEBUG_OR_RELEASE=release
@if "%2" == "release"   SET   DEBUG_OR_RELEASE=release
@echo #################  Building '%THIS_PROJECT_NAME%' [%1] (%DEBUG_OR_RELEASE%) #################
@%UTILD%\textattr NORMAL
@SET DEBUG_OR_RELEASE=
:
@if "%1" == "-a"        del   %THIS_PROJECT_MAKEFILE%
@if "%1" == "clean"     del   %THIS_PROJECT_MAKEFILE%
%UTILD%\tweakmak %THIS_PROJECT_NAME%.mak %THIS_PROJECT_MAKEFILE%

@if "%1" == "-a"        goto  MY_BUILD
@if "%1" == "debug"     goto  MY_BUILD
@if "%2" == "debug"     goto  MY_BUILD
@if "%1" == "release"   goto  MY_BUILD
@if "%2" == "release"   goto  MY_BUILD

:IBM_BUILD
@if "%THIS_LIBRARY_NAME%" == "" goto START_IBM_BUILD
@if "%1" == "clean" goto   FINISH_CLEAN
@goto START_IBM_BUILD
:FINISH_CLEAN
del %LIBD%\%THIS_LIBRARY_NAME%.LIB
del %LIBD%\%THIS_LIBRARY_NAME%.EXP
:START_IBM_BUILD
nmake /I /f %UTILD%\ibm_stub.mak %1 %2 %3 %4 %5 %6 %7 %8 %9
@goto BUILD_DONE


:MY_BUILD
: This spot will be reached only for my own builds (m [-a] debug/release).
: BLDDEBUG is already set in root m.cmd file, I do it in here just in case
: I want to build some subproject separately.
:
@if "%1" == "debug"     SET BLDDEBUG=YES
@if "%2" == "debug"     SET BLDDEBUG=YES
@if "%1" == "release"   SET BLDDEBUG=
@if "%2" == "release"   SET BLDDEBUG=
@call ..\SETENV.CMD
@if "%1" == "-a" goto   MY_CLEAN
@goto MY_ONLY

:MY_CLEAN
nmake /f %UTILD%\ibm_stub.mak clean
@if "%THIS_LIBRARY_NAME%" == "" goto MY_MAKE_ALL
del %LIBD%\%THIS_LIBRARY_NAME%.LIB
del %LIBD%\%THIS_LIBRARY_NAME%.EXP
:MY_MAKE_ALL
nmake /A /f %UTILD%\ibm_stub.mak
nmake    /f %UTILD%\ibm_stub.mak library
@goto BUILD_DONE

:MY_ONLY
nmake /f %UTILD%\ibm_stub.mak
nmake /f %UTILD%\ibm_stub.mak library
@goto BUILD_DONE

:
:BUILD_DONE
@SET INCPATHS=%SAVED_INCPATHS%
@SET SAVED_INCPATHS=
@SET THIS_PROJECT_MAKEFILE=
@SET LIB=%SAVED_LIB%
@SET SAVED_LIB=
@goto  EXIT
:-----------------------------------------------------

:
:SYNTAX
@echo Syntax:
@echo    %0 depend
@echo    %0 compile
@echo    %0 help
@echo    %0 library
@echo    %0 exedll
@echo    %0 all
@echo    %0 clean
@echo    %0 [-a] debug/release
@echo Note: following environment variables must be set:
@echo       THIS_PROJECT_NAME  'testdll'
@echo       THIS_LIBRARY_NAME  'my_lib'  - if DLL project. 
@echo       (Library name my be different from DLL name).
@goto EXIT

:EXIT
@SET   THIS_PROJECT_NAME=
@SET   THIS_PROJECT_MAKEFILE=
@SET   THIS_LIBRARY_NAME=
