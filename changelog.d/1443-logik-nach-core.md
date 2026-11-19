### Geändert
- Startprofile und „Beim Öffnen bauen“: Der Ablauf liegt jetzt ohne IDE in Core (`Atlas.Core.StartProfiles.Flow`, `TAtlasOpenBuild.Plan`, `TAtlasOpenBuildTarget`) und ist dort getestet. Die IDE-Units liefern nur noch, was die IDE geladen hat, und bilden die Meldungen. Kein sichtbarer Unterschied (#1443).
