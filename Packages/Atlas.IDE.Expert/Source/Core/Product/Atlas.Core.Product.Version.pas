unit Atlas.Core.Product.Version;

// Version des Plugins (#493: steht in jeder Fehlerzeile des Protokolls). Die
// Versionsangabe steht nur in Atlas.Text.Product.Version, gemeinsam mit Server
// und Installer (ADR 0012); Tools/Set-Version.ps1 schreibt sie dort.

interface

uses
  Atlas.Text.Product.Version;

type
  TAtlasPluginVersion = class
  public const
    Version = TAtlasVersion.Version;
  end;

implementation

end.
