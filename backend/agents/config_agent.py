"""
CodeWhale Config Agent — Agent de configuration et diagnostic du système.

Cet agent est spécialisé dans :
- La configuration du serveur (Docker, réseau, firewall)
- Le diagnostic des problèmes (logs, performance, disques)
- La gestion des certificats SSL
- La surveillance des services

Accessible via :
    POST /agent/run avec model=deepseek-v4-pro et prompt adapté
    ou directement via agent.zentic.fr
"""

import asyncio
import json
import os
import subprocess
import time
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

import httpx
from fastapi import APIRouter, HTTPException, Request
from fastapi.responses import StreamingResponse

from backend.core.logging import get_logger

logger = get_logger(__name__)
router = APIRouter(prefix="/config", tags=["config-agent"])

# ─── Tools spécifiques à l'agent de config ─────────────────────────────────

CONFIG_TOOLS = [
    {
        "type": "function",
        "function": {
            "name": "check_disk_usage",
            "description": "Vérifier l'utilisation des disques (df -h, lsblk).",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "path": {"type": "string", "description": "Chemin à vérifier (défaut: /)"},
                },
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "check_docker_status",
            "description": "Vérifier l'état des containers Docker et l'utilisation des ressources.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {},
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "check_ssl_certs",
            "description": "Vérifier l'état des certificats SSL pour un domaine.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "domain": {"type": "string", "description": "Nom de domaine (ex: zentic.fr)"},
                },
                "required": ["domain"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "manage_volume",
            "description": "Monter/démonter un volume de stockage.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "action": {"type": "string", "enum": ["list", "mount", "unmount", "format"], "description": "Action à effectuer"},
                    "device": {"type": "string", "description": "Périphérique (ex: /dev/sdb)"},
                    "mount_point": {"type": "string", "description": "Point de montage (ex: /opt/corelia)"},
                },
                "required": ["action"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "check_logs",
            "description": "Consulter les logs d'un service.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "service": {"type": "string", "description": "Nom du service (backend, agent, caddy, redis, ollama)"},
                    "lines": {"type": "integer", "description": "Nombre de lignes (défaut: 50)"},
                },
                "required": ["service"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "restart_service",
            "description": "Redémarrer un service Docker.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "service": {"type": "string", "description": "Nom du service à redémarrer"},
                },
                "required": ["service"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "migrate_docker_data",
            "description": "Migrer les données Docker vers un nouveau volume.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "target_path": {"type": "string", "description": "Chemin cible (ex: /opt/docker)"},
                },
                "required": ["target_path"],
                "additionalProperties": False,
            },
        },
    },
    {
        "type": "function",
        "function": {
            "name": "task_complete",
            "description": "Marquer la tâche de configuration comme terminée.",
            "strict": True,
            "parameters": {
                "type": "object",
                "properties": {
                    "summary": {"type": "string", "description": "Résumé des actions effectuées"},
                    "recommendations": {"type": "array", "items": {"type": "string"}, "description": "Recommandations"},
                },
                "required": ["summary"],
                "additionalProperties": False,
            },
        },
    },
]

# ─── Tool Executors ────────────────────────────────────────────────────────

async def exec_check_disk_usage(path: str = "/") -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            "df", "-h", path,
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        return stdout.decode()[:2000]
    except Exception as e:
        return f"Erreur: {e}"

async def exec_check_docker_status() -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "ps", "--format", "table {{.Names}}\t{{.Status}}\t{{.Ports}}",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, _ = await proc.communicate()
        
        proc2 = await asyncio.create_subprocess_exec(
            "docker", "system", "df",
            stdout=asyncio.subprocess.PIPE
        )
        stdout2, _ = await proc2.communicate()
        
        return f"Containers:\n{stdout.decode()}\n\nUtilisation:\n{stdout2.decode()}"
    except Exception as e:
        return f"Erreur: {e}"

async def exec_check_ssl_certs(domain: str) -> str:
    try:
        # Vérifier via OpenSSL
        proc = await asyncio.create_subprocess_exec(
            "bash", "-c", f"echo | openssl s_client -servername {domain} -connect {domain}:443 2>/dev/null | openssl x509 -noout -dates -issuer 2>/dev/null || echo 'Pas de certificat HTTPS trouvé'",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        result = stdout.decode()
        
        # Vérifier aussi via DNS
        proc2 = await asyncio.create_subprocess_exec(
            "bash", "-c", f"dig +short {domain} A",
            stdout=asyncio.subprocess.PIPE
        )
        stdout2, _ = await proc2.communicate()
        ip = stdout2.decode().strip()
        
        return f"DNS: {domain} → {ip}\n\nTLS:\n{result}"
    except Exception as e:
        return f"Erreur: {e}"

async def exec_manage_volume(action: str, device: str = "", mount_point: str = "") -> str:
    try:
        if action == "list":
            proc = await asyncio.create_subprocess_exec(
                "lsblk", "-o", "NAME,SIZE,TYPE,MOUNTPOINT",
                stdout=asyncio.subprocess.PIPE
            )
            stdout, _ = await proc.communicate()
            return stdout.decode()
        elif action == "mount" and device and mount_point:
            os.makedirs(mount_point, exist_ok=True)
            proc = await asyncio.create_subprocess_exec(
                "mount", device, mount_point,
                stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
            )
            stdout, stderr = await proc.communicate()
            return stdout.decode() or stderr.decode() or f"Monté: {device} → {mount_point}"
        else:
            return f"Action '{action}' non supportée ou paramètres manquants"
    except Exception as e:
        return f"Erreur: {e}"

async def exec_check_logs(service: str, lines: int = 50) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "logs", f"corelia-{service}", f"--tail={lines}",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        result = stdout.decode()
        if stderr:
            result += "\n[stderr]\n" + stderr.decode()
        return result[-3000:] if len(result) > 3000 else result
    except Exception as e:
        return f"Erreur: {e}"

async def exec_restart_service(service: str) -> str:
    try:
        proc = await asyncio.create_subprocess_exec(
            "docker", "restart", f"corelia-{service}",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        stdout, stderr = await proc.communicate()
        return f"Redémarré: {stdout.decode().strip() or 'OK'}"
    except Exception as e:
        return f"Erreur: {e}"

async def exec_migrate_docker_data(target_path: str) -> str:
    """Migre /var/lib/docker vers un nouveau volume."""
    try:
        steps = []
        # 1. Arrêter Docker
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "stop", "docker",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await proc.communicate()
        steps.append("✅ Docker arrêté")
        
        # 2. Créer dossier cible
        os.makedirs(target_path, exist_ok=True)
        steps.append(f"✅ Dossier créé: {target_path}")
        
        # 3. Copier les données
        proc = await asyncio.create_subprocess_exec(
            "rsync", "-avz", "/var/lib/docker/", f"{target_path}/",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await proc.communicate()
        steps.append("✅ Données copiées")
        
        # 4. Configurer le daemon
        config_path = "/etc/docker/daemon.json"
        try:
            with open(config_path) as f:
                config = json.load(f)
        except:
            config = {}
        config["data-root"] = target_path
        with open(config_path, "w") as f:
            json.dump(config, f, indent=2)
        steps.append(f"✅ Config mise à jour: data-root={target_path}")
        
        # 5. Redémarrer Docker
        proc = await asyncio.create_subprocess_exec(
            "systemctl", "start", "docker",
            stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE
        )
        await proc.communicate()
        steps.append("✅ Docker redémarré")
        
        return "\n".join(steps)
    except Exception as e:
        return f"❌ Erreur migration: {e}"

CONFIG_TOOL_EXECUTORS = {
    "check_disk_usage": exec_check_disk_usage,
    "check_docker_status": exec_check_docker_status,
    "check_ssl_certs": exec_check_ssl_certs,
    "manage_volume": exec_manage_volume,
    "check_logs": exec_check_logs,
    "restart_service": exec_restart_service,
    "migrate_docker_data": exec_migrate_docker_data,
}

# ─── System Prompt ─────────────────────────────────────────────────────────

CONFIG_SYSTEM_PROMPT = """Tu es l'Agent de Configuration CorelIA Cloud.

Tu es spécialisé dans l'administration système :
- Diagnostic des problèmes (disques, réseau, Docker, certificats)
- Gestion des volumes de stockage
- Redémarrage des services
- Migration des données Docker
- Vérification SSL/TLS

RÈGLES :
1. Diagnostique d'abord (check_*) avant d'agir
2. Explique chaque action avant de l'exécuter
3. Vérifie le résultat de chaque action
4. Termine par task_complete avec un résumé clair
"""

# ─── Routes ───────────────────────────────────────────────────────────────

@router.get("/health")
async def config_agent_health():
    return {
        "agent": "config-agent",
        "tools": list(CONFIG_TOOL_EXECUTORS.keys()),
        "status": "ok"
    }

@router.post("/diagnose")
async def config_diagnose(request: Request):
    """Diagnostic complet du système."""
    body = await request.json()
    prompt = body.get("prompt", "Fais un diagnostic complet du système")
    
    # Appeler l'agent principal avec les outils de config
    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(
            "http://codewhale-agent:8001/agent/run",
            json={
                "prompt": f"{CONFIG_SYSTEM_PROMPT}\n\nTÂCHE: {prompt}",
                "model": body.get("model", "deepseek-v4-pro"),
                "max_turns": body.get("max_turns", 15),
            },
        )
        return resp.json()

@router.post("/migrate")
async def config_migrate(request: Request):
    """Migrer Docker vers un nouveau volume."""
    body = await request.json()
    target = body.get("target", "/opt/docker")
    
    async with httpx.AsyncClient(timeout=300.0) as client:
        resp = await client.post(
            "http://codewhale-agent:8001/agent/run",
            json={
                "prompt": f"{CONFIG_SYSTEM_PROMPT}\n\nTÂCHE: Migre les données Docker vers {target}. Utilise migrate_docker_data.",
                "model": "deepseek-v4-pro",
                "max_turns": 10,
            },
        )
        return resp.json()
