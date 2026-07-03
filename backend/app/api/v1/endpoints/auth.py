from datetime import timedelta
from fastapi import APIRouter, Depends, HTTPException, status
from fastapi.security import OAuth2PasswordRequestForm
from sqlalchemy.orm import Session
from ....core.config import settings
from ....core.security import create_access_token
from ....crud.user import authenticate_user
from ..deps import get_db
from ....schemas.user import Token

router = APIRouter()

@router.post("/login", response_model=Token)
def login(
  db: Session = Depends(get_db), 
  form_data: OAuth2PasswordRequestForm = Depends()
):
  user = authenticate_user(db, email=form_data.username, password=form_data.password)
  if not user:
    raise HTTPException(
      status_code=status.HTTP_400_BAD_REQUEST,
      detail="Incorrect email or password",
    )
  
  access_token_expires = timedelta(minutes=settings.ACCESS_TOKEN_EXPIRE_MINUTES)
  access_token = create_access_token(
    subject=user.id, expires_delta=access_token_expires
  )
  
  return {
    "access_token": access_token,
    "token_type": "bearer",
  }
