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
  Atlas.Common.Lsp.StatusFile;

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
        mSource := Format('Atlas-Server der IDE (Prozess %d, Stand %s)',
          [mPid, FormatDateTime('hh":"nn":"ss', mWritten)]);
        if AJson then
        begin
          mObject.AddPair('source', mSource);
          mObject.RemovePair('markdown').Free;
          Exit(mObject.Format(2));
        end;
        mMarkdown := '';
        if mObject.GetValue('markdown') is TJSONString then
          mMarkdown := mObject.GetValue('markdown').Value;
        Exit('Quelle: ' + mSource + #10#10 + mMarkdown);
      end;
    finally
      mValue.Free;
    end;
  end;
  mStatus := AOwn();
  mSource := 'dieser MCP-Prozess (für den Ordner läuft gerade kein Atlas-Server der IDE)';
  mObject := mStatus.ToJson;
  try
    if AJson then
    begin
      mObject.AddPair('source', mSource);
      mObject.RemovePair('markdown').Free;
      Result := mObject.Format(2);
    end
    else
      Result := 'Quelle: ' + mSource + #10#10 + mStatus.ToMarkdown;
  finally
    mObject.Free;
  end;
end;

end.
