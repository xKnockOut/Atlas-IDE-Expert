### Behoben
- Syntaxprüfung: Nach einem `{$I …}`, das Quelltext einfügt (etwa eine ganze Klassendeklaration), meldet Atlas keine Folgefehler mehr, da der Parser den Inhalt der Include-Datei nicht liest.
- Regel `invalid-var-argument` meldet `@Variable` einer prozeduralen Variable oder eines prozeduralen Feldes an einem `var`-Parameter vom Typ `Pointer` nicht mehr (die Adresse einer Variablen ist dort zulässig).
- Regel `argument-count-mismatch` wählt bei überschriebenen Überladungen ohne `overload` im Nachfahren die passende Fassung der Vorfahrklasse.
- Regeln `property-accessor-invalid`, `default-property` und `property-redeclaration` übergehen Quelltext in inaktiven Bedingungszweigen (`{$IFDEF BCB}`).
- Regel `use-after-free` meldet keinen Zugriff mehr nach `inherited Methode` (die Methode kann das Feld neu belegen) und keine gleichnamigen Mitglieder im Rumpf eines `with`.
- Regel `event-call-without-assigned` hält Funktionszeiger ohne `of object` (etwa aus einer DLL geladene Routinen) nicht mehr für Ereignisse.
