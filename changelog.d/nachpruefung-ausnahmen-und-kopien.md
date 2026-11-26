### Geändert
- Selbstprüfung: Eine genehmigte Architektur-Ausnahme (`allow` in `atlas.json`), die keinen Verstoß mehr abdeckt, meldet `Tools/Check-PackageDependencies.ps1` jetzt als Fehler. Die nach dem Umzug der Versionsverwaltung übrig gebliebene Ausnahme `Atlas.IDE.Tests.Composition -> Atlas.Core.*.Providers.*` ist gestrichen.
- Die letzten beiden wortgleichen Routinen sind zusammengelegt (Kurzname eines Typs über `TTextNames.BareTypeName`, Abbruch der Prozessläufer für git und svn über `TAtlasVcsCancellation`); die Liste bekannter Kopien ist leer.
