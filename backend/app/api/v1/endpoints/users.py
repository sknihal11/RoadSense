from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session
from ....crud.user import create_user, get_user_by_email
from ....models.user import User
from ....schemas.user import UserCreate, UserResponse
from ..deps import get_db, get_current_user

router = APIRouter()

@router.post("/signup", response_model=UserResponse, status_code=status.HTTP_201_CREATED)
def signup(user_in: UserCreate, db: Session = Depends(get_db)):
  user = get_user_by_email(db, email=user_in.email)
  if user:
    raise HTTPException(
      status_code=status.HTTP_400_BAD_REQUEST,
      detail="The user with this email already exists in the system.",
    )
  return create_user(db, user_in=user_in)

@router.get("/me", response_model=UserResponse)
def read_user_me(current_user: User = Depends(get_current_user)):
  return current_user
