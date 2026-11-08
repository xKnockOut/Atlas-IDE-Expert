unit Atlas.Core.Files.ProcessLeftovers;

// Reste beendeter IDE-Prozesse unter %LOCALAPPDATA%\Atlas: Die Liste offener und
// ungespeicherter Dateien (editor-dirty-<pid>.json) und der Build-Eingang
// (ide-builds\<pid>) gehören je einem Prozess. Endet er sauber, räumt er sie weg;
// stürzt er ab oder wird er hart beendet, bleiben sie liegen. Das Plugin räumt sie
// beim Start auf: Weg darf ein Eintrag, dessen Prozess nicht mehr läuft oder dessen
// Nummer inzwischen ein später gestarteter Prozess trägt (Stand des Eintrags älter
// als der Prozess). Den eigenen Prozess fasst es nie an.
// Ohne Windows und Dateisystem: Einträge und die Frage „läuft noch?“ kommen herein.

interface

uses
  System.SysUtils;

type
  /// <summary>Ein Eintrag mit Prozessnummer im Namen.</summary>
  TAtlasLeftover = record
    Path: string;
    Pid: Cardinal;
    /// <summary>Letzte Änderung des Eintrags (Ortszeit).</summary>
    Stamp: TDateTime;
    class function Create(const APath: string; APid: Cardinal; AStamp: TDateTime): TAtlasLeftover; static;
  end;

  /// <summary>Läuft Prozess APid noch, und lief er schon zur Zeit AStamp (sonst gehört die Nummer einem neuen)?
  /// </summary>
  TAtlasLeftoverAlive = reference to function(APid: Cardinal; AStamp: TDateTime): Boolean;

  TAtlasProcessLeftovers = class
  public const
    cDirtyPrefix = 'editor-dirty-';
    cDirtySuffix = '.json';
    cBuildsFolder = 'ide-builds';
  public
    /// <summary>Prozessnummer aus AName = APrefix + Zahl + ASuffix (Groß-/Kleinschreibung egal); False sonst.
    /// </summary>
    class function PidOf(const AName, APrefix, ASuffix: string; out APid: Cardinal): Boolean; static;
    /// <summary>Pfade der Einträge, die weg dürfen: nicht AOwnPid und AAlive verneint.</summary>
    class function Stale(const AEntries: TArray<TAtlasLeftover>; AOwnPid: Cardinal;
      const AAlive: TAtlasLeftoverAlive): TArray<string>; static;
  end;

implementation

{ TAtlasLeftover }

class function TAtlasLeftover.Create(const APath: string; APid: Cardinal; AStamp: TDateTime): TAtlasLeftover;
begin
  Result.Path := APath;
  Result.Pid := APid;
  Result.Stamp := AStamp;
end;

{ TAtlasProcessLeftovers }

class function TAtlasProcessLeftovers.PidOf(const AName, APrefix, ASuffix: string; out APid: Cardinal): Boolean;
var
  mDigits: string;
  mValue: Int64;
begin
  APid := 0;
  Result := (Length(AName) > Length(APrefix) + Length(ASuffix)) and
    SameText(Copy(AName, 1, Length(APrefix)), APrefix) and
    SameText(Copy(AName, Length(AName) - Length(ASuffix) + 1, Length(ASuffix)), ASuffix);
  if not Result then
  begin
    Exit;
  end;
  mDigits := Copy(AName, Length(APrefix) + 1, Length(AName) - Length(APrefix) - Length(ASuffix));
  Result := (mDigits <> '') and (mDigits[1] <> '-') and (mDigits[1] <> '+') and TryStrToInt64(mDigits, mValue) and
    (mValue > 0) and (mValue <= High(Cardinal));
  if Result then
  begin
    APid := Cardinal(mValue);
  end;
end;

class function TAtlasProcessLeftovers.Stale(const AEntries: TArray<TAtlasLeftover>; AOwnPid: Cardinal;
  const AAlive: TAtlasLeftoverAlive): TArray<string>;
var
  mEntry: TAtlasLeftover;
begin
  Result := nil;
  for mEntry in AEntries do
  begin
    if (mEntry.Pid <> AOwnPid) and not AAlive(mEntry.Pid, mEntry.Stamp) then
    begin
      Result := Result + [mEntry.Path];
    end;
  end;
end;

end.
