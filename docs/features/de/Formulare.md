# Formulare

Zurück zum [README](../../../README_DE.md)

- Offene Formulare gehen im Stand des Designers an den Server: Referenzen, Umbenennen und Prüfungen sehen auch ungespeicherte Komponenten
- Umbenennen eines Ereignis-Handlers ändert auch seine Zuordnung im Designer
- Komponenten des Formulars in der Vervollständigung, `Sender` mit passender Typumwandlung
- Prüfungen zwischen Formular und Code sowie **Eigenschaftsregeln** für Formulardateien mit Schnellkorrektur
- Binäre Formulare in Textformulare umwandeln

## Im Designer

Befehle der [Designer-Leiste](Navigieren.md#designer-leiste) für die Auswahl im Formular-Designer:

- **Gleiche auswählen** (#738): alle Komponenten derselben Klasse, auch mit Nachfahren (bei Mehrfachauswahl ab der gemeinsamen Basisklasse), desselben Elternelements, die Kinder oder alle Nachkommen eines Containers, mit demselben gespeicherten Eigenschaftswert (`Font.Name = 'Tahoma'`) oder demselben Ereignis-Handler; dazu „Auswahl umkehren“. Jeder Eintrag nennt die Trefferzahl, Umschalt beim Klick ergänzt die Auswahl. Bereich ganzes Formular oder nur das Elternelement (`designer.selectSimilar.scope`).
