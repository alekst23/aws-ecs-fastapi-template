from fastapi import FastAPI, Depends, Request, HTTPException
from fastapi.middleware.cors import CORSMiddleware
from fastapi.openapi.docs import get_swagger_ui_html, get_redoc_html
from fastapi.openapi.utils import get_openapi
from app.api.routes import router
from app.core.config import settings
from app.core.auth import require_api_key
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Conditionally disable docs if docs protection is enabled
docs_url = "/docs" if not settings.ENABLE_API_KEY_DOCS else None
redoc_url = "/redoc" if not settings.ENABLE_API_KEY_DOCS else None
openapi_url = f"{settings.API_V1_STR}/openapi.json" if not settings.ENABLE_API_KEY_DOCS else None

app = FastAPI(
    title=settings.APP_NAME,
    version=settings.APP_VERSION,
    description="AWS ECS API Template",
    docs_url=docs_url,
    redoc_url=redoc_url,
    openapi_url=openapi_url
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

app.include_router(router, prefix=settings.API_V1_STR)

@app.get("/health")
async def health_check():
    return {"status": "healthy", "service": settings.APP_NAME}

# Protected documentation endpoints (require API key when auth is enabled)
if settings.ENABLE_API_KEY_DOCS:
    @app.get("/docs", include_in_schema=False)
    async def get_docs(_: str = Depends(require_api_key)):
        return get_swagger_ui_html(openapi_url=f"{settings.API_V1_STR}/openapi.json", title="API docs")

    @app.get("/redoc", include_in_schema=False)
    async def get_redoc(_: str = Depends(require_api_key)):
        return get_redoc_html(openapi_url=f"{settings.API_V1_STR}/openapi.json", title="API docs")

    @app.get(f"{settings.API_V1_STR}/openapi.json", include_in_schema=False)
    async def openapi(_: str = Depends(require_api_key)):
        return get_openapi(title=settings.APP_NAME, version=settings.APP_VERSION, routes=app.routes)

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "app.main:app",
        host="0.0.0.0",
        port=8000,
        log_level="info",
        reload=settings.DEBUG
    )