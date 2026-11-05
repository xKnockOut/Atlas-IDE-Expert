unit Shell.Mcp.Conventions;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Ressource „Projektkonventionen“ (#272): Regelprofil, Formatstil,
// Benennungsregeln und aktive Prüfregeln des Projekts als Markdown. Name und Beschreibung der Ressource in der
// Sprache der Oberfläche (#1458). Eigene Unit, damit Shell.Mcp die Prüfregeln nicht kennen muss.

interface

uses
  Atlas.Common.Mcp.Server,
  Shell.Workspace;

type
  TMcpConventions = class
  public
    /// <summary>Uri der Ressource.</summary>
    const Uri = 'delphi://conventions';
    /// <summary>Meldet die Ressource an AServer an; gelesen wird erst beim Abruf, mit den Einstellungen von
    /// AWorkspace zu diesem Zeitpunkt.</summary>
    class procedure Register(AServer: TMcpServer; AWorkspace: TShellWorkspace); static;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Localization.Texts;

type
{$SCOPEDENUMS ON}
  TMcpConventionsText = (Name, Description);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TMcpConventionsText] of TAtlasText = (
    (De: 'Projektkonventionen'; En: 'Project conventions'),
    (De: 'Regelprofil, Formatstil, Benennungsregeln und aktive Prüfregeln des Projekts als Markdown.';
    En: 'Rule profile, format style, naming rules and active check rules of the project as Markdown.'));

/// <summary>Projektkonventionen (#272) als Markdown; eigene Routine, damit die anonyme Methode nur AWorkspace
/// einfängt.</summary>
function ConventionsOf(AWorkspace: TShellWorkspace): TFunc<string>;
begin
  Result :=
    function: string
    var
      mCatalog: TRuleCatalog;
    begin
      mCatalog := TFindingPrompt.GermanCatalog;
      try
        Result := TRuleConventions.Markdown(BuiltinRules, AWorkspace.Configuration.Settings, mCatalog);
      finally
        mCatalog.Free;
      end;
    end;
end;

class procedure TMcpConventions.Register(AServer: TMcpServer; AWorkspace: TShellWorkspace);
begin
  AServer.AddResource(Uri, cTexts[TMcpConventionsText.Name].Text, cTexts[TMcpConventionsText.Description].Text,
    'text/markdown', ConventionsOf(AWorkspace));
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.Conventions', cTexts);

end.
