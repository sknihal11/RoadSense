from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ....crud.report import update_report_verification, get_report_by_id
from ....schemas.report import ReportResponse, ReportUpdate
from ....models.user import User
from ..deps import get_db, get_current_user

router = APIRouter()

@router.put("/verify/{report_id}", response_model=ReportResponse)
def verify_anomaly_report(
  report_id: int,
  update_data: ReportUpdate,
  db: Session = Depends(get_db),
  current_user: User = Depends(get_current_user)
):
  # Retrieve and verify report exists
  db_report = get_report_by_id(db, report_id=report_id)
  if not db_report:
    raise HTTPException(
      status_code=status.HTTP_404_NOT_FOUND,
      detail=f"Anomaly report with ID {report_id} not found."
    )
  
  # Toggle validation status
  updated = update_report_verification(
    db, 
    report_id=report_id, 
    is_verified=update_data.is_verified if update_data.is_verified is not None else db_report.is_verified,
    status=update_data.status
  )
  return updated
