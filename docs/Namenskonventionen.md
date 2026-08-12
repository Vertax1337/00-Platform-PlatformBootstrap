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

```text
sc-cust<CustomerNumber>-azure-reader
sc-cust<CustomerNumber>-avd-deploy
sc-cust<CustomerNumber>-vaultwarden-deploy
```

## `10-Automation` Repositories

Aktuell verifizierte Namen:

```text
AzureInfrastructureCollector
10-Automation-OPNsenseDocumentation
```

Für `10-Automation-OPNsenseDocumentation` ist die Präfixierung mit dem Azure-DevOps-Projektnamen bewusst beschlossen. Daraus wird derzeit **keine globale `<Projektname>-<Repositoryname>`-Umbenennung** für alle vorhandenen Repositories abgeleitet.

Der fachliche Modulparameter `OPNsenseDocumentation` ist davon getrennt und bleibt als Modulname bestehen.
