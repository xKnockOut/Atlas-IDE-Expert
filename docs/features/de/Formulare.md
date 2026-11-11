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
- **Auswahlsätze** (#739): Im selben Menü speichert „Auswahl speichern …“ (oder Strg+Umschalt+S im Designer) die Auswahl unter einem Namen je Formular. Strg+Umschalt+1…9 stellt die ersten neun Sätze wieder her; im Menü stellt ein Klick her, Umschalt+Klick fügt hinzu, Strg+Klick entfernt, dazu überschreiben, erweitern, umbenennen, verschieben und löschen. Umbenannte Komponenten bleiben im Satz, gelöschte fallen heraus. Ablage lokal oder gemeinsam neben dem Formular (`designer.selectionSets.storage`), die .dfm bleibt unverändert.
- **Räumliche Navigation** (#745): Alt+Pfeil wählt das nächste Steuerelement in dieser Richtung, Alt+Umschalt+Pfeil fügt es hinzu, Alt+Pos1 wählt das Elternelement, Alt+Ende das Kind oben links, Alt+Bild auf/ab wechselt den Container. Am Rand eines Panels geht es ins Panel daneben (`designer.spatialNavigation.crossContainers`); ein kurzer Rahmen zeigt das Ziel.
