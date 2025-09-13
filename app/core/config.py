from pydantic_settings import BaseSettings
from typing import Optional
import os

class Settings(BaseSettings):
    APP_NAME: str = "AWS ECS API Template"
    APP_VERSION: str = "1.0.0"
    DEBUG: bool = False
    API_V1_STR: str = "/api/v1"
    
    # AWS Settings
    AWS_REGION: str = "us-east-1"
    AWS_ACCOUNT_ID: Optional[str] = None
    ECR_REPOSITORY_URI: Optional[str] = None
    ECS_CLUSTER_NAME: Optional[str] = None
    ECS_SERVICE_NAME: Optional[str] = None
    
    # Environment
    ENVIRONMENT: str = "dev"
    
    # Security
    API_KEY: Optional[str] = None
    ENABLE_API_KEY_AUTH: bool = True
    ENABLE_API_KEY_DOCS: bool = False  # New setting to control docs protection
    
    model_config = {
        "env_file": ".env",
        "case_sensitive": True,
        "extra": "ignore"
    }

settings = Settings()