unit Core.Mcp.Conventions;

// Host-Rolle Core: MCP-Modus (--mcp, #48), Ressource „Projektkonventionen“ (#272): Regelprofil, Formatstil,
// Benennungsregeln, aktive Prüfregeln und geschützte Dateien (#2608) des Projekts als Markdown. Name und
// Beschreibung der Ressource in der Sprache der Oberfläche (#1458). Den Teil der Prüfregeln liefert IMcpConventions
// (Rules über den Host-Adapter Adapters.Mcp.Conventions).

interface

uses
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract.Conventions,
  Atlas.Common.Mcp.Contract.Workspace;

type
  TMcpConventions = class
  public
    /// <summary>Uri der Ressource.</summary>
    const cUri = 'delphi://conventions';
    /// <summary>Meldet die Ressource an AServer an; gelesen wird erst beim Abruf, mit den Einstellungen von
    /// AWorkspace zu diesem Zeitpunkt und den Konventionen aus AConventions.</summary>
    class procedure Register(AServer: TMcpServer; const AWorkspace: IMcpWorkspace; const AConventions: IMcpConventions);
      static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Mcp.ProtectedFiles,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpConventionsText = (Name, Description);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpConventionsText] of TAtlasText = (
    (De: 'Projektkonventionen'; En: 'Project conventions'),
    (De: 'Regelprofil, Formatstil, Benennungsregeln, aktive Prüfregeln und geschützte Dateien des Projekts als ' +
      'Markdown.';
    En: 'Rule profile, format style, naming rules, active check rules and protected files of the project as ' +
      'Markdown.'));

/// <summary>Projektkonventionen (#272) als Markdown; eigene Routine, damit die anonyme Methode nur AWorkspace und
/// AConventions einfängt.</summary>
function ConventionsOf(const AWorkspace: IMcpWorkspace; const AConventions: IMcpConventions): TFunc<string>;
var
  mConventions: IMcpConventions;
begin
  mConventions := AConventions;
  Result :=
    function: string
    var
      mProtected: string;
    begin
      Result := mConventions.Markdown(AWorkspace.Settings);
      mProtected := TMcpProtectedFiles.Markdown(AWorkspace.Settings.AssistantProtected);
      if mProtected <> '' then
      begin
        Result := TrimRight(Result) + sLineBreak + sLineBreak + mProtected;
      end;
    end;
end;

{ TMcpConventions }

class procedure TMcpConventions.Register(AServer: TMcpServer; const AWorkspace: IMcpWorkspace;
  const AConventions: IMcpConventions);
begin
  AServer.AddResource(cUri, cTexts[TMcpConventionsText.Name].Text, cTexts[TMcpConventionsText.Description].Text,
    'text/markdown', ConventionsOf(AWorkspace, AConventions));
end;

initialization
  TAtlasTextTables.Add('Core.Mcp.Conventions', cTexts);

end.
