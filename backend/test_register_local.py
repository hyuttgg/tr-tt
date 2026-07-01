import asyncio
from fastapi import FastAPI
from httpx import AsyncClient, ASGITransport
import sys

# Import app
from backend.main import app
from backend.main import lifespan

async def test_register():
    # Use lifespan to connect to DB
    async with lifespan(app):
        transport = ASGITransport(app=app)
        async with AsyncClient(transport=transport, base_url="http://testserver") as client:
            try:
                response = await client.post("/auth/register", json={
                    "username": "testuser_local",
                    "password": "testpassword_local"
                })
                print("Status Code:", response.status_code)
                print("Response body:", response.text)
            except Exception as e:
                print("Exception:", e)

if __name__ == "__main__":
    asyncio.run(test_register())
