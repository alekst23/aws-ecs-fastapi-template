"""CLI entry points for the application."""
import uvicorn


def start():
    """Start the application in production mode."""
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        log_level="info"
    )


def dev():
    """Start the application in development mode with auto-reload."""
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        log_level="info",
        reload=True
    )