unit Atlas.Core.Status.Lines;

// Feste Zeilen des Atlas-Statusfelds (#591), ohne VCL und Open Tools API:
// Text, Zustand und Kurztext für Server, Index und aktive Datei aus den
// Daten, die die IDE-Schicht sammelt.
// - Server: nicht gestartet (neutral), wird gestartet (gelb), läuft (grün;
//   gelb ab SlowMs mittlerer Antwortzeit), gestoppt oder Start
//   fehlgeschlagen (rot). Antwortzeit über die letzten 50 Anfragen (#28).
// - Index: wird aufgebaut (gelb, mit Prozent) oder Anzahl Units (grün).
// - Datei: Kodierung und Zeilenende (#121); gemischte Zeilenenden gelb,
//   eine gewählte Umstellung wird beim nächsten Speichern geschrieben.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Files.Format;

type
{$SCOPEDENUMS ON}
  TAtlasServerPhase = (NotStarted, Starting, Running, Stopped, Failed);
{$SCOPEDENUMS OFF}

  TAtlasServerInfo = record
    Phase: TAtlasServerPhase;
    /// <summary>Version aus serverInfo der Antwort auf initialize; '' = unbekannt.</summary>
    Version: string;
    /// <summary>Mittlere Antwortzeit der letzten Anfragen in ms und deren Anzahl.</summary>
    AverageMs: Double;
    Samples: Integer;
    /// <summary>Grund bei Failed (ohne Pfade).</summary>
    Error: string;
  end;

  TAtlasIndexInfo = record
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    Units: Integer;
    Indexing: Boolean;
    /// <summary>Fortschritt beim Aufbau; -1 = unbekannt.</summary>
    Percent: Integer;
  end;

  TAtlasFileInfo = record
    /// <summary>Name ohne Pfad; '' = keine Datei aktiv.</summary>
    Name: string;
    Known: Boolean;
    Format: TAtlasFileFormat;
    /// <summary>Gewählte Umstellung, die beim Speichern geschrieben wird.</summary>
    HasTarget: Boolean;
    Target: TAtlasFileFormat;
  end;

  TAtlasStatusLines = class
  public const
    ServerId = 'atlas.server';
    IndexId = 'atlas.index';
    FileId = 'atlas.file';
    ServerOrder = 0;
    IndexOrder = 10;
    FileOrder = 20;
    /// <summary>Ab dieser mittleren Antwortzeit gilt der Server als langsam.</summary>
    SlowMs = 500;
    /// <summary>Status-Befehl des Servers (#28); liefert u. a. "units".</summary>
    StatusCommand = 'atlas.server.status';
    /// <summary>Abstand der Abfrage im Hintergrund (Antwortzeit, Units).</summary>
    PollMs = 5000;
  public
    class function ServerText(const AInfo: TAtlasServerInfo): string; static;
    class function ServerState(const AInfo: TAtlasServerInfo): TAtlasStatusState; static;
    class function ServerSummary(const AInfo: TAtlasServerInfo): string; static;
    class function IndexText(const AInfo: TAtlasIndexInfo): string; static;
    class function IndexState(const AInfo: TAtlasIndexInfo): TAtlasStatusState; static;
    class function IndexSummary(const AInfo: TAtlasIndexInfo): string; static;
    class function FileText(const AInfo: TAtlasFileInfo): string; static;
    class function FileState(const AInfo: TAtlasFileInfo): TAtlasStatusState; static;
    /// <summary>Units aus der JSON-Antwort von atlas.server.status als Text ("units": n); -1 ohne.</summary>
    class function UnitsOf(const AStatusJson: string): Integer; static;
  end;

implementation

uses
  System.JSON;

function Milliseconds(AValue: Double): string;
begin
  Result := FormatFloat('0', AValue, TFormatSettings.Invariant) + ' ms';
end;

{ TAtlasStatusLines }

class function TAtlasStatusLines.ServerText(const AInfo: TAtlasServerInfo): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := 'Server: wird gestartet';
    TAtlasServerPhase.Running:
      begin
        Result := 'Server: läuft';
        if AInfo.Samples > 0 then
        begin
          Result := Result + Format(', %s im Mittel der letzten %d Anfragen', [Milliseconds(AInfo.AverageMs),
            AInfo.Samples]);
          if AInfo.AverageMs >= SlowMs then
            Result := Result + ' (langsam)';
        end;
      end;
    TAtlasServerPhase.Stopped:
      Result := 'Server: gestoppt';
    TAtlasServerPhase.Failed:
      begin
        Result := 'Server: Start fehlgeschlagen';
        if AInfo.Error <> '' then
          Result := Result + ' (' + AInfo.Error + ')';
      end;
  else
    Result := 'Server: nicht gestartet';
  end;
  if AInfo.Version <> '' then
    Result := Result + ', Version ' + AInfo.Version;
end;

class function TAtlasStatusLines.ServerState(const AInfo: TAtlasServerInfo): TAtlasStatusState;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := TAtlasStatusState.Yellow;
    TAtlasServerPhase.Running:
      if (AInfo.Samples > 0) and (AInfo.AverageMs >= SlowMs) then
        Result := TAtlasStatusState.Yellow
      else
        Result := TAtlasStatusState.Green;
    TAtlasServerPhase.Stopped, TAtlasServerPhase.Failed:
      Result := TAtlasStatusState.Red;
  else
    Result := TAtlasStatusState.Neutral;
  end;
end;

class function TAtlasStatusLines.ServerSummary(const AInfo: TAtlasServerInfo): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := 'startet';
    TAtlasServerPhase.Running:
      if (AInfo.Samples > 0) and (AInfo.AverageMs >= SlowMs) then
        Result := 'Server langsam'
      else
        Result := '';
    TAtlasServerPhase.Stopped:
      Result := 'Server gestoppt';
    TAtlasServerPhase.Failed:
      Result := 'Server fehlt';
  else
    Result := '';
  end;
end;

class function TAtlasStatusLines.IndexText(const AInfo: TAtlasIndexInfo): string;
begin
  if AInfo.Indexing then
  begin
    Result := 'Index: wird aufgebaut';
    if AInfo.Percent >= 0 then
      Result := Result + Format(' (%d %%)', [AInfo.Percent]);
    if AInfo.Units >= 0 then
      Result := Result + Format(', bisher %d Units', [AInfo.Units]);
  end
  else if AInfo.Units >= 0 then
    Result := Format('Index: %d Units', [AInfo.Units])
  else
    Result := 'Index: unbekannt';
end;

class function TAtlasStatusLines.IndexState(const AInfo: TAtlasIndexInfo): TAtlasStatusState;
begin
  if AInfo.Indexing then
    Result := TAtlasStatusState.Yellow
  else if AInfo.Units >= 0 then
    Result := TAtlasStatusState.Green
  else
    Result := TAtlasStatusState.Neutral;
end;

class function TAtlasStatusLines.IndexSummary(const AInfo: TAtlasIndexInfo): string;
begin
  if not AInfo.Indexing then
    Result := ''
  else if AInfo.Percent >= 0 then
    Result := Format('Index %d %%', [AInfo.Percent])
  else
    Result := 'Index …';
end;

class function TAtlasStatusLines.FileText(const AInfo: TAtlasFileInfo): string;
begin
  if AInfo.Name = '' then
    Exit('Datei: keine aktiv');
  if not AInfo.Known then
    Result := Format('Datei %s: noch nicht gespeichert', [AInfo.Name])
  else
    Result := Format('Datei %s: %s', [AInfo.Name, AInfo.Format.Text]);
  if AInfo.HasTarget then
    Result := Result + Format(' → %s beim Speichern', [AInfo.Target.Text]);
end;

class function TAtlasStatusLines.FileState(const AInfo: TAtlasFileInfo): TAtlasStatusState;
begin
  if (AInfo.Name = '') or not AInfo.Known then
    Result := TAtlasStatusState.Neutral
  else if AInfo.Format.LineBreak = TAtlasLineBreak.Mixed then
    Result := TAtlasStatusState.Yellow
  else
    Result := TAtlasStatusState.Green;
end;

class function TAtlasStatusLines.UnitsOf(const AStatusJson: string): Integer;
var
  Value: TJSONValue;
begin
  Result := -1;
  Value := TJSONObject.ParseJSONValue(AStatusJson);
  try
    if Value is TJSONObject then
      Result := TJSONObject(Value).GetValue<Integer>('units', -1);
  finally
    Value.Free;
  end;
end;

end.
