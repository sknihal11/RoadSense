from typing import Generator
from fastapi import Depends, HTTPException, status
from fastapi.security import OAuth2PasswordBearer
from jose import jwt, JWTError
from sqlalchemy.orm import Session
from app.core.config import settings
from app.core.database import SessionLocal
from app.models.user import User
from app.crud.user import get_user_by_id
from app.schemas.user import TokenPayload

oauth2_scheme = OAuth2PasswordBearer(
  tokenUrl=f"{settings.API_V1_STR}/auth/login"
)

def get_db() -> Generator[Session, None, None]:
  db = SessionLocal()
  try:
    yield db
  finally:
    db.close()

def get_current_user(
  db: Session = Depends(get_db), 
  token: str = Depends(oauth2_scheme)
) -> User:
  credentials_exception = HTTPException(
    status_code=status.HTTP_401_UNAUTHORIZED,
    detail="Could not validate credentials",
    headers={"WWW-Authenticate": "Bearer"},
  )
  try:
    payload = jwt.decode(
      token, settings.SECRET_KEY, algorithms=[settings.ALGORITHM]
    )
    user_id: int = int(payload.get("sub"))
    if user_id is None:
      raise credentials_exception
    token_payload = TokenPayload(sub=user_id)
  except (JWTError, ValueError):
    raise credentials_exception
  
  user = get_user_by_id(db, user_id=token_payload.sub)
  if not user:
    raise HTTPException(
      status_code=status.HTTP_404_NOT_FOUND, 
      detail="User not found"
    )
  if not user.is_active:
    raise HTTPException(
      status_code=status.HTTP_400_BAD_REQUEST, 
      detail="Inactive user"
    )
  return user
