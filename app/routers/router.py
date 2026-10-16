from fastapi import APIRouter, Response, status

from app.core.database import ping_db
from app.routers.auth_route import router as auth_router
from app.routers.user_route import router as user_router
from app.routers.department_route import router as department_router
from app.routers.report_route import router as report_router
from app.routers.audit_route import router as audit_router
from app.routers.notification_route import router as notification_router
from app.routers.Docter.docter_route import router as docter_router
from app.routers.appointment_route import router as appointment_router
from app.routers.recep_route import router as recep_router


router = APIRouter()


@router.get('/health', tags=['health'])
def health_check(response: Response):
    if ping_db():
        return {'status': 'ok', 'database': 'healthy'}
    else:
        response.status_code = status.HTTP_503_SERVICE_UNAVAILABLE
        return {'status': 'error', 'database': 'unhealthy'}


router.include_router(auth_router)
router.include_router(user_router)
router.include_router(department_router)
router.include_router(report_router)
router.include_router(audit_router)
router.include_router(notification_router)

router.include_router(docter_router)
router.include_router(appointment_router)
router.include_router(recep_router)
