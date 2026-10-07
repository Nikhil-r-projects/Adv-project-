@echo off
REM ============================================================================
REM Push ML-KEM NTT Project to GitHub
REM ============================================================================

set GIT=C:\Users\Admin\.gemini\antigravity\scratch\mingit\cmd\git.exe

if not "%1"=="" (
    echo Pushing using provided Personal Access Token...
    %GIT% push -u https://%1@github.com/Nikhil-r-projects/Adv-project-.git main
) else (
    echo Pushing to origin main...
    echo (If prompted, enter your GitHub Username and Personal Access Token)
    %GIT% push -u origin main
)
