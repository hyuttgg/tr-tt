from fastapi import FastAPI
import uvicorn
import asyncio
from httpx import AsyncClient, ASGITransport

app = FastAPI()

@app.post("/relay")
@app.post("/data")
async def relay():
    return {"status": "ok"}

async def main():
    async with AsyncClient(transport=ASGITransport(app=app), base_url="http://test") as ac:
        r1 = await ac.post("/relay")
        r2 = await ac.post("/data")
        print("Relay:", r1.status_code)
        print("Data:", r2.status_code)

if __name__ == "__main__":
    asyncio.run(main())
