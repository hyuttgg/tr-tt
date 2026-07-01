import requests

try:
    response = requests.post("http://localhost:8000/auth/register", json={
        "username": "testuser",
        "password": "testpassword"
    })
    print("Status Code:", response.status_code)
    print("Response body:", response.text)
except Exception as e:
    print("Error:", e)
