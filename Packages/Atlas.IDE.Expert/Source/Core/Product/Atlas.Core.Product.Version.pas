unit Atlas.Core.Product.Version;

// Version des Plugins (#493: steht in jeder Fehlerzeile des Protokolls). Das
// Plugin bindet Atlas.Common nicht ein; Tools/Set-Version.ps1 schreibt die
// Version hier und in Atlas.Common.Product.Version, Tools/Check-Version.ps1
// prüft, dass beide übereinstimmen.

interface

type
  TAtlasPluginVersion = class
  public const
    Version = '0.1.0';
  end;

implementation

end.
