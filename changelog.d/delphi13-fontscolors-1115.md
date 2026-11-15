### Behoben
- Delphi-Bau von main-merging: `Atlas.IDE.Designer.FontsColors` bindet `DesignIntf` im Interface-Teil ein, `SelectNames` nutzt `IDesigner` in der Klassendeklaration (E2003).

### Tests
- Gemerkte Komponenten und Haltepunkt-Sätze: einmaliger Speicher bei erster Benutzung wird in `[SetupFixture]` vorab angelegt, der Leckmonitor schrieb ihn dem ersten Test zu (auch im Einzellauf).
