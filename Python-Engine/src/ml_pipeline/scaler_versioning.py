import json, os, tempfile, shutil
from typing import Dict

class ScalerVersionManager:
    def __init__(self, path="Python-Engine/configs/scaler.json", registry="ML_Models/registry"):
        self.path = path; self.registry = registry
        os.makedirs(registry, exist_ok=True)

    def update_atomic(self, new_scaler: Dict, model_id: str):
        tmp_fd, tmp_path = tempfile.mkstemp(prefix="scaler_", suffix=".json")
        with os.fdopen(tmp_fd, 'w') as f: json.dump(new_scaler, f)
        backup = f"{self.path}.bak"
        if os.path.exists(self.path): shutil.copy2(self.path, backup)
        os.replace(tmp_path, self.path)  # atomic on POSIX
        shutil.copy2(self.path, f"{self.registry}/scaler_{model_id}.json")

    def rollback(self):
        bak = f"{self.path}.bak"
        if os.path.exists(bak): os.replace(bak, self.path)