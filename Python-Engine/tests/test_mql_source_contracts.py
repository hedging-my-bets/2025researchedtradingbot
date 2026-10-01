from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
EA = ROOT / "MT5-Platform/MQL5/Experts/FXSuite/MASTER_CONTROLLER.mq5"
INC = ROOT / "MT5-Platform/MQL5/Include/FXSuite"

def test_master_is_strict_and_live_defaults_off():
    src = EA.read_text(encoding="utf-8")
    assert "#property strict" in src
    assert "input bool InpEnableTrades=false;" in src
    assert "input bool InpEnableOmegaSizer=false;" in src
    assert "input bool InpEnableOmegaRiskPolicy=false;" in src

def test_required_omega_inputs_exist():
    src = EA.read_text(encoding="utf-8")
    required = [
        "InpBE_TriggerPctEquity","InpBE_TriggerR","InpBE_OffsetPips",
        "InpConformalMaxWidth","InpWeeklyLossLimit","InpPeakLossLimit",
        "InpEnableRolloverGuard","InpStrictNewsGuard",
    ]
    for name in required:
        assert name in src

def test_known_mql_regressions_are_absent():
    all_src = "\n".join(p.read_text(encoding="utf-8") for p in INC.rglob("*.mqh"))
    assert "StringUpper(" not in all_src
    assert "->" not in all_src

def test_required_audit_event_families_exist():
    src = (INC / "Telemetry/NDJSONLogger.mqh").read_text(encoding="utf-8")
    for event in [
        "trade_intent","broker_ack","sl_change","risk_state","hedge_state",
        "calibration_metrics","parity_metric","news_guard","rollover_guard",
        "trade_close","mtf_vector",
    ]:
        assert f'"{event}"' in src

def test_restart_safety_guards_are_present():
    src = EA.read_text(encoding="utf-8")
    portfolio = (INC / "Core/PortfolioControl.mqh").read_text(encoding="utf-8")
    assert 'FolderCreate("FXSuite")' in src
    assert "GlobalVariableSet(g_bar_key" in src
    assert "portfolio_risk_state.csv" in portfolio
    assert "LoadState()" in portfolio
    assert "PersistState()" in portfolio

def test_restart_cvar_and_signed_beta_contracts():
    cvar = (INC / "Risk/CVaRTracker.mqh").read_text(encoding="utf-8")
    hedge = (INC / "Portfolio/NetHedge.mqh").read_text(encoding="utf-8")
    master = EA.read_text(encoding="utf-8")
    assert "bool Load(" in cvar
    assert "bool Save(" in cvar
    assert "cvar_history.csv" in master
    assert "-beta*corr" not in hedge.replace(" ", "")
    assert "return ClampRatio(-beta,max_ratio);" in hedge

def test_live_approval_is_wired_but_legacy_off():
    src = EA.read_text(encoding="utf-8")
    fp = (INC / "Core/BuildFingerprint.mqh").read_text(encoding="utf-8")
    assert "input bool InpRequireLiveApproval=false;" in src
    assert "LiveApprovalOK" in src
    assert "live_approval.csv" in src
    assert 'FXSUITE_BUILD_FINGERPRINT "UNARMED"' in fp

def test_mtf_live_wiring_is_opt_in():
    src = EA.read_text(encoding="utf-8")
    mtf = (INC / "ML/MTFConfidence.mqh").read_text(encoding="utf-8")
    assert "input bool InpEnableMTF=false;" in src
    assert "PERIOD_M15" in src and "PERIOD_H1" in src and "PERIOD_H4" in src and "PERIOD_D1" in src
    assert "MTFVector" in src
    assert "ShouldBlock" in mtf
    assert "conformal_width=MathMax" in src
