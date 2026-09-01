# CUST-* Intune Tenant Repository Contract

> **Status:** Repositorygrenze, Namensschema und CustomerConfiguration-Zuordnung BESCHLOSSEN; technische Provisionierung im Customer-Onboarding noch OFFEN.  
> **Stand:** 2026-09-01

## 1. Zweck

Dieser Vertrag konkretisiert den unter `docs/Intune-Cross-Project-Contract.md` beschlossenen kundenspezifischen Intune-Bereich.

Er beantwortet ausschließlich:

- wie ein produktiv verwalteter Microsoft-Intune-/Entra-Tenant innerhalb einer `CUST-*`-Boundary repräsentiert wird,
- wie sein Repository benannt und stabil zugeordnet wird,
- wo die kanonische Tenant→Repository-Zuordnung gespeichert wird,
- welche Sicherheits- und Lifecycle-Regeln für diesen Repositorytyp gelten.

Er implementiert noch nicht IntuneCD, IntuneCD Monitor, Graph-Berechtigungen, Snapshot-Schema oder DocumentationEngine-Adapter.

## 2. Verbindliche Customer-Boundary

Ein Kunde kann `0..n` produktiv verwaltete Intune-Tenants besitzen.

Für jeden aktivierten Tenant wird innerhalb des bestehenden Kundenprojekts genau ein eigenes Repository für den von IntuneCD erfassten Iststand geführt:

```text
CUST-<CustomerNumber>-<CustomerSlug>
├── CustomerConfiguration
├── Documentation
├── Intune-<TenantSlug>                 # 0..n
└── Firewall-<CustomerSlug>-<SiteSlug>  # 0..n
```

Kundenspezifische Intune-Snapshots werden nicht zentral in `30-IDD` gesammelt.

## 3. Verbindliches Repository-Namensschema

```text
Intune-<TenantSlug>
```

Beispiele:

```text
Intune-contoso
Intune-contoso-prod
Intune-emea
```

### 3.1 Bedeutung von `TenantSlug`

`TenantSlug` ist ein bei der erstmaligen Registrierung festgelegter, innerhalb des Kundenprojekts eindeutiger technischer Alias für den Tenant.

Er ist **nicht** die technische Tenant-Identität.

Verbindlich gilt:

- die technische Identität ist immer die Microsoft Entra Tenant ID (`tenantId`),
- `TenantSlug` dient ausschließlich der stabilen, menschenlesbaren Repositorybenennung,
- der Slug wird beim ersten Onboarding normalisiert und danach in `CustomerConfiguration` persistiert,
- Änderungen von Tenant-Displayname, primärer Domäne oder Kundenname führen **nicht** automatisch zu einer Repository-Umbenennung,
- eine spätere bewusste Repository-Umbenennung ist eine eigene Migration und darf nicht implizit durch Reconciliation entstehen.

Damit bleibt beispielsweise `Intune-contoso-prod` erhalten, auch wenn sich der Tenant später umbenennt.

### 3.2 Kollisions- und Idempotenzregeln

Fail Closed:

- dieselbe `tenantId` darf innerhalb einer Customer Boundary nur genau einer Intune-Repositoryzuordnung entsprechen,
- derselbe Repositoryname darf nur genau einer `tenantId` entsprechen,
- mehrere unterschiedliche Tenants dürfen nicht denselben `TenantSlug` verwenden,
- eine vorhandene abweichende Zuordnung wird nicht automatisch umgeschrieben oder zusammengeführt,
- eine nicht eindeutig auflösbare Zuordnung führt zu `BLOCKED`.

Der Repositoryname darf niemals als Ersatz für `tenantId` verwendet werden.

## 4. Kanonische Tenant→Repository-Registry

Die kanonische Customer-seitige Zuordnung liegt in `CustomerConfiguration`, nicht in der Datenbank von IntuneCD Monitor.

Der bestehende `customer.yml`-Vertrag wird fachlich um einen eigenen Intune-Bereich erweitert:

```yaml
intune:
  enabled: true
  tenants:
    - tenantId: "11111111-2222-3333-4444-555555555555"
      name: "Contoso Production"
      slug: "contoso-prod"
      repository: "Intune-contoso-prod"
      classification: "RAW-CONFIDENTIAL"
      purpose: "intunecd-actual-snapshots"
```

Verbindliche Semantik:

- `tenantId`: stabile Microsoft-Entra-Tenant-ID und primärer technischer Schlüssel,
- `name`: menschenlesbarer Anzeigename; darf sich ändern,
- `slug`: persistierter Repository-Alias; wird nicht automatisch nachgezogen,
- `repository`: erwarteter Repositoryname innerhalb des aufgelösten `CUST-*`-Projekts,
- `classification`: für den nativen IntuneCD-Iststand zunächst `RAW-CONFIDENTIAL`,
- `purpose`: `intunecd-actual-snapshots`.

Die konkrete YAML-Schreib-/Merge-Implementierung bleibt dem Customer-Onboarding-Workchunk vorbehalten.

### Bestehendes `customer.tenantId`

Das bereits vorhandene Feld `customer.tenantId` beziehungsweise der bisherige Bootstrap-Parameter `TenantId` wird **nicht** stillschweigend zum Multi-Tenant-Intune-Register umdefiniert.

Intune verwendet den expliziten `intune.tenants[]`-Vertrag. Ein späteres Frontend darf bei einem eindeutigen Single-Tenant-Kunden einen vorhandenen Tenant als Vorschlag übernehmen, muss das Ergebnis aber explizit in `intune.tenants[]` persistieren.

## 5. Repositoryklassifikation und Inhalt

Das Intune-Tenant-Repository enthält providernahe Konfigurationsdaten aus einem realen Tenant und wird deshalb zunächst als

```text
RAW-CONFIDENTIAL
```

klassifiziert.

Zulässiger fachlicher Inhalt:

```text
native IntuneCD Backup-Artefakte
+
BSSE Intune Snapshot / Provenance Envelope
+
maschinenlesbare, aus demselben Capture abgeleitete Reports/Evidence
```

Nicht zulässig:

- produktive Secrets oder Credentials als bewusst versionierter Sollbestand,
- PATs, Client Secrets oder sonstige Repositoryzugangsdaten,
- manuell erfundene Policies/Assignments zur "Vervollständigung" des Snapshots,
- final gerenderte BSSE-Kundendokumentation als Source of Truth,
- Vermischung mit dem freigegebenen `30-IDD` Desired State.

Die finale Dokumentation wird durch die DocumentationEngine erzeugt und gehört in den bestehenden Dokumentationspfad.

## 6. Initialisierung des Repositories

Anders als ein OPNsense-RAW-Repository muss das Intune-Repository nicht zwingend vollständig leer bleiben.

Für die spätere IntuneCD-Monitor-Integration gilt als Ziel:

- das Repository besitzt einen definierten Default Branch,
- Bootstrap-/Metadateninhalt darf einen initialen Commit erzeugen,
- ein solcher Initialcommit darf **keinen synthetischen Intune-Snapshot** vortäuschen,
- der erste `actual` Snapshot entsteht ausschließlich aus einem erfolgreich validierten IntuneCD-Capture.

Exakte Seed-Dateien und Branchstrategie werden erst zusammen mit dem IntuneCD-/Monitor-Integrationsworkchunk festgelegt.

## 7. Lifecycle

### Aktivierung

```text
Customer vorhanden
+ Intune Management aktiviert
+ tenantId eindeutig
+ TenantSlug eindeutig
        ↓
CUST-* auflösen
        ↓
Intune-<TenantSlug> auflösen/provisionieren
        ↓
CustomerConfiguration-Zuordnung persistieren
        ↓
später: Monitor-Registrierung
```

### Mehrere Tenants

Jeder weitere Tenant erhält eine eigene Registry-Zeile und ein eigenes Repository.

```text
CUST-4711-Contoso
├── Intune-contoso-prod
└── Intune-contoso-lab
```

### Umfirmierung / Tenant-Umbenennung

CustomerNumber und `tenantId` bleiben die stabilen Identitäten. Namen und Domains können aktualisiert werden, ohne Repositorynamen automatisch zu verändern.

### Deaktivierung

Das Deaktivieren von Intune Management löscht weder Repository noch Historie automatisch. Entfernen/Archivieren eines Tenant-Repositories erfordert einen expliziten Decommission-/Retention-Workchunk.

## 8. IntuneCD Monitor

IntuneCD Monitor darf die Customer-/Tenant-Zuordnung operativ cachen und eigene Laufzeitdaten wie Schedules, Jobstatus oder letzte Backups halten.

Nicht zulässig ist, die Monitor-Datenbank zum alleinigen kanonischen Verzeichnis von

```text
CustomerNumber ↔ tenantId ↔ Repository
```

zu machen.

Die versionierte CustomerConfiguration bleibt Source of Truth für diese Zuordnung. Die konkrete automatische Monitor-Registrierung bleibt technisch offen.

## 9. Snapshot-Perspektive

Jeder durch IntuneCD aus diesem Kunden-Tenant erzeugte und als erfolgreich validierte Snapshot ist grundsätzlich:

```text
perspective = actual
```

Der freigegebene Sollstand bleibt separat:

```text
30-IDD / IntuneDefaultDeployment
→ perspective = desiredDeployment
```

Das Customer-Intune-Repository wird nicht dadurch zum Desired-State-Repository, dass IntuneCD grundsätzlich auch Update-/Restore-Funktionen besitzt.

## 10. Security- und Secret-Grenze

Bis ein genauer IntuneCD-Modul-/Secretvertrag nachgewiesen ist, gilt Fail Closed:

- keine bekannten Secretwerte bewusst committen,
- keine Repositorycredentials im Repository oder in `customer.yml`,
- keine PAT-basierte Tenant-Registry,
- Snapshot-Validierung/Sanitization muss vor der DocumentationEngine-Nutzung einen expliziten Status liefern,
- Module, die besonders sensible Werte exportieren können, werden erst nach eigener Prüfung produktiv freigegeben.

## 11. Customer-Onboarding-Zielvertrag

PlatformBootstrap bleibt Owner der Provisionierung.

Der spätere idempotente Onboarding-/Reconciliation-Pfad muss mindestens diese Semantik unterstützen:

```text
0 Intune-Tenants
→ kein Intune-Repository

1 Intune-Tenant
→ genau ein Intune-<TenantSlug>-Repository

n Intune-Tenants
→ genau n eindeutig zugeordnete Intune-<TenantSlug>-Repositories
```

Er muss vor Mutation prüfen:

- CustomerNumber löst genau ein `CUST-*`-Projekt auf,
- jede `tenantId` ist ein gültiger GUID-Wert,
- jeder TenantSlug ist normalisiert und innerhalb des Projekts eindeutig,
- Repositoryname und Registry widersprechen sich nicht,
- vorhandene Repositories werden niemals aufgrund einer bloßen Namensähnlichkeit übernommen.

Die genaue CLI-/Pipeline-Parameteroberfläche (`-IntuneTenants`, separates Add-Kommando oder vergleichbarer strukturierter Input) wird erst im Implementierungsworkchunk festgelegt.

## 12. Status

### Bereits beschlossen

- ein eigenes Repository pro produktiv verwaltetem Intune-Tenant,
- Namensschema `Intune-<TenantSlug>`,
- `tenantId` als stabile technische Tenant-Identität,
- persistierter, nach Erstregistrierung nicht automatisch veränderter `TenantSlug`,
- kanonische Zuordnung in `CustomerConfiguration/customer.yml` unter `intune.tenants[]`,
- Customer-Intune-Repositories sind `RAW-CONFIDENTIAL`,
- Customer-Intune-Snapshots sind `actual`,
- Monitor-Laufzeitdaten dürfen die versionierte CustomerConfiguration nicht als Source of Truth ersetzen,
- Deaktivierung löscht Repository/Historie nicht automatisch.

### Bereits implementiert

- dieser fachliche Repositoryvertrag.

### Noch offen

- technische Erweiterung von `New-BSSECustomerProject.ps1`, `Start-BSSECustomerOnboarding.ps1` und den Customer-Onboarding-Pipelines,
- konkrete strukturierte Eingabeoberfläche für `0..n` Intune-Tenants,
- technische `customer.yml`-Merge-/Reconciliation-Implementierung,
- Seed-/Default-Branch-Vertrag des neuen Repositorytyps,
- Repository-spezifische Azure-DevOps-Berechtigungen,
- automatische IntuneCD-Monitor-Registrierung,
- BSSE Intune Snapshot Schema v1,
- IntuneCD-/Monitor-Runtime und Identity,
- DocumentationEngine Intune Source Adapter.
