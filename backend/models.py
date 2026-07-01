from pydantic import BaseModel, Field
from typing import Optional
from datetime import datetime


# ─────────────────────────────────────────────
# Payload Lua gửi lên (request body)
# ─────────────────────────────────────────────

class AccountPayload(BaseModel):
    api_key: str

    # Identity
    username: str
    user_id: int

    # Stats
    level: int = 0
    beli: int = 0
    fragments: int = 0
    race: str = "Unknown"
    sea: int = 1

    # Equipment
    fruit: str = "None"
    sword: str = "None"
    gun: str = "None"
    melee: str = "None"

    # Inventory
    inventory: list[str] = Field(default_factory=list)
    accessories: list[str] = Field(default_factory=list)
    materials: dict[str, int] = Field(default_factory=dict)

    # Meta
    status: str = "online"  # "online" | "offline"
    timestamp: Optional[int] = None  # os.time() từ Lua


# ─────────────────────────────────────────────
# Document trong MongoDB (response model)
# ─────────────────────────────────────────────

class AccountDocument(BaseModel):
    owner: str = ""
    username: str
    user_id: int

    level: int
    beli: int
    fragments: int
    race: str
    sea: int

    fruit: str
    sword: str
    gun: str
    melee: str

    inventory: list[str]
    accessories: list[str]
    materials: dict[str, int]

    status: str
    last_seen: datetime
    created_at: datetime
    updated_at: datetime


# ─────────────────────────────────────────────
# Authentication Models
# ─────────────────────────────────────────────

class UserCreate(BaseModel):
    username: str
    password: str

class UserLogin(BaseModel):
    username: str
    password: str

class Token(BaseModel):
    access_token: str
    token_type: str

class UserDocument(BaseModel):
    username: str
    hashed_password: str
    api_key: str = ""
    role: str = "user"
    created_at: datetime


# ─────────────────────────────────────────────
# Response helpers
# ─────────────────────────────────────────────

class RelayResponse(BaseModel):
    success: bool
    message: str
    username: str = ""


class AccountListResponse(BaseModel):
    total: int
    online: int
    accounts: list[dict]
