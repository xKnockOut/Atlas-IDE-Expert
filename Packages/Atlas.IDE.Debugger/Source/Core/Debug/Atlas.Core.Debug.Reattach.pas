unit Atlas.Core.Debug.Reattach;

// Erneut an einen Prozess anhängen und auf den Start eines Prozesses warten
// (#2171), ohne IDE und ohne Windows:
// - TAtlasReattach.Decide wählt aus der Prozessliste: genau ein Prozess mit
//   dem gemerkten Pfad wird ohne Rückfrage angehängt; mehrere mit dem Pfad
//   oder nur gleiche Namen (etwa eine andere Version an anderem Ort) gehen in
//   die Auswahl; ohne Treffer bietet Atlas das Warten an. Ist kein Pfad
//   bekannt, zählt der Name wie der Pfad.
// - Arrival findet beim Warten den ersten passenden Prozess, der beim Beginn
//   des Wartens noch nicht lief.
// - Cells und Row liefern die Zeile der Auswahl: Kennung, Startzeit,
//   Befehlszeile.

interface

uses
  System.SysUtils;

type
  {$SCOPEDENUMS ON}
  /// <summary>Was „Erneut anhängen“ tut: sofort anhängen, auswählen lassen oder Warten anbieten.</summary>
  TAtlasReattachDecision = (Attach, Choose, Wait);
  {$SCOPEDENUMS OFF}

  /// <summary>Ein laufender Prozess, wie ihn die IDE-Schicht aus Windows liest.</summary>
  TAtlasReattachProcess = record
    Pid: Cardinal;
    /// <summary>Vollständiger Pfad der EXE; '' ohne Zugriff.</summary>
    Path: string;
    /// <summary>Name der EXE, z. B. "Kunden.exe".</summary>
    Name: string;
    /// <summary>Startzeit (lokal); 0 = unbekannt.</summary>
    StartedAt: TDateTime;
    /// <summary>Befehlszeile; '' ohne Zugriff.</summary>
    CommandLine: string;
    class function Create(APid: Cardinal; const APath, AName: string): TAtlasReattachProcess; static;
  end;

  TAtlasReattachProcesses = TArray<TAtlasReattachProcess>;

  TAtlasReattach = record
  public
    /// <summary>Name zu APath ("C:\Bin\Kunden.exe" → "Kunden.exe").</summary>
    class function NameOf(const APath: string): string; static;
    /// <summary>Passt AProcess zum gemerkten ATarget (Pfad; ohne Pfad nur Name)?</summary>
    class function SamePath(const ATarget: string; const AProcess: TAtlasReattachProcess): Boolean; static;
    class function SameName(const ATarget: string; const AProcess: TAtlasReattachProcess): Boolean; static;
    /// <summary>Entscheidung für ATarget (Pfad der EXE); ACandidates sind die Prozesse zum Anhängen bzw. für die
    /// Auswahl (erst gleicher Pfad, sonst gleicher Name).</summary>
    class function Decide(const ATarget: string; const AProcesses: TAtlasReattachProcesses;
      out ACandidates: TAtlasReattachProcesses): TAtlasReattachDecision; static;
    /// <summary>Kennungen aller Prozesse (Stand beim Beginn des Wartens).</summary>
    class function Pids(const AProcesses: TAtlasReattachProcesses): TArray<Cardinal>; static;
    /// <summary>Erster Prozess zu ATarget, dessen Kennung nicht in AKnown steht; False ohne.</summary>
    class function Arrival(const ATarget: string; const AProcesses: TAtlasReattachProcesses;
      const AKnown: TArray<Cardinal>; out AProcess: TAtlasReattachProcess): Boolean; static;
    /// <summary>Zellen der Auswahl: Kennung, Startzeit ('' = unbekannt), Befehlszeile (sonst Pfad, sonst Name).
    /// </summary>
    class function Cells(const AProcess: TAtlasReattachProcess; const AFormat: TFormatSettings): TArray<string>;
      static;
    /// <summary>Zeile der Auswahl: "4711 · 13.11.2026 10:15:02 · C:\Bin\Kunden.exe -demo".</summary>
    class function Row(const AProcess: TAtlasReattachProcess; const AFormat: TFormatSettings): string; static;
  end;

implementation

const
  cSeparator = ' · ';

{ TAtlasReattachProcess }

class function TAtlasReattachProcess.Create(APid: Cardinal; const APath, AName: string): TAtlasReattachProcess;
begin
  Result := Default(TAtlasReattachProcess);
  Result.Pid := APid;
  Result.Path := APath;
  Result.Name := AName;
end;

{ TAtlasReattach }

class function TAtlasReattach.NameOf(const APath: string): string;
var
  mIndex: Integer;
begin
  Result := APath;
  for mIndex := Length(APath) downto 1 do
  begin
    if CharInSet(APath[mIndex], ['\', '/']) then
    begin
      Exit(Copy(APath, mIndex + 1, MaxInt));
    end;
  end;
end;

class function TAtlasReattach.SamePath(const ATarget: string; const AProcess: TAtlasReattachProcess): Boolean;
begin
  if NameOf(ATarget) = ATarget then
  begin
    // Nur ein Name gemerkt: der Name zählt wie der Pfad.
    Exit(SameName(ATarget, AProcess));
  end;
  Result := (AProcess.Path <> '') and SameText(AProcess.Path, ATarget);
end;

class function TAtlasReattach.SameName(const ATarget: string; const AProcess: TAtlasReattachProcess): Boolean;
var
  mName: string;
begin
  mName := AProcess.Name;
  if mName = '' then
  begin
    mName := NameOf(AProcess.Path);
  end;
  Result := (mName <> '') and SameText(mName, NameOf(ATarget));
end;

class function TAtlasReattach.Decide(const ATarget: string; const AProcesses: TAtlasReattachProcesses;
  out ACandidates: TAtlasReattachProcesses): TAtlasReattachDecision;
var
  mProcess: TAtlasReattachProcess;
  mByName: TAtlasReattachProcesses;
begin
  ACandidates := nil;
  mByName := nil;
  if Trim(ATarget) = '' then
  begin
    Exit(TAtlasReattachDecision.Wait);
  end;
  for mProcess in AProcesses do
  begin
    if SamePath(ATarget, mProcess) then
    begin
      ACandidates := ACandidates + [mProcess];
    end
    else if SameName(ATarget, mProcess) then
    begin
      mByName := mByName + [mProcess];
    end;
  end;
  if Length(ACandidates) = 1 then
  begin
    Exit(TAtlasReattachDecision.Attach);
  end;
  // Mehrere mit gleichem Pfad: nur diese zur Wahl; sonst die mit gleichem Namen (andere Version).
  if ACandidates = nil then
  begin
    ACandidates := mByName;
  end;
  Result := TAtlasReattachDecision.Choose;
  if ACandidates = nil then
  begin
    Result := TAtlasReattachDecision.Wait;
  end;
end;

class function TAtlasReattach.Pids(const AProcesses: TAtlasReattachProcesses): TArray<Cardinal>;
var
  mIndex: Integer;
begin
  SetLength(Result, Length(AProcesses));
  for mIndex := 0 to High(AProcesses) do
  begin
    Result[mIndex] := AProcesses[mIndex].Pid;
  end;
end;

function Contains(const APids: TArray<Cardinal>; APid: Cardinal): Boolean;
var
  mPid: Cardinal;
begin
  for mPid in APids do
  begin
    if mPid = APid then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasReattach.Arrival(const ATarget: string; const AProcesses: TAtlasReattachProcesses;
  const AKnown: TArray<Cardinal>; out AProcess: TAtlasReattachProcess): Boolean;
var
  mProcess: TAtlasReattachProcess;
begin
  AProcess := Default(TAtlasReattachProcess);
  for mProcess in AProcesses do
  begin
    if SamePath(ATarget, mProcess) and not Contains(AKnown, mProcess.Pid) then
    begin
      AProcess := mProcess;
      Exit(True);
    end;
  end;
  Result := False;
end;

class function TAtlasReattach.Cells(const AProcess: TAtlasReattachProcess;
  const AFormat: TFormatSettings): TArray<string>;
var
  mStart, mWhat: string;
begin
  mStart := '';
  if AProcess.StartedAt > 0 then
  begin
    mStart := DateTimeToStr(AProcess.StartedAt, AFormat);
  end;
  mWhat := AProcess.CommandLine;
  if mWhat = '' then
  begin
    mWhat := AProcess.Path;
  end;
  if mWhat = '' then
  begin
    mWhat := AProcess.Name;
  end;
  Result := [IntToStr(AProcess.Pid), mStart, mWhat];
end;

class function TAtlasReattach.Row(const AProcess: TAtlasReattachProcess; const AFormat: TFormatSettings): string;
var
  mCells: TArray<string>;
  mCell: string;
begin
  mCells := Cells(AProcess, AFormat);
  Result := mCells[0];
  for mCell in Copy(mCells, 1, MaxInt) do
  begin
    if mCell <> '' then
    begin
      Result := Result + cSeparator + mCell;
    end;
  end;
end;

end.
