### Behoben
- inline-not-expanded erkennt H2443, wenn eine inline-Routine Mitglieder eines Parameters liest, dessen Typ ein Alias aus einer anderen Unit ist (`A.Line` bei `A: TTextPosition = Atlas.Text.Lines.TTextPosition`): verlangt wird die Unit hinter dem Alias. unused-uses meldet diese Unit deshalb nicht mehr als unbenutzt (#2309).
