# Generisches Kunden-Onboarding

## Pflichtfelder

- interne Kunden-/Debitorennummer
- Kundenname

## Optional

- Azure Tenant ID für den bestehenden Azure-Dokumentationsvertrag
- Plattformmodule
- 0..n OPNsense-Firewalls
- künftig 0..n produktiv verwaltete Intune-Tenants

## Beispiel Cannon

```powershell
.\bootstrap\New-BSSECustomerProject.ps1 `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "<DEBITORENNUMMER>" `
  -CustomerName "Cannon Deutschland GmbH" `
  -TenantId "b1e23349-29c5-410c-befa-ee649ea88549" `
  -Modules AzureDocumentation,OPNsenseDocumentation `
  -Firewalls "HQ"
```

Resultat heute:

```text
CUST-<DEBITOR>-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
└── Firewall-Cannon-Deutschland-GmbH-HQ
```

Die technische Intune-Onboarding-Erweiterung ist noch nicht implementiert. Sobald sie umgesetzt wird, ergänzt ein aktivierter Intune-Tenant denselben Customer-Boundary-Vertrag:

```text
CUST-<DEBITOR>-Cannon-Deutschland-GmbH
├── CustomerConfiguration
├── Documentation
├── Intune-cannon-prod
└── Firewall-Cannon-Deutschland-GmbH-HQ
```

## Weitere Firewall später

```powershell
.\bootstrap\Add-BSSECustomerFirewall.ps1 `
  -OrganizationUrl "https://dev.azure.com/BSSE-CloudOps/" `
  -CustomerNumber "<DEBITORENNUMMER>" `
  -Firewalls "Branch01"
```

## Firewall-Namen

`-Firewalls` erwartet logische, stabile Geräte-/Standortbezeichnungen:

```powershell
-Firewalls "HQ","Branch01","Warehouse"
```

Daraus entstehen automatisch Slugs.

## OPNsense-Anbindung

Das erzeugte `Firewall-*` Repo bleibt vollständig leer, bis die OPNsense selbst über `os-git-backup` den ersten Push durchführt.

## Intune-Tenant-Vertrag

Für Intune ist die fachliche Repositorygrenze bereits beschlossen, die CLI-/Pipelineoberfläche aber noch nicht implementiert.

Pro produktiv verwaltetem Tenant gilt:

```text
Intune-<TenantSlug>
```

Die stabile technische Identität ist nicht der Repositoryname, sondern die Microsoft Entra Tenant ID.

Die versionierte Zuordnung wird künftig in `CustomerConfiguration/customer.yml` geführt:

```yaml
intune:
  enabled: true
  tenants:
    - tenantId: "11111111-2222-3333-4444-555555555555"
      name: "Cannon Production"
      slug: "cannon-prod"
      repository: "Intune-cannon-prod"
      classification: "RAW-CONFIDENTIAL"
      purpose: "intunecd-actual-snapshots"
```

Mehrere Tenants pro Kunde sind ausdrücklich zulässig. Jeder Tenant erhält ein eigenes Repository.

Das bestehende `-TenantId` beziehungsweise `customer.tenantId` wird nicht stillschweigend zum Multi-Tenant-Intune-Register umdefiniert. Die zukünftige Oberfläche für `0..n` Intune-Tenants wird separat implementiert.

Details:

```text
docs/Intune-Customer-Repository-Contract.md
docs/Intune-Cross-Project-Contract.md
```

## Hinweis Modulname vs. Repositoryname

Der Bootstrap-Parameter:

```powershell
-Modules OPNsenseDocumentation
```

bleibt unverändert. `OPNsenseDocumentation` ist der fachliche Modulbezeichner. Das zentrale Implementierungsrepository im Projekt `10-Automation` heißt dagegen:

```text
10-Automation-OPNsenseDocumentation
```

Intune ist davon getrennt: Der Intune Configuration Lifecycle gehört nach `30-IDD`; kundenspezifische IntuneCD-Iststände liegen als `Intune-<TenantSlug>` innerhalb der jeweiligen `CUST-*`-Boundary.
