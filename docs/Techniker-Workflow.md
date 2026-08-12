# Techniker-Workflow – PlatformBootstrap

## Ziel

Der produktive Kunden-Onboarding-Prozess soll ohne lokalen Download des Bootstrap-Repositories funktionieren.

Der Techniker startet das Onboarding zentral in Azure DevOps über die Pipeline:

```text
00-Platform
└── Pipeline: Customer-Onboarding
    └── YAML: /pipelines/customer-onboarding.yml
```

Das zugrunde liegende PowerShell-Skript bleibt identisch zur lokalen Entwicklungs- und Fehleranalyse:

```text
bootstrap/New-BSSECustomerProject.ps1
```

## Ausführungsmodi

### Local

Für Entwicklung, Debugging und Bootstrap-Weiterentwicklung kann das Skript weiterhin lokal gestartet werden.

Die gemeinsame Authentifizierungslogik erkennt eine lokale Ausführung automatisch und verwendet:

1. vorhandenen Azure-CLI-Kontext,
2. passenden gecachten Tenant-/Subscription-Kontext,
3. falls erforderlich gezielten interaktiven Login,
4. lokalen Browser-Fallback nur für die Erstinitialisierung.

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
Kundendaten / Module / Firewalls eingeben
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
- AVD
- Vaultwarden
- Firewalls (optional, kommasepariert)

## Sicherheitsmodell

Die Pipeline darf nicht mit einer globalen, unbeschränkten Owner-/Contributor-Identität betrieben werden.

Die für PlatformBootstrap verwendete Azure-DevOps-Service-Connection erhält ausschließlich die für die Provisionierungsaufgaben erforderlichen Azure-DevOps-Berechtigungen.

Zielname:

```text
sc-platform-bootstrap-azdo
```

## Aktueller Implementierungsstatus

### Implementiert im Repository

- automatische Local-/Pipeline-Erkennung in `BSSE.AzureDevOps.Common.ps1`
- lokale Authentifizierung bleibt kompatibel
- Pipeline-Modus ohne interaktive Logins
- AzureCLI@3-/Service-Connection-Erkennung
- System.AccessToken-Kompatibilitätsfallback
- `pipelines/customer-onboarding.yml`
- Validate → Dry Run → Approval → Apply → Verify

### Noch in Azure DevOps einzurichten / zu verifizieren

- Azure DevOps Service Connection `sc-platform-bootstrap-azdo`
- Microsoft Entra Workload Identity Federation für diese Verbindung
- minimale Azure-DevOps-Berechtigungen der Service-Connection-Identität
- Registrierung der Pipeline aus `/pipelines/customer-onboarding.yml`
- echter Pipeline-Dry-Run
- echter Apply-Test gegen eine dafür vorgesehene Test-Provisionierung
- Verifikation des Post-Apply-Idempotenzchecks

Bis diese Punkte tatsächlich ausgeführt wurden, ist der Techniker-Pipelineweg als implementiert im Code, aber noch nicht produktiv verifiziert zu bewerten.
