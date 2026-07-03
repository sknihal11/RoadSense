from typing import List
from fastapi import APIRouter, Depends
from sqlalchemy.orm import Session
from ....crud.report import get_verified_reports
from ....schemas.report import HazardMapResponse
from ..deps import get_db

router = APIRouter()

@router.get("/map", response_model=List[HazardMapResponse])
def get_public_hazards(db: Session = Depends(get_db)):
  # Retrieve verified reports to plot on public map
  verified = get_verified_reports(db)
  
  return [
    HazardMapResponse(
      id=r.id,
      latitude=r.latitude,
      longitude=r.longitude,
      anomaly_type=r.anomaly_type,
      confidence=r.confidence,
      is_verified=r.is_verified
    )
    for r in verified
  ]
