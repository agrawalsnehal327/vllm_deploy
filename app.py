from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from fastapi.responses import JSONResponse
from pydantic import BaseModel
import requests

app = FastAPI()

# Allow requests from your frontend
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],  # Restrict to ["http://localhost:3000"] in prod
    allow_credentials=True,
    allow_methods=["*"],
    allow_headers=["*"],
)

VLLM_URL = "http://192.168.67.2:31909/v1/completions"

class PromptRequest(BaseModel):
    prompt: str
    max_tokens: int = 50

@app.post("/generate")
def generate(req: PromptRequest):
    payload = {
        "model": "openai/gpt-oss-20b",
        "prompt": req.prompt,
        "max_tokens": req.max_tokens
    }
    response = requests.post(VLLM_URL, json=payload)

    try:
        data = response.json()
    except Exception:
        return JSONResponse(content={"error": "Invalid response from VLLM"}, status_code=500)

    return JSONResponse(content=data)
