import os

import torch
import transformers

model_id = os.environ.get("MODEL_ID", "TinyLlama/TinyLlama-1.1B-Chat-v1.0")  # Hugging Face model identifier.

pipeline_kwargs = {
    "task": "text-generation",  # Load a text-generation pipeline.
    "model": model_id,
    "device_map": "auto",
    "torch_dtype": torch.bfloat16 if torch.cuda.is_available() else torch.float32,  # Use bfloat16 on GPU; fall back to float32 on CPU.
}

hf_token = os.environ.get("HF_TOKEN")  # Some models require a Hugging Face token to download.
if hf_token:
    pipeline_kwargs["token"] = hf_token

pipeline = transformers.pipeline(**pipeline_kwargs)  # Initialize the model runtime.

messages = [
    {"role": "user", "content": "Hey how are you doing today?"},
]

result = pipeline(messages, max_new_tokens=256)
print(result[0]["generated_text"][-1]["content"])  # Print only the assistant response.
