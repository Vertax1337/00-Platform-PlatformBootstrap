# CUST Intune Tenant Repository Contract

> **Status:** Repository-/Identity-/Lifecycle-Contract BESCHLOSSEN; technische Customer-Onboarding-Implementierung OFFEN.  
> **Stand:** 2026-09-01

## 1. Zweck

Dieses Dokument definiert den verbindlichen Customer-seitigen Repositoryvertrag für produktiv durch BSSE verwaltete Microsoft-Intune-Tenants.

Der Vertrag konkretisiert den bereits beschlossenen Intune Cross-Project Contract zwischen:

```text
00-Platform / PlatformBootstrap
30-IDD
CUST-<CustomerNumber>-<CustomerSlug>
00-Platform / DocumentationEngine
```

Er entscheidet ausschließlich die Customer-Boundary, Repositorybenennung, stabile Identität und Lifecycle-Regeln. Die konkrete IntuneCD-/Monitor-Runtime, Graph-Identity und Snapshot-Serialisierung werden hier nicht vorweggenommen.

## 2. Verbindliches Repository-Schema

Jeder produktiv verwaltete Intune-Tenant erhält innerhalb des zugehörigen `CUST-*`-Projekts ein eigenes Repository.

Verbindlicher Repositoryname:

```text
Intune-<TenantAlias>
```

Beispiele:

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
├── Intune-Primary
└── Intune-Legacy
```

`TenantAlias` ist ein explizit beim Onboarding vergebener, menschenlesbarer und innerhalb des Kundenprojekts eindeutiger technischer Alias.

Der Alias ist **nicht** die kanonische Tenant-Identität.

## 3. Stable Identity

Verbindliche Identitäten:

```text
Customer Identity → CustomerNumber
Intune Tenant      → Microsoft Entra Tenant ID
Repository Locator → Intune-<TenantAlias>
```

Die Microsoft Entra Tenant ID ist die einzige stabile technische Tenant-Zuordnungsidentität für Cross-Project-Verträge, Snapshot-Provenance, Monitor-Registrierung und DocumentationEngine.

Nicht als stabile Tenant-Identität zulässig:

- Repositoryname,
- TenantAlias,
- Tenant-Anzeigename,
- primäre/onmicrosoft.com-Domain,
- kundenseitige Maildomain.

Diese Werte können sich ändern oder sind nicht global eindeutig genug.

## 4. TenantAlias

Der `TenantAlias` dient ausschließlich der lesbaren Repository- und Technikerzuordnung.

Verbindlich gilt:

- Alias wird beim ersten Onboarding explizit festgelegt,
- Alias muss innerhalb des `CUST-*`-Projekts eindeutig sein,
- Alias darf nicht automatisch aus einer später veränderbaren Domain erneut berechnet werden,
- Aliasänderungen führen nicht automatisch zu einer Repository-Umbenennung,
- eine spätere Umbenennung ist eine bewusste Migration und kein normaler idempotenter Bootstrap-Schritt,
- mehrere Aliase dürfen niemals auf dieselbe Tenant ID zeigen,
- eine Tenant ID darf innerhalb eines Kundenprojekts nur einmal registriert sein.

Die konkrete Zeichen-/Längenvalidierung wird mit der technischen Onboarding-Implementierung an die bestehenden PlatformBootstrap-Slug-Regeln angelehnt und separat getestet.

## 5. 0..n Intune-Tenants pro Kunde

Ein Kunde kann keinen, einen oder mehrere verwaltete Intune-Tenants besitzen.

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
├── Intune-Primary      → Tenant ID A
└── Intune-Legacy       → Tenant ID B
```

Das Modell darf deshalb keine 1:1-Annahme `Customer == Tenant` in Repositorynamen oder Cross-Project-Logik festschreiben.

## 6. CustomerConfiguration als Zuordnungsregister

`CustomerConfiguration` bleibt die kundenbezogene Source of Truth für die Zuordnung zwischen CustomerNumber, Tenant ID, Alias und Repository.

Verbindliche fachliche Struktur:

```text
intuneTenants:
  - tenantId: "<Microsoft-Entra-Tenant-ID>"
    alias: "Primary"
    repository: "Intune-Primary"
    classification: "RAW-CONFIDENTIAL"
    purpose: "intunecd-snapshot"
```

Die exakte YAML-Feldserialisierung wird mit der technischen Customer-Onboarding-Implementierung finalisiert. Die oben gezeigten Felder sind fachlich verbindlich; zusätzliche technische Felder können später ergänzt werden, dürfen aber die stabile Tenant-ID nicht ersetzen.

## 7. Repository-Klassifikation

Ein Customer-Intune-Repository enthält versionierte Roh-/Providerartefakte aus IntuneCD und ist deshalb:

```text
classification: RAW-CONFIDENTIAL
purpose: intunecd-snapshot
perspective: actual
```

Es ist **kein** allgemeines Dokumentationsrepository und **kein** Desired-State-Repository.

Daraus folgt:

- keine direkte Veröffentlichung,
- keine direkte Übernahme nativer Rohdaten in Kundendokumentation,
- keine automatische Interpretation als freigegebener Sollstand,
- Zugriff nach Least Privilege,
- Weitergabe an DocumentationEngine nur über den validierten BSSE Intune Snapshot-/Provenance-Contract.

## 8. Actual / Desired Boundary

Verbindlich:

```text
CUST-* / Intune-<TenantAlias>
→ Actual State

30-IDD / IntuneDefaultDeployment
→ Desired Deployment State
```

Ein Commit im Customer-Intune-Repository wird niemals allein durch seine Git-Versionierung zu Desired State.

Der freigegebene Sollzustand bleibt zentral unter `30-IDD / IntuneDefaultDeployment`.

## 9. Provisionierungsregel

Das Repository wird nicht pauschal für jeden Kunden angelegt.

Es wird nur provisioniert, wenn Intune Management für einen konkreten Tenant explizit aktiviert/registriert wird.

Logischer Ablauf:

```text
CustomerNumber
+ Tenant ID
+ TenantAlias
+ Intune Management = enabled
        ↓
CUST-* Boundary auflösen
        ↓
CustomerConfiguration prüfen
        ↓
Tenant ID / Alias auf Eindeutigkeit prüfen
        ↓
Intune-<TenantAlias> provisionieren/auflösen
        ↓
Mapping persistieren
        ↓
später: 30-IDD / Monitor registrieren
```

Die Monitor-Registrierung selbst ist nicht Bestandteil dieses Workchunks.

## 10. Idempotenz und Konflikte

Die technische Implementierung muss folgende Zustände unterscheiden:

```text
Tenant ID + Alias + Repository stimmen überein
→ EXISTS

Tenant ID noch nicht registriert, Alias frei
→ PLAN / CREATE

Tenant ID bereits mit anderem Alias/Repository registriert
→ BLOCKED

Alias bereits für andere Tenant ID verwendet
→ BLOCKED

Repository existiert, aber Mapping in CustomerConfiguration fehlt/abweicht
→ BLOCKED bis zur bewussten Klärung
```

PlatformBootstrap darf bei Identitätskonflikten nicht anhand von Namen raten.

## 11. Initialzustand des Repositories

Der Bootstrap darf keine erfundenen Intune-Snapshots oder Placeholder-Konfiguration als technische Wahrheit erzeugen.

Bis der IntuneCD-/Monitor-Producervertrag finalisiert ist, gilt deshalb:

- Repository-Provisionierung und Mapping sind getrennt von der ersten IntuneCD-Befüllung,
- kein künstlicher `actual` Snapshot wird durch PlatformBootstrap erzeugt,
- konkrete Initial-Branch-/Seed-Regeln für IntuneCD Monitor bleiben Teil des späteren Producer-/Runtime-Contracts.

Damit wird die zukünftige Monitor-Integration nicht durch eine heute erfundene Dateistruktur blockiert.

## 12. Deaktivierung und Löschung

Das Deaktivieren von Intune Management darf historische Snapshots nicht automatisch löschen.

Verbindlich:

- kein automatisches Löschen des Repositories durch normales Customer-Onboarding,
- keine automatische Historienbereinigung,
- keine automatische Repository-Umbenennung bei Tenant-/Domain-/DisplayName-Änderungen,
- Löschung oder Archivierung benötigt einen separaten bewussten Lifecycle-/Retention-Prozess.

## 13. Abgrenzung zu IntuneCD Monitor

Der Monitor darf das Customer-Repository als technische Snapshot-Quelle/-Senke verwenden, besitzt aber nicht die kanonische Customer-/Tenant-Identität.

Kanonische Zuordnung:

```text
PlatformBootstrap / CustomerConfiguration
        ↓
CustomerNumber + Tenant ID + Repository Mapping
        ↓
30-IDD / IntuneCD Monitor
```

Eine Monitor-Datenbank kann diese Zuordnung referenzieren oder synchronisieren, aber nicht stillschweigend eine abweichende Customer-/Tenant-Source-of-Truth etablieren.

## 14. Abgrenzung zur DocumentationEngine

Die DocumentationEngine konsumiert das Customer-Intune-Repository nicht als freie Dateisammlung.

Pfad:

```text
CUST-* / Intune-<TenantAlias>
        ↓
validierter BSSE Intune Snapshot Contract
        ↓
DocumentationEngine Intune Source Adapter
        ↓
Canonical Graph [actual]
```

Repositoryname und Alias dürfen in der DocumentationEngine nur als Provenance-/Locator-Metadaten verwendet werden. Die Tenant-Korrelation erfolgt über die Entra Tenant ID.

## 15. Nicht durch diesen Contract entschieden

Noch offen bleiben:

- konkrete Parameteroberfläche von `New-BSSECustomerProject.ps1` / Customer-Onboarding,
- technische YAML-Serialisierung und additive Änderung bestehender `CustomerConfiguration`,
- separates `Add-BSSECustomerIntuneTenant.ps1` oder Integration in bestehenden Onboarding-Pfad,
- Initial-Branch-/Seed-Verhalten des leeren Intune-Repositories,
- Repository-Berechtigungsdetails,
- Retention-/Archivierungsprozess,
- Monitor-Registrierung,
- Azure-Repos-Authentifizierung des Monitors,
- Graph-Identitäten und Permissions,
- Snapshot-Schemaformat,
- IntuneCD-/Monitor-Repositorystruktur unter `30-IDD`.

## 16. Status

### Bereits beschlossen

- ein eigenes Customer-Repository pro produktiv verwaltetem Intune-Tenant,
- Repositoryschema `Intune-<TenantAlias>`,
- expliziter, menschenlesbarer und innerhalb des Kundenprojekts eindeutiger TenantAlias,
- Entra Tenant ID als stabile Tenant-Identität,
- CustomerNumber als stabile Customer-Identität,
- `CustomerConfiguration` als kanonisches Customer-/Tenant-/Repository-Zuordnungsregister,
- Customer-Intune-Repository ist `RAW-CONFIDENTIAL`, Zweck `intunecd-snapshot`, Perspektive `actual`,
- 0..n Intune-Tenants pro Kunde,
- keine automatische Repository-Umbenennung bei DisplayName-/Domainänderungen,
- keine automatische Löschung beim Deaktivieren,
- Fail Closed bei Alias-/Tenant-ID-/Mapping-Konflikten.

### Bereits implementiert

- dieser fachliche Repositoryvertrag in PlatformBootstrap.

### Noch offen

- technische Customer-Onboarding-/Provisionierungsimplementierung,
- CustomerConfiguration-Migrations-/Additive-Update-Mechanik,
- Monitor-Registrierung und Runtime,
- Snapshot-Schemaimplementierung,
- Runtime-Verifikation in Azure DevOps.
