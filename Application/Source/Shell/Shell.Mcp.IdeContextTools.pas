unit Shell.Mcp.IdeContextTools;

// Host-Rolle Shell: MCP-Modus (--mcp, #48), Zustand der laufenden IDE für KI-Assistenten (get_ide_context, #2050):
// wo der Entwickler gerade ist. Die Dateien liest Shell.Mcp.Ide, Auswahl und Ausgabe Atlas.Common.Mcp.IdeContext.

interface

uses
  Shell.Mcp.Context;

/// <summary>Meldet get_ide_context an.</summary>
procedure RegisterIdeContextTools(const AContext: TMcpToolContext);

implementation

uses
  System.SysUtils,
  System.DateUtils,
  System.JSON,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.IdeContext,
  Atlas.Text.IdeContext,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Timestamps,
  Shell.Mcp.Ide;

type
{$SCOPEDENUMS ON}
  TIdeContextToolText = (Tool, Include, Ide, Format);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TIdeContextToolText] of TAtlasText = (
    (De: 'Zustand der laufenden IDE: offene Datei mit Cursor (ab 1), ungespeichert ja/nein und Methode am Cursor, ' +
      'markierter Text, aktives Projekt mit Konfiguration, Plattform und Projektgruppe, letzter Build mit Fehlern ' +
      'und Warnungen, offene Reiter. Für Fragen wie „diese Methode“ oder „die Auswahl“; Code lesen und prüfen ' +
      'weiter mit den übrigen Werkzeugen. Laufen mehrere IDEs, gilt die mit dem jüngsten Stand.';
     En: 'State of the running IDE: open file with cursor (from 1), unsaved yes/no and method at the cursor, ' +
      'selected text, active project with configuration, platform and project group, last build with errors and ' +
      'warnings, open tabs. For requests like "this method" or "the selection"; read and check code with the ' +
      'other tools. With several IDEs, the one with the newest state wins.'),
    (De: 'Abschnitte: editor, selection, project, build, tabs (Vorgabe: alle)';
     En: 'Sections: editor, selection, project, build, tabs (default: all)'),
    (De: 'Prozess-ID der IDE, wenn mehrere mit Atlas laufen (Vorgabe: jüngster Stand)';
     En: 'Process ID of the IDE when several run with Atlas (default: newest state)'),
    (De: 'text (Vorgabe) oder json'; En: 'text (default) or json'));

/// <summary>Jetzt in UTC: Ortszeit mit Versatz geschrieben und als UTC gelesen (wie unter Windows und Linux).
/// </summary>
function NowUtc: TDateTime;
begin
  Result := TTextTimestamp.IsoOrZero(DateToISO8601(Now, False), True);
end;

function ToolGetIdeContext(const AContext: TMcpToolContext; const AArguments: TJSONObject): string;
var
  mRequest: TMcpIdeContextRequest;
  mContexts: TArray<TIdeContext>;
  mIndex: Integer;
  mReason: string;
begin
  mRequest := TMcpIdeContextRequest.FromArguments(AArguments);
  mContexts := IdeContexts;
  if Length(mContexts) = 0 then
  begin
    Exit(TMcpIdeContext.NoContext(RunningIdePids));
  end;
  mIndex := TMcpIdeContext.Pick(mContexts, mRequest.Ide, mReason);
  if mIndex < 0 then
  begin
    raise EMcpToolError.Create(mReason);
  end;
  Result := TMcpIdeContext.Report(mContexts[mIndex], mRequest, NowUtc);
end;

procedure RegisterIdeContextTools(const AContext: TMcpToolContext);
begin
  AContext.Server.AddTool('get_ide_context', cTexts[TIdeContextToolText.Tool].Text,
    SchemaWith('{"type":"object","properties":{' +
      '"include":{"type":"array","items":{"type":"string","enum":["editor","selection","project","build",' +
      '"tabs"]},"description":%s},' +
      '"ide":{"type":"integer","minimum":1,"description":%s},' +
      '"format":{"type":"string","enum":["text","json"],"default":"text","description":%s}}}',
      [cTexts[TIdeContextToolText.Include].Text, cTexts[TIdeContextToolText.Ide].Text,
      cTexts[TIdeContextToolText.Format].Text]),
    ContextTool(AContext, ToolGetIdeContext));
end;

initialization
  TAtlasTextTables.Add('Shell.Mcp.IdeContextTools', cTexts);

end.
