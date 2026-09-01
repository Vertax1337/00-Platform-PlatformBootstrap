# Project Branding – Azure DevOps Project Avatars

> **Status:** v1.9 Candidate. Project Branding ist für `00-Platform`, `10-Automation`, `20-IaC`, `30-IDD`, `99-LAB` und `CUST-*` code-seitig implementiert. Avatar-PUT, Project-Property-Marker und idempotenter `EXISTS`-Folgelauf wurden für die vier bisher runtime-geprüften Core-Projekte real bestätigt. Das neue `30-IDD`-Asset ist versioniert und code-seitig aktiviert; dessen Azure-DevOps-Apply/Readback ist noch offen.

## Zweck

`PlatformBootstrap` verwaltet die Azure-DevOps-Projekt-Avatare als Teil des gewünschten Plattformzustands für Projekttypen mit freigegebenem und versioniertem Branding-Asset.

Versionierte Branding-Assets:

```text
assets/
└── project-icons/
    ├── 00-platform.png
    ├── 10-automation.png
    ├── 20-iac.png
    ├── 30-idd.png
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
→ assets/project-icons/30-idd.png

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

Die Projekt-Provisionierung ruft für die verwalteten Projekttypen diese zentrale Funktion auf:

```text
Ensure-BSSEProjectAvatar
```

Verwendung:

- `New-BSSEAzureDevOpsCore.ps1` provisioniert `00-Platform`, `10-Automation`, `20-IaC`, `30-IDD` und `99-LAB` und führt für alle fünf Core-Projekte denselben Brandingvertrag aus,
- `New-BSSECustomerProject.ps1` verwendet die Brandingfunktion für alle `CUST-*`-Projekte.

Damit gilt für `30-IDD` jetzt derselbe fail-closed Brandingpfad wie für die übrigen Core-Projekte.

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

Ein früher realer Apply erreichte diesen PATCH und erhielt HTTP 500, weil das zuvor mit `@(...) | ConvertTo-Json` erzeugte ein-elementige Array von PowerShell in der Pipeline enumeriert und als einzelnes JSON-Objekt serialisiert wurde. Der Code verwendet deshalb `ConvertTo-Json -InputObject $patchDocument` und prüft zusätzlich, dass der serialisierte Body tatsächlich mit `[` beginnt. Nach dieser Korrektur wurden Marker-PATCH/GET und Idempotenz für die vier bisher runtime-geprüften Core-Projekte real erfolgreich verifiziert.

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

## Fehlerbehandlung

Project Branding ist nach Freigabe eines Assets ein verwalteter Bestandteil des Sollzustands und keine rein kosmetische Best-Effort-Aktion.

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

JSON-Patch nicht als Array serialisierbar
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

Für neu durch PlatformBootstrap erzeugte `CUST-*`-Projekte wird die bereits bestehende Projekt-Ersteller-/Project-Administrator-Logik weiterverwendet.

## Asset-Integrität

Das ursprünglich freigegebene Brandingpaket enthält fünf PNGs. Diese fünf ursprünglichen Assets bleiben im Regressionstest über ihre geprüften Dateigrößen und SHA-256-Werte fixiert.

Das `30-IDD`-Asset wurde anschließend separat durch den Projektverantwortlichen in `assets/project-icons/30-idd.png` versioniert. Der aktuell versionierte Stand besitzt:

```text
Dateigröße: 1074185 Byte
Git Blob:   8cbe66d5b92b864ddc136adb7e643e4e8055b824
```

Der Regressionstest `tests/Test-BSSEProjectBranding.ps1` pinnt für dieses nachträglich ergänzte Asset die Dateigröße und exakte Git-Blob-Identität, prüft die PNG-Signatur und prüft das Mapping `30-IDD → assets/project-icons/30-idd.png`. Der für die Azure-DevOps-Project-Property benötigte SHA-256 wird von der produktiven Brandinglogik direkt aus den versionierten Bytes berechnet.

## Verifikationsstatus

### Bereits verifiziert

- ursprünglicher ZIP-Inhalt und Pfade,
- PNG-Gültigkeit, Dimension und Farbmodus der fünf ursprünglichen Source Assets,
- Bytegrößen und SHA-256 der fünf ursprünglichen Source Assets,
- diese fünf Assets im Git-Tree bytegenau gegen die geprüften Originale abgeglichen,
- `30-idd.png` als Repository-Asset vorhanden; GitHub meldet Dateigröße `1074185` Byte und Git-Blob `8cbe66d5b92b864ddc136adb7e643e4e8055b824`,
- Core-/Customer-Provisionierungsintegration code-seitig,
- Avatar-PUT akzeptiert den real beobachteten HTTP-204-Erfolg,
- Marker-PATCH/GET nach JSON-Patch-Korrektur real erfolgreich,
- Branding für `00-Platform`, `10-Automation`, `20-IaC` und `99-LAB` real angewendet,
- Folge-Apply erkennt diese vier runtime-geprüften Core-Projekte idempotent als `EXISTS`.

### Code-seitig implementiert

- zentrales Mapping einschließlich `30-IDD`,
- Asset-/PNG-Validierung,
- SHA-256-Markerstrategie,
- Core-Projektintegration,
- Customer-Projektintegration,
- Dry-Run-/Apply-/Fail-Closed-Verhalten,
- Regressionstest für alle sechs aktuell verwalteten Source Assets,
- `30-IDD` verwendet denselben produktiven Brandingpfad wie die übrigen Core-Projekte.

### Noch offen

- Branding für `30-IDD` per Dry Run → Apply → Marker-Readback → idempotentem Folge-Dry-Run in Azure DevOps verifizieren,
- tatsächliche Anzeige des `30-IDD`-Icons in der Azure-DevOps-UI bestätigen.
