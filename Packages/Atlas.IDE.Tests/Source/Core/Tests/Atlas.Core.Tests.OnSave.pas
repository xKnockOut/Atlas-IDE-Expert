unit Atlas.Core.Tests.OnSave;

// Betroffene Tests nach dem Speichern im Hintergrund (#1775, tests.onSave),
// ohne VCL und Open Tools API:
// - Welche Dateien zählen: Units, Formulare und Include-Dateien (dieselben,
//   die der Server für betroffene Tests zuordnet, #1353).
// - Warteschlange: Speichern während eines Laufs (Ermitteln, Bauen, Testen)
//   sammelt die Dateien; nach dem Lauf folgt höchstens ein weiterer mit allen
//   bis dahin gespeicherten. Ein Lauf wird nie abgebrochen.
// - Sperrgründe: Schalter aus, Debug-Sitzung, Build, anderer Testlauf.
// - Entscheidung nach dem Ermitteln: keine Tests, zu viele (über
//   tests.onSave.max) bzw. alle nötig, sonst laufen sie.

interface

uses
  System.SysUtils,
  Atlas.Core.Settings.Plugin;

type
{$SCOPEDENUMS ON}
  /// <summary>Warum nach dem Speichern kein Lauf beginnt; None = er darf beginnen.</summary>
  TAtlasOnSaveBlock = (None, Off, Debugging, Building, TestsBusy);
  /// <summary>Was mit den ermittelten Tests geschieht.</summary>
  TAtlasOnSaveVerdict = (Run, NoTests, TooMany, AllNeeded);
{$SCOPEDENUMS OFF}

  /// <summary>Lage der IDE beim Beginn eines Laufs.</summary>
  TAtlasOnSaveSituation = record
    Debugging: Boolean;
    /// <summary>Ein Build des Benutzers oder auf Auftrag läuft (nicht Atlas' eigene Prüfung).</summary>
    Building: Boolean;
    /// <summary>Ein anderer Testlauf oder ein Test im Debugger läuft.</summary>
    TestsBusy: Boolean;
  end;

  /// <summary>Gespeicherte Dateien, die auf einen Lauf warten.</summary>
  TAtlasTestsOnSaveQueue = class
  private
    FPending: TArray<string>;
    FActive: Boolean;
  public
    /// <summary>AFileName vormerken (einmal je Datei). True: Kein Lauf ist im Gange, der Aufrufer beginnt einen
    /// (Take); False: Die Datei wartet auf den Folgelauf.</summary>
    function Add(const AFileName: string): Boolean;
    /// <summary>Alle wartenden Dateien für den nächsten Lauf; ab jetzt ist ein Lauf im Gange.</summary>
    function Take: TArray<string>;
    /// <summary>Der Lauf ist zu Ende. True: Es warten Dateien, der Aufrufer beginnt den Folgelauf (Take).</summary>
    function Finish: Boolean;
    /// <summary>Wartende Dateien verwerfen (Schalter aus); ein Lauf im Gange bleibt.</summary>
    procedure Clear;
    property Active: Boolean read FActive;
    property Pending: TArray<string> read FPending;
  end;

  TAtlasTestsOnSave = class
  public
    /// <summary>Zählt die Datei für betroffene Tests (.pas, .dfm, .fmx, .inc)?</summary>
    class function Counts(const AFileName: string): Boolean; static;
    /// <summary>Darf ein Lauf beginnen? Schalter: tests.onSave mit tests.affected und tests.run.</summary>
    class function Block(const ASettings: TAtlasPluginSettings;
      const ASituation: TAtlasOnSaveSituation): TAtlasOnSaveBlock; static;
    /// <summary>ACount betroffene Tests, AAll: alle nötig; AMax = tests.onSave.max.</summary>
    class function Verdict(ACount: Integer; AAll: Boolean; AMax: Integer): TAtlasOnSaveVerdict; static;
  end;

implementation

uses
  System.StrUtils;

{ TAtlasTestsOnSaveQueue }

function TAtlasTestsOnSaveQueue.Add(const AFileName: string): Boolean;
begin
  if IndexText(AFileName, FPending) < 0 then
  begin
    FPending := FPending + [AFileName];
  end;
  Result := not FActive;
end;

function TAtlasTestsOnSaveQueue.Take: TArray<string>;
begin
  Result := FPending;
  FPending := nil;
  FActive := True;
end;

function TAtlasTestsOnSaveQueue.Finish: Boolean;
begin
  FActive := False;
  Result := Length(FPending) > 0;
end;

procedure TAtlasTestsOnSaveQueue.Clear;
begin
  FPending := nil;
end;

{ TAtlasTestsOnSave }

class function TAtlasTestsOnSave.Counts(const AFileName: string): Boolean;
begin
  Result := MatchText(ExtractFileExt(AFileName), ['.pas', '.dfm', '.fmx', '.inc']);
end;

class function TAtlasTestsOnSave.Block(const ASettings: TAtlasPluginSettings;
  const ASituation: TAtlasOnSaveSituation): TAtlasOnSaveBlock;
begin
  Result := TAtlasOnSaveBlock.None;
  if not (ASettings.Enabled and ASettings.TestRun and ASettings.TestsAffected and ASettings.TestsOnSave) then
  begin
    Result := TAtlasOnSaveBlock.Off;
  end
  else if ASituation.Debugging then
  begin
    Result := TAtlasOnSaveBlock.Debugging;
  end
  else if ASituation.Building then
  begin
    Result := TAtlasOnSaveBlock.Building;
  end
  else if ASituation.TestsBusy then
  begin
    Result := TAtlasOnSaveBlock.TestsBusy;
  end;
end;

class function TAtlasTestsOnSave.Verdict(ACount: Integer; AAll: Boolean; AMax: Integer): TAtlasOnSaveVerdict;
begin
  if AAll then
  begin
    Result := TAtlasOnSaveVerdict.AllNeeded;
  end
  else if ACount <= 0 then
  begin
    Result := TAtlasOnSaveVerdict.NoTests;
  end
  else if ACount > AMax then
  begin
    Result := TAtlasOnSaveVerdict.TooMany;
  end
  else
  begin
    Result := TAtlasOnSaveVerdict.Run;
  end;
end;

end.
