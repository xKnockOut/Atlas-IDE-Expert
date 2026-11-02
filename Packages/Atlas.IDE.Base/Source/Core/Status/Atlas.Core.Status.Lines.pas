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
    /// <summary>Anfragen, die der Server nach zwei Abstürzen an derselben Datei überspringt (Sicherheitsnetz,
    /// #1355); bei Running gelb.</summary>
    Skipped: Integer;
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

/// <summary>„1 Anfrage übersprungen nach Absturz“ (#1355); '' ohne.</summary>
function SkippedText(const AInfo: TAtlasServerInfo): string;
begin
  Result := '';
  if AInfo.Skipped = 1 then
  begin
    Result := '1 Anfrage übersprungen nach Absturz';
  end
  else if AInfo.Skipped > 1 then
  begin
    Result := Format('%d Anfragen übersprungen nach Absturz', [AInfo.Skipped]);
  end;
end;

{ TAtlasStatusLines }

class function TAtlasStatusLines.When(AValue, ANow: TDateTime): string;
begin
  if AValue <= 0 then
  begin
    Exit('');
  end;
  if Trunc(AValue) = Trunc(ANow) then
  begin
    Result := FormatDateTime('hh":"nn', AValue);
  end
  else
  begin
    Result := FormatDateTime('dd"."mm"." hh":"nn', AValue);
  end;
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
        begin
          Result := Result + ' seit ' + When(AInfo.Since, ANow);
        end;
        if AInfo.Samples > 0 then
        begin
          Result := Result + Format(', %s im Mittel der letzten %d Anfragen', [Milliseconds(AInfo.AverageMs),
            AInfo.Samples]);
          if AInfo.AverageMs >= SlowMs then
          begin
            Result := Result + ' (langsam)';
          end;
        end;
        if AInfo.Skipped > 0 then
        begin
          Result := Result + ', ' + SkippedText(AInfo);
        end;
      end;
    TAtlasServerPhase.Stopped:
      begin
        if AInfo.Ended then
        begin
          Result := 'Server: beendet';
        end
        else
        begin
          Result := 'Server: abgestürzt';
        end;
        if AInfo.Since > 0 then
        begin
          Result := Result + ' um ' + When(AInfo.Since, ANow);
        end;
        if not AInfo.Ended and (AInfo.Error <> '') then
        begin
          Result := Result + ' (' + AInfo.Error + ')';
        end;
      end;
    TAtlasServerPhase.Failed:
      begin
        Result := 'Server: Start fehlgeschlagen';
        if AInfo.Error <> '' then
        begin
          Result := Result + ' (' + AInfo.Error + ')';
        end;
      end;
  else
    Result := 'Server: nicht gestartet';
  end;
  if AInfo.Version <> '' then
  begin
    Result := Result + ', Version ' + AInfo.Version;
  end;
end;

class function TAtlasStatusLines.ServerState(const AInfo: TAtlasServerInfo): TAtlasStatusState;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := TAtlasStatusState.Yellow;
    TAtlasServerPhase.Running:
      // Übersprungene Anfragen (#1355) sichtbar wie ein langsamer Server.
      if IsSlow(AInfo) or (AInfo.Skipped > 0) then
      begin
        Result := TAtlasStatusState.Yellow;
      end
      else
      begin
        Result := TAtlasStatusState.Green;
      end;
    TAtlasServerPhase.Stopped:
      // Von Atlas beendet ist kein Fehler; abgestürzt schon.
      if AInfo.Ended then
      begin
        Result := TAtlasStatusState.Neutral;
      end
      else
      begin
        Result := TAtlasStatusState.Red;
      end;
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
      if AInfo.Skipped > 0 then
      begin
        Result := 'übersprungen nach Absturz';
      end
      else if IsSlow(AInfo) then
      begin
        Result := 'Server langsam';
      end
      else
      begin
        Result := '';
      end;
    TAtlasServerPhase.Stopped:
      if AInfo.Ended then
      begin
        Result := '';
      end
      else
      begin
        Result := 'Server abgestürzt';
      end;
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
      if AInfo.Skipped > 0 then
      begin
        Result := 'Server läuft, ' + SkippedText(AInfo);
      end
      else if IsSlow(AInfo) then
      begin
        Result := 'Server läuft langsam';
      end
      else
      begin
        Result := 'Server läuft';
      end;
    TAtlasServerPhase.Stopped:
      if AInfo.Ended then
      begin
        Result := 'Server beendet';
      end
      else
      begin
        Result := 'Server abgestürzt';
      end;
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
      begin
        if AInfo.Since > 0 then
        begin
          Result := 'seit ' + When(AInfo.Since, ANow);
        end;
        if (AInfo.Skipped > 0) and (Result <> '') then
        begin
          Result := Result + ', ' + SkippedText(AInfo);
        end
        else if AInfo.Skipped > 0 then
        begin
          Result := SkippedText(AInfo);
        end;
      end;
    TAtlasServerPhase.Stopped:
      begin
        if AInfo.Since > 0 then
        begin
          Result := 'um ' + When(AInfo.Since, ANow);
        end;
        if not AInfo.Ended and (AInfo.Error <> '') and (Result <> '') then
        begin
          Result := Result + ', ' + AInfo.Error;
        end
        else if not AInfo.Ended and (AInfo.Error <> '') then
        begin
          Result := AInfo.Error;
        end;
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
    begin
      Result := Format('Index: %d Units, Stand vom %s (Server läuft nicht)', [AInfo.Units, When(AInfo.StoredAt, ANow)]);
    end
    else
    begin
      Result := 'Index: Server läuft nicht';
    end;
  end
  else if AInfo.Indexing then
  begin
    Result := 'Index: wird aufgebaut';
    if AInfo.Percent >= 0 then
    begin
      Result := Result + Format(' (%d %%)', [AInfo.Percent]);
    end;
    if AInfo.Units >= 0 then
    begin
      Result := Result + Format(', bisher %d Units', [AInfo.Units]);
    end;
  end
  else if AInfo.Units >= 0 then
  begin
    Result := Format('Index: %d Units', [AInfo.Units]);
    if AInfo.FullAt > 0 then
    begin
      Result := Result + ', vollständig indiziert ' + When(AInfo.FullAt, ANow);
    end;
  end
  else
  begin
    Result := 'Index: unbekannt';
  end;
end;

class function TAtlasStatusLines.IndexState(const AInfo: TAtlasIndexInfo): TAtlasStatusState;
begin
  if AInfo.Offline then
  begin
    Result := TAtlasStatusState.Neutral;
  end
  else if AInfo.Indexing then
  begin
    Result := TAtlasStatusState.Yellow;
  end
  else if AInfo.Units >= 0 then
  begin
    Result := TAtlasStatusState.Green;
  end
  else
  begin
    Result := TAtlasStatusState.Neutral;
  end;
end;

class function TAtlasStatusLines.IndexSummary(const AInfo: TAtlasIndexInfo): string;
begin
  if AInfo.Offline or not AInfo.Indexing then
  begin
    Result := '';
  end
  else if AInfo.Percent >= 0 then
  begin
    Result := Format('Index %d %%', [AInfo.Percent]);
  end
  else
  begin
    Result := 'Index …';
  end;
end;

class function TAtlasStatusLines.IndexBrief(const AInfo: TAtlasIndexInfo): string;
begin
  if not AInfo.Offline and AInfo.Indexing then
  begin
    Result := 'Index wird aufgebaut';
  end
  else if (AInfo.Units >= 0) and (not AInfo.Offline or (AInfo.StoredAt > 0)) then
  begin
    Result := Format('Index: %d Units', [AInfo.Units]);
  end
  else
  begin
    Result := 'Index unbekannt';
  end;
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
    begin
      Result := 'Stand vom ' + When(AInfo.StoredAt, ANow);
    end
    else
    begin
      Result := 'Server läuft nicht';
    end;
  end
  else if AInfo.Indexing then
  begin
    if AInfo.Percent >= 0 then
    begin
      Result := Format('%d %%', [AInfo.Percent]);
    end;
  end
  else if (AInfo.Units >= 0) and (AInfo.FullAt > 0) then
  begin
    Result := 'indiziert ' + When(AInfo.FullAt, ANow);
  end;
end;

class function TAtlasStatusLines.UpdateAvailable(const AInfo: TAtlasVersionInfo): Boolean;
begin
  Result := Trim(AInfo.Available) <> '';
end;

class function TAtlasStatusLines.VersionText(const AInfo: TAtlasVersionInfo): string;
begin
  Result := 'Version: Atlas ' + AInfo.Installed;
  if UpdateAvailable(AInfo) then
  begin
    Result := Result + ', Update ' + AInfo.Available + ' bereit';
  end
  else if not AInfo.CheckEnabled then
  begin
    Result := Result + ' (Update-Prüfung aus)';
  end
  else if AInfo.Checked then
  begin
    Result := Result + ' (aktuell)';
  end
  else
  begin
    Result := Result + ' (noch nicht geprüft)';
  end;
end;

class function TAtlasStatusLines.VersionState(const AInfo: TAtlasVersionInfo): TAtlasStatusState;
begin
  if UpdateAvailable(AInfo) then
  begin
    Result := TAtlasStatusState.Yellow;
  end
  else if AInfo.CheckEnabled and AInfo.Checked then
  begin
    Result := TAtlasStatusState.Green;
  end
  else
  begin
    Result := TAtlasStatusState.Neutral;
  end;
end;

class function TAtlasStatusLines.VersionSummary(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
  begin
    Result := 'Update ' + AInfo.Available;
  end
  else
  begin
    Result := '';
  end;
end;

class function TAtlasStatusLines.VersionBrief(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
  begin
    Result := 'Update ' + AInfo.Available + ' bereit';
  end
  else
  begin
    Result := 'Atlas ' + AInfo.Installed;
  end;
end;

class function TAtlasStatusLines.VersionDetail(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) then
  begin
    Result := 'installiert ' + AInfo.Installed;
  end
  else if not AInfo.CheckEnabled then
  begin
    Result := 'Update-Prüfung aus';
  end
  else if AInfo.Checked then
  begin
    Result := 'aktuell';
  end
  else
  begin
    Result := 'noch nicht geprüft';
  end;
end;

class function TAtlasStatusLines.FileText(const AInfo: TAtlasFileInfo): string;
begin
  if AInfo.Name = '' then
  begin
    Exit('Datei: keine aktiv');
  end;
  if not AInfo.Known then
  begin
    Result := Format('Datei %s: noch nicht gespeichert', [AInfo.Name]);
  end
  else
  begin
    Result := Format('Datei %s: %s', [AInfo.Name, AInfo.Format.Text]);
  end;
  if AInfo.HasTarget then
  begin
    Result := Result + Format(' → %s beim Speichern', [AInfo.Target.Text]);
  end;
end;

class function TAtlasStatusLines.FileState(const AInfo: TAtlasFileInfo): TAtlasStatusState;
begin
  if (AInfo.Name = '') or not AInfo.Known then
  begin
    Result := TAtlasStatusState.Neutral;
  end
  else if AInfo.Format.LineBreak = TAtlasLineBreak.Mixed then
  begin
    Result := TAtlasStatusState.Yellow;
  end
  else
  begin
    Result := TAtlasStatusState.Green;
  end;
end;

class function TAtlasStatusLines.UnitsOf(const AStatusJson: string): Integer;
var
  Value: TJSONValue;
begin
  Result := -1;
  Value := TJSONObject.ParseJSONValue(AStatusJson);
  try
    if Value is TJSONObject then
    begin
      Result := TJSONObject(Value).GetValue<Integer>('units', -1);
    end;
  finally
    Value.Free;
  end;
end;

end.
