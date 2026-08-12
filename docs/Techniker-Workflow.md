# Techniker-Workflow – PlatformBootstrap

## Ziel

Der produktive Kunden-Onboarding-Prozess soll ohne lokalen Download des Bootstrap-Repositories funktionieren.

Der Techniker startet das Onboarding zentral in Azure DevOps über die Pipeline:

```text
00-Platform
└── Pipeline: Customer-Onboarding
    └── YAML: /pipelines/customer-onboarding.yml
```

Das zugrunde liegende PowerShell-Backend bleibt identisch zur lokalen Entwicklungs- und Fehleranalyse:

```text
bootstrap/New-BSSECustomerProject.ps1
```

Für die lokale Entwicklungs-/Testausführung existiert zusätzlich ein interaktives Frontend:

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

Dieses Frontend sammelt dieselben fachlichen Eingaben wie die Azure-DevOps-Pipeline und ruft anschließend dasselbe Backend auf.

## Verbindliche Architekturgrenze

`Customer-Onboarding` ist **kein IaC-Deployment-Workflow**.

Diese Pipeline behandelt ausschließlich:

- Kundenprojekt / Kunden-Repositories,
- `AzureDocumentation`,
- `OPNsenseDocumentation`,
- optionale OPNsense RAW-Backup-Repositories `Firewall-*`.

Nicht Bestandteil dieses Workflows:

```text
AVD
Vaultwarden
```

AVD und Vaultwarden sind IaC-Produkte unter `20-IaC`. Sie werden über separate Deployment-Workflows mit eigenen Deployment-Service-Connections, Plan/What-If, Approval, Deploy und Verify behandelt.

## Ausführungsmodi

### Local

Für Entwicklung, Debugging und Bootstrap-Weiterentwicklung wird bevorzugt das interaktive Frontend gestartet:

```powershell
pwsh.exe -ExecutionPolicy Bypass `
  -File ".\bootstrap\Start-BSSECustomerOnboarding.ps1"
```

Das Frontend fragt ab:

- CustomerNumber
- CustomerName
- CustomerSlug (optional)
- TenantId (optional)
- AzureDocumentation
- OPNsenseDocumentation
- Firewalls (optional, kommasepariert)

Der lokale Ablauf entspricht der Pipeline-Semantik:

```text
Eingaben
    ↓
Dry Run
    ↓
Dry-Run-Ausgabe prüfen
    ↓
lokale Bestätigung
    ↓
Apply
    ↓
Post-Apply Dry Run
    ↓
Idempotenz-Verifikation
```

Enthält der Dry Run `[BLOCKED]`, wird Apply lokal nicht angeboten. Enthält der Dry Run keinen `[PLAN]`-Zustand, wird kein Apply benötigt.

Die gemeinsame Authentifizierungslogik erkennt die lokale Ausführung automatisch und verwendet:

1. vorhandenen Azure-CLI-Kontext,
2. passenden gecachten Tenant-/Subscription-Kontext,
3. falls erforderlich gezielten interaktiven Login,
4. lokalen Browser-Fallback nur für die Erstinitialisierung.

Das Backend kann weiterhin direkt mit CLI-Parametern aufgerufen werden. Das ist vor allem für Debugging, Automatisierung und gezielte Regressionstests vorgesehen.

### Pipeline

In Azure Pipelines wird die Pipeline-Umgebung automatisch erkannt.

Interaktive Anmeldung und Browser-Fallback sind dort grundsätzlich deaktiviert.

Priorität der Pipeline-Authentifizierung:

1. bereits hergestellte Azure-DevOps-Service-Connection-/AzureCLI@3-Session,
2. optionaler Kompatibilitätsfallback über `SYSTEM_ACCESSTOKEN`, sofern dieser explizit in den Skriptprozess gemappt wurde,
3. andernfalls Fail Closed mit eindeutiger Fehlermeldung.

Bevorzugter Zielzustand ist eine Azure DevOps Service Connection mit Microsoft Entra Workload Identity Federation und `AzureCLI@3` mit `connectionType: azureDevOps`.

## Techniker-Ablauf

```text
Run pipeline
    ↓
Kundendaten / Dokumentationsmodule / Firewalls eingeben
    ↓
Validate
    ↓
Dry Run
    ↓
Dry-Run-Ausgabe prüfen
    ↓
Manual Approval
    ↓
Apply
    ↓
Post-Apply Dry Run
    ↓
Idempotenz-Verifikation
```

Der Post-Apply-Dry-Run schlägt fehl, wenn weiterhin ein `[PLAN]`, `[CREATE]`, `[RENAME]` oder `[BLOCKED]` Zustand erkannt wird.

## Pipeline-Parameter

- CustomerNumber
- CustomerName
- CustomerSlug (optional)
- TenantId (optional)
- AzureDocumentation
- OPNsenseDocumentation
- Firewalls (optional, kommasepariert)

AVD- oder Vaultwarden-Parameter sind in dieser Pipeline bewusst nicht vorhanden.

## Sicherheitsmodell

Die Pipeline darf nicht mit einer globalen, unbeschränkten Owner-/Contributor-Identität betrieben werden.

Die für PlatformBootstrap verwendete Azure-DevOps-Service-Connection erhält ausschließlich die für die Provisionierungsaufgaben erforderlichen Azure-DevOps-Berechtigungen.

Zielname:

```text
sc-platform-bootstrap-azdo
```

Diese Identität ist von späteren IaC-Deployment-Identitäten getrennt, z. B.:

```text
sc-cust<CustomerNumber>-avd-deploy
sc-cust<CustomerNumber>-vaultwarden-deploy
```

## Aktueller Implementierungsstatus

### Implementiert im Repository

- automatische Local-/Pipeline-Erkennung in `BSSE.AzureDevOps.Common.ps1`
- lokale Authentifizierung bleibt kompatibel
- lokales interaktives Frontend `Start-BSSECustomerOnboarding.ps1`
- lokale Parameterabfrage entspricht fachlich der Pipeline-Maske
- lokaler Ablauf Dry Run → Bestätigung → Apply → Verify
- Pipeline-Modus ohne interaktive Logins
- AzureCLI@3-/Service-Connection-Erkennung
- System.AccessToken-Kompatibilitätsfallback
- `pipelines/customer-onboarding.yml`
- Validate → Dry Run → Approval → Apply → Verify
- Pipeline-Parameter ausschließlich für Kunden-/Dokumentations-Onboarding
- AVD/Vaultwarden aus Customer-Onboarding entfernt
- `New-BSSECustomerProject.ps1` akzeptiert nur noch `AzureDocumentation` und `OPNsenseDocumentation`; IaC-Produkte werden explizit abgewiesen

### Noch in Azure DevOps einzurichten / zu verifizieren

- Azure DevOps Service Connection `sc-platform-bootstrap-azdo`
- Microsoft Entra Workload Identity Federation für diese Verbindung
- minimale Azure-DevOps-Berechtigungen der Service-Connection-Identität
- Registrierung der Pipeline aus `/pipelines/customer-onboarding.yml`
- echter Pipeline-Dry-Run
- echter Apply-Test gegen eine dafür vorgesehene Test-Provisionierung
- Verifikation des Post-Apply-Idempotenzchecks

### Noch funktional zu ergänzen

`New-BSSECustomerProject.ps1 -Apply` erzeugt das CustomerConfiguration-Dokumentations-Scaffold derzeit unter `generated-customers/<Projekt>` im lokalen Dateisystem des ausführenden Prozesses.

Bei lokaler Ausführung bleibt dieses Ergebnis auf dem Entwickler-Endpunkt erhalten. Bei einem Microsoft-hosted Pipeline-Agent ist dieser Arbeitsbereich jedoch nicht als dauerhafte Kundenkonfiguration zu betrachten.

Vor produktiver Nutzung des Technikerwegs muss deshalb noch ein kontrollierter Persistierungsweg umgesetzt werden. Ziel ist, den generierten und validierten Scaffold sicher in das jeweilige Kunden-Repository `CustomerConfiguration` zu überführen, ohne bestehende Inhalte oder Git-Historie unkontrolliert zu überschreiben.

Die konkrete Push-/Merge-Strategie ist noch offen und wird nicht durch diesen Authentifizierungs-/Pipeline-Change vorweggenommen.

## Separater IaC-Technikerweg

Für AVD und Vaultwarden ist ein eigener Techniker-/Deployment-Workflow vorgesehen. Dieser ist **noch offen** und wird nicht in `customer-onboarding.yml` integriert.

Zielprinzip:

```text
20-IaC Produkt
    ↓
Validate
    ↓
Lint / Security
    ↓
Plan / What-If
    ↓
Approval
    ↓
Deploy
    ↓
Verify
```

Bis die Azure-DevOps-seitigen Schritte tatsächlich ausgeführt wurden, ist der Customer-Onboarding-Pipelineweg als implementiert im Code, aber noch nicht produktiv verifiziert zu bewerten.
