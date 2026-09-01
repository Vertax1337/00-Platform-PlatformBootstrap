# Project Branding – Azure DevOps Project Avatars

> **Status:** v1.9 Candidate. Project Branding ist für `00-Platform`, `10-Automation`, `20-IaC`, `99-LAB` und `CUST-*` code-seitig implementiert. Avatar-PUT, Project-Property-Marker und idempotenter `EXISTS`-Folgelauf wurden für die vier bisher gebrandeten Core-Projekte real bestätigt. `30-IDD` ist inzwischen ein Core-Projekt, besitzt im aktuell versionierten Brandingpaket aber noch kein freigegebenes `30-idd.png`; sein Branding bleibt deshalb ausdrücklich OPEN und wird nicht mit einem Fallback-Icon überschrieben.

## Zweck

`PlatformBootstrap` verwaltet die Azure-DevOps-Projekt-Avatare als Teil des gewünschten Plattformzustands, sobald für den jeweiligen Projekttyp ein freigegebenes und versioniertes Branding-Asset existiert.

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

30-IDD
→ OPEN: freigegebenes 30-idd.png noch nicht versioniert

99-LAB
→ assets/project-icons/99-lab.png

CUST-*
→ assets/project-icons/cust-generic.png
```

Alle Kundenprojekte verwenden zunächst dasselbe generische Customer-Icon.

Für `30-IDD` gilt bis zur Integration des freigegebenen Intune-Default-Deployment-Originalassets ausdrücklich:

```text
Project-/Repository-Provisioning
→ verwaltet

Project Branding
→ OPEN / keine Änderung
```

Es wird weder ein anderes Core-Icon als Fallback verwendet noch ein neues Brandingasset stillschweigend erfunden.

## Zentrale Implementierung

Die wiederverwendbare Branding-Logik liegt in:

```text
bootstrap/BSSE.AzureDevOps.Branding.ps1
```

Die Projekt-Provisionierung ruft für Projekte mit freigegebenem Branding ausschließlich diese zentrale Funktion auf:

```text
Ensure-BSSEProjectAvatar
```

Verwendung:

- `New-BSSEAzureDevOpsCore.ps1` provisioniert `00-Platform`, `10-Automation`, `20-IaC`, `30-IDD` und `99-LAB`; für `30-IDD` wird bis zum freigegebenen Asset ein expliziter `OPEN`-Status ausgegeben und kein Avatar-Write ausgeführt,
- `New-BSSECustomerProject.ps1` verwendet die Brandingfunktion für alle `CUST-*`-Projekte.

Damit bleibt die bestehende fail-closed Brandinglogik unverändert. Der neue Core-Projekttyp wird nicht durch ein fehlendes, noch nicht freigegebenes Asset künstlich blockiert.

## Microsoft-API

Für das Setzen des Projekt-Avatars wird die dokumentierte Azure-DevOps-Core-API verwendet:

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

Microsoft dokumentiert für `Set Project Avatar` HTTP 200 als Erfolg. Der reale BSSE-CloudOps-Apply am 13.08.2026 lieferte für den Avatar-PUT von `00-Platform` HTTP 204. PlatformBootstrap akzeptiert deshalb für diesen Endpoint explizit HTTP 200 und HTTP 204; der gewünschte Zustand gilt trotzdem erst nach erfolgreichem Marker-Write und Marker-Readback als verifiziert.

Für den verwalteten SHA-256-Marker werden die offiziellen Project-Properties-APIs verwendet:

```text
GET   https://dev.azure.com/{organization}/_apis/projects/{projectId}/properties?keys=...&api-version=7.1-preview.1
PATCH https://dev.azure.com/{organization}/_apis/projects/{projectId}/properties?api-version=7.1-preview.1
```

Der PATCH erwartet `application/json-patch+json` und einen `JsonPatchDocument`-Body als JSON-Array, auch wenn nur eine Operation enthalten ist:

```json
[
  {
    "op": "add",
    "path": "/BSSE.PlatformBootstrap.ProjectAvatarSha256",
    "value": "<sha256>"
  }
]
```

Ein früher realer Apply erreichte diesen PATCH und erhielt HTTP 500, weil das zuvor mit `@(...) | ConvertTo-Json` erzeugte ein-elementige Array von PowerShell in der Pipeline enumeriert und als einzelnes JSON-Objekt serialisiert wurde. Der Code verwendet deshalb `ConvertTo-Json -InputObject $patchDocument` und prüft zusätzlich, dass der serialisierte Body tatsächlich mit `[` beginnt. Nach dieser Korrektur wurden Marker-PATCH/GET und Idempotenz für alle vier gebrandeten Core-Projekte real erfolgreich verifiziert.

Die bestehende Bootstrap-Authentifizierung wird weiterverwendet:

- lokal: Azure-CLI-/Entra-Kontext,
- Pipeline: bevorzugt AzureCLI@3 + Azure-DevOps-Service-Connection/WIF,
- optionaler Pipeline-Kompatibilitätsweg: explizit gemapptes `SYSTEM_ACCESSTOKEN`.

Es wird kein zusätzliches PAT oder Client Secret für Project Branding eingeführt.

## Idempotenz

Die Azure-DevOps-Core-REST-Referenz dokumentiert für **Project Avatars** Set und Remove, aber keinen belastbaren Project-Avatar-GET-Endpunkt.

Daher wird kein undokumentierter Avatar-Readback verwendet.

Stattdessen verwaltet PlatformBootstrap pro gebrandetem Projekt folgende Project Property:

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
               JSON-Patch als Array serialisieren
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

Eine manuelle Änderung des Projekt-Avatars außerhalb von PlatformBootstrap kann mit der aktuell verwendeten dokumentierten Core-API nicht zuverlässig als Avatar-Drift gelesen werden.

Wenn jemand den Avatar manuell ändert, die Bootstrap-Property aber unverändert bleibt, sieht der nächste Bootstrap-Lauf weiterhin einen passenden verwalteten Hash-Marker.

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
JSON-Patch garantiert Array?
    ↓
Marker schreibbar?
    ↓
Marker erneut lesbar und exakt verifiziert?
```

Ein neuer Projekt-Dry-Run kann das Projekt naturgemäß noch nicht auflösen. In diesem Zustand wird nach erfolgreicher Asset-Validierung der geplante Avatar-Write als `PLAN ... after project creation` ausgegeben.

Bei Apply wird das Projekt mit Retry erneut aufgelöst; fehlt anschließend weiterhin eine Project-ID, wird der Lauf blockiert.

Für einen Core-Projekteintrag mit ausdrücklich dokumentiertem `BrandingPendingReason` wird diese Brandingpipeline nicht aufgerufen. Stattdessen zeigt `New-BSSEAzureDevOpsCore.ps1` den offenen Brandingzustand an und verändert den bestehenden Avatar nicht.

## Fehlerbehandlung

Project Branding ist nach Freigabe eines Assets ein verwalteter Bestandteil des Sollzustands und keine rein kosmetische Best-Effort-Aktion.

Daher gilt für gebrandete Projekttypen:

```text
Asset fehlt/ist ungültig
→ BLOCKED / Fehler

Projekt oder Project-ID nach Apply nicht ermittelbar
→ BLOCKED / Fehler

REST-/Berechtigungsfehler
→ BLOCKED / Fehler

Avatar PUT nicht mit HTTP 200 oder 204 bestätigt
→ BLOCKED / Fehler

JSON-Patch nicht als Array serialisierbar
→ BLOCKED / Fehler

Hash-Marker nicht schreib-/les-/verifizierbar
→ BLOCKED / Fehler
```

Ein **explizit dokumentierter** Core-Projekttyp ohne bereits freigegebenes/versioniertes Brandingasset ist davon getrennt: Das Provisioning bleibt möglich, der Avatar bleibt unverändert und der Status wird sichtbar als `OPEN` ausgegeben.

Der Bootstrap rollt bereits vorher erfolgreich angelegte Azure-DevOps-Objekte nicht zurück oder löscht sie. Ein erneuter Lauf kann den noch fehlenden Branding-Sollzustand nach Behebung der Ursache fortsetzen.

## Berechtigungen

Die ausführende Identität benötigt ausreichende Azure-DevOps-Projektrechte für das Aktualisieren des Projekt-Avatars. Der Avatar-REST-Endpoint dokumentiert den OAuth-Scope `vso.project_manage`.

Für den idempotenten Hash-Marker werden zusätzlich die offiziellen Project-Properties-APIs verwendet:

```text
GET   .../_apis/projects/{projectId}/properties
PATCH .../_apis/projects/{projectId}/properties
```

Für die Project-Property-Verwaltung muss die ausführende Identität die entsprechenden Projektberechtigungen besitzen (`Manage project properties`).

Für neu durch PlatformBootstrap erzeugte `CUST-*`-Projekte wird die bereits bestehende Projekt-Ersteller-/Project-Administrator-Logik weiterverwendet.

## Asset-Integrität

Das bisher freigegebene Brandingpaket wurde vor der Implementierung geprüft. Es enthält exakt fünf PNGs unter `assets/project-icons/`; alle fünf sind valide PNGs mit 1254×1254 Pixeln im RGB-Modus.

Der Regressionstest `tests/Test-BSSEProjectBranding.ps1` fixiert die geprüften Originalgrößen und SHA-256-Werte. Die fünf freigegebenen Source Assets sind in `main` versioniert und bytegenau gegen die geprüften Originale abgeglichen.

`30-IDD` war nicht Bestandteil dieses fünfteiligen Brandingpakets. Das vorhandene Intune-Default-Deployment-Logo muss deshalb als eigener, bewusst freigegebener Asset-Schritt integriert werden. Erst dann werden `30-idd.png`, Mapping und Hash-Test gemeinsam erweitert.

## Verifikationsstatus

### Bereits verifiziert

- ursprünglicher ZIP-Inhalt und Pfade,
- PNG-Gültigkeit, Dimension und Farbmodus der fünf Source Assets,
- Bytegrößen und SHA-256 der fünf Source Assets,
- Assets im `main`-Git-Tree bytegenau gegen die geprüften Originale abgeglichen,
- Core-/Customer-Provisionierungsintegration code-seitig,
- Avatar-PUT akzeptiert den real beobachteten HTTP-204-Erfolg,
- Marker-PATCH/GET nach JSON-Patch-Korrektur real erfolgreich,
- Branding für `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB` real angewendet,
- Folge-Apply erkennt die vier gebrandeten Core-Projekte idempotent als `EXISTS`.

### Code-seitig implementiert

- zentrales Mapping,
- Asset-/PNG-Validierung,
- SHA-256-Markerstrategie,
- Core-Projektintegration,
- Customer-Projektintegration,
- Dry-Run-/Apply-/Fail-Closed-Verhalten,
- Regressionstest mit den freigegebenen Asset-Hashes,
- expliziter Core-Projektzustand für noch nicht freigegebenes Branding ohne Fallback-Write.

### Noch offen

- freigegebenes Intune-Default-Deployment-Originalasset als `assets/project-icons/30-idd.png` integrieren,
- `Get-BSSEProjectAvatarAssetRelativePath` um `30-IDD` erweitern,
- Regressionstest um Größe/SHA-256 von `30-idd.png` erweitern,
- `BrandingPendingReason` für `30-IDD` aus dem Core-Vertrag entfernen,
- Branding für `30-IDD` per Dry Run → Apply → Readback → idempotentem Folge-Dry-Run verifizieren,
- tatsächliche Anzeige des 30-IDD-Icons in der Azure-DevOps-UI bestätigen.
