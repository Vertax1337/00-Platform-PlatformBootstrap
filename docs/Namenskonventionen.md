# Namenskonventionen

## Core-Projekte

- `00-Platform`
- `10-Automation`
- `20-IaC`
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

Aus dieser Festlegung für `10-Automation` wird derzeit **keine globale `<Projektname>-<Repositoryname>`-Umbenennung** für Repositories anderer Azure-DevOps-Projekte abgeleitet. Insbesondere bleiben die bestehenden Namen unter `00-Platform`, `20-IaC` und `99-LAB` unverändert, solange hierzu keine eigene Entscheidung getroffen wurde.

## Kunde

```text
CUST-<CustomerNumber>-<CustomerSlug>
```

## Kunden-Repositories

```text
CustomerConfiguration
Documentation
Firewall-<CustomerSlug>-<FirewallSlug>
```

Beispiele:

```text
Firewall-Cannon-Deutschland-GmbH-HQ
Firewall-Cannon-Deutschland-GmbH-Branch01
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