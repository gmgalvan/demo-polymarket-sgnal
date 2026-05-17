import os

from fastapi import FastAPI
from pydantic import BaseModel
import torch
import transformers

app = FastAPI()


class InputText(BaseModel):
    text: str


class OutputText(BaseModel):
    text: str


def get_pipeline():
    model_id = os.environ.get("MODEL_ID", "TinyLlama/TinyLlama-1.1B-Chat-v1.0")
    pipeline_kwargs = {
        "task": "text-generation",
        "model": model_id,
        "device_map": "auto",
        "torch_dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,
    }
    hf_token = os.environ.get("HF_TOKEN")
    if hf_token:
        pipeline_kwargs["token"] = hf_token
    return transformers.pipeline(**pipeline_kwargs)


pipeline = get_pipeline()


@app.post("/generate", response_model=OutputText)
async def generate_func(prompt: InputText):
    output = pipeline(
        [{"role": "user", "content": prompt.text}],
        max_new_tokens=int(os.environ.get("MAX_NEW_TOKENS", "256")),
    )
    return {"text": output[0]["generated_text"][-1]["content"]}
