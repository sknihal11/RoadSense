from typing import List, Optional
from sqlalchemy.orm import Session
from ..models.report import Report
from ..schemas.report import ReportCreate

def get_report_by_id(db: Session, report_id: int) -> Optional[Report]:
  return db.query(Report).filter(Report.id == report_id).first()

def get_reports(db: Session, skip: int = 0, limit: int = 100) -> List[Report]:
  return db.query(Report).offset(skip).limit(limit).all()

def get_verified_reports(db: Session) -> List[Report]:
  return db.query(Report).filter(Report.is_verified == True).all()

def create_report(
  db: Session, 
  report_in: ReportCreate, 
  image_url: Optional[str] = None,
  reporter_id: Optional[int] = None
) -> Report:
  db_report = Report(
    latitude=report_in.latitude,
    longitude=report_in.longitude,
    timestamp=report_in.timestamp,
    anomaly_type=report_in.anomaly_type,
    confidence=report_in.confidence,
    image_url=image_url,
    is_verified=report_in.is_verified or False,
    status=report_in.status or "pending",
    reporter_name=report_in.reporter_name,
    address=report_in.address,
    severity=report_in.severity,
    reporter_id=reporter_id
  )
  db.add(db_report)
  db.commit()
  db.refresh(db_report)
  return db_report

def update_report_verification(db: Session, report_id: int, is_verified: bool, status: Optional[str] = None) -> Optional[Report]:
  db_report = get_report_by_id(db, report_id)
  if not db_report:
    return None
  db_report.is_verified = is_verified
  if status:
    db_report.status = status
  else:
    db_report.status = "verified" if is_verified else "pending"
  db.add(db_report)
  db.commit()
  db.refresh(db_report)
  return db_report

def delete_report(db: Session, report_id: int) -> Optional[Report]:
  db_report = get_report_by_id(db, report_id)
  if not db_report:
    return None
  db.delete(db_report)
  db.commit()
  return db_report
