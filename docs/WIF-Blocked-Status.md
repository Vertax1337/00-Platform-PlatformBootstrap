# Azure DevOps WIF – BLOCKED Runtime-Status

**Stand:** 2026-08-13  
**Komponente:** `00-Platform / PlatformBootstrap`  
**Produktiver Zielzustand:** `sc-platform-bootstrap-azdo` mit Microsoft Entra Workload Identity Federation  
**Aktueller Status:** **BLOCKED – produktive WIF-Finalisierung offen**

## Zweck der WIF-Service-Connection

Die WIF-Service-Connection ist **nicht** für die fachliche Customer-Onboarding-Logik selbst erforderlich. Die Backend-Skripte können lokal mit der angemeldeten Administratoridentität ausgeführt werden.

WIF wird benötigt, damit der **zentrale Azure-DevOps-Technikerweg** die gleichen Bootstrap-Skripte nicht-interaktiv und secretless ausführen kann:

```text
Techniker
  ↓
Azure DevOps / Customer-Onboarding
  ↓
sc-platform-bootstrap-azdo
  ↓ Microsoft Entra WIF
sp-bsse-platform-bootstrap-azdo
  ↓
Azure DevOps CLI / REST / Git
  ↓
CUST-* Projekt + Repositories + Branding + CustomerConfiguration
```

Die dedizierte Plattformidentität besitzt dabei den bereits bestätigten Least-Privilege-Zielzustand:

```text
Basic
00-Platform / Readers
Create new projects = Allow
keine Project Collection Administrators-Mitgliedschaft
```

Die Service Connection soll später ausschließlich für die `Customer-Onboarding`-Pipeline autorisiert werden.

## Bereits runtime-verifiziert

Folgende Punkte wurden in `BSSE-CloudOps` real bestätigt:

- App Registration `sp-bsse-platform-bootstrap-azdo` existiert.
- Service Principal / Enterprise Application existiert.
- Tenant: `f9acedfe-a77a-4831-b79c-f010afa6b889`.
- Application / Client ID: `3a2af393-311d-4297-a9c2-d693fe85677f`.
- Application Object ID: `112d87cc-9594-48fe-8954-b7bccbe7fd78`.
- Service Principal Object ID: `4cd8f8cf-be28-4101-999e-8867931fab0a`.
- `signInAudience = AzureADMyOrg`.
- Azure-DevOps-Graph-Identität des Service Principals existiert.
- `Basic + 00-Platform/Readers` ist vorhanden.
- `Create new projects = Allow` wurde real gesetzt, verifiziert und später als `EXISTS` wiedererkannt.
- Der reale Endpoint-Type ist `workloadidentityuser` mit `WorkloadIdentityFederation`.
- `data.objectId` verwendet für `Application` die Service Principal Object ID. Dies entspricht auch dem realen Azure-DevOps-UI-Payload.
- Ein fehlgeschlagener `workloadidentityuser`-Create persistiert trotzdem einen Draft.
- Der Draft enthält serverseitig erzeugten `workloadIdentityFederationIssuer` und `workloadIdentityFederationSubject`.
- Ein exakt passendes Federated Credential kann auf der Entra-App erfolgreich angelegt und wieder gelesen werden.
- Ein normales `PUT` des Drafts wird vom Endpoint-Typ mit `Currently editing is not supported. Please remove and recreated the service connection.` abgelehnt.
- Die Azure-DevOps-Weboberfläche verwendet beim echten `Finish setup`:

```text
PUT /_apis/serviceendpoint/endpoints/{id}?operation=
```

- `Finish setup` schlägt weiterhin mit folgender Azure-DevOps-Backendmeldung fehl:

```text
App registration or Managed Identity with ObjectId
4cd8f8cf-be28-4101-999e-8867931fab0a
was not found in tenant
f9acedfe-a77a-4831-b79c-f010afa6b889.
```

- Die Service Principal Object ID ist real vorhanden und wird durch Azure DevOps selbst im UI ausgewählt/verwendet.
- Ein Test mit der Application Object ID `112d87cc-9594-48fe-8954-b7bccbe7fd78` wird vom gleichen Backend ebenfalls als nicht gefunden abgelehnt.
- Der ausführende Administrator besitzt `Application Administrator`.
- Explizites App-Registration-Ownership wurde testweise hinzugefügt und änderte den Fehler nicht.
- Explizites Service-Principal-Ownership war bereits vorhanden.

Damit ist eine einfache lokale ID-, Tenant-, Single-Tenant- oder Owner-Fehlkonfiguration nach dem aktuellen Runtime-Teststand nicht mehr plausibel.

## Bereinigungsregeln für Diagnoseobjekte

Für fehlgeschlagene `workloadidentityuser`-Drafts wurde folgende Löschreihenfolge real verifiziert:

```text
1. zugehöriges Federated Credential entfernen
2. Service Endpoint organisationsweit löschen:

DELETE /_apis/serviceendpoint/endpoints/{endpointId}
       ?projectIds={projectId}
       &deep=false
       &api-version=7.1

→ HTTP 204
```

Ist das FIC noch vorhanden, wurde beim Delete stattdessen ein Azure-DevOps-Fehler beim Entfernen des Federated Credentials beobachtet.

Die projektbezogene DELETE-Route `/{project}/_apis/serviceendpoint/endpoints/{id}` ist für diesen Endpoint-Typ nicht unterstützt und lieferte HTTP 405.

## Produktiver Status

### Bereits beschlossen

Der produktive Zielzustand bleibt unverändert:

```text
Customer-Onboarding
→ sc-platform-bootstrap-azdo
→ Microsoft Entra WIF
→ sp-bsse-platform-bootstrap-azdo
```

Es wird **kein** permanenter PAT-, Client-Secret- oder breit privilegierter Ersatz eingeführt.

### Bereits implementiert

Die gemeinsamen Bootstrap-Komponenten unterstützen bereits zwei Pipeline-Authentifizierungswege:

```text
bevorzugt:
AzureCLI@3 + Azure DevOps Service Connection / WIF

temporärer Kompatibilitätspfad:
SYSTEM_ACCESSTOKEN
→ prozesslokal als AZURE_DEVOPS_EXT_PAT
```

Auch Project Branding und `CustomerConfiguration`-Gitzugriff können den explizit gemappten `System.AccessToken` verwenden.

### Noch offen / BLOCKED

- produktive Erstellung/Fertigstellung von `sc-platform-bootstrap-azdo`,
- produktives `fic-sc-platform-bootstrap-azdo`,
- pipeline-spezifische WIF-Service-Connection-Autorisierung,
- WIF-E2E-Lauf der produktiven `Customer-Onboarding`-Pipeline,
- abschließender Dependency-Verify ohne offenen WIF-Zustand.

Diese Punkte bleiben offen, bis der Azure-DevOps-`workloadidentityuser`-Finish-Setup-Pfad funktioniert oder Microsoft eine belastbare andere Vorgehensweise dokumentiert.

## Temporärer E2E-Testpfad

Um die **fachliche Customer-Onboarding-Pipeline unabhängig vom blockierten Preview-WIF-Finish-Setup** weiter zu testen, existiert eine getrennte Testpipeline:

```text
pipelines/customer-onboarding-system-access-token-test.yml
```

Registrierungshelfer:

```text
bootstrap/Register-BSSECustomerOnboardingSystemTokenTestPipeline.ps1
```

Pipeline-Name:

```text
Customer-Onboarding-TEST-SystemAccessToken
```

Eigenschaften:

- verwendet exakt dieselben Backend-Skripte `New-BSSECustomerProject.ps1` und `Sync-BSSECustomerConfiguration.ps1`,
- verwendet **keinen PAT und kein Client Secret**,
- mappt ausschließlich den kurzlebigen Pipeline-Jobtoken `System.AccessToken`,
- benötigt ein explizites Run-Opt-in `confirmTemporarySystemAccessToken=true`,
- gibt im Validate-Stage die tatsächlich verwendete Build-Service-Identität aus,
- behält `Validate → DryRun → Approval → Apply → Verify`,
- ersetzt den produktiven WIF-Zielzustand ausdrücklich nicht.

Die effektiven Rechte des `System.AccessToken` ergeben sich aus Job Authorization Scope und den Berechtigungen der tatsächlich verwendeten Build-Service-Identität. Vor dem ersten Apply müssen diese Rechte separat geprüft und nur für den Test notwendige Berechtigungen vergeben werden.

Der temporäre Testpfad dient ausschließlich der E2E-Validierung des Customer-Onboarding-Backends, solange die produktive WIF-Service-Connection BLOCKED ist.
