from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
from typing import Any
import math
import yaml

@dataclass(frozen=True)
class FeatureSpec:
    name: str
    type: str
    unit: str
    minimum: float
    maximum: float
    null_policy: str
    clip: bool

class FeatureRegistry:
    def __init__(self, version: int, registry_version: str, specs: list[FeatureSpec]):
        self.version = version
        self.registry_version = registry_version
        self.specs = specs
        self.names = [s.name for s in specs]
        if len(self.specs) != 64 or len(set(self.names)) != 64:
            raise ValueError("feature registry must contain 64 unique ordered features")

    @classmethod
    def load(cls, path: Path):
        raw = yaml.safe_load(path.read_text())
        specs = []
        for item in raw["meta_features"]:
            for required in ("name","type","unit","min","max","null_policy","clip"):
                if required not in item:
                    raise ValueError(f"feature {item.get('name')} missing {required}")
            specs.append(FeatureSpec(
                name=str(item["name"]),
                type=str(item["type"]),
                unit=str(item["unit"]),
                minimum=float(item["min"]),
                maximum=float(item["max"]),
                null_policy=str(item["null_policy"]),
                clip=bool(item["clip"]),
            ))
        return cls(int(raw["features_version"]), str(raw["registry_version"]), specs)

    def sanitize(self, values) -> list[float]:
        if len(values) != 64:
            raise ValueError(f"expected 64 features, got {len(values)}")
        out = []
        for spec, raw in zip(self.specs, values):
            value = float(raw)
            if not math.isfinite(value):
                if spec.null_policy == "reject":
                    raise ValueError(f"non-finite feature: {spec.name}")
                value = 0.0
            if value < spec.minimum or value > spec.maximum:
                if not spec.clip:
                    raise ValueError(f"feature out of range: {spec.name}={value}")
                value = min(spec.maximum, max(spec.minimum, value))
            out.append(value)
        return out

    def as_dict(self) -> dict[str, Any]:
        return {
            "features_version": self.version,
            "registry_version": self.registry_version,
            "features": [s.__dict__ for s in self.specs],
        }
