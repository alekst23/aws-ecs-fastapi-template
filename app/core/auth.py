from fastapi import HTTPException, Security, status
from fastapi.security import HTTPBearer, HTTPAuthorizationCredentials
from typing import Optional
from .config import settings

security = HTTPBearer(auto_error=False)

class APIKeyError(HTTPException):
    def __init__(self):
        super().__init__(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid or missing API key",
            headers={"WWW-Authenticate": "Bearer"},
        )

def get_api_key(credentials: Optional[HTTPAuthorizationCredentials] = Security(security)) -> str:
    """
    Validate API key from Authorization header.
    Expected format: Authorization: Bearer <api-key>
    """
    # Skip authentication if disabled or no API key configured
    if not settings.ENABLE_API_KEY_AUTH or not settings.API_KEY:
        return "bypass"
    
    if not credentials:
        raise APIKeyError()
    
    if credentials.credentials != settings.API_KEY:
        raise APIKeyError()
    
    return credentials.credentials

def require_api_key(api_key: str = Security(get_api_key)) -> str:
    """
    Dependency to require API key authentication.
    Use this in your route dependencies.
    """
    return api_key