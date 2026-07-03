from sqlalchemy import Boolean, Column, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import relationship
from app.core.database import Base

class Report(Base):
  __tablename__ = "reports"

  id = Column(Integer, primary_key=True, index=True)
  latitude = Column(Float, nullable=False)
  longitude = Column(Float, nullable=False)
  timestamp = Column(DateTime, nullable=False)
  anomaly_type = Column(String, nullable=False) # e.g. "pothole", "crack"
  confidence = Column(Float, nullable=False)
  image_url = Column(String, nullable=True) # URL or path of stored verification image
  is_verified = Column(Boolean, default=False)
  status = Column(String, default="pending") # pending, verified, resolved
  reporter_name = Column(String, nullable=True)
  address = Column(String, nullable=True)
  severity = Column(String, nullable=True)
  
  reporter_id = Column(Integer, ForeignKey("users.id"), nullable=True)
  
  # Relationship to User profile who submitted the report
  reporter = relationship("User", back_populates="reports")
