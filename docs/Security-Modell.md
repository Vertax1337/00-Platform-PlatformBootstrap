# Security-Modell

## Read-only Documentation

- AzureInfrastructureCollector (Komponente; Repo `10-Automation-AzureInfrastructureCollector`): Read-only
- OPNsenseDocumentation (Modul; Repo `10-Automation-OPNsenseDocumentation`): Verarbeitung verändert die Quell-Firewall nicht
- Fail Closed

## OPNsense RAW Repository

`Firewall-*` ist Schutzklasse **RAW-CONFIDENTIAL**.

Darin können u. a. sensible Netz-, VPN-, Credential- und Zertifikatsinformationen enthalten sein.

Regeln:

1. ein Repository pro Firewall,
2. keine gemeinsame kundenübergreifende RAW-Ablage,
3. Bootstrap schreibt keine Inhalte hinein,
4. keine RAW-Daten in `Documentation`,
5. keine RAW-Daten in `10-Automation`,
6. vor KI-/Dokumentationsverarbeitung zwingend Sanitize + Validate,
7. Repository ACL später restriktiver als normales CustomerConfiguration konfigurieren.

## IaC

- Validate
- Plan/What-If
- Approval
- Deploy
- Verify
