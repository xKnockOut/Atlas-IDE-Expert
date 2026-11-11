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
    /// <summary>Beginn der Phase in Ortszeit: Start bei Running, Ende bei Stopped und Failed; 0 = unbekannt
    /// (#754).</summary>
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
    /// <summary>Der Server läuft nicht: Units und FullAt sind gespeicherte Werte vom Zeitpunkt StoredAt
    /// (#754).</summary>
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
    /// <summary>Stand der Installation des Updates (#1519), z. B. „wird beim Beenden installiert“; '' = keine.
    /// </summary>
    Install: string;
    /// <summary>Fehlerart der letzten Abfrage, z. B. „HTTP 407“; '' = sie ist gelungen oder es gab noch keine.
    /// </summary>
    Failure: string;
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
    cServerId = 'atlas.server';
    cIndexId = 'atlas.index';
    cFileId = 'atlas.file';
    /// <summary>Installierte Version und Update (#495, #754); gemeldet von der Update-Prüfung.</summary>
    cVersionId = 'atlas.version';
    /// <summary>Kennungen anderer Zeilen, die die Zustandskachel (#754) liest: Diagnosemodus (#479) und
    /// Einrichtung (#625, wie TAtlasSetupChecklist.cStatusId).</summary>
    cDiagnosticModeId = 'atlas.diagnosticMode';
    cSetupId = 'atlas.setup';
    cServerOrder = 0;
    cVersionOrder = 1;
    cIndexOrder = 10;
    cFileOrder = 20;
    /// <summary>Ab dieser mittleren Antwortzeit gilt der Server als langsam.</summary>
    cSlowMs = 500;
    /// <summary>Status-Befehl des Servers (#28); liefert u. a. "units".</summary>
    cStatusCommand = 'atlas.server.status';
    /// <summary>Abstand der Abfrage im Hintergrund (Antwortzeit, Units).</summary>
    cPollMs = 5000;
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
    /// <summary>Gelb mit Update oder nach einer gescheiterten Abfrage, grün nach einer Prüfung ohne Update, sonst
    /// neutral.</summary>
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
  System.JSON,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TLinesText = (N1RequestSkippedAfterA, RequestsSkippedAfterACrash, ServerRunning, Since, OnAverageOverTheLast, Slow,
    ServerStopped, ServerCrashed, AtText, ServerStarting, ServerStartFailed, ServerNotStarted, Starting,
    SkippedAfterACrash, ServerSlow, ServerCrashed2, ServerMissing, ServerStarting2, ServerRunning2,
    ServerRunningSlowly, ServerRunning3, ServerStopped2, ServerStartFailed2, ServerNotStarted2, Since2, AtText2,
    IndexUnitsAsOfServer, IndexServerNotRunning, IndexBuilding, UnitsSoFar, IndexUnits, FullyIndexed, IndexUnknown,
    IndexBuilding2, IndexUnknown2, AsOf, ServerNotRunning, Indexed, Ready, UpdateCheckOff, UpToDate, NotCheckedYet,
    Installed, UpdateCheckOff2, UpToDate2, NotCheckedYet2, FileNoneActive, FileNotSavedYet, FileText, OnSave,
    CheckFailed, CheckFailed2);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TLinesText] of string = (
    ('1 Anfrage übersprungen nach Absturz',
     '%d Anfragen übersprungen nach Absturz',
     'Server: läuft',
     ' seit ',
     ', %s im Mittel der letzten %d Anfragen',
     ' (langsam)',
     'Server: beendet',
     'Server: abgestürzt',
     ' um ',
     'Server: wird gestartet',
     'Server: Start fehlgeschlagen',
     'Server: nicht gestartet',
     'startet',
     'übersprungen nach Absturz',
     'Server langsam',
     'Server abgestürzt',
     'Server fehlt',
     'Server startet',
     'Server läuft, ',
     'Server läuft langsam',
     'Server läuft',
     'Server beendet',
     'Server-Start fehlgeschlagen',
     'Server nicht gestartet',
     'seit ',
     'um ',
     'Index: %d Units, Stand vom %s (Server läuft nicht)',
     'Index: Server läuft nicht',
     'Index: wird aufgebaut',
     ', bisher %d Units',
     'Index: %d Units',
     ', vollständig indiziert ',
     'Index: unbekannt',
     'Index wird aufgebaut',
     'Index unbekannt',
     'Stand vom ',
     'Server läuft nicht',
     'indiziert ',
     ' bereit',
     ' (Update-Prüfung aus)',
     ' (aktuell)',
     ' (noch nicht geprüft)',
     'installiert ',
     'Update-Prüfung aus',
     'aktuell',
     'noch nicht geprüft',
     'Datei: keine aktiv',
     'Datei %s: noch nicht gespeichert',
     'Datei %s: %s',
     ' → %s beim Speichern',
     ' (Prüfung fehlgeschlagen)',
     'Prüfung fehlgeschlagen: %s'),
    ('1 request skipped after a crash',
     '%d requests skipped after a crash',
     'Server: running',
     ' since ',
     ', %s on average over the last %d requests',
     ' (slow)',
     'Server: stopped',
     'Server: crashed',
     ' at ',
     'Server: starting',
     'Server: start failed',
     'Server: not started',
     'starting',
     'skipped after a crash',
     'Server slow',
     'Server crashed',
     'Server missing',
     'Server starting',
     'Server running, ',
     'Server running slowly',
     'Server running',
     'Server stopped',
     'Server start failed',
     'Server not started',
     'since ',
     'at ',
     'Index: %d units, as of %s (server not running)',
     'Index: server not running',
     'Index: building',
     ', %d units so far',
     'Index: %d units',
     ', fully indexed ',
     'Index: unknown',
     'Index building',
     'Index unknown',
     'as of ',
     'Server not running',
     'indexed ',
     ' ready',
     ' (update check off)',
     ' (up to date)',
     ' (not checked yet)',
     'installed ',
     'Update check off',
     'up to date',
     'not checked yet',
     'File: none active',
     'File %s: not saved yet',
     'File %s: %s',
     ' → %s on save',
     ' (check failed)',
     'check failed: %s'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TLinesText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

function Milliseconds(AValue: Double): string;
begin
  Result := FormatFloat('0', AValue, TFormatSettings.Invariant) + ' ms';
end;

function IsSlow(const AInfo: TAtlasServerInfo): Boolean;
begin
  Result := (AInfo.Samples > 0) and (AInfo.AverageMs >= TAtlasStatusLines.cSlowMs);
end;

/// <summary>„1 Anfrage übersprungen nach Absturz“ (#1355); '' ohne.</summary>
function SkippedText(const AInfo: TAtlasServerInfo): string;
begin
  Result := '';
  if AInfo.Skipped = 1 then
  begin
    Result := UiText(TLinesText.N1RequestSkippedAfterA);
  end
  else if AInfo.Skipped > 1 then
  begin
    Result := Format(UiText(TLinesText.RequestsSkippedAfterACrash), [AInfo.Skipped]);
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

function RunningText(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
begin
  Result := UiText(TLinesText.ServerRunning);
  if AInfo.Since > 0 then
  begin
    Result := Result + UiText(TLinesText.Since) + TAtlasStatusLines.When(AInfo.Since, ANow);
  end;
  if AInfo.Samples > 0 then
  begin
    Result := Result + Format(UiText(TLinesText.OnAverageOverTheLast), [Milliseconds(AInfo.AverageMs),
      AInfo.Samples]);
    if AInfo.AverageMs >= TAtlasStatusLines.cSlowMs then
    begin
      Result := Result + UiText(TLinesText.Slow);
    end;
  end;
  if AInfo.Skipped > 0 then
  begin
    Result := Result + ', ' + SkippedText(AInfo);
  end;
end;

function StoppedText(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
begin
  if AInfo.Ended then
  begin
    Result := UiText(TLinesText.ServerStopped);
  end
  else
  begin
    Result := UiText(TLinesText.ServerCrashed);
  end;
  if AInfo.Since > 0 then
  begin
    Result := Result + UiText(TLinesText.AtText) + TAtlasStatusLines.When(AInfo.Since, ANow);
  end;
  if not AInfo.Ended and (AInfo.Error <> '') then
  begin
    Result := Result + ' (' + AInfo.Error + ')';
  end;
end;

/// <summary>AFirst und ASecond mit ", " verbunden; leere fallen weg.</summary>
function Joined(const AFirst, ASecond: string): string;
begin
  if (AFirst <> '') and (ASecond <> '') then
  begin
    Result := AFirst + ', ' + ASecond;
  end
  else
  begin
    Result := AFirst + ASecond;
  end;
end;

class function TAtlasStatusLines.ServerText(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := UiText(TLinesText.ServerStarting);
    TAtlasServerPhase.Running:
      Result := RunningText(AInfo, ANow);
    TAtlasServerPhase.Stopped:
      Result := StoppedText(AInfo, ANow);
    TAtlasServerPhase.Failed:
      begin
        Result := UiText(TLinesText.ServerStartFailed);
        if AInfo.Error <> '' then
        begin
          Result := Result + ' (' + AInfo.Error + ')';
        end;
      end;
  else
    Result := UiText(TLinesText.ServerNotStarted);
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
      Result := UiText(TLinesText.Starting);
    TAtlasServerPhase.Running:
      if AInfo.Skipped > 0 then
      begin
        Result := UiText(TLinesText.SkippedAfterACrash);
      end
      else if IsSlow(AInfo) then
      begin
        Result := UiText(TLinesText.ServerSlow);
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
        Result := UiText(TLinesText.ServerCrashed2);
      end;
    TAtlasServerPhase.Failed:
      Result := UiText(TLinesText.ServerMissing);
  else
    Result := '';
  end;
end;

class function TAtlasStatusLines.ServerBrief(const AInfo: TAtlasServerInfo): string;
begin
  case AInfo.Phase of
    TAtlasServerPhase.Starting:
      Result := UiText(TLinesText.ServerStarting2);
    TAtlasServerPhase.Running:
      if AInfo.Skipped > 0 then
      begin
        Result := UiText(TLinesText.ServerRunning2) + SkippedText(AInfo);
      end
      else if IsSlow(AInfo) then
      begin
        Result := UiText(TLinesText.ServerRunningSlowly);
      end
      else
      begin
        Result := UiText(TLinesText.ServerRunning3);
      end;
    TAtlasServerPhase.Stopped:
      if AInfo.Ended then
      begin
        Result := UiText(TLinesText.ServerStopped2);
      end
      else
      begin
        Result := UiText(TLinesText.ServerCrashed2);
      end;
    TAtlasServerPhase.Failed:
      Result := UiText(TLinesText.ServerStartFailed2);
  else
    Result := UiText(TLinesText.ServerNotStarted2);
  end;
end;

class function TAtlasStatusLines.ServerDetail(const AInfo: TAtlasServerInfo): string;
begin
  Result := ServerDetail(AInfo, Now);
end;

class function TAtlasStatusLines.ServerDetail(const AInfo: TAtlasServerInfo; ANow: TDateTime): string;
var
  mSince, mMore: string;
begin
  mSince := '';
  mMore := '';
  case AInfo.Phase of
    TAtlasServerPhase.Running:
      begin
        if AInfo.Since > 0 then
        begin
          mSince := UiText(TLinesText.Since2) + When(AInfo.Since, ANow);
        end;
        if AInfo.Skipped > 0 then
        begin
          mMore := SkippedText(AInfo);
        end;
      end;
    TAtlasServerPhase.Stopped:
      begin
        if AInfo.Since > 0 then
        begin
          mSince := UiText(TLinesText.AtText2) + When(AInfo.Since, ANow);
        end;
        if not AInfo.Ended then
        begin
          mMore := AInfo.Error;
        end;
      end;
    TAtlasServerPhase.Failed:
      mMore := AInfo.Error;
    TAtlasServerPhase.NotStarted: ;
    TAtlasServerPhase.Starting: ;
  end;
  Result := Joined(mSince, mMore);
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
      Result := Format(UiText(TLinesText.IndexUnitsAsOfServer), [AInfo.Units, When(AInfo.StoredAt, ANow)]);
    end
    else
    begin
      Result := UiText(TLinesText.IndexServerNotRunning);
    end;
  end
  else if AInfo.Indexing then
  begin
    Result := UiText(TLinesText.IndexBuilding);
    if AInfo.Percent >= 0 then
    begin
      Result := Result + Format(' (%d %%)', [AInfo.Percent]);
    end;
    if AInfo.Units >= 0 then
    begin
      Result := Result + Format(UiText(TLinesText.UnitsSoFar), [AInfo.Units]);
    end;
  end
  else if AInfo.Units >= 0 then
  begin
    Result := Format(UiText(TLinesText.IndexUnits), [AInfo.Units]);
    if AInfo.FullAt > 0 then
    begin
      Result := Result + UiText(TLinesText.FullyIndexed) + When(AInfo.FullAt, ANow);
    end;
  end
  else
  begin
    Result := UiText(TLinesText.IndexUnknown);
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
    Result := UiText(TLinesText.IndexBuilding2);
  end
  else if (AInfo.Units >= 0) and (not AInfo.Offline or (AInfo.StoredAt > 0)) then
  begin
    Result := Format(UiText(TLinesText.IndexUnits), [AInfo.Units]);
  end
  else
  begin
    Result := UiText(TLinesText.IndexUnknown2);
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
      Result := UiText(TLinesText.AsOf) + When(AInfo.StoredAt, ANow);
    end
    else
    begin
      Result := UiText(TLinesText.ServerNotRunning);
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
    Result := UiText(TLinesText.Indexed) + When(AInfo.FullAt, ANow);
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
    Result := Result + ', Update ' + AInfo.Available + UiText(TLinesText.Ready);
    if AInfo.Install <> '' then
    begin
      Result := Result + ' (' + AInfo.Install + ')';
    end;
  end
  else if not AInfo.CheckEnabled then
  begin
    Result := Result + UiText(TLinesText.UpdateCheckOff);
  end
  else if AInfo.Failure <> '' then
  begin
    // Ohne Antwort ist unbekannt, ob es eine neuere Version gibt: nie „aktuell“.
    Result := Result + UiText(TLinesText.CheckFailed);
  end
  else if AInfo.Checked then
  begin
    Result := Result + UiText(TLinesText.UpToDate);
  end
  else
  begin
    Result := Result + UiText(TLinesText.NotCheckedYet);
  end;
end;

class function TAtlasStatusLines.VersionState(const AInfo: TAtlasVersionInfo): TAtlasStatusState;
begin
  if UpdateAvailable(AInfo) or (AInfo.CheckEnabled and (AInfo.Failure <> '')) then
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
    Result := 'Update ' + AInfo.Available + UiText(TLinesText.Ready);
  end
  else
  begin
    Result := 'Atlas ' + AInfo.Installed;
  end;
end;

class function TAtlasStatusLines.VersionDetail(const AInfo: TAtlasVersionInfo): string;
begin
  if UpdateAvailable(AInfo) and (AInfo.Install <> '') then
  begin
    Result := AInfo.Install;
  end
  else if UpdateAvailable(AInfo) then
  begin
    Result := UiText(TLinesText.Installed) + AInfo.Installed;
  end
  else if not AInfo.CheckEnabled then
  begin
    Result := UiText(TLinesText.UpdateCheckOff2);
  end
  else if AInfo.Failure <> '' then
  begin
    Result := Format(UiText(TLinesText.CheckFailed2), [AInfo.Failure]);
  end
  else if AInfo.Checked then
  begin
    Result := UiText(TLinesText.UpToDate2);
  end
  else
  begin
    Result := UiText(TLinesText.NotCheckedYet2);
  end;
end;

class function TAtlasStatusLines.FileText(const AInfo: TAtlasFileInfo): string;
begin
  if AInfo.Name = '' then
  begin
    Exit(UiText(TLinesText.FileNoneActive));
  end;
  if not AInfo.Known then
  begin
    Result := Format(UiText(TLinesText.FileNotSavedYet), [AInfo.Name]);
  end
  else
  begin
    Result := Format(UiText(TLinesText.FileText), [AInfo.Name, AInfo.Format.Text]);
  end;
  if AInfo.HasTarget then
  begin
    Result := Result + Format(UiText(TLinesText.OnSave), [AInfo.Target.Text]);
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
  mValue: TJSONValue;
begin
  Result := -1;
  mValue := TJSONObject.ParseJSONValue(AStatusJson);
  try
    if mValue is TJSONObject then
    begin
      Result := TJSONObject(mValue).GetValue<Integer>('units', -1);
    end;
  finally
    mValue.Free;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.Core.Status.Lines', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
