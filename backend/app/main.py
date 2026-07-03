from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from app.core.config import settings
from datetime import datetime
from sqlalchemy.orm import Session
from app.core.database import Base, engine, SessionLocal
from app.models.report import Report
from app.api.v1.api import api_router

# As a helper for initial developer testing without needing manual migrations,
# we create all database schema tables on startup automatically if they don't exist.
Base.metadata.create_all(bind=engine)

def seed_database():
  db: Session = SessionLocal()
  try:
    if db.query(Report).count() == 0:
      initial_reports = [
        Report(
          latitude=17.7290,
          longitude=83.3087,
          anomaly_type="pothole",
          confidence=0.84,
          timestamp=datetime.fromisoformat("2026-07-03T14:00:00"),
          is_verified=False,
          status="pending",
          reporter_name="Nihal (Driver Profile #421)",
          address="RTC Complex Road, Visakhapatnam",
          severity="High"
        ),
        Report(
          latitude=17.8176,
          longitude=83.3488,
          anomaly_type="crack",
          confidence=0.72,
          timestamp=datetime.fromisoformat("2026-07-03T14:05:00"),
          is_verified=False,
          status="pending",
          reporter_name="Aman (Driver Profile #108)",
          address="Madhurawada Highway, near IT Hill",
          severity="Medium"
        ),
        Report(
          latitude=17.9157,
          longitude=83.3980,
          anomaly_type="pothole",
          confidence=0.91,
          timestamp=datetime.fromisoformat("2026-07-03T14:10:00"),
          is_verified=True,
          status="verified",
          reporter_name="Rohit (Driver Profile #332)",
          address="Anandapuram Junction Bypass",
          severity="Critical"
        ),
        Report(
          latitude=17.9310,
          longitude=83.4289,
          anomaly_type="crack",
          confidence=0.65,
          timestamp=datetime.fromisoformat("2026-07-03T14:12:00"),
          is_verified=True,
          status="resolved",
          reporter_name="Sita (System Audit)",
          address="Tagarapuvalasa Bridge Road",
          severity="Low"
        )
      ]
      db.bulk_save_objects(initial_reports)
      db.commit()
      print("Database successfully seeded with initial reports.")
  except Exception as e:
    print(f"Error seeding database: {e}")
  finally:
    db.close()

seed_database()

app = FastAPI(
  title=settings.PROJECT_NAME,
  description="Backend REST API for RoadSense AI safe navigation and road quality reporting.",
  version="1.0.0",
  openapi_url=f"{settings.API_V1_STR}/openapi.json",
  docs_url="/docs", # Swagger UI endpoint
  redoc_url="/redoc"
)

# Set CORS origins
app.add_middleware(
  CORSMiddleware,
  allow_origins=["*"], # Allow all for mobile client API testing
  allow_credentials=False,
  allow_methods=["*"],
  allow_headers=["*"],
)

# Mount central API router
app.include_router(api_router, prefix=settings.API_V1_STR)

@app.get("/")
def root_endpoint():
  return {
    "project": settings.PROJECT_NAME,
    "status": "online",
    "docs_url": "/docs"
  }
