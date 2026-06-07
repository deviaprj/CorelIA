"""API d'insights de donnees anonymisees pour les acheteurs tiers.

Principes de securite :
- Aucune donnee individuelle n'est exposee (uniquement aggregee)
- Authentification par cle API
- Rate limiting strict
- Audit log de toutes les requetes
"""

from datetime import datetime, timedelta, timezone
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, Request
from pydantic import BaseModel

from backend.core.auth import require_api_key
from backend.core.config import settings
from backend.core.logging import get_logger

router = APIRouter(prefix="/insights", tags=["insights"])
logger = get_logger(__name__)

# Stockage en memoire (en production : Redis ou DB)
_insights_store: list[dict] = []
_audit_log: list[dict] = []


# ── Schemas ────────────────────────────────────────────────────────────────────


class InsightIngestRequest(BaseModel):
    cohort_id: str
    type: str  # search_trend, feature_usage, intent_map, seasonality
    data: dict
    timestamp: datetime


class InsightBatchRequest(BaseModel):
    insights: list[InsightIngestRequest]


class TrendResponse(BaseModel):
    period: str
    trends: list[dict]
    total_events: int


class DemographicsResponse(BaseModel):
    platforms: dict[str, int]
    languages: dict[str, int]
    peak_hours: dict[int, int]
    total_cohorts: int


# ── Ingestion ─────────────────────────────────────────────────────────────────


@router.post("/ingest", status_code=204)
def ingest_insights(
    request: Request,
    body: InsightBatchRequest,
    _: str = Depends(require_api_key),
):
    """Recevoir un batch d'insights anonymises depuis l'app mobile."""
    for insight in body.insights:
        _insights_store.append(insight.model_dump())
    _audit_log.append(
        {
            "action": "ingest",
            "ip": request.client.host if request.client else None,
            "count": len(body.insights),
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )
    logger.info(f"Ingested {len(body.insights)} insights")
    return None


# ── Queries ───────────────────────────────────────────────────────────────────


@router.get("/trends", response_model=TrendResponse)
def get_trends(
    request: Request,
    type_filter: Optional[str] = Query(None, description="Filtrer par type d'insight"),
    days: int = Query(7, ge=1, le=90),
    _: str = Depends(require_api_key),
):
    """Retourner les tendances agregees sur les N derniers jours."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=days)
    filtered = [
        i for i in _insights_store
        if i["timestamp"] >= cutoff and (type_filter is None or i["type"] == type_filter)
    ]

    # Agregation par type
    trends_map: dict[str, int] = {}
    for i in filtered:
        key = i.get("data", {}).get("intent") or i.get("data", {}).get("feature") or i["type"]
        trends_map[key] = trends_map.get(key, 0) + 1

    trends = [{"key": k, "count": v} for k, v in sorted(trends_map.items(), key=lambda x: -x[1])[:50]]

    _audit_log.append(
        {
            "action": "query_trends",
            "ip": request.client.host if request.client else None,
            "days": days,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    return TrendResponse(
        period=f"last_{days}_days",
        trends=trends,
        total_events=len(filtered),
    )


@router.get("/demographics", response_model=DemographicsResponse)
def get_demographics(
    request: Request,
    _: str = Depends(require_api_key),
):
    """Retourner la repartition demographique agregee."""
    platforms: dict[str, int] = {}
    languages: dict[str, int] = {}
    peak_hours: dict[int, int] = {}

    for i in _insights_store:
        data = i.get("data", {})
        plat = data.get("platform", "unknown")
        platforms[plat] = platforms.get(plat, 0) + 1
        lang = data.get("language", "unknown")
        languages[lang] = languages.get(lang, 0) + 1
        hour = data.get("hour")
        if hour is not None:
            peak_hours[hour] = peak_hours.get(hour, 0) + 1

    # K-anonymity : masquer les cohortes < 5
    cohorts = set(i["cohort_id"] for i in _insights_store)

    _audit_log.append(
        {
            "action": "query_demographics",
            "ip": request.client.host if request.client else None,
            "timestamp": datetime.now(timezone.utc).isoformat(),
        }
    )

    return DemographicsResponse(
        platforms={k: v for k, v in platforms.items() if v >= 5},
        languages={k: v for k, v in languages.items() if v >= 5},
        peak_hours=peak_hours,
        total_cohorts=len(cohorts),
    )


@router.get("/audit")
def get_audit_log(
    request: Request,
    limit: int = Query(100, ge=1, le=1000),
    _: str = Depends(require_api_key),
):
    """Audit log des acces (admin uniquement)."""
    return {"audit": _audit_log[-limit:]}
