from sqlalchemy import create_engine
from sqlalchemy.orm import declarative_base, sessionmaker
from app.core.config import settings

db_url = settings.DATABASE_URL
connect_args = {}

if db_url.startswith("sqlite"):
    connect_args = {"check_same_thread": False}
elif "pg8000" in db_url:
    import ssl
    # Setup SSL context required by Neon/Supabase for pg8000 connection
    ssl_context = ssl.create_default_context()
    ssl_context.check_hostname = False
    ssl_context.verify_mode = ssl.CERT_NONE
    connect_args = {"ssl_context": ssl_context}
    
    # Remove query params (?sslmode=...) which cause pg8000 driver signature errors
    if "?" in db_url:
        db_url = db_url.split("?")[0]

engine = create_engine(
    db_url,
    pool_pre_ping=not db_url.startswith("sqlite"),
    connect_args=connect_args
)

SessionLocal = sessionmaker(autocommit=False, autoflush=False, bind=engine)

Base = declarative_base()
