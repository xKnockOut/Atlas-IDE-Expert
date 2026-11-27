### Geändert
- Selbstprüfung: Eine genehmigte Architektur-Ausnahme (`allow` in `atlas.json`), die keinen Verstoß mehr abdeckt, meldet `Tools/Check-PackageDependencies.ps1` jetzt als Fehler. Die nach dem Umzug der Versionsverwaltung übrig gebliebene Ausnahme `Atlas.IDE.Tests.Composition -> Atlas.Core.*.Providers.*` ist gestrichen.
- Die letzten beiden wortgleichen Routinen sind zusammengelegt (Kurzname eines Typs über `TTextNames.BareTypeName`, Abbruch der Prozessläufer für git und svn über `TAtlasVcsCancellation`); die Liste bekannter Kopien ist leer.

### Tests
- Zwei Testunits des Plugins übersetzten nicht (Code hinter `initialization` in den Tests des Haltepunkte-Fensters, fehlendes Argument im Rauchtest des Logpunkt-Dialogs); behoben. Die CI meldet Syntaxfehler jetzt im ganzen Repository, auch in Testunits, die nur Delphi übersetzt.
- 105 Hinweise und Warnungen von Atlas in den Tests abgebaut, vor allem Vergleiche in `Assert.IsTrue`, die jetzt mit `Assert.AreEqual` erwarteten und tatsächlichen Wert nennen.
