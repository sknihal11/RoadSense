from fastapi import APIRouter
from app.api.v1.endpoints import auth, users, reports, hazards, verification

api_router = APIRouter()

api_router.include_router(auth.router, prefix="/auth", tags=["authentication"])
api_router.include_router(users.router, prefix="/users", tags=["users"])
api_router.include_router(reports.router, prefix="/reports", tags=["reports"])
api_router.include_router(hazards.router, prefix="/hazards", tags=["hazards"])
api_router.include_router(verification.router, prefix="/verification", tags=["verification"])
