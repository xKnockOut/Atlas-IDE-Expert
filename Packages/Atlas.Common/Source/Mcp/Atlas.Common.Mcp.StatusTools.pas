unit Atlas.Common.Mcp.StatusTools;

// MCP-Werkzeug get_server_status (#1356): dieselben Zahlen wie das Fenster
// „Atlas-Server“ der IDE, damit Claude bei „Atlas ist langsam“ selbst
// nachsehen kann. Der MCP-Prozess ist nicht der Server der IDE; er liest
// dessen letzten Status aus der Statusdatei (TServerStatusFile, alle 5 s
// geschrieben, solange das Plugin den Server abfragt). Gibt es für den
// Projektordner keinen frischen, zeigt das Werkzeug den Status dieses
// MCP-Prozesses und sagt das dazu. Nur lesend.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Status;

type
  /// <summary>Status dieses Prozesses, falls kein Server der IDE für den Ordner läuft.</summary>
  TMcpOwnStatusFunc = reference to function: TServerStatus;

  TMcpStatusTools = class
  public const
    ToolName = 'get_server_status';
  public
    /// <summary>Text des Werkzeugs: AJson = JSON (mit "source"), sonst Markdown mit Quelle in der ersten Zeile.
    /// </summary>
    class function ServerStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
      const AOwn: TMcpOwnStatusFunc): string; static;
  end;

implementation

uses
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TStatusToolsText = (AtlasServerOfTheIDE, ThisMCPProcessNoAtlas, Source);

const
  cTexts: array[TStatusToolsText] of TAtlasText = (
    (De: 'Atlas-Server der IDE (Prozess %d, Stand %s)'; En: 'Atlas server of the IDE (process %d, state %s)'),
    (De: 'dieser MCP-Prozess (für den Ordner läuft gerade kein Atlas-Server der IDE)';
     En: 'this MCP process (no Atlas server of the IDE is running for the folder right now)'),
    (De: 'Quelle: %s' + #10 + #10;
     En: 'Source: %s' + #10 + #10));

{$SCOPEDENUMS OFF}

class function TMcpStatusTools.ServerStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
  const AOwn: TMcpOwnStatusFunc): string;
var
  mText, mSource, mMarkdown: string;
  mPid: Cardinal;
  mWritten: TDateTime;
  mValue: TJSONValue;
  mObject: TJSONObject;
  mStatus: TServerStatus;
begin
  if TServerStatusFile.Find(ACacheRoot, AFolder, ANow, mText, mPid, mWritten) then
  begin
    mValue := TJSONObject.ParseJSONValue(mText);
    try
      if mValue is TJSONObject then
      begin
        mObject := TJSONObject(mValue);
        mSource := cTexts[TStatusToolsText.AtlasServerOfTheIDE].Fmt([mPid, FormatDateTime('hh":"nn":"ss', mWritten)]);
        if AJson then
        begin
          mObject.AddPair('source', mSource);
          mObject.RemovePair('markdown').Free;
          Exit(mObject.Format(2));
        end;
        mMarkdown := '';
        if mObject.GetValue('markdown') is TJSONString then
        begin
          mMarkdown := mObject.GetValue('markdown').Value;
        end;
        Exit(cTexts[TStatusToolsText.Source].Fmt([mSource]) + mMarkdown);
      end;
    finally
      mValue.Free;
    end;
  end;
  mStatus := AOwn();
  mSource := cTexts[TStatusToolsText.ThisMCPProcessNoAtlas].Text;
  mObject := mStatus.ToJson;
  try
    if AJson then
    begin
      mObject.AddPair('source', mSource);
      mObject.RemovePair('markdown').Free;
      Result := mObject.Format(2);
    end
    else
    begin
      Result := cTexts[TStatusToolsText.Source].Fmt([mSource]) + mStatus.ToMarkdown;
    end;
  finally
    mObject.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Mcp.StatusTools', cTexts);

end.
