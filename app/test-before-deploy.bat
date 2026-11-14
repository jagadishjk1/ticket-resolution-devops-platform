@echo off
echo ============================================
echo 🧪 Testing Project Before Railway Deployment
echo ============================================
echo.

echo 📋 Step 1: Testing Backend...
echo ============================================
cd backend

echo Checking Python environment...
python --version
if errorlevel 1 (
    echo ❌ Python not found! Install Python 3.11+
    pause
    exit /b 1
)

echo.
echo Checking backend dependencies...
pip list | findstr "fastapi" >nul
if errorlevel 1 (
    echo ⚠️  FastAPI not installed. Installing dependencies...
    pip install -r requirements.txt
)

echo.
echo Starting backend server...
echo (Press Ctrl+C to stop after testing)
start "Backend Server" cmd /k "python app.py"

timeout /t 5 /nobreak >nul

echo.
echo Testing backend health endpoint...
curl http://localhost:8000/health
if errorlevel 1 (
    echo ❌ Backend health check failed
) else (
    echo ✅ Backend is running!
)

echo.
echo 📋 Step 2: Testing Frontend...
echo ============================================
cd ..\frontend

echo.
echo Checking Node.js...
node --version
if errorlevel 1 (
    echo ❌ Node.js not found! Install Node.js 18+
    pause
    exit /b 1
)

echo.
echo Checking frontend dependencies...
if not exist node_modules (
    echo ⚠️  Dependencies not installed. Installing...
    npm install
)

echo.
echo Starting frontend...
echo (Will open in browser automatically)
start "Frontend Server" cmd /k "npm run dev"

echo.
echo ============================================
echo ✅ Both servers should now be running!
echo ============================================
echo.
echo Backend:  http://localhost:8000
echo Frontend: http://localhost:5173
echo.
echo 📝 Test the following:
echo   1. Visit frontend URL in browser
echo   2. Try uploading a ticket
echo   3. Check if fallback response appears
echo   4. Verify no console errors
echo.
echo Press Ctrl+C in each terminal window to stop servers
echo ============================================
echo.
pause
