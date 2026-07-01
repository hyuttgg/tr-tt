import sys, os
import asyncio
from httpx import AsyncClient, ASGITransport

sys.path.insert(0, os.path.abspath('backend'))
from main import app, lifespan

async def run():
    async with lifespan(app):
        transport = ASGITransport(app=app, raise_app_exceptions=False)
        async with AsyncClient(transport=transport, base_url="http://test") as client:
            r = await client.post("/auth/register", json={"username": "t", "password": "t"})
            print(r.status_code)
            print(r.text)

asyncio.run(run())
