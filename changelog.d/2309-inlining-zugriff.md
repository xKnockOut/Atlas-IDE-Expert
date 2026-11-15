### Behoben
- `inline-not-expanded` (H2443) nach dem Delphi-13-Bau geschärft (#2309): Die Regel verlangt die Unit der inline-Routine selbst, wenn ihr Rumpf Verweise hat (`ListView.Columns.Count` ohne `System.Classes`, `TCollection.GetCount`), die Unit hinter einem Alias als Ergebnistyp (`Font.Style` ohne `System.UITypes`, `TFont.GetStyle`) und bei Feldern generischer Instanzen nur noch den Bedarf eines inline-Mitglieds (`TJSONArray[0]` über `TList<T>.GetItem` braucht `System.Generics.Collections`, `TJSONArray.Count` liest in Delphi 13 nur ein Feld).
- `caption-string-helper` (E2018) erkennt `TCaption` auch über neu deklarierte Properties wie `Label.Caption` und `Memo.Text`, über Felder und Unterobjekte (`Dialog.Parts.Content.DescriptionMemo.Text`): Die Namensauflösung übernimmt Typ und Zugriffe der geerbten Property auch dann, wenn diese im Vorfahren `protected` ist (#2309).
- `dunitx-areequal-length` (E2532) meldet auch Rechnungen wie `Length(Zeilen) - 1` gegen eine Ganzzahl (#2309).
- W1050 (Regel der String-Umwandlungen) meldet Zeichen und Zeichenliterale in einer Menge vom Typ `TSysCharSet` (`'}' in AStops`), Korrektur `CharInSet` (#2309).

### Tests
- `inaccessible-member` (E2361): private statische Klassenmethode einer anderen Unit hinter einem `public const`-Abschnitt als Testfall (#2309).
