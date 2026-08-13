# Project Branding – Azure DevOps Project Avatars

> **Status:** v1.9 Candidate auf `main`. Code, Mapping und die fünf freigegebenen Original-PNGs sind versioniert. Der erste reale Apply hat den Avatar-PUT für `00-Platform` erreicht und von Azure DevOps HTTP 204 erhalten. Die Implementierung akzeptiert deshalb nun HTTP 200 oder 204 als erfolgreichen Avatar-PUT; Marker-Write/Readback und vollständige Runtime-Verifikation bleiben noch offen.

## Zweck

`PlatformBootstrap` verwaltet die Azure-DevOps-Projekt-Avatare als Teil des gewünschten Plattformzustands.

Versionierte Branding-Assets:

```text
assets/
└── project-icons/
    ├── 00-platform.png
    ├── 10-automation.png
    ├── 20-iac.png
    ├── 99-lab.png
    └── cust-generic.png
```

## Verbindliches Mapping

```text
00-Platform
→ assets/project-icons/00-platform.png

10-Automation
→ assets/project-icons/10-automation.png

20-IaC
→ assets/project-icons/20-iac.png

99-LAB
→ assets/project-icons/99-lab.png

CUST-*
→ assets/project-icons/cust-generic.png
```

Alle Kundenprojekte verwenden zunächst dasselbe generische Customer-Icon.

## Zentrale Implementierung

Die wiederverwendbare Branding-Logik liegt in:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

Die Projekt-Provisionierung ruft ausschließlich diese zentrale Funktion auf:

```text
Ensure-BSSEProjectAvatar
```

Verwendung:

- `New-BSSEAzureDevOpsCore.ps1` für `00-Platform`, `10-Automation`, `20-IaC`, `99-LAB`,
- `New-BSSECustomerProject.ps1` für alle `CUST-*`-Projekte.

Damit gilt dieselbe Logik für bereits vorhandene und neu angelegte Projekte.

## Microsoft-API

Für das Setzen des Projekt-Avatars wird die aktuell dokumentierte Azure-DevOps-Core-API verwendet:

```text
PUT https://dev.azure.com/{organization}/_apis/projects/{projectId}/avatar?api-version=7.1-preview.1
```

Der Request Body enthält `ProjectAvatar.image` als Bytearray (`number[]`).

Microsoft dokumentiert für diesen Endpoint den OAuth-Scope:

```text
vso.project_manage
```

Referenz:

```text
https://learn.microsoft.com/rest/api/azure/devops/core/avatar/set-project-avatar?view=azure-devops-rest-7.1
```

Microsoft dokumentiert für `Set Project Avatar` aktuell HTTP 200 als Erfolg. Der erste reale BSSE-CloudOps-Apply am 13.08.2026 lieferte für den Avatar-PUT von `00-Platform` jedoch HTTP 204. Da beide Statuscodes erfolgreiche 2xx-Antworten darstellen und der gewünschte Zustand anschließend zusätzlich über den verwalteten Marker verifiziert wird, akzeptiert PlatformBootstrap für diesen Endpoint explizit HTTP 200 und HTTP 204.

Die bestehende Bootstrap-Authentifizierung wird weiterverwendet:

- lokal: Azure-CLI-/Entra-Kontext,
- Pipeline: bevorzugt AzureCLI@3 + Azure-DevOps-Service-Connection/WIF,
- optionaler Pipeline-Kompatibilitätsweg: explizit gemapptes `SYSTEM_ACCESSTOKEN`.

Es wird kein zusätzliches PAT oder Client Secret für Project Branding eingeführt.

## Idempotenz

Die Azure-DevOps-Core-REST-Referenz dokumentiert für **Project Avatars** aktuell Set und Remove, aber keinen Project-Avatar-GET-Endpunkt.

Daher wird kein nicht dokumentierter Avatar-Readback verwendet.

Stattdessen verwaltet PlatformBootstrap pro Projekt folgende Project Property:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Der Wert ist der SHA-256-Hash des vorgesehenen PNG-Assets.

Ablauf:

```text
Asset bestimmen
    ↓
PNG validieren
    ↓
SHA-256 berechnen
    ↓
Project Property lesen
    ↓
Hash identisch?
 ├─ Ja → EXISTS / kein Avatar-Write
 └─ Nein
      ↓
      Dry Run → PLAN
      Apply   → Avatar PUT
                 ↓
               HTTP 200 oder 204 erforderlich
                 ↓
               SHA-256-Property schreiben
                 ↓
               Property erneut lesen
                 ↓
               exakten Hash verifizieren
```

Der Hash-Marker wird **erst nach einem erfolgreichen Avatar-PUT** gespeichert.

Dadurch erzeugt ein normaler wiederholter Bootstrap-Lauf keinen unnötigen Avatar-Write.

### Bekannte technische Grenze

Eine manuelle Änderung des Projekt-Avatars außerhalb von PlatformBootstrap kann mit der aktuell dokumentierten Core-API nicht zuverlässig als Avatar-Drift gelesen werden.

Wenn jemand den Avatar manuell ändert, die Bootstrap-Property aber unverändert bleibt, sieht der nächste Bootstrap-Lauf deshalb weiterhin einen passenden verwalteten Hash-Marker.

Diese externe Drift wird erst korrigiert, wenn beispielsweise:

- der verwaltete Marker entfernt/geändert wird,
- sich das Asset ändert und damit ein neuer SHA-256 entsteht,
- eine zukünftige offiziell unterstützte Project-Avatar-Readback-API eine belastbare Byte-/Hash-Prüfung ermöglicht.

Es wird bewusst **kein** undokumentierter Endpoint verwendet, nur um diese Drift scheinbar erkennen zu können.

## Validierung

Vor einem Avatar-Write prüft der Bootstrap mindestens:

```text
Mapping vorhanden?
    ↓
Asset vorhanden?
    ↓
PNG-Signatur gültig?
    ↓
SHA-256 berechnet?
    ↓
Projekt vorhanden?
    ↓
Project-ID ermittelt?
    ↓
Marker lesbar?
    ↓
Avatar API HTTP 200/204?
    ↓
Marker schreibbar?
    ↓
Marker erneut lesbar und exakt verifiziert?
```

Ein neuer Projekt-Dry-Run kann das Projekt naturgemäß noch nicht auflösen. In diesem Zustand wird nach erfolgreicher Asset-Validierung der geplante Avatar-Write als `PLAN ... after project creation` ausgegeben.

Bei Apply wird das Projekt mit Retry erneut aufgelöst; fehlt anschließend weiterhin eine Project-ID, wird der Lauf blockiert.

## Fehlerbehandlung

Project Branding ist ein verwalteter Bestandteil des Sollzustands und keine rein kosmetische Best-Effort-Aktion.

Daher gilt:

```text
Asset fehlt/ist ungültig
→ BLOCKED / Fehler

Projekt oder Project-ID nach Apply nicht ermittelbar
→ BLOCKED / Fehler

REST-/Berechtigungsfehler
→ BLOCKED / Fehler

Avatar PUT nicht mit HTTP 200 oder 204 bestätigt
→ BLOCKED / Fehler

Hash-Marker nicht schreib-/les-/verifizierbar
→ BLOCKED / Fehler
```

Der Bootstrap rollt bereits vorher erfolgreich angelegte Azure-DevOps-Objekte nicht zurück oder löscht sie. Ein erneuter Lauf kann den noch fehlenden Branding-Sollzustand nach Behebung der Ursache fortsetzen.

## Berechtigungen

Die ausführende Identität benötigt ausreichende Azure-DevOps-Projektrechte für das Aktualisieren des Projekt-Avatars. Der Avatar-REST-Endpoint dokumentiert den OAuth-Scope `vso.project_manage`.

Für den idempotenten Hash-Marker werden zusätzlich die offiziellen Project-Properties-APIs verwendet:

```text
GET   .../_apis/projects/{projectId}/properties
PATCH .../_apis/projects/{projectId}/properties
```

Für die Project-Property-Verwaltung muss die ausführende Identität die entsprechenden Projektberechtigungen besitzen (`Manage project properties`).

Für neu durch PlatformBootstrap erzeugte `CUST-*`-Projekte wird die bereits bestehende Projekt-Ersteller-/Project-Administrator-Logik weiterverwendet. Die reale Rechtewirkung wird erst mit dem Azure-DevOps-Runtime-Test als verifiziert markiert.

## Asset-Integrität

Die angehängte ZIP wurde vor der Implementierung geprüft. Sie enthält exakt fünf PNGs unter `assets/project-icons/`; alle fünf sind valide PNGs mit 1254×1254 Pixeln im RGB-Modus.

Der Regressionstest `tests/Test-BSSEProjectBranding.ps1` fixiert die geprüften Originalgrößen und SHA-256-Werte. Die fünf freigegebenen Source Assets sind inzwischen in `main` versioniert und bytegenau gegen die zuvor geprüften Originale abgeglichen.

## Verifikationsstatus

### Bereits verifiziert

- ZIP-Inhalt und Pfade,
- PNG-Gültigkeit, Dimension und Farbmodus der fünf Source Assets,
- Bytegrößen und SHA-256 der fünf Source Assets,
- Assets im `main`-Git-Tree bytegenau gegen die geprüften Originale abgeglichen,
- Core-/Customer-Provisionierungsintegration code-seitig in `main`,
- realer Avatar-PUT für `00-Platform` wurde am 13.08.2026 erreicht,
- reale Azure-DevOps-Antwort auf diesen PUT: HTTP 204.

### Code-seitig implementiert

- zentrales Mapping,
- Asset-/PNG-Validierung,
- SHA-256-Markerstrategie,
- Core-Projektintegration,
- Customer-Projektintegration,
- Dry-Run-/Apply-/Fail-Closed-Verhalten,
- Regressionstest mit den freigegebenen Asset-Hashes,
- Avatar-PUT akzeptiert dokumentiertes HTTP 200 sowie den real beobachteten HTTP-204-Erfolg.

### Noch offen

- `tests/Test-BSSEProjectBranding.ps1` lokal ausführen,
- korrigierten Apply erneut ausführen,
- Project-Property-Marker für `00-Platform` schreiben und per GET exakt verifizieren,
- Branding für `10-Automation`, `20-IaC` und `99-LAB` durchlaufen,
- tatsächliche Anzeige der Icons in der Azure-DevOps-UI bestätigen,
- anschließend idempotenten Dry Run ohne verbleibenden Branding-PLAN verifizieren.

### Noch nicht runtime-verifiziert

Bis zum nächsten realen Azure-DevOps-Lauf dürfen folgende Punkte nicht als bestätigt gelten:

- erfolgreicher Marker-PATCH/GET-Readback in `BSSE-CloudOps`,
- vollständiger Branding-Apply für alle Core-Projekte,
- WIF-Pipeline-Identität für Project Avatar + Project Properties,
- tatsächliche Anzeige aller Icons in der Azure-DevOps-UI.
