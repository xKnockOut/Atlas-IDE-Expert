### Behoben
- Vervollständigung von `inherited`: Parameter mit Zeichenkette im Standardwert (etwa `const S: string = ';'`) werden nicht mehr an einem Semikolon innerhalb der Zeichenkette getrennt.

### Geändert
- Gemeinsame Helfer statt Kopien: Dateiname für die Namensauflösung der Prüfregeln (`TRuleContext.ResolverFileName`), Knoten in Baumreihenfolge und Vorkommen eines Bezeichners (`TSyntaxNode`), Teilen von Parameterlisten (`TRoutineSignatures.SplitTopLevel`) und die oberste Editoransicht (`TAtlasEditorBuffer.TopView`). Die Kopien-Sperre in `Tools/Check-PackageDependencies.ps1` kennt die alten Namen.
