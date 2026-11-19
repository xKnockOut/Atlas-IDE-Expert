### Geändert
- Rollen Adapters und Providers: `Tools/Check-PackageDependencies.ps1` erkennt Interfaces auch über einen Alias (`IAtlasX = IAtlasY;`). Der so gefundene Zuhörer der Debug-Sitzung ist jetzt `TAtlasDebugListener` in Core, sein Vertrag `IAtlasDebugListener` steht in `Atlas.Core.Debug.Contract` (#1443).
