unit Atlas.Core.Vcs.ToolCheck;

// „Prüfen“ auf der Seite Versionsverwaltung (#1285): startet git --version
// bzw. svn --version --quiet mit kurzer Zeitgrenze und ordnet das Ergebnis
// einem Zustand zu (gefunden mit Version, fehlt, startet nicht mit Exit-Code,
// antwortet nicht). Die Auswertung der Ausgabe und die Zuordnung sind reine
// Funktionen; Check startet einen Prozess und gehört nie in den Hauptthread.
// Ohne VCL; die Texte für die Anzeige bildet die Optionsseite.

interface

uses
  System.SysUtils,
  Atlas.Core.Vcs.Contract,
  Atlas.Core.Vcs.Tools;

type
{$SCOPEDENUMS ON}
  /// <summary>Found: Programm antwortet mit Version. Missing: nicht gefunden (oder eigener Pfad fehlt).
  /// StartFailed: Exit-Code ungleich 0 oder Start misslungen. NoAnswer: Zeitgrenze überschritten.
  /// NotRecognized: Exit-Code 0, aber keine Versionsangabe von git bzw. svn.</summary>
  TAtlasVcsToolState = (Found, Missing, StartFailed, NoAnswer, NotRecognized);
{$SCOPEDENUMS OFF}

  /// <summary>Ergebnis einer Prüfung.</summary>
  TAtlasVcsToolCheck = record
    Kind: TAtlasVcsKind;
    State: TAtlasVcsToolState;
    /// <summary>Versionsangabe, z. B. "git version 2.47.1" bzw. "svn 1.14.3"; '' ohne.</summary>
    Version: string;
    /// <summary>Exit-Code bei StartFailed; -1, wenn der Prozess nicht lief.</summary>
    ExitCode: Integer;
    Location: TAtlasVcsToolLocation;
  end;

  TAtlasVcsToolChecks = class
  public const
    /// <summary>Zeitgrenze für „Prüfen“.</summary>
    TimeoutMs = 5000;
  public
    /// <summary>Argumente der Versionsabfrage: git --version bzw. svn --version --quiet.</summary>
    class function VersionArguments(AKind: TAtlasVcsKind): TArray<string>; static;
    /// <summary>Versionsangabe aus der Ausgabe; '' wenn sie nicht von git bzw. svn stammt. git: erste Zeile
    /// "git version …" ohne Zusatz wie ".windows.1"; svn --quiet: nur die Nummer, daraus "svn 1.14.3".</summary>
    class function ParseVersion(AKind: TAtlasVcsKind; const AOutput: string): string; static;
    /// <summary>Zustand aus Fundort und Prozessergebnis (reine Funktion).</summary>
    class function Classify(AKind: TAtlasVcsKind; const ALocation: TAtlasVcsToolLocation;
      const ARun: TAtlasVcsRunResult): TAtlasVcsToolCheck; static;
    /// <summary>Zustand ohne Prozess (Programm fehlt), für die Anzeige beim Öffnen der Seite.</summary>
    class function Missing(AKind: TAtlasVcsKind; const ALocation: TAtlasVcsToolLocation): TAtlasVcsToolCheck;
      static;
    /// <summary>Prüft das Programm an ALocation über ARunner (Zeitgrenze TimeoutMs). Startet einen Prozess:
    /// nur aus einem Hintergrund-Thread.</summary>
    class function Check(AKind: TAtlasVcsKind; const ALocation: TAtlasVcsToolLocation;
      const ARunner: IAtlasVcsRunner): TAtlasVcsToolCheck; static;
  end;

implementation

class function TAtlasVcsToolChecks.VersionArguments(AKind: TAtlasVcsKind): TArray<string>;
begin
  if AKind = TAtlasVcsKind.Svn then
    Result := TArray<string>.Create('--version', '--quiet')
  else
    Result := TArray<string>.Create('--version');
end;

class function TAtlasVcsToolChecks.ParseVersion(AKind: TAtlasVcsKind; const AOutput: string): string;
const
  cGitPrefix = 'git version ';
var
  mLine, mNumber: string;
  mLines: TArray<string>;
  mIndex, mDots: Integer;
begin
  Result := '';
  mLines := AOutput.Replace(#13, '').Split([#10]);
  mLine := '';
  for mIndex := 0 to High(mLines) do
    if Trim(mLines[mIndex]) <> '' then
    begin
      mLine := Trim(mLines[mIndex]);
      Break;
    end;
  if mLine = '' then
    Exit;
  if AKind = TAtlasVcsKind.Git then
  begin
    if not mLine.StartsWith(cGitPrefix, True) then
      Exit;
    mNumber := Trim(Copy(mLine, Length(cGitPrefix) + 1, MaxInt));
  end
  else if AKind = TAtlasVcsKind.Svn then
    mNumber := mLine
  else
    Exit;
  // Nur die ersten drei Zahlen ("2.47.1.windows.1" → "2.47.1"); ohne Ziffer am Anfang keine Version.
  if (mNumber = '') or not CharInSet(mNumber[1], ['0'..'9']) then
    Exit;
  mDots := 0;
  for mIndex := 1 to Length(mNumber) do
  begin
    if mNumber[mIndex] = '.' then
    begin
      Inc(mDots);
      if mDots = 3 then
      begin
        mNumber := Copy(mNumber, 1, mIndex - 1);
        Break;
      end;
    end
    else if not CharInSet(mNumber[mIndex], ['0'..'9']) then
    begin
      mNumber := Copy(mNumber, 1, mIndex - 1);
      Break;
    end;
  end;
  mNumber := mNumber.TrimRight(['.']);
  if mNumber = '' then
    Exit;
  if AKind = TAtlasVcsKind.Git then
    Result := cGitPrefix + mNumber
  else
    Result := 'svn ' + mNumber;
end;

class function TAtlasVcsToolChecks.Missing(AKind: TAtlasVcsKind;
  const ALocation: TAtlasVcsToolLocation): TAtlasVcsToolCheck;
begin
  Result.Kind := AKind;
  Result.State := TAtlasVcsToolState.Missing;
  Result.Version := '';
  Result.ExitCode := -1;
  Result.Location := ALocation;
end;

class function TAtlasVcsToolChecks.Classify(AKind: TAtlasVcsKind; const ALocation: TAtlasVcsToolLocation;
  const ARun: TAtlasVcsRunResult): TAtlasVcsToolCheck;
begin
  Result := Missing(AKind, ALocation);
  if ALocation.Executable = '' then
    Exit;
  case ARun.Outcome of
    TAtlasVcsOutcome.Ok:
      if ARun.ExitCode <> 0 then
      begin
        Result.State := TAtlasVcsToolState.StartFailed;
        Result.ExitCode := ARun.ExitCode;
      end
      else
      begin
        Result.ExitCode := 0;
        Result.Version := ParseVersion(AKind, TEncoding.UTF8.GetString(ARun.Output));
        if Result.Version <> '' then
          Result.State := TAtlasVcsToolState.Found
        else
          Result.State := TAtlasVcsToolState.NotRecognized;
      end;
    TAtlasVcsOutcome.ToolMissing:
      Result.State := TAtlasVcsToolState.Missing;
    TAtlasVcsOutcome.TimedOut, TAtlasVcsOutcome.Cancelled:
      Result.State := TAtlasVcsToolState.NoAnswer;
  else
    // Failed (Start misslungen, z. B. keine ausführbare Datei) und MainThread.
    Result.State := TAtlasVcsToolState.StartFailed;
    Result.ExitCode := ARun.ExitCode;
  end;
end;

class function TAtlasVcsToolChecks.Check(AKind: TAtlasVcsKind; const ALocation: TAtlasVcsToolLocation;
  const ARunner: IAtlasVcsRunner): TAtlasVcsToolCheck;
var
  mRun: TAtlasVcsRunResult;
  mDir: string;
begin
  if (ALocation.Executable = '') or (ARunner = nil) then
    Exit(Missing(AKind, ALocation));
  mDir := ExtractFileDir(ALocation.Executable);
  mRun := ARunner.Run(ALocation.Executable, VersionArguments(AKind), mDir, TimeoutMs);
  Result := Classify(AKind, ALocation, mRun);
end;

end.
