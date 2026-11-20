unit Atlas.Common.Mcp.StatusTools;

// MCP-Werkzeug get_server_status (#1356): dieselben Zahlen wie das Fenster
// „Atlas-Server“ der IDE, damit der KI-Assistent bei „Atlas ist langsam“ selbst
// nachsehen kann. Der MCP-Prozess ist nicht der Server der IDE; er liest
// dessen letzten Status aus der Statusdatei (TServerStatusFile, alle 5 s
// geschrieben, solange das Plugin den Server abfragt). Gibt es für den
// Projektordner keinen frischen, zeigt das Werkzeug den Status dieses
// MCP-Prozesses und sagt das dazu. Nur lesend.
// Aufrufstatistik (#2611): get_server_status hängt die Zahlen der laufenden MCP-Sitzung an (Markdown: Abschnitt,
// JSON: Schlüssel mcp); die Ressource delphi://stats zeigt sie mit dem Verlauf der letzten Tage.

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Lsp.Status,
  Atlas.Common.Mcp.Statistics;

type
  /// <summary>Status dieses Prozesses, falls kein Server der IDE für den Ordner läuft.</summary>
  TMcpOwnStatusFunc = reference to function: TServerStatus;

  TMcpStatusTools = class
  public const
    cToolName = 'get_server_status';
    cStatisticsUri = 'delphi://stats';
  private
    /// <summary>Status aus der Statusdatei des Servers der IDE bzw. dieses Prozesses, ohne Statistik.</summary>
    class function PlainStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
      const AOwn: TMcpOwnStatusFunc): string; static;
  public
    /// <summary>Text des Werkzeugs: AJson = JSON (mit "source"), sonst Markdown mit Quelle in der ersten Zeile.
    /// AStatistics (nil = abgeschaltet) kommt als Abschnitt bzw. Schlüssel mcp dazu.</summary>
    class function ServerStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
      const AOwn: TMcpOwnStatusFunc; AStatistics: TMcpStatistics): string; static;
    /// <summary>Text der Ressource delphi://stats: Sitzung und Verlauf aus AHistoryFile (Zeilen bis ANow); bei nil
    /// der Hinweis, dass die Statistik aus ist.</summary>
    class function StatisticsText(AStatistics: TMcpStatistics; const AHistoryFile: string; ANow: TDateTime): string;
      static;
  end;

implementation

uses
  Atlas.Common.Lsp.StatusFile,
  Atlas.Common.Mcp.StatisticsText,
  Atlas.Common.Mcp.StatisticsHistory,
  Atlas.Common.Localization.Texts,
  Atlas.Text.Json;

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

{ TMcpStatusTools }

class function TMcpStatusTools.ServerStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
  const AOwn: TMcpOwnStatusFunc; AStatistics: TMcpStatistics): string;
var
  mObject: TJSONObject;
begin
  Result := PlainStatus(ACacheRoot, AFolder, AJson, ANow, AOwn);
  if AStatistics = nil then
  begin
    Exit;
  end;
  if not AJson then
  begin
    Exit(TrimRight(Result) + #10 + #10 + TMcpStatisticsText.Markdown(AStatistics.Snapshot));
  end;
  mObject := TJsonRead.ParseObject(Result);
  if mObject = nil then
  begin
    Exit;
  end;
  try
    mObject.AddPair('mcp', AStatistics.Snapshot.Plain.ToJson);
    Result := mObject.Format(2);
  finally
    mObject.Free;
  end;
end;

class function TMcpStatusTools.StatisticsText(AStatistics: TMcpStatistics; const AHistoryFile: string;
  ANow: TDateTime): string;
begin
  if AStatistics = nil then
  begin
    Exit(TMcpStatisticsText.SwitchedOff);
  end;
  Result := TMcpStatisticsText.Markdown(AStatistics.Snapshot) +
    TMcpStatisticsText.HistoryMarkdown(TMcpStatisticsHistory.Read(AHistoryFile, ANow));
end;

class function TMcpStatusTools.PlainStatus(const ACacheRoot, AFolder: string; AJson: Boolean; ANow: TDateTime;
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
