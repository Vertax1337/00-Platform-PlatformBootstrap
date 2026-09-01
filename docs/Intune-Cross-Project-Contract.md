# Intune Cross-Project Contract – `30-IDD` / `CUST-*` / `DocumentationEngine`

> **Status:** Fachliche Boundary, Ownership und CUST-Intune-Repositoryvertrag BESCHLOSSEN; technische Snapshot-Serialisierung, Runtime, Identity und Adapterimplementierung teilweise OFFEN.  
> **Stand:** 2026-09-01

## 1. Zweck

Dieser Vertrag definiert die projektübergreifende Verantwortungsgrenze für den Intune Configuration Lifecycle zwischen:

```text
00-Platform / PlatformBootstrap
30-IDD
CUST-<CustomerNumber>-<CustomerSlug>
00-Platform / DocumentationEngine
```

Der vollständige Vertrag wird nicht in allen beteiligten Repositories dupliziert. `PlatformBootstrap` hält die kanonische Plattform-/Ownership-Grenze. Die `DocumentationEngine` hält ihren eigenen fachlichen Consumer-/Adaptervertrag für Intune-Daten.

Ein eigenständiges `30-IDD`-GitHub-Arbeitsrepository ist zum Zeitpunkt dieser Entscheidung nicht vorhanden. Deshalb wird dort aktuell kein paralleler Vertragsstand erzeugt. Sobald die Azure-DevOps-Struktur produktiv provisioniert und das erste `30-IDD`-Repository befüllt wird, muss dessen eigener Umsetzungsplan auf diesen Vertrag verweisen und nur die `30-IDD`-spezifische Producer-/Runtime-Seite ergänzen.

Der konkrete CUST-seitige Repositoryvertrag ist separat unter [`Intune-Customer-Repository-Contract.md`](Intune-Customer-Repository-Contract.md) dokumentiert und Bestandteil dieser Plattformgrenze.

## 2. Verbindliche Ownership

| Verantwortung | Kanonischer Owner |
|---|---|
| Provisionierung von `30-IDD` und zentralen Basis-Repositories | `00-Platform / PlatformBootstrap` |
| Provisionierung der `CUST-*`-Boundary | `00-Platform / PlatformBootstrap` |
| Intune Default Deployment / freigegebener Sollstand | `30-IDD / IntuneDefaultDeployment` |
| Intune Backup / Compare / kontrolliertes Update | `30-IDD` über IntuneCD / IntuneCD Monitor |
| Techniker-Frontend für den Intune Lifecycle | `30-IDD` / IntuneCD Monitor |
| Kundenspezifischer Intune-Iststand | jeweilige `CUST-*`-Boundary |
| Tenant→Repository-Registry | `CUST-* / CustomerConfiguration` |
| Providerunabhängige Interpretation / Canonical Model | `00-Platform / DocumentationEngine` |
| Intune Source Adapter und Evidence-/Coverage-Semantik | `00-Platform / DocumentationEngine` |
| Actual-/Desired-Reconciliation | `00-Platform / DocumentationEngine` |
| Finale Kundendokumentation / DVM | `00-Platform / DocumentationEngine` |

## 3. Projekt- und Repositorygrenzen

### 3.1 `30-IDD`

Initialer Bootstrap-Vertrag:

```text
30-IDD
└── IntuneDefaultDeployment
```

`30-IDD` ist die zentrale Intune Control Plane. Weitere Repositories für IntuneCD, IntuneCD Monitor oder gemeinsame Intune-Komponenten werden erst nach ihrem technischen Integrationsvertrag provisioniert.

### 3.2 `CUST-*`

Kundenspezifische Intune-Snapshots werden nicht als zentraler Sammeldatenbestand in `30-IDD` gespeichert.

**Beschlossen:** Jeder produktiv verwaltete Intune-Tenant erhält innerhalb seiner `CUST-*`-Boundary genau ein eigenes versioniertes Repository für den Intune-Iststand.

Verbindliches Namensschema:

```text
Intune-<TenantSlug>
```

Beispiel:

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
├── Intune-contoso-prod
└── Intune-contoso-lab
```

Der Repositoryname ist menschenlesbar, aber keine technische Tenant-Identität.

Verbindliche stabile Zuordnung:

```text
Customer Identity → CustomerNumber
Intune Tenant      → Microsoft Entra Tenant ID
Repository Alias   → persistierter TenantSlug
```

Die kanonische `tenantId ↔ TenantSlug ↔ Repository`-Zuordnung liegt versioniert in `CustomerConfiguration/customer.yml` unter `intune.tenants[]`. Mehrere Intune-Tenants pro Kunde sind damit ausdrücklich unterstützt.

Der `TenantSlug` wird bei der ersten Registrierung persistiert und durch spätere Tenant-/Domain-/Kunden-Umbenennungen nicht automatisch geändert. Abweichende oder mehrdeutige Zuordnungen führen Fail Closed zu `BLOCKED`.

Details: [`Intune-Customer-Repository-Contract.md`](Intune-Customer-Repository-Contract.md).

## 4. Actual State und Desired State

Verbindliche Perspektivgrenze:

```text
IntuneCD Backup aus realem Kunden-Tenant
→ ACTUAL

freigegebener Stand in 30-IDD / IntuneDefaultDeployment
→ DESIRED DEPLOYMENT
```

Ein Git-Commit wird nicht allein durch seine Existenz zu Desired State. Desired State entsteht erst durch den freigegebenen `30-IDD`-Workflow und dessen versionierten Commit-/Releasebezug.

Der operative `baseline`-Status von IntuneCD Monitor ist kein Ersatz für die kanonische Desired-State-Quelle.

Actual und Desired werden nicht implizit zusammengeführt. Ein Abgleich erfolgt ausschließlich über einen expliziten Reconciliation-Contract der DocumentationEngine.

## 5. BSSE Intune Snapshot Contract

Zwischen IntuneCD/Monitor, Customer-Repository und DocumentationEngine wird ein kleiner versionierter Snapshot-/Provenance-Contract eingeführt.

Dieser Contract kapselt die jeweilige native IntuneCD-Ausgabe und verhindert, dass zentrale Plattformkomponenten direkt an eine zufällige Verzeichnisstruktur oder einzelne IntuneCD-Version gekoppelt werden.

Logisches Zielbild:

```text
Intune Tenant
    ↓
IntuneCD
    ↓
nativer IntuneCD Output
    +
BSSE Snapshot / Provenance Envelope
    ↓
versionierter Commit im CUST-* Intune-Repository
    ↓
DocumentationEngine Intune Adapter
```

### 5.1 Verbindliche semantische Mindestinformationen

Der technische Contract muss mindestens folgende Informationen transportieren können:

- Contract-/Schema-Version,
- `customerNumber`,
- `tenantId`,
- eindeutige `snapshotId`,
- Perspektive (`actual` bzw. für den freigegebenen Sollstand `desiredDeployment`),
- Capture-/Build-Zeitpunkt, soweit für die Perspektive relevant,
- Source Tool und Tool-Version,
- Repository- und immutable Commit-Provenance,
- Referenz auf den freigegebenen Desired-State-Commit/Release bei `desiredDeployment`,
- enthaltene Intune-/Entra-Domänen,
- explizit ausgeschlossene bzw. nicht erhobene Domänen,
- Referenzen auf die eigentlichen Artefakte,
- Artefakt-Hashes bzw. eine gleichwertige Integritätsprovenance,
- Validierungsstatus,
- Security-/Sanitization-Status,
- Coverage-/Unavailable-Informationen.

Die **konkrete JSON-/YAML-Repräsentation, Dateibenennung und Schema-Technologie sind noch OFFEN** und werden nicht durch dieses Dokument vorweggenommen.

## 6. Stable Identity

Repository- oder Dateinamen dürfen nicht als primäre technische Objektidentität dienen.

Für Intune-/Entra-Objekte werden die von Microsoft Graph bzw. der belegten Source gelieferten stabilen technischen IDs bevorzugt und in Evidence/Source References erhalten.

IntuneCDs `--append-id` kann später als Betriebsstandard für stabilere Dateinamen beschlossen werden, ist aber **nicht** Voraussetzung für die kanonische Identität der DocumentationEngine.

Name-only-Korrelation ist unzulässig.

## 7. IntuneCD Native Output und Compare

Die native IntuneCD-Struktur bleibt die quellspezifische Provider-Ausgabe. Sie ist nicht selbst das providerunabhängige Canonical Model.

Die native IntuneCD Markdown-/HTML-Dokumentation kann als Spezial-/Technikeransicht erhalten bleiben, ist aber nicht die kanonische BSSE-Kundendokumentation.

`IntuneCD-startcompare` darf als provider-spezifische Vergleichs-/Evidence-Hilfe verwendet werden. Es ersetzt nicht den providerunabhängigen Reconciliation-Contract der DocumentationEngine.

## 8. DocumentationEngine-Grenze

Die DocumentationEngine konsumiert ausschließlich einen validierten Snapshot-/Source-Contract und erzeugt daraus einen Intune-spezifischen Canonical Graph.

Sie darf insbesondere nicht:

- live parallel erneut denselben Tenant inventarisieren,
- Beziehungen aus Namensähnlichkeit ableiten,
- fehlende Policies, Assignments oder Gruppen aus Referenzarchitekturen ergänzen,
- Actual und Desired stillschweigend mischen,
- native IntuneCD Markdown-Dokumentation als Source of Truth parsen.

Der Consumer-/Adaptervertrag wird in der DocumentationEngine unter `docs/INTUNECD_INTERFACE.md` geführt.

## 9. Customer-Onboarding

PlatformBootstrap bleibt Owner der Customer Boundary.

Für einen aktivierten Intune-Lifecycle gilt fachlich bereits:

```text
CustomerNumber
+ 0..n Intune-Tenants
  - tenantId
  - name
  - persistierter TenantSlug
        ↓
CUST-* Boundary auflösen
        ↓
pro Tenant Intune-<TenantSlug> auflösen/provisionieren
        ↓
CustomerConfiguration / intune.tenants[] persistieren
        ↓
später: Repository-/Tenant-Metadaten an 30-IDD / Monitor übergeben
```

Das bestehende `customer.tenantId` wird nicht stillschweigend zum Multi-Tenant-Intune-Register umdefiniert. Die genaue CLI-/Pipeline-Parameteroberfläche und Monitor-Registrierung bleiben technisch OFFEN.

## 10. Nicht durch diesen Vertrag entschieden

Noch offen bleiben insbesondere:

- exakter Name und Anzahl zusätzlicher `30-IDD`-Repositories,
- Fork-/Upstream-Strategie für IntuneCD und IntuneCD Monitor,
- Hosting-/Runtime-Technologie des Monitors,
- Azure-Repos-Authentifizierung des Monitors,
- konkrete Microsoft-Graph-Berechtigungen,
- genaue Trennung von Backup- und Deployment-Identitäten,
- technische Customer-Onboarding-Implementierung für `0..n` Intune-Tenants,
- Seed-/Default-Branch-Vertrag der Customer-Intune-Repositories,
- technisches Snapshot-Schema und Serialisierungsformat,
- konkrete Pipeline-/Trigger-Integration,
- technische Intune-Adapterimplementierung,
- Reconciliation Result Model und Property-Level-Driftumfang.

## 11. Status

### Bereits beschlossen

- `30-IDD` ist die zentrale Intune Control Plane.
- `IntuneDefaultDeployment` ist die versionierte Desired-State-Quelle.
- IntuneCD-Kundenbackup ist Actual State.
- Kundenspezifische Intune-Snapshots bleiben in der `CUST-*`-Boundary.
- Ein produktiv verwalteter Intune-Tenant erhält genau ein eigenes versioniertes Customer-Repository `Intune-<TenantSlug>`.
- CustomerNumber und Entra Tenant ID sind die stabilen Customer-/Tenant-Identitäten; TenantSlug ist ein persistierter menschenlesbarer Repositoryalias.
- Die kanonische Tenant→Repository-Zuordnung liegt in `CustomerConfiguration/customer.yml` unter `intune.tenants[]`.
- Customer-Intune-Repositories sind bis zur feineren Datenklassifikation `RAW-CONFIDENTIAL`.
- BSSE führt einen versionierten Snapshot-/Provenance-Contract zwischen IntuneCD, Customer-Repository und DocumentationEngine ein.
- IntuneCD Native Docs und Compare bleiben provider-spezifische Hilfen und ersetzen weder DVM noch Reconciliation.

### Bereits implementiert

- dieser Cross-Project-Contract in `PlatformBootstrap`,
- fachlicher CUST-Intune-Repositoryvertrag unter `docs/Intune-Customer-Repository-Contract.md`,
- initiale `30-IDD/IntuneDefaultDeployment`-Provisionierung im Core-Bootstrap.

### Noch offen

- physische `30-IDD`-Provisionierung/Runtime-Verifikation in Azure DevOps,
- technische Customer-Onboarding-Erweiterung für `Intune-<TenantSlug>`,
- technische Snapshot-Schemaimplementierung,
- IntuneCD-/Monitor-Runtime und Identity,
- DocumentationEngine Intune Adapter,
- providerunabhängige Reconciliation-Implementierung.
