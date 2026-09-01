# Namenskonventionen

## Core-Projekte

- `00-Platform`
- `10-Automation`
- `20-IaC`
- `30-IDD`
- `99-LAB`

## `00-Platform` Repositories

- `PlatformBootstrap`
- `PipelineTemplates`
- `DocumentationEngine`
- `SecurityValidation`
- `SharedModules`

## `10-Automation` Repositories

Für die aktuell bestehenden Automations-Repositories ist die Präfixierung mit dem Azure-DevOps-Projektnamen beschlossen:

```text
10-Automation-AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Lokale Struktur:

```text
Repositorys/
└── DEVOPS_Plattform/
    └── 10-Automation/
        ├── 10-Automation-AzureInfrastructureCollector/
        └── 10-Automation-OPNsenseDocumentation/
```

Die fachlichen Komponenten-/Modulnamen bleiben davon getrennt:

```text
AzureInfrastructureCollector
OPNsenseDocumentation
```

## `30-IDD` Repositories

Initialer verbindlicher Bootstrap-Vertrag:

```text
IntuneDefaultDeployment
```

`30-IDD` ist der zentrale Projektbereich für Intune Default Deployment und den Intune-Konfigurationslebenszyklus. Weitere Repositories für IntuneCD, IntuneCD Monitor oder gemeinsame Intune-Komponenten werden erst nach Abschluss des entsprechenden Integrationsvertrags benannt und provisioniert.

Existiert im bereits angelegten Azure-DevOps-Projekt nur das automatisch erzeugte initiale Repository `30-IDD`, ist dessen kontrollierte Umbenennung zu `IntuneDefaultDeployment` Bestandteil dieses expliziten `30-IDD`-Vertrags.

Details:

```text
docs/Intune-Default-Deployment.md
```

Aus der Präfixentscheidung für `10-Automation` wird **keine globale `<Projektname>-<Repositoryname>`-Konvention** für andere Azure-DevOps-Projekte abgeleitet. Die bestehenden Namen unter `00-Platform`, `20-IaC` und `99-LAB` bleiben unverändert, solange hierzu keine eigene Entscheidung getroffen wurde. Für `30-IDD` gilt separat der oben definierte initiale Repositoryname `IntuneDefaultDeployment` ohne `30-IDD-`-Präfix.

## Kunde

```text
CUST-<CustomerNumber>-<CustomerSlug>
```

## Kunden-Repositories

Basis:

```text
CustomerConfiguration
Documentation
```

Optional pro Firewall:

```text
Firewall-<CustomerSlug>-<FirewallSlug>
```

Optional pro produktiv verwaltetem Intune-Tenant:

```text
Intune-<TenantAlias>
```

Beispiele:

```text
Firewall-Cannon-Deutschland-GmbH-HQ
Firewall-Cannon-Deutschland-GmbH-Branch01
Intune-Primary
Intune-Legacy
```

### `Intune-<TenantAlias>`

`TenantAlias` ist ein explizit beim ersten Intune-Onboarding vergebener, menschenlesbarer und innerhalb des jeweiligen `CUST-*`-Projekts eindeutiger technischer Alias.

Verbindlich gilt:

```text
Customer Identity → CustomerNumber
Tenant Identity   → Microsoft Entra Tenant ID
Repository Name   → Intune-<TenantAlias>
```

Der Repositoryname ist nicht die Tenant-Identität. Domain, Anzeigename oder Aliasänderungen führen deshalb nicht automatisch zu einer Repository-Umbenennung.

Ein Kunde kann 0..n Intune-Tenants besitzen:

```text
CUST-4711-Contoso
├── CustomerConfiguration
├── Documentation
├── Intune-Primary
└── Intune-Legacy
```

Die Zuordnung `Tenant ID ↔ TenantAlias ↔ Repository` wird in `CustomerConfiguration` geführt. Details und Lifecycle-Regeln:

```text
docs/Customer-Intune-Tenant-Repository.md
```

## Service Connections

### Dokumentation / Read-only

```text
sc-cust<CustomerNumber>-azure-reader
```

Diese Verbindung gehört zur Dokumentationsplattform und besitzt ausschließlich die erforderlichen Leserechte.

### IaC Deployment

```text
sc-cust<CustomerNumber>-avd-deploy
sc-cust<CustomerNumber>-vaultwarden-deploy
```

Diese Verbindungen gehören zu den IaC-Produkten unter `20-IaC` und sind ausdrücklich nicht Bestandteil des Customer-/Dokumentations-Onboardings.

### PlatformBootstrap

```text
sc-platform-bootstrap-azdo
```

Diese Verbindung dient ausschließlich der Azure-DevOps-Provisionierung durch den zentralen Customer-Onboarding-Workflow und ist von Dokumentations-Reader- und IaC-Deployment-Identitäten getrennt.

## PlatformBootstrap-Dienstidentität

Microsoft-Entra-App/Service-Principal:

```text
sp-bsse-platform-bootstrap-azdo
```

Federated Credential für die zentrale Service Connection:

```text
fic-sc-platform-bootstrap-azdo
```

Zuordnung:

```text
sp-bsse-platform-bootstrap-azdo
        ↓ Workload Identity Federation
fic-sc-platform-bootstrap-azdo
        ↓
sc-platform-bootstrap-azdo
        ↓ ausschließlich autorisiert für
Customer-Onboarding
```

Die PlatformBootstrap-Identität ist weder Dokumentations-Reader noch IaC-Deployment-Identität.
