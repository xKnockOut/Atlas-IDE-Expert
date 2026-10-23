unit Atlas.Core.Status.Lines;

// Feste Zeilen des Atlas-Statusfelds (#591), ohne VCL und Open Tools API:
// Text, Zustand und Kurztext für Server, Index und aktive Datei aus den
// Daten, die die IDE-Schicht sammelt.
// - Server: nicht gestartet (neutral), wird gestartet (gelb), läuft seit
//   Uhrzeit (grün; gelb ab SlowMs mittlerer Antwortzeit), von Atlas beendet
//   (neutral), abgestürzt mit Zeitpunkt und Ursache (Exit-Code, Bericht H5)
//   oder Start fehlgeschlagen (rot).
//   Antwortzeit über die letzten 50 Anfragen (#28).
// - Index: wird aufgebaut (gelb, mit Prozent) oder Anzahl Units (grün) mit
//   Zeitpunkt der letzten vollständigen Indizierung; läuft der Server nicht,
//   die gespeicherten Werte mit „Stand vom …“ (neutral, #754).
// - Version (#495, #754): installierte Version, gelb mit Versionsnummer,
//   wenn ein Update bereitsteht.
// - Datei: Kodierung und Zeilenende (#121); gemischte Zeilenenden gelb,
//   eine gewählte Umstellung wird beim nächsten Speichern geschrieben.
// Brief/Detail liefern je Zeile die Kurzform für die Zustandskachel der
// Willkommensseite (#754); Zustand und Aktion bleiben dieselben.

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
    /// <summary>Grund bei Failed (ohne Pfade); bei einem abgestürzten Server die Ursache, etwa
    /// „Stapelüberlauf (0xC00000FD)“ (Bericht H5).</summary>
    Error: string;
    /// <summary>Beginn der Phase in Ortszeit: Start bei Running, Ende bei Stopped und Failed; 0 = unbekannt (#754).</summary>
    Since: TDateTime;
    /// <summary>Stopped: von Atlas beendet (Neustart, Abschalten), nicht abgestürzt (#754).</summary>
    Ended: Boolean;
  end;

  TAtlasIndexInfo = record
    /// <summary>Units im Index; -1 = unbekannt.</summary>
    Units: Integer;
    Indexing: Boolean;
    /// <summary>Fortschritt beim Aufbau; -1 = unbekannt.</summary>
    Percent: Integer;
    /// <summary>Ende der letzten vollständigen Indizierung in Ortszeit; 0 = unbekannt (#754).</summary>
    FullAt: TDateTime;
    /// <summary>Der Server läuft nicht: Units und FullAt sind gespeicherte Werte vom Zeitpunkt StoredAt (#754).</summary>
    Offline: Boolean;
    /// <summary>Stand der gespeicherten Werte in Ortszeit; 0 = keine gespeicherten Werte.</summary>
    StoredAt: TDateTime;
  end;

  /// <summary>Installierte Version und Ergebnis der Update-Prüfung (#495) für die Zeile „Version“ (#754).</summary>
  TAtlasVersionInfo = record
    Installed: string;
    /// <summary>Neuere Version, die bereitsteht; '' = keine bekannt.</summary>
    Available: string;
    /// <summary>updates.check an.</summary>
    CheckEnabled: Boolean;
    /// <summary>Schon einmal erfolgreich oder vergeblich geprüft.</summary>
    Checked: Boolean;
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
    /// <summary>Installierte Version und Update (#495, #754); gemeldet von der Update-Prüfung.</summary>
    VersionId = 'atlas.version';
    /// <summary>Kennungen anderer Zeilen, die die Zustandskachel (#754) liest: Diagnosemodus (#479) und
    /// Einrichtung (#625, wie TAtlasSetupChecklist.StatusId).</summary>
    DiagnosticModeId = 'atlas.diagnosticMode';
    SetupId = 'atlas.setup';
    ServerOrder = 0;
    VersionOrder = 1;
    IndexOrder = 10;
    FileOrder = 20;
    /// <summary>Ab dieser mittleren Antwortzeit gilt der Server als langsam.</summary>
    SlowMs = 500;
    /// <summary>Status-Befehl des Servers (#28); liefert u. a. "units".</summary>
    StatusCommand = 'atlas.server.status';
    /// <summary>Abstand der Abfrage im Hintergrund (Antwortzeit, Units).</summary>
    PollMs = 5000;
  public
    /// <summary>Uhrzeit "19:02", an einem anderen Tag als ANow "14.10. 19:02"; '' für 0.</summary>
    class function When(AValue, ANow: TDateTime): string; static;
    class function ServerText(const AInfo: TAtlasServerInfo): string; overload; static;
    class function ServerText(const AInfo: TAtlasServerInfo; ANow: TDateTime): string; overload; static;
    class function ServerState(const AInfo: TAtlasServerInfo): TAtlasStatusState; static;
    class function ServerSummary(const AInfo: TAtlasServerInfo): string; static;
    /// <summary>Kurzform für die Zustandskachel (#754), z. B. "Server läuft".</summary>
    class function ServerBrief(const AInfo: TAtlasServerInfo): string; static;
    /// <summary>Zusatz rechts, z. B. "seit 19:02" oder "um 14:32" (Absturz).</summary>
    class function ServerDetail(const AInfo: TAtlasServerInfo): string; overload; static;
    class function ServerDetail(const AInfo: TAtlasServerInfo; ANow: TDateTime): string; overload; static;
    class function IndexText(const AInfo: TAtlasIndexInfo): string; overload; static;
    class function IndexText(const AInfo: TAtlasIndexInfo; ANow: TDateTime): string; overload; static;
    class function IndexState(const AInfo: TAtlasIndexInfo): TAtlasStatusState; static;
    class function IndexSummary(const AInfo: TAtlasIndexInfo): string; static;
    class function IndexBrief(const AInfo: TAtlasIndexInfo): string; static;
    /// <summary>Fortschritt in Prozent, Zeitpunkt der letzten vollständigen Indizierung oder „Stand vom …“.</summary>
    class function IndexDetail(const AInfo: TAtlasIndexInfo): string; overload; static;
    class function IndexDetail(const AInfo: TAtlasIndexInfo; ANow: TDateTime): string; overload; static;
    /// <summary>True, wenn AInfo.Available neuer ist als AInfo.Installed (Vergleich durch den Aufrufer: Available
    /// ist nur gesetzt, wenn die Update-Prüfung sie als neuer gemeldet hat).</summary>
    class function UpdateAvailable(const AInfo: TAtlasVersionInfo): Boolean; static;
    class function VersionText(const AInfo: TAtlasVersionInfo): string; static;
    /// <summary>Gelb mit Update, grün nach einer Prüfung ohne Update, sonst neutral.</summary>
    class function VersionState(const AInfo: TAtlasVersionInfo): TAtlasStatusState; static;
    class function VersionSummary(const AInfo: TAtlasVersionInfo): string; static;
    class function VersionBrief(const AInfo: TAtlasVersionInfo): string; static;
    class function VersionDetail(const AInfo: TAtlasVersionInfo): string; static;
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

function IsSlow(const AInfo: TAtlasServerInfo): Boolean;
begin
  Result := (AInfo.Samples > 0) and (AInfo.AverageMs >= TAtlasStatusLines.SlowMs);
end;

{ TAtlasStatusLines }

class function TAtlasStatusLines.When(AValue, ANow: TDateTime): string;
begin
  if AValue <= 0 then
    Exit('');
  if Trunc(AValue) = Trunc(ANow) then
    Result := FormatDateTime('hh":"nn', AValue)
  else
    Result := FormatDateTime('dd"."mm"." hh":"nn', AValue);
end;

class function TAtlasStatusLines.ServerText(const AInfo: TAtlasServerInfo): string;
begin
  Result := ServerText(AInfo, Now);
end;

class function TAtlasStatusLines.ServerText(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := 'Server: wird gestartet';
    TAtlasServerPhase.Running:
      begin
        Result := 'Server: läuft';
        if AInfo.Since > 0 then
          Result := Result + ' seit ' + When(AInfo.Since, ANow);
        if AInfo.Samples > 0 then
        begin
          Result := Result + Format(', %s im Mittel der letzten %d Anfragen', [Milliseconds(AInfo.AverageMs),
            AInfo.Samples]);
          if AInfo.AverageMs >= SlowMs then
            Result := Result + ' (langsam)';
        end;
      end;
    TAtlasServerPhase.Stopped:
      begin
        if AInfo.Ended then
          Result := 'Server: beendet'
        else
          Result := 'Server: abgestürzt';
        if AInfo.Since > 0 then
          Result := Result + ' um ' + When(AInfo.Since, ANow);
        if not AInfo.Ended and (AInfo.Error <> '') then
          Result := Result + ' (' + AInfo.Error + ')';
      end;
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
      if IsSlow(AInfo) then
        Result := TAtlasStatusState.Yellow
      else
        Result := TAtlasStatusState.Green;
    TAtlasServerPhase.Stopped:
      // Von Atlas beendet ist kein Fehler; abgestürzt schon.
      if AInfo.Ended then
        Result := TAtlasStatusState.Neutral
      else
        Result := TAtlasStatusState.Red;
    TAtlasServerPhase.Failed:
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
      if IsSlow(AInfo) then
        Result := 'Server langsam'
      else
        Result := '';
    TAtlasServerPhase.Stopped:
      if AInfo.Ended then
        Result := ''
      else
        Result := 'Server abgestürzt';
    TAtlasServerPhase.Failed:
      Result := 'Server fehlt';
  else
    Result := '';
  end;
end;

class function TAtlasStatusLines.ServerBrief(const AInfo: TAtlasServerInfo): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := 'Server startet';
    TAtlasServerPhase.Running:
      if IsSlow(AInfo) then
        Result := 'Server läuft langsam'
      else
        Result := 'Server läuft';
    TAtlasServerPhase.Stopped:
      if AInfo.Ended then
        Result := 'Server beendet'
      else
        Result := 'Server abgestürzt';
    TAtlasServerPhase.Failed:
      Result := 'Server-Start fehlgeschlagen';
  else
    Result := 'Server nicht gestartet';
  end;
end;

class function TAtlasStatusLines.ServerDetail(const AInfo: TAtlasServerInfo): string;
begin
  Result := ServerDetail(AInfo, Now);
end;

class function TAtlasStatusLines.ServerDetail(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
begin
  Result := '';
  case AInfo.Phase of
    TAtlasServerPhase.Running:
      if AInfo.Since > 0 then
        Result := 'seit ' + When(AInfo.Since, ANow);
    TAtlasServerPhase.Stopped:
      begin
        if AInfo.Since > 0 then
          Result := 'um ' + When(AInfo.Since, ANow);
        if not AInfo.Ended and (AInfo.Error <> '') and (Result <> '') then
          Result := Result + ', ' + AInfo.Error
        else if not AInfo.Ended and (AInfo.Error <> '') then
          Result := AInfo.Error;
      end;
    TAtlasServerPhase.Failed:
      Result := AInfo.Error;
    TAtlasServerPhase.NotStarted: ;
    TAtlasServerPhase.Starting: ;
  end;
end;

class function TAtlasStatusLines.IndexText(const AInfo: TAtlasIndexInfo): string;
begin
  Result := IndexText(AInfo, Now);
end;

class function TAtlasStatusLines.IndexText(const AInfo: TAtlasIndexInfo; ANow: TDateTime): string;
begin
  if AInfo.Offline then
  begin
    // Ohne Server nur gespeicherte Werte (#754).
    if (AInfo.Units >= 0) and (AInfo.StoredAt > 0) then
      Result := Format('Index: %d Units, Stand vom %s (Server läuft nicht)', [AInfo.Units, When(AInfo.StoredAt, ANow)])
    else
      Result := 'Index: Server läuft nicht';
  end
  else if AInfo.Indexing then
  begin
    Result := 'Index: wird aufgebaut';
    if AInfo.Percent >= 0 then
      Result := Result + Format(' (%d %%)', [AInfo.Percent]);
    if AInfo.Units >= 0 then
      Result := Result + Format(', bisher %d Units', [AInfo.Units]);
  end
  else if AInfo.Units >= 0 then
  begin
    Result := Format('Index: %d Units', [AInfo.Units]);
    if AInfo.FullAt > 0 then
      Result := Result + ', vollständig indiziert ' + When(AInfo.FullAt, ANow);
  end
  else
    Result := 'Index: unbekannt';
end;

class function TAtlasStatusLines.IndexState(const AInfo: TAtlasIndexInfo): TAtlasStatusState;
begin
  if AInfo.Offline then
    Result := TAtlasStatusState.Neutral
  else if AInfo.Indexing then
    Result := TAtlasStatusState.Yellow
  else if AInfo.Units >= 0 then
    Result := TAtlasStatusState.Green
  else
    Result := TAtlasStatusState.Neutral;
end;

class function TAtlasStatusLines.IndexSummary(const AInfo: TAtlasIndexInfo): string;
begin
  if AInfo.Offline or not AInfo.Indexing then
    Result := ''
  else if AInfo.Percent >= 0 then
    Result := Format('Index %d %%', [AInfo.Percent])
  else
    Result := 'Index …';
end;

class function TAtlasStatusLines.IndexBrief(const AInfo: TAtlasIndexInfo): string;
begin
  if not AInfo.Offline and AInfo.Indexing then
    Result := 'Index wird aufgebaut'
  else if (AInfo.Units >= 0) and (not AInfo.Offline or (AInfo.StoredAt > 0)) then
    Result := Format('Index: %d Units', [AInfo.Units])
  else
    Result := 'Index unbekannt';
end;

class function TAtlasStatusLines.IndexDetail(const AInfo: TAtlasIndexInfo): string;
begin
  Result := IndexDetail(AInfo, Now);
end;

class function TAtlasStatusLines.IndexDetail(const AInfo: TAtlasIndexInfo; ANow: TDateTime): string;
begin
  Result := '';
  if AInfo.Offline then
  begin
    if (AInfo.Units >= 0) and (AInfo.StoredAt > 0) then
      Result := 'Stand vom ' + When(AInfo.StoredAt, ANow)
    else
      Result := 'Server läuft nicht';
  end
  else if AInfo.Indexing then
  begin
    if AInfo.Percent >= 0 then
      Result := Format('%d %%', [AInfo.Percent]);
  end
  else if (AInfo.Units >= 0) and (AInfo.FullAt > 0) then
    Result := 'indiziert ' + When(AInfo.FullAt, ANow);
end;

class function TAtlasStatusLines.UpdateAvailable(const AInfo: TAtlasVersionInfo): Boolean;
begin
  Result := Trim(AInfo.Available) <> '';
end;

class function TAtlasStatusLines.VersionText(const AInfo: TAtlasVersionInfo): string;
begin
  Result := 'Version: Atlas ' + AInfo.Installed;
  if UpdateAvailable(AInfo) then
    Result := Result + ', Update ' + AInfo.Available + ' bereit'
  else if not AInfo.CheckEnabled then
    Result := Result + ' (Update-Prüfung aus)'
  else if AInfo.Checked then
    Result := Result + ' (aktuell)'
  else
    Result := Result + ' (noch nicht geprüft)';
end;

class function TAtlasStatusLines.VersionState(const AInfo: TAtlasVersionInfo): TAtlasStatusState;
begin
  if UpdateAvailable(AInfo) then
    Result := TAtlasStatusState.Yellow
  else if AInfo.CheckEnabled and AInfo.Checked then
    Result := TAtlasStatusState.Green
  else
    Result := TAtlasStatusState.Neutral;
end;

class function TAtlasStatusLines.VersionSummary(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
    Result := 'Update ' + AInfo.Available
  else
    Result := '';
end;

class function TAtlasStatusLines.VersionBrief(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
    Result := 'Update ' + AInfo.Available + ' bereit'
  else
    Result := 'Atlas ' + AInfo.Installed;
end;

class function TAtlasStatusLines.VersionDetail(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
    Result := 'installiert ' + AInfo.Installed
  else if not AInfo.CheckEnabled then
    Result := 'Update-Prüfung aus'
  else if AInfo.Checked then
    Result := 'aktuell'
  else
    Result := 'noch nicht geprüft';
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
