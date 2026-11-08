unit Atlas.Core.VersionControl.ToolCheck;

// „Prüfen“ auf der Seite Versionsverwaltung (#1285): startet git --version
// bzw. svn --version --quiet mit kurzer Zeitgrenze und ordnet das Ergebnis
// einem Zustand zu (gefunden mit Version, fehlt, startet nicht mit Exit-Code,
// antwortet nicht). Die Auswertung der Ausgabe und die Zuordnung sind reine
// Funktionen; Check startet einen Prozess und gehört nie in den Hauptthread.
// Ohne VCL; die Texte für die Anzeige bildet die Optionsseite.

interface

uses
  System.SysUtils,
  Atlas.Core.VersionControl.Contract,
  Atlas.Core.VersionControl.Tools;

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
    cTimeoutMs = 5000;
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
  begin
    Result := TArray<string>.Create('--version', '--quiet');
  end
  else
  begin
    Result := TArray<string>.Create('--version');
  end;
end;

/// <summary>Erste nicht leere Zeile, getrimmt; '' ohne.</summary>
function FirstLine(const AOutput: string): string;
var
  mLine: string;
begin
  for mLine in AOutput.Replace(#13, '').Split([#10]) do
  begin
    if Trim(mLine) <> '' then
    begin
      Exit(Trim(mLine));
    end;
  end;
  Result := '';
end;

/// <summary>Nur die ersten drei Zahlen ("2.47.1.windows.1" → "2.47.1"); '' ohne Ziffer am Anfang.</summary>
function VersionNumber(const AText: string): string;
var
  mIndex, mDots: Integer;
begin
  Result := '';
  if (AText = '') or not CharInSet(AText[1], ['0'..'9']) then
  begin
    Exit;
  end;
  mDots := 0;
  mIndex := 1;
  while (mIndex <= Length(AText)) and (mDots < 3) and CharInSet(AText[mIndex], ['0'..'9', '.']) do
  begin
    if AText[mIndex] = '.' then
    begin
      Inc(mDots);
    end;
    Inc(mIndex);
  end;
  // Der dritte Punkt gehört nicht dazu.
  Result := Copy(AText, 1, mIndex - 1).TrimRight(['.']);
end;

class function TAtlasVcsToolChecks.ParseVersion(AKind: TAtlasVcsKind; const AOutput: string): string;
const
  cGitPrefix = 'git version ';
var
  mLine, mNumber: string;
begin
  Result := '';
  mLine := FirstLine(AOutput);
  mNumber := '';
  if (AKind = TAtlasVcsKind.Git) and mLine.StartsWith(cGitPrefix, True) then
  begin
    mNumber := VersionNumber(Trim(Copy(mLine, Length(cGitPrefix) + 1, MaxInt)));
  end
  else if AKind = TAtlasVcsKind.Svn then
  begin
    mNumber := VersionNumber(mLine);
  end;
  if mNumber = '' then
  begin
    Exit;
  end;
  if AKind = TAtlasVcsKind.Git then
  begin
    Result := cGitPrefix + mNumber;
  end
  else
  begin
    Result := 'svn ' + mNumber;
  end;
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
  begin
    Exit;
  end;
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
        begin
          Result.State := TAtlasVcsToolState.Found;
        end
        else
        begin
          Result.State := TAtlasVcsToolState.NotRecognized;
        end;
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
  begin
    Exit(Missing(AKind, ALocation));
  end;
  mDir := ExtractFileDir(ALocation.Executable);
  mRun := ARunner.Run(ALocation.Executable, VersionArguments(AKind), mDir, cTimeoutMs);
  Result := Classify(AKind, ALocation, mRun);
end;

end.
