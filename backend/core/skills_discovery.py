"""Découverte et chargement des Skills Agent (format SKILL.md).

Inspiré de Deep Code / DeepSeek-TUI :
- User-level : ~/.agents/skills/<name>/SKILL.md
- Project-level : ./.github/skills/<name>/SKILL.md
- Project-level : ./.codewhale/skills/<name>/SKILL.md
"""

from __future__ import annotations

from pathlib import Path
from typing import Any

from backend.core.logging import get_logger

logger = get_logger(__name__)

# Chemins de découverte (priorité: projet > utilisateur)
_SKILL_SEARCH_PATHS: list[Path] = []


def _init_search_paths() -> list[Path]:
    """Initialise les chemins de recherche des skills (paresseux)."""
    global _SKILL_SEARCH_PATHS
    if _SKILL_SEARCH_PATHS:
        return _SKILL_SEARCH_PATHS

    paths: list[Path] = []

    # Projet CorelIA
    cwd = Path.cwd()
    for candidate in [
        cwd / ".github" / "skills",
        cwd / ".codewhale" / "skills",
        cwd / ".deepseek" / "skills",
    ]:
        if candidate.is_dir():
            paths.append(candidate)

    # Utilisateur
    home = Path.home()
    for candidate in [
        home / ".agents" / "skills",
        home / ".codewhale" / "skills",
        home / ".deepseek" / "skills",
    ]:
        if candidate.is_dir():
            paths.append(candidate)

    _SKILL_SEARCH_PATHS = paths
    logger.info(
        "Skills search paths initialized",
        extra={"paths": [str(p) for p in paths]},
    )
    return paths


def discover_skills() -> dict[str, dict[str, Any]]:
    """Découvre tous les skills disponibles.

    Returns:
        Dict {skill_id: {name, description, path, source}}
    """
    skills: dict[str, dict[str, Any]] = {}
    search_paths = _init_search_paths()

    for base_path in search_paths:
        if not base_path.is_dir():
            continue

        for skill_dir in sorted(base_path.iterdir()):
            if not skill_dir.is_dir():
                continue

            skill_md = skill_dir / "SKILL.md"
            if not skill_md.is_file():
                continue

            skill_id = skill_dir.name

            # Extraire nom + description du SKILL.md (premières lignes)
            name = skill_id.replace("-", " ").title()
            description = ""
            try:
                content = skill_md.read_text(encoding="utf-8")
                lines = content.strip().split("\n")
                # La première ligne est souvent le titre (# Name)
                if lines and lines[0].startswith("# "):
                    name = lines[0][2:].strip()
                # Chercher une description courte
                for line in lines[1:10]:
                    line = line.strip()
                    if line and not line.startswith("#") and not line.startswith("---"):
                        description = line[:200]
                        break
            except Exception:
                pass

            skills[skill_id] = {
                "id": skill_id,
                "name": name,
                "description": description,
                "path": str(skill_dir),
                "source": "project" if str(cwd := Path.cwd()) in str(base_path) else "user",
            }

    return skills


def load_skill(skill_id: str) -> dict[str, Any] | None:
    """Charge le contenu complet d'un skill.

    Args:
        skill_id: Identifiant du skill (nom du dossier)

    Returns:
        Dict avec 'id', 'name', 'content', 'files' ou None si introuvable
    """
    search_paths = _init_search_paths()

    for base_path in search_paths:
        skill_dir = base_path / skill_id
        skill_md = skill_dir / "SKILL.md"
        if not skill_md.is_file():
            continue

        try:
            content = skill_md.read_text(encoding="utf-8")
            # Lister les fichiers compagnons
            companion_files: list[str] = []
            for f in skill_dir.iterdir():
                if f.is_file() and f.name != "SKILL.md":
                    companion_files.append(f.name)

            name = skill_id.replace("-", " ").title()
            for line in content.strip().split("\n"):
                if line.startswith("# "):
                    name = line[2:].strip()
                    break

            return {
                "id": skill_id,
                "name": name,
                "content": content,
                "files": companion_files,
                "path": str(skill_dir),
            }
        except Exception as exc:
            logger.warning("Failed to load skill", extra={"skill": skill_id, "error": str(exc)})
            continue

    return None


def get_skills_context() -> str:
    """Génère un résumé des skills disponibles pour injection dans le system prompt.

    Format adapté pour le contexte LLM (compact, informatif).
    """
    skills = discover_skills()
    if not skills:
        return ""

    lines = ["## Compétences disponibles (Skills)", ""]
    for skill_id, info in sorted(skills.items()):
        desc = info["description"][:120] if info["description"] else "(pas de description)"
        lines.append(f"- **{info['name']}** (`{skill_id}`) : {desc}")

    lines.append("")
    lines.append(
        "Pour activer un skill, mentionne son nom ou utilise `/skill <nom>`."
    )
    return "\n".join(lines)
