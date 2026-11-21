### Neu
- Prüfregel `architecture-feature-cycle`: meldet am uses-Eintrag, wenn eine Unit einen Zyklus zwischen Features desselben Präfixes schließt (etwa `Atlas.Core.Lsp` ↔ `Atlas.Core.Hover`) oder gegen eine Richtung aus `directions` verstößt (`"Atlas.Common: Lsp | Rules | Editing | Mcp"`: keine Kante zwischen diesen Features; `"Atlas.Common: Semantics < Lsp"`: Semantics verwendet Lsp nicht). Bestehende Zyklen und Kanten lassen sich in `known` bzw. `knownEdges` festhalten; ein Eintrag, der nicht mehr vorkommt, ist ein Fehler. Dieselbe Prüfung läuft als `Tools/Check-FeatureCycles.ps1` in der CI, beide mit derselben Fallliste.

### Geändert
- Atlas selbst hat keine Zyklen zwischen Features mehr: Gemeinsame Typen liegen im unteren Feature (Inlay-Hinweise und Projektkontext im Vertrag der Sitzung, Statussignal in `Atlas.Core.Status.Signal`, abgesicherte Sitzung in den Schnellschaltern, Kennzahlentexte der Brotkrumen-Karte im Feature Popup, Sammelkorrektur-Dialog im Feature Rules).
