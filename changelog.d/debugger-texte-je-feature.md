### Geändert
- Debugger: Die Oberflächentexte liegen je Funktion in einer eigenen Texttabelle (`Atlas.UI.Debug.<Funktion>.Strings`) statt in einer Tabelle für das ganze Modul; Texte, die nur der Debugger nutzt (Arten der Visualisierer, Schrittfilter), sind aus der gemeinsamen Tabelle von Base in den Debugger gewandert. An den angezeigten Texten ändert sich nichts.
