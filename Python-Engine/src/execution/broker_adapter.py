class BrokerAdapter:
    """
    Maps broker-specific quirks to canonical forms (symbols, pip size, contract size, swaps).
    """
    def __init__(self, mapping: dict):
        self.map = mapping

    def normalize_symbol(self, broker_symbol: str) -> str:
        return self.map.get("symbols", {}).get(broker_symbol, broker_symbol)

    def pip_value(self, symbol: str) -> float:
        return self.map.get("pip_value", {}).get(symbol, 0.0001)

    def contract_size(self, symbol: str) -> float:
        return self.map.get("contract_size", {}).get(symbol, 100000.0)

    def swap_method(self, symbol: str) -> str:
        return self.map.get("swap_method", {}).get(symbol, "points")