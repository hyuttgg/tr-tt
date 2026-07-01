"""
Blox Fruits Account Manager — FastAPI Relay Server
────────────────────────────────────────────────────
Endpoints:
  POST /relay          ← Lua Sender gửi data lên
  GET  /accounts       ← Lấy tất cả acc
  GET  /accounts/{u}   ← Lấy 1 acc theo username
  GET  /online         ← Lấy acc đang online
  GET  /stats          ← Thống kê tổng quan
  GET  /health         ← Health check
"""

import sys
import os
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import asyncio
import time
from contextlib import asynccontextmanager
from datetime import datetime, timezone, timedelta

from fastapi import FastAPI, HTTPException, Request, status, Depends
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from fastapi.security import OAuth2PasswordBearer
from jose import JWTError, jwt

from motor.motor_asyncio import AsyncIOMotorClient, AsyncIOMotorDatabase

import config
import auth
from models import AccountPayload, RelayResponse, AccountListResponse, UserCreate, UserLogin, Token, UserDocument


# ─────────────────────────────────────────────────────
# Khởi tạo MongoDB
# ─────────────────────────────────────────────────────

db: AsyncIOMotorDatabase | None = None
_mongo_client: AsyncIOMotorClient | None = None


@asynccontextmanager
async def lifespan(app: FastAPI):
    global db, _mongo_client
    print("[DB] Connecting to MongoDB Atlas...")
    _mongo_client = AsyncIOMotorClient(config.MONGODB_URI)
    db = _mongo_client[config.MONGODB_DB]

    # Tạo index unique trên username
    await db["accounts"].create_index("username", unique=True)
    await db["accounts"].create_index("user_id")
    await db["accounts"].create_index("last_seen")
    
    # Tạo index cho users
    await db["users"].create_index("username", unique=True)

    print(f"[DB] Connected -> database: {config.MONGODB_DB}")
    yield

    _mongo_client.close()
    print("[DB] Connection closed")


# ─────────────────────────────────────────────────────
# FastAPI App
# ─────────────────────────────────────────────────────

app = FastAPI(
    title="Blox Fruits Account Manager API",
    version="1.0.0",
    description="Relay server nhận data từ Lua Sender và lưu vào MongoDB",
    lifespan=lifespan,
)

app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],   # Cho phép tất cả các nguồn truy cập
    allow_credentials=False,  # JWT Token truyền qua Header nên không cần allow_credentials=True
    allow_methods=["*"],
    allow_headers=["*"],
)


# ─────────────────────────────────────────────────────
# Rate Limiter — in-memory per username
# ─────────────────────────────────────────────────────

_rate_cache: dict[str, float] = {}  # username → last_request_time


def check_rate_limit(username: str) -> bool:
    """
    Trả về True nếu được phép, False nếu bị rate-limit.
    Mặc định: 1 request / 3 giây / user.
    """
    now = time.monotonic()
    last = _rate_cache.get(username, 0.0)

    if now - last < config.RATE_LIMIT_SECONDS:
        return False   # Bị giới hạn

    _rate_cache[username] = now
    return True


# ─────────────────────────────────────────────────────
# Auth Dependency & Endpoints
# ─────────────────────────────────────────────────────

oauth2_scheme = OAuth2PasswordBearer(tokenUrl="auth/login")

async def get_current_user(token: str = Depends(oauth2_scheme)):
    credentials_exception = HTTPException(
        status_code=status.HTTP_401_UNAUTHORIZED,
        detail="Could not validate credentials",
        headers={"WWW-Authenticate": "Bearer"},
    )
    try:
        payload = jwt.decode(token, config.SECRET_KEY, algorithms=[config.ALGORITHM])
        username: str = payload.get("sub")
        if username is None:
            raise credentials_exception
    except JWTError:
        raise credentials_exception
    
    user = await db["users"].find_one({"username": username})
    if user is None:
        raise credentials_exception
    return user

@app.post("/auth/register")
async def register(user: UserCreate):
    # Kiểm tra xem user đã tồn tại chưa
    existing_user = await db["users"].find_one({"username": user.username})
    if existing_user:
        raise HTTPException(status_code=400, detail="Username already registered")
        
    hashed_password = auth.get_password_hash(user.password)
    user_dict = {
        "username": user.username,
        "hashed_password": hashed_password,
        "role": "user",
        "created_at": datetime.now(timezone.utc)
    }
    
    # Ở đây nếu muốn chỉ 1 admin, có thể đếm xem có user nào chưa, nếu có rồi thì chặn (tùy vào rule)
    # Tạm thời cho đăng ký thoải mái.
    await db["users"].insert_one(user_dict)
    return {"message": "User registered successfully"}

@app.post("/auth/login", response_model=Token)
async def login(user: UserLogin):
    db_user = await db["users"].find_one({"username": user.username})
    if not db_user or not auth.verify_password(user.password, db_user["hashed_password"]):
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Incorrect username or password",
            headers={"WWW-Authenticate": "Bearer"},
        )
        
    access_token = auth.create_access_token(
        data={"sub": user.username}
    )
    return {"access_token": access_token, "token_type": "bearer"}


# ─────────────────────────────────────────────────────
# Helper: serialize MongoDB document → dict an toàn
# ─────────────────────────────────────────────────────

def serialize_doc(doc: dict) -> dict:
    """Loại bỏ _id và format datetime sang ISO string."""
    doc.pop("_id", None)
    for k, v in doc.items():
        if isinstance(v, datetime):
            doc[k] = v.isoformat()
    return doc


def is_online(doc: dict) -> bool:
    """Kiểm tra acc có đang online không dựa vào last_seen."""
    last_seen = doc.get("last_seen")
    if not last_seen:
        return False
    if isinstance(last_seen, str):
        last_seen = datetime.fromisoformat(last_seen)
    threshold = datetime.now(timezone.utc) - timedelta(
        seconds=config.OFFLINE_THRESHOLD_SECONDS
    )
    # Đảm bảo timezone aware
    if last_seen.tzinfo is None:
        last_seen = last_seen.replace(tzinfo=timezone.utc)
    return last_seen >= threshold


# ─────────────────────────────────────────────────────
# POST /relay — Lua Sender gửi data lên
# ─────────────────────────────────────────────────────

@app.post("/relay", response_model=RelayResponse)
@app.post("/data", response_model=RelayResponse)
async def relay(payload: AccountPayload, request: Request):
    # 1. Xác thực API Key
    if payload.api_key not in config.API_KEYS:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="Invalid API key"
        )

    # 2. Rate limit
    if not check_rate_limit(payload.username):
        raise HTTPException(
            status_code=status.HTTP_429_TOO_MANY_REQUESTS,
            detail=f"Rate limit: tối đa 1 request / {config.RATE_LIMIT_SECONDS}s"
        )

    # 3. Build document
    now = datetime.now(timezone.utc)

    update_doc = {
        "$set": {
            "username":     payload.username,
            "user_id":      payload.user_id,
            "level":        payload.level,
            "beli":         payload.beli,
            "fragments":    payload.fragments,
            "race":         payload.race,
            "sea":          payload.sea,
            "fruit":        payload.fruit,
            "sword":        payload.sword,
            "gun":          payload.gun,
            "melee":        payload.melee,
            "inventory":    payload.inventory,
            "accessories":  payload.accessories,
            "materials":    payload.materials,
            "status":       payload.status,
            "last_seen":    now,
            "updated_at":   now,
        },
        "$setOnInsert": {
            "created_at": now,
        }
    }

    # 4. Upsert vào MongoDB
    try:
        await db["accounts"].update_one(
            {"username": payload.username},
            update_doc,
            upsert=True,
        )
    except Exception as e:
        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"DB error: {str(e)}"
        )

    return RelayResponse(
        success=True,
        message="Data received",
        username=payload.username,
    )


# ─────────────────────────────────────────────────────
# GET /accounts — Tất cả tài khoản
# ─────────────────────────────────────────────────────

@app.get("/accounts")
async def get_accounts(
    sea: int | None = None,
    min_level: int | None = None,
    max_level: int | None = None,
    status: str | None = None,
    limit: int = 100,
    skip: int = 0,
    current_user: dict = Depends(get_current_user)
):
    """
    Lấy danh sách tài khoản với filter tùy chọn.
    - sea: 1, 2, 3
    - min_level / max_level: filter theo level
    - status: "online" | "offline"
    - limit / skip: pagination
    """
    query: dict = {}

    if sea is not None:
        query["sea"] = sea

    if min_level is not None or max_level is not None:
        level_filter: dict = {}
        if min_level is not None:
            level_filter["$gte"] = min_level
        if max_level is not None:
            level_filter["$lte"] = max_level
        query["level"] = level_filter

    cursor = db["accounts"].find(query).sort("level", -1).skip(skip).limit(limit)
    docs = await cursor.to_list(length=limit)

    # Serialize + đánh dấu online/offline realtime
    results = []
    online_count = 0
    for doc in docs:
        s = serialize_doc(doc)
        online = is_online({"last_seen": s.get("last_seen")})
        s["is_online"] = online
        if online:
            online_count += 1

        # Filter by status nếu có
        if status == "online" and not online:
            continue
        if status == "offline" and online:
            continue

        results.append(s)

    total = await db["accounts"].count_documents(query)

    return {
        "total": total,
        "online": online_count,
        "returned": len(results),
        "accounts": results,
    }


# ─────────────────────────────────────────────────────
# GET /accounts/{username} — 1 tài khoản
# ─────────────────────────────────────────────────────

@app.get("/accounts/{username}")
async def get_account(username: str, current_user: dict = Depends(get_current_user)):
    doc = await db["accounts"].find_one({"username": username})
    if not doc:
        raise HTTPException(status_code=404, detail=f"Account '{username}' not found")

    result = serialize_doc(doc)
    result["is_online"] = is_online({"last_seen": result.get("last_seen")})
    return result


# ─────────────────────────────────────────────────────
# GET /online — Tài khoản đang online
# ─────────────────────────────────────────────────────

@app.get("/online")
async def get_online(current_user: dict = Depends(get_current_user)):
    threshold = datetime.now(timezone.utc) - timedelta(
        seconds=config.OFFLINE_THRESHOLD_SECONDS
    )
    cursor = db["accounts"].find(
        {"last_seen": {"$gte": threshold}}
    ).sort("last_seen", -1)

    docs = await cursor.to_list(length=500)
    results = [serialize_doc(doc) for doc in docs]
    for r in results:
        r["is_online"] = True

    return {"online": len(results), "accounts": results}


# ─────────────────────────────────────────────────────
# GET /stats — Thống kê tổng quan
# ─────────────────────────────────────────────────────

@app.get("/stats")
async def get_stats(current_user: dict = Depends(get_current_user)):
    total = await db["accounts"].count_documents({})

    threshold = datetime.now(timezone.utc) - timedelta(
        seconds=config.OFFLINE_THRESHOLD_SECONDS
    )
    online_count = await db["accounts"].count_documents(
        {"last_seen": {"$gte": threshold}}
    )

    sea1 = await db["accounts"].count_documents({"sea": 1})
    sea2 = await db["accounts"].count_documents({"sea": 2})
    sea3 = await db["accounts"].count_documents({"sea": 3})

    # Top fruit
    pipeline = [
        {"$group": {"_id": "$fruit", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
        {"$limit": 5},
    ]
    top_fruits_cursor = db["accounts"].aggregate(pipeline)
    top_fruits = []
    async for doc in top_fruits_cursor:
        top_fruits.append({"fruit": doc["_id"], "count": doc["count"]})

    # Top race
    race_pipeline = [
        {"$group": {"_id": "$race", "count": {"$sum": 1}}},
        {"$sort": {"count": -1}},
        {"$limit": 5},
    ]
    top_races = []
    async for doc in db["accounts"].aggregate(race_pipeline):
        top_races.append({"race": doc["_id"], "count": doc["count"]})

    # Avg level
    avg_pipeline = [{"$group": {"_id": None, "avg_level": {"$avg": "$level"}}}]
    avg_doc = None
    async for doc in db["accounts"].aggregate(avg_pipeline):
        avg_doc = doc

    return {
        "total_accounts": total,
        "online_now": online_count,
        "offline": total - online_count,
        "sea_breakdown": {"sea1": sea1, "sea2": sea2, "sea3": sea3},
        "top_fruits": top_fruits,
        "top_races": top_races,
        "avg_level": round(avg_doc["avg_level"], 1) if avg_doc else 0,
    }


# ─────────────────────────────────────────────────────
# GET /health — Health check
# ─────────────────────────────────────────────────────

@app.get("/health")
async def health():
    return {"status": "ok", "timestamp": datetime.now(timezone.utc).isoformat()}


# ─────────────────────────────────────────────────────
# Entry point
# ─────────────────────────────────────────────────────

if __name__ == "__main__":
    import uvicorn
    uvicorn.run(
        "main:app",
        host=config.HOST,
        port=config.PORT,
        reload=True,
        log_level="info",
    )
