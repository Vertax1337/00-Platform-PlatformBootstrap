# Project Branding – Azure DevOps Project Avatars

## Zweck

`PlatformBootstrap` verwaltet die Azure-DevOps-Projekt-Avatare als Teil des gewünschten Plattformzustands.

Die Branding-Assets liegen versioniert im Repository unter:

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

Der Request Body enthält `ProjectAvatar.image` als Bytearray.

Microsoft dokumentiert für diesen Endpoint den OAuth-Scope:

```text
vso.project_manage
```

Referenz:

```text
https://learn.microsoft.com/rest/api/azure/devops/core/avatar/set-project-avatar?view=azure-devops-rest-7.1
```

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
               HTTP 200 erforderlich
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
Avatar API HTTP 200?
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

Avatar PUT nicht mit HTTP 200 bestätigt
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

Die vorgesehenen Source Assets aus dem Branding-Paket werden unverändert unter `assets/project-icons/` versioniert.

Für Regressionstests werden die erwarteten SHA-256-Werte festgehalten. Damit kann erkannt werden, wenn ein Asset versehentlich ersetzt oder verändert wurde.

## Verifikationsstatus

### Code-seitig implementiert

- zentrales Mapping,
- Asset-/PNG-Validierung,
- SHA-256-Markerstrategie,
- Core-Projektintegration,
- Customer-Projektintegration,
- Dry-Run-/Apply-/Fail-Closed-Verhalten.

### Noch nicht runtime-verifiziert

Bis zum ersten realen Azure-DevOps-Lauf dürfen folgende Punkte nicht als bestätigt gelten:

- tatsächlicher Avatar-PUT in `BSSE-CloudOps`,
- tatsächliche Berechtigung der lokalen bzw. WIF-Pipeline-Identität für Project Avatar + Project Properties,
- tatsächlicher Project-Property-Write/Readback in der Zielorganisation,
- tatsächliche Anzeige der Icons in der Azure-DevOps-UI.
