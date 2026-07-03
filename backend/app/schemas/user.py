from typing import Optional
from pydantic import BaseModel, EmailStr

# Base shared properties
class UserBase(BaseModel):
  email: Optional[EmailStr] = None
  full_name: Optional[str] = None
  is_active: Optional[bool] = True

# Properties to receive via API on creation
class UserCreate(UserBase):
  email: EmailStr
  full_name: str
  password: str

# Properties to receive via API on update
class UserUpdate(BaseModel):
  full_name: Optional[str] = None
  password: Optional[str] = None

# Additional properties stored in DB
class UserInDBBase(UserBase):
  id: Optional[int] = None

  class Config:
    from_attributes = True

# Properties to return to client
class UserResponse(UserInDBBase):
  pass

# JWT structures
class Token(BaseModel):
  access_token: str
  token_type: str

class TokenPayload(BaseModel):
  sub: Optional[int] = None
