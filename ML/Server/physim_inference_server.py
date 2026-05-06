import numpy as np
import onnxruntime as ort
from fastapi import FastAPI
from pydantic import BaseModel
import uvicorn, os

app = FastAPI()
BASE = os.path.dirname(os.path.abspath(__file__))

s2_sess = ort.InferenceSession(
    os.path.join(BASE, "../Models/sonata2.onnx"),
    providers=["CPUExecutionProvider"]
)
print("[Server] sonata2.onnx loaded.")

class S2Request(BaseModel):
    scene_static : list[float]
    obj_static   : list[float]
    context      : list[float]
    obj_mask     : list[float]

@app.post("/predict_s2")
def predict_s2(req: S2Request):
    feeds = {
        "scene_static": np.array(req.scene_static, dtype=np.float32).reshape(1, 3),
        "obj_static"  : np.array(req.obj_static,   dtype=np.float32).reshape(1, 6, 11),
        "context"     : np.array(req.context,       dtype=np.float32).reshape(1, 10, 6, 27),
        "obj_mask"    : np.array(req.obj_mask,       dtype=np.float32).reshape(1, 6),
    }
    pred = s2_sess.run(["prediction"], feeds)[0]
    return {"prediction": pred.flatten().tolist()}

@app.get("/ping")
def ping():
    return {"status": "ok"}

if __name__ == "__main__":
    uvicorn.run(app, host="127.0.0.1", port=7842, log_level="warning")