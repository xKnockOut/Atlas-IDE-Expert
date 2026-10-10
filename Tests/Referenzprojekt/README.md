# Referenz-Testprojekt

Delphi-Projekt, auf das sich Abnahmekriterien („im Testprojekt“) und die
Messung der Regelqualität (#152) beziehen. Es gehört nicht zur
Projektgruppe des Servers und wird von dessen Build nicht übersetzt.

## Inhalt

| Datei | Zweck |
|---|---|
| `RefGruppe.groupproj` | Projektgruppe mit allen drei Projekten |
| `RefRuntime.dpk` | Runtime-Package mit der Komponente |
| `RefDesign.dpk` | Design-Time-Package, registriert die Komponente |
| `RefApp.dpr` | VCL-Anwendung mit Formularen, Frame und Datenbankzugriff |
| `Source/Ref.Komponenten.Anzeige.pas` | Komponente mit `published`-Properties samt `default`, `Notification`, `Paint` |
| `Source/Ref.Komponenten.Registrierung.pas` | `Register` für das Design-Time-Package |
| `Source/Ref.Formulare.Haupt.pas/.dfm` | Hauptformular |
| `Source/Ref.Formulare.Detail.pas/.dfm` | Von `TBasisFormular` geerbtes Formular (`inherited` in der DFM) |
| `Source/Ref.Formulare.Basis.pas/.dfm` | Basisformular |
| `Source/Ref.Formulare.Suchrahmen.pas/.dfm` | Frame |
| `Source/Ref.Sprache.Merkmale.pas` | Generics, Interfaces, Class Helper, anonyme Methoden, Inline-Variablen, `{$IFDEF WIN32/WIN64}` |
| `Source/Ref.Daten.Kunden.pas` | FireDAC-Zugriffe für die Framework-Profile |
| `Source/Ref.Pruefung.Verstoesse.pas` | Bewusst eingebaute Regelverstöße |
| `Source/Ref.Daten.Auftraege.pas` mit `.inc`, `.Rumpf.inc` | Deklarationen und Rümpfe aus Include-Dateien (#500) |
| `Source/Ref.Daten.Verwendung.pas` | Nutzt die Typen aus der Include-Datei aus einer anderen Unit (#500) |

## Markierung erwarteter Treffer

Jeder bewusst eingebaute Verstoß trägt am Zeilenende einen Kommentar

```pascal
// ERWARTET: <regel-id>
```

Die Zeile mit dem Kommentar ist die Zeile, auf der der Treffer erwartet
wird. Mehrere Regeln werden mit Komma getrennt. Zeilen mit
`// KEIN-TREFFER: <regel-id>` sind Gegenbeispiele, auf denen die Regel
nicht anschlagen darf. Ein Werkzeug für #152 kann so Treffer und
Fehlalarme zählen, ohne Zeilennummern zu pflegen.

## Öffnen

`RefGruppe.groupproj` in RAD Studio öffnen. Die `.dproj`-Dateien sind
bewusst minimal; die IDE ergänzt sie beim ersten Speichern.

Die eingebauten Verstöße erzeugen beim Übersetzen absichtlich Hinweise
(z. B. H2164 für die ungenutzte Variable). Die Regel „0 Hinweise“ gilt
für den Server, nicht für dieses Projekt.
