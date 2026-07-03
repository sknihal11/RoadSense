from datetime import datetime
from typing import Optional
from pydantic import BaseModel

# Shared properties
class ReportBase(BaseModel):
  latitude: float
  longitude: float
  timestamp: datetime
  anomaly_type: str
  confidence: float
  status: Optional[str] = "pending"
  is_verified: Optional[bool] = False
  reporter_name: Optional[str] = None
  address: Optional[str] = None
  severity: Optional[str] = None

# Properties to receive on creation
class ReportCreate(ReportBase):
  pass

# Properties to receive on updates (e.g. toggling verification)
class ReportUpdate(BaseModel):
  is_verified: Optional[bool] = None
  status: Optional[str] = None

# Properties to return to client
class ReportResponse(ReportBase):
  id: int
  image_url: Optional[str] = None
  is_verified: bool
  reporter_id: Optional[int] = None

  class Config:
    from_attributes = True

# Custom response structure for public safety map
class HazardMapResponse(BaseModel):
  id: int
  latitude: float
  longitude: float
  anomaly_type: str
  confidence: float
  is_verified: bool
