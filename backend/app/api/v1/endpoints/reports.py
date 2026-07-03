from datetime import datetime
import shutil
import os
from typing import List
from fastapi import APIRouter, Depends, File, Form, UploadFile, status, HTTPException
from sqlalchemy.orm import Session
from app.crud.report import create_report, get_reports, delete_report
from app.models.user import User
from app.schemas.report import ReportCreate, ReportResponse
from app.api.v1.deps import get_db, get_current_user

router = APIRouter()

# Directory to save uploaded evidence files locally (mock file storage path)
UPLOAD_DIR = "uploads/evidence"
os.makedirs(UPLOAD_DIR, exist_ok=True)

@router.post("/upload", response_model=ReportResponse, status_code=status.HTTP_201_CREATED)
async def upload_report(
  latitude: float = Form(...),
  longitude: float = Form(...),
  timestamp: str = Form(...),
  anomaly_type: str = Form(...),
  confidence: float = Form(...),
  file: UploadFile = File(...),
  db: Session = Depends(get_db),
  current_user: User = Depends(get_current_user)
):
  # 1. Save uploaded file to disk
  file_path = os.path.join(UPLOAD_DIR, f"{datetime.now().timestamp()}_{file.filename}")
  with open(file_path, "wb") as buffer:
    shutil.copyfileobj(file.file, buffer)
  
  # 2. Parse date string
  try:
    parsed_time = datetime.fromisoformat(timestamp)
  except ValueError:
    parsed_time = datetime.now()

  # 3. Write metadata report to database
  report_in = ReportCreate(
    latitude=latitude,
    longitude=longitude,
    timestamp=parsed_time,
    anomaly_type=anomaly_type,
    confidence=confidence
  )

  db_report = create_report(
    db, 
    report_in=report_in, 
    image_url=file_path, 
    reporter_id=current_user.id
  )
  
  return db_report

@router.get("/", response_model=List[ReportResponse])
def read_reports(skip: int = 0, limit: int = 100, db: Session = Depends(get_db)):
  return get_reports(db, skip=skip, limit=limit)

@router.delete("/{report_id}", response_model=ReportResponse)
def delete_anomaly_report(report_id: int, db: Session = Depends(get_db)):
  db_report = delete_report(db, report_id=report_id)
  if not db_report:
    raise HTTPException(
      status_code=status.HTTP_404_NOT_FOUND,
      detail=f"Anomaly report with ID {report_id} not found."
    )
  return db_report
