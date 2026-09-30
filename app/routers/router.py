from fastapi import APIRouter, Response, status
from app.routers.userAuth import router as auth_router
from app.core.database import ping_db

router = APIRouter()

@router.get("/health", tags=["health"])
def health_check(response: Response):
    if ping_db():
        return {"status": "ok", "database": "healthy"}
    else:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {"status": "error", "database": "unhealthy"}

# Include all your modular routers here
router.include_router(auth_router)
