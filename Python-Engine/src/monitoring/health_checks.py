import time, os, shutil, requests

def ping_inference_server(url="http://127.0.0.1:8081/health", timeout=0.5) -> bool:
    try:
        r = requests.get(url, timeout=timeout)
        return r.status_code == 200
    except Exception:
        return False

def check_data_staleness(paths, max_age_sec=120):
    now = time.time()
    for p in paths:
        if not os.path.exists(p): return False
        if now - os.path.getmtime(p) > max_age_sec: return False
    return True

def check_disk_space(path="/", min_gb=5.0):
    return shutil.disk_usage(path).free/1e9 > min_gb