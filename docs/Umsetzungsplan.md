# Umsetzungsplan – BSSE Azure DevOps Platform

**Status:** Source-of-Truth / v1.9 Candidate in Umsetzung  
**Version:** 1.9 Candidate  
**Stand:** 2026-08-13

> `main` ist der Arbeits- und Source-of-Truth-Branch. Dieser Plan enthält die bindenden Architekturentscheidungen, den bestätigten Runtime-Stand und die offenen Umsetzungsschritte. Detaildiagnosen werden in den zugehörigen Fachdokumentationen gepflegt. Eine Phase gilt erst als abgeschlossen, wenn Fachdokumentation und dieser kanonische Plan denselben bestätigten Status enthalten.

## 1. Zielarchitektur

```text
00-Platform
├── PlatformBootstrap
├── PipelineTemplates
├── DocumentationEngine
├── SecurityValidation
└── SharedModules

10-Automation
├── 10-Automation-AzureInfrastructureCollector
└── 10-Automation-OPNsenseDocumentation

20-IaC
├── Vaultwarden
├── AVD-Accelerator
└── Shared-IaC-Modules

99-LAB
├── LabConfiguration
└── LabDocumentation

CUST-<CustomerNumber>-<CustomerSlug>
├── CustomerConfiguration
├── Documentation
└── Firewall-<CustomerSlug>-<SiteSlug>   # 0..n
```

### Verantwortungsgrenzen

`00-Platform` stellt die gemeinsame technische Plattform bereit.  
`10-Automation` enthält Collector-/Sanitization-/Normalisierungslogik.  
`20-IaC` enthält getrennte Deployment-Produkte.  
`99-LAB` ist die Integrations-/E2E-Stufe vor realen Kunden.  
`CUST-*` ist die kundenbezogene technische Boundary.

`PlatformBootstrap` provisioniert `CUST-*` und die Onboarding-Voraussetzungen. Die finale Knowledge-Base-/Publishing-Architektur wird ausschließlich in `00-Platform / DocumentationEngine` entschieden und umgesetzt.

## 2. Kundenidentität und Customer Boundary

Verbindliches Namensschema:

```text
CUST-<CustomerNumber>-<CustomerSlug>
```

Die Kunden-/Debitorennummer ist die stabile technische ID. Ein bereits existierendes `CUST-<CustomerNumber>-*` wird bei Umfirmierung wiederverwendet; mehrere Treffer sind `BLOCKED`.

Mindest-Repositories:

```text
CustomerConfiguration
Documentation
```

Optional pro Firewall:

```text
Firewall-<CustomerSlug>-<SiteSlug>
```

Firewall-Repositories sind RAW-CONFIDENTIAL und bleiben bei Bootstrap-Erstellung vollständig leer. Kein README, keine `.gitignore`, kein Initial-Commit.

## 3. Dokumentationsplattform vs. IaC

### Customer-/Dokumentations-Onboarding

```text
AzureDocumentation
OPNsenseDocumentation
```

### Getrennte IaC-Produkte

```text
20-IaC / AVD-Accelerator
20-IaC / Vaultwarden
```

AVD und Vaultwarden sind keine Customer-Onboarding-Module und werden weder von `New-BSSECustomerProject.ps1` noch von `customer-onboarding.yml` provisioniert.

IaC-Zielkette:

```text
Validate
→ Lint / Security
→ Plan / What-If
→ Approval
→ Deploy
→ Verify
```

IaC verwendet eigene Deployment-Identitäten und Service Connections.

## 4. OPNsense-Datenfluss

```text
CUST-xxx / Firewall-* RAW
        ↓
10-Automation / OPNsenseDocumentation
        ↓ Sanitize
        ↓ Validate
        ↓ Secret Check
        ↓ Normalize
00-Platform / DocumentationEngine
        ↓
finale Dokumentation / Publishing-Ziel gemäß DocumentationEngine
```

RAW-Konfigurationen dürfen nicht direkt in Dokumentation oder KI-Verarbeitung übernommen werden.

## 5. Project Branding

Versionierte Assets:

```text
assets/project-icons/00-platform.png
assets/project-icons/10-automation.png
assets/project-icons/20-iac.png
assets/project-icons/99-lab.png
assets/project-icons/cust-generic.png
```

Mapping:

```text
00-Platform   → 00-platform.png
10-Automation → 10-automation.png
20-IaC        → 20-iac.png
99-LAB        → 99-lab.png
CUST-*        → cust-generic.png
```

Idempotenz-Marker:

```text
BSSE.PlatformBootstrap.ProjectAvatarSha256
```

Runtime bestätigt:

- Avatar-PUT für alle vier Core-Projekte erfolgreich,
- reale Azure-DevOps-Antwort HTTP 204 wird als Erfolg akzeptiert,
- Project-Property-Marker erfolgreich geschrieben und gelesen,
- Folge-Apply erkennt alle vier Core-Branding-Zustände als `EXISTS`.

Bekannte Grenze: Externe manuelle Avatar-Änderungen können ohne dokumentierten Avatar-GET bei unverändertem Marker nicht zuverlässig erkannt werden.

## 6. Self-Hosting-Erstinitialisierung

Der erste Plattformlauf erfolgt lokal. Ziel ist anschließend der zentrale Technikerweg über Azure DevOps.

```text
lokaler Administrator
        ↓
Initialize-BSSEPlatformDependencies.ps1
        ↓
Core-Projekte/-Repos
PlatformBootstrap-Ausführungsquelle
Entra-Plattformidentität
Azure-DevOps-Entitlement
Collection-Berechtigung
produktive WIF-Service-Connection
FIC
Pipeline-Registrierung/-Autorisierung
```

`Initialize-BSSEPlatformDependencies.ps1 -Apply` ist in Azure Pipelines ausdrücklich blockiert. Eine Pipeline darf sich ihre eigene Identität oder organisationsweiten Rechte nicht selbst geben.

### Source Guard

```text
lokaler Working Tree dirty
→ BLOCKED

Azure PlatformBootstrap leer
→ Seed aus lokalem committed HEAD zulässig

Azure main == lokaler committed HEAD
→ EXISTS

Azure main != lokaler committed HEAD
→ BLOCKED
```

Kein automatischer Force-Push.

## 7. Plattformidentität

Zielidentität:

```text
sp-bsse-platform-bootstrap-azdo
```

Zielzustand:

```text
passwordless Entra App + Service Principal
Azure DevOps Basic
00-Platform / Readers
Create new projects = Allow
keine Project Collection Administrators-Mitgliedschaft
```

Runtime bestätigt:

- Entra App/Service Principal real erstellt,
- `Basic + 00-Platform/Readers` real erzeugt und später als `EXISTS` verifiziert,
- einmaliger `VS403283` unmittelbar nach Entra-Erstellung als transient bestätigt,
- begrenzter Retry ausschließlich für diesen bekannten Materialisierungsfall implementiert,
- Collection-ACL-Struktur real normalisiert,
- `Create new projects = Allow` real gesetzt, direkt verifiziert und später als `EXISTS` wiedererkannt.

Der Plattform-Service-Principal wird nicht zum Project Collection Administrator gemacht.

## 8. Produktive Azure-DevOps-WIF-Service-Connection

Ziel:

```text
sc-platform-bootstrap-azdo
→ Microsoft Entra Workload Identity Federation
→ sp-bsse-platform-bootstrap-azdo
```

Zweck: Der zentrale `Customer-Onboarding`-Pipelineweg benötigt eine nicht-interaktive, secretless Azure-DevOps-Identität für CLI-, REST- und Git-Operationen. Die WIF-Service-Connection ist **nicht** Bestandteil der fachlichen Customer-Onboarding-Logik selbst.

Der Endpoint-Typ und seine Inputs werden zur Laufzeit aus Azure DevOps ermittelt. Nicht deklarierte typspezifische Felder werden nicht erfunden. Ein unbekannter explizit erforderlicher Input führt zu Fail Closed.

### Aktueller Status: BLOCKED

Der reale Azure-DevOps-Endpoint-Typ ist:

```text
workloadidentityuser
```

Runtime bestätigt:

- Create erreicht den realen Endpoint-Typ,
- ein fehlgeschlagener Create persistiert einen Draft,
- Draft enthält gültigen serverseitigen Issuer und FederationSubject,
- exakt passendes FIC kann in Entra erzeugt und gelesen werden,
- normales Editieren/PUT des Drafts wird für diesen Endpoint-Typ nicht unterstützt,
- echter UI-`Finish setup`-Request wurde ermittelt,
- `Finish setup` scheitert weiterhin Azure-DevOps-seitig mit `App registration or Managed Identity with ObjectId ... was not found in tenant ...`, obwohl der Service Principal real existiert und von Azure DevOps selbst ausgewählt wird,
- Application Object ID als Alternative wurde ausgeschlossen,
- `AzureADMyOrg`, Application Administrator, explizites App-Ownership und vorhandenes Service-Principal-Ownership wurden als einfache Ursachen ausgeschlossen.

Produktive WIF-Finalisierung bleibt offen. Es werden keine weiteren spekulativen ID-/Payload-Änderungen in den produktiven Bootstrap übernommen.

Fachdokumentation:

```text
docs/WIF-Blocked-Status.md
```

### Verifizierter Diagnose-Cleanup

Reihenfolge für Probe-Drafts:

```text
1. zugehöriges FIC entfernen
2. organisationsweiter Endpoint-DELETE
   mit projectIds=<projectId>&deep=false
3. HTTP 204 / Endpoint-Abwesenheit verifizieren
```

Das vor dem Diagnoseversuch bereits vorhandene Service-Principal-Ownership bleibt unverändert. Das nur für die Diagnose hinzugefügte App-Registration-Ownership wird wieder entfernt.

## 9. Customer-Onboarding – produktiver Zielweg

```text
Techniker
    ↓
Azure DevOps / Customer-Onboarding
    ↓
Validate
    ↓
Dry Run
    ↓
Approval nur bei PLAN
    ↓
Apply
    ↓
Verify / Idempotenz
```

Pipeline:

```text
pipelines/customer-onboarding.yml
```

Produktive Authentifizierung:

```text
AzureCLI@3
connectionType: azureDevOps
azureDevOpsServiceConnection: sc-platform-bootstrap-azdo
```

Dieser Weg bleibt bis zur WIF-Klärung auth-seitig BLOCKED.

## 10. Temporärer Azure-DevOps-E2E-Testpfad

### Bevorzugt: AzureRM-WIF-Bridge

Während der produktive `workloadidentityuser`-Pfad BLOCKED ist, wird die fachliche Customer-Onboarding-Pipeline über eine getrennte temporäre AzureRM-WIF-Bridge E2E getestet.

Pipeline:

```text
pipelines/customer-onboarding-azure-rm-wif-bridge-test.yml
```

Pipeline-Name:

```text
Customer-Onboarding-TEST-AzureRmWifBridge
```

Bridge-Zielobjekte:

```text
sc-platform-bootstrap-azdo-arm-bridge
fic-sc-platform-bootstrap-azdo-arm-bridge
```

Eigenschaften:

- AzureRM Service Connection mit `WorkloadIdentityFederation`,
- dieselbe dedizierte Plattformidentität wie der produktive Zielweg,
- keine Azure-RBAC-Zuweisung,
- all-zero Subscription-ID nur zum Unterdrücken eines Azure-Subscription-Kontexts,
- `AzureCLI@3` mit `allowNoSubscriptions: true`,
- aus der WIF-Entra-Session wird ein Azure-DevOps-Entra-Token bezogen,
- dieselben Backend-Skripte wie der produktive Weg,
- kein PAT,
- kein Client Secret,
- explizites Run-Opt-in erforderlich,
- `Validate → DryRun → Approval → Apply → Verify` bleibt erhalten,
- Bridge ersetzt den produktiven `workloadidentityuser`-Zielzustand nicht.

Fachdokumentation:

```text
docs/AzureRM-WIF-Bridge-Test.md
```

**Status:** Testpipeline code-seitig implementiert; Bridge-Service-Connection, Bridge-FIC, pipeline-spezifische Autorisierung und realer E2E-Lauf sind noch nicht runtime-verifiziert.

### Sekundärer Fallback: System.AccessToken

Der bereits implementierte getrennte System.AccessToken-Testpfad bleibt als sekundärer Kompatibilitätsfallback vorhanden:

```text
pipelines/customer-onboarding-system-access-token-test.yml
bootstrap/Register-BSSECustomerOnboardingSystemTokenTestPipeline.ps1
Customer-Onboarding-TEST-SystemAccessToken
```

Er wird nicht bevorzugt, weil die Build-Service-Identität dafür zusätzliche Customer-Onboarding-Rechte benötigen würde. Die AzureRM-WIF-Bridge verwendet dagegen die bereits dedizierte Plattformidentität.

## 11. Lokaler Customer-Onboarding-Weg

Backend:

```text
bootstrap/New-BSSECustomerProject.ps1
bootstrap/Sync-BSSECustomerConfiguration.ps1
```

Lokales Frontend:

```text
bootstrap/Start-BSSECustomerOnboarding.ps1
```

Der lokale Weg nutzt die angemeldete Administratoridentität und ist fachlich unabhängig von WIF. Die aktuelle Frontend-Readiness koppelt ihn jedoch noch an die vollständigen produktiven Self-Hosting-Dependencies. Diese Kopplung wird nicht stillschweigend degradiert; der temporäre Bridge-Testpfad ist separat.

## 12. CustomerConfiguration

`Sync-BSSECustomerConfiguration.ps1` verwaltet den Bootstrap-Sollzustand kontrolliert:

```text
fehlend    → PLAN / ADD
identisch  → EXISTS
abweichend → BLOCKED
```

Eigenschaften:

- stabiles `CUST-<CustomerNumber>-*` wird ermittelt,
- nur fehlende Bootstrap-Zieldateien werden ergänzt,
- abweichende vorhandene Dateien werden nicht überschrieben,
- Git-Historie statt blindem Write,
- OAuth-/Entra-/System.AccessToken wird nicht in Remote-URLs persistiert.

## 13. Pipeline-Registrierung und Readiness

Produktive Registrierung:

```text
bootstrap/Register-BSSECustomerOnboardingPipeline.ps1
```

Produktive Readiness:

```text
bootstrap/Test-BSSECustomerOnboardingReadiness.ps1
```

```text
kein PLAN / kein BLOCKED → READY
PLAN                    → Dependency fehlt
BLOCKED / Fehler         → NOT READY
```

Solange die produktive WIF-Service-Connection BLOCKED ist, ist der produktive zentrale Weg nicht vollständig READY. Die temporären TEST-Pipelines sind davon getrennt und dürfen diesen Status nicht als produktiv READY ausgeben.

## 14. Promotion / Testreihenfolge

Beschlossen:

```text
Development
→ 99-LAB
→ CUST-00000 BSSE
→ Pilotkunde
→ weitere Kunden
```

Cannon wird erst nach LAB-/BSSE-E2E als Pilot verwendet.

BSSE:

```text
CustomerNumber: 00000
Project: CUST-00000-Bernd-Schneider-Software-Engineering-GmbH
Tenant: f9acedfe-a77a-4831-b79c-f010afa6b889
```

## 15. Implementierungsstatus

### Bereits beschlossen

- Zielarchitektur und Repository-Zuordnung,
- Dokumentations-/IaC-Trennung,
- CustomerNumber als stabile Kunden-ID,
- OPNsense RAW pro Firewall in eigenem Repo,
- lokaler First-Run / zentraler späterer Technikerweg,
- secretless produktive WIF-Plattformidentität,
- kein PCA für Plattformidentität,
- `Basic + 00-Platform/Readers + Create new projects = Allow`,
- Pipeline darf sich nicht selbst privilegieren,
- direktes Arbeiten auf `main`,
- produktiver WIF-Zielzustand bleibt trotz Preview-BLOCKED unverändert,
- AzureRM-WIF-Bridge ist nur temporärer E2E-Testpfad und keine Architekturänderung.

### Bereits implementiert

- Core-/Customer-Bootstrap,
- CustomerConfiguration-Sync,
- Branding inkl. Hash-Marker,
- Self-Hosting-Initializer,
- lokales Customer-Onboarding-Frontend,
- produktive Customer-Onboarding-YAML,
- WIF-Metadatenauflösung,
- Entitlement-Retry für bestätigten `VS403283`,
- ACL-Normalisierung / CreateProjects-Grant,
- `System.AccessToken`-Kompatibilitätsweg in Common/Branding/CustomerConfiguration,
- temporäre System.AccessToken-E2E-Testpipeline,
- temporäre AzureRM-WIF-Bridge-Testpipeline,
- Fachdokumentation für den AzureRM-WIF-Bridge-Test.

### Bereits runtime-verifiziert

- Core-Projekte/-Repositories,
- Core-Branding + Marker + Idempotenz,
- PlatformBootstrap Source Guard,
- Entra App/SP-Erstellung,
- Basic + Readers,
- transienter VS403283-Grundfall,
- Collection-ACL-Auswertung,
- Create new projects Grant + Verify + EXISTS,
- realer `workloadidentityuser`-Endpoint-Typ,
- Draft-Persistenz nach Create-Fehler,
- realer Issuer/Subject,
- passendes Probe-FIC,
- UI-Finish-Setup-Request,
- Diagnose-Cleanup eines Probe-Drafts mit HTTP 204,
- `AzureADMyOrg` für die Plattform-App.

### Noch offen

- Diagnoseobjekte des letzten UI-Probes vollständig bereinigen,
- nur diagnostisch hinzugefügtes App-Registration-Ownership entfernen,
- Branding-Regressionstest lokal ausführen,
- Core-Icons visuell in Azure DevOps bestätigen,
- `VS403283`-Retry in einem frischen Same-Process-Erstlauf runtime-verifizieren,
- **BLOCKED:** produktive `sc-platform-bootstrap-azdo` fertigstellen,
- produktives `fic-sc-platform-bootstrap-azdo`,
- produktive pipeline-spezifische Service-Connection-Autorisierung,
- produktiver Dependency-Verify ohne WIF-PLAN/BLOCKED,
- produktiver WIF-Customer-Onboarding-E2E,
- AzureRM-WIF-Bridge-Service-Connection/FIC erzeugen und verifizieren,
- Bridge-Testpipeline registrieren/gezielt autorisieren,
- Bridge-Validate mit Azure-DevOps-Entra-Token runtime-verifizieren,
- Bridge-DryRun/Approval/Apply/Verify E2E ausführen,
- Git-Push nach `CustomerConfiguration` aus echtem Pipeline-Lauf bestätigen,
- erst danach v1.9 als vollständig verifiziert markieren.

## 16. Aktueller nächster Umsetzungsschritt

1. Diagnoseobjekte `sc-platform-bootstrap-azdo-ui-probe` / zugehöriges FIC bereinigen; nur das für den Test hinzugefügte App-Registration-Ownership entfernen. Vorbestehendes Service-Principal-Ownership bleibt unverändert.
2. GitHub-`main` in die Azure-Repos-Ausführungskopie `00-Platform/PlatformBootstrap/main` synchronisieren.
3. Temporäre AzureRM-WIF-Bridge `sc-platform-bootstrap-azdo-arm-bridge` erzeugen.
4. Passendes separates Bridge-FIC erzeugen und exakt verifizieren.
5. `Customer-Onboarding-TEST-AzureRmWifBridge` registrieren und ausschließlich für diese Bridge-Service-Connection autorisieren.
6. Validate-Stage starten und Azure-DevOps-Entra-Token der dedizierten Plattformidentität verifizieren.
7. Customer-Onboarding-Dry-Run prüfen.
8. Nach Review Apply + Verify für den E2E-Test ausführen.
9. Produktive WIF-Implementierung bleibt parallel BLOCKED/offen; keine automatische Umstellung des produktiven `customer-onboarding.yml` auf die Bridge.
