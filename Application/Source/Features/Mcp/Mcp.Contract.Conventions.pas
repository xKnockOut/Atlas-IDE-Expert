unit Mcp.Contract.Conventions;

// Was die Ressource delphi://conventions (#272) und explain_finding vom Server brauchen: Konventionen des Projekts
// und den Auftrag zu einem Befund als Markdown. Der Host verbindet es mit Rules (Adapters.Mcp.Conventions); die
// MCP-Werkzeuge kennen nur diese Unit.

interface

uses
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Findings.Contract;

type
  IMcpConventions = interface
    ['{6CFD1DFC-2F8F-4C3E-BFB5-E1AE14976C16}']
    /// <summary>Regelprofil, Formatstil, Benennungsregeln und aktive Prüfregeln nach ASettings.</summary>
    function Markdown(const ASettings: TServerSettings): string;
  end;

  IMcpFindingPrompts = interface
    ['{0DE6EA9B-359B-437C-A365-6FA279EE7029}']
    /// <summary>Auftrag zu AFinding in AText (Datei AFileName).</summary>
    function Markdown(const AFinding: TRuleFinding; const AFileName, AText: string): string;
  end;

implementation

end.
