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

## Geschützte Repository-Branches

Branch-Policy-Reconciliation ist eine zentrale PlatformBootstrap-
Verantwortung. Workload-Repositories enthalten ihre Pipeline und
Entwicklerdokumentation, aber keine duplizierte Policy-Provisionierungslogik.

Für geschützte Branches gilt:

1. erforderliche Kommentar- und Build-Policies werden auf den
   exakten Repository-/Branch-Scope begrenzt,
2. IDs und Permission-Bits werden zur Laufzeit aus Azure DevOps aufgelöst,
3. unbekannte, mehrdeutige oder widersprüchliche Zustände führen zu `BLOCKED`,
4. Dry Runs verändern keine Azure-DevOps-Objekte,
5. Apply ist nur lokal durch einen bewusst privilegierten Administrator
   zulässig und wird anschließend per Read-back verifiziert.

Für `20-IaC/Vaultwarden/master` ist kein Human-Review- oder Vier-Augen-Gate
vorgesehen. Der verbindliche Ablauf ist PR, grüne `Vaultwarden-CI` und
Auflösung aller aktiven Kommentare. Eine Minimum-Reviewer-Policy ist kein
Bestandteil des Zielzustands. Nur die exakt bekannte, durch den verworfenen
Bootstrap-Zwischenvertrag erzeugte Signatur darf kontrolliert entfernt werden;
eine fremde Reviewer-Policy wird niemals ungeprüft gelöscht.

### Break Glass

Die projektspezifische Break-Glass-Gruppe ist im Normalzustand leer. Sie erhält
auf dem geschützten Branch ausschließlich:

- `Bypass policies when pushing = Allow`,
- `Bypass policies when completing pull requests = Allow`.

Beide Actions werden ausschließlich über ihre exakten modernen `displayName`-
Werte aus dem aktuellen Git-Security-Namespace aufgelöst. Festgeschriebene
numerische Bits und ein Fallback über den historischen internen Namen
`PolicyExempt` sind verboten. Kann Azure DevOps beide modernen Actions nicht
eindeutig liefern, bleibt der Apply `BLOCKED`.

Die Gruppe vergibt insbesondere kein `Contribute`, `Force push`, `Edit
policies` oder `Manage permissions`. Ein Incident-Benutzer muss `Contribute`
bereits aus seinen regulären Rechten besitzen; andernfalls scheitert der
Incident-Preflight. PlatformBootstrap erweitert die Gruppe nicht um weitere
dauerhafte Rechte.

Normale Benutzer werden einschließlich direkter Zuweisungen und transitiver
Gruppenmitgliedschaften auf beide effektiven Bypass-Rechte geprüft. Bereits
vorhandene fremde Bypass-/Legacy-ACLs werden dokumentiert und bei effektiver
Wirkung als Sicherheitsdrift blockiert, aber weder überschrieben noch
automatisch bereinigt. Ein Rollback entfernt ausschließlich die zwei von
PlatformBootstrap verwalteten modernen Allows der Break-Glass-Gruppe. Dafür
ist der unveränderte Apply-Nachweis erforderlich; weichen Namespace, moderne
Anzeigenamen, interne Action-Namen oder Laufzeit-Bits ab, bleibt der Rollback
`BLOCKED`.
