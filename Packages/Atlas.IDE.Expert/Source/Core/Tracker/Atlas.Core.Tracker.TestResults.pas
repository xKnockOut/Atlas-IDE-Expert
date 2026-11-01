unit Atlas.Core.Tracker.TestResults;

// Bereich „Testergebnisse“ der Willkommensseite (#763), Teil ohne VCL und
// Open Tools API: welche Projekte erscheinen, ihre Ampel lokal und auf dem
// Build-Server, die Liste der fehlgeschlagenen Tests, was „Fehlgeschlagene
// erneut ausführen“ startet und wann der Server wieder gefragt wird.
// - Lokal: Abschnitt "tests" der Projekt-Zusammenfassung (#69, letzter
//   DUnitX-Lauf aus der IDE). Rot bei Fehlschlägen oder Fehlern, grün bei
//   bestandenen Tests, gelb, wenn nichts bestanden hat (alles übersprungen).
// - Server: Abschnitt "ci" (letzter Abruf, Atlas.Core.Ci.Contract). Er zählt
//   nur, wenn er zum Job aus .atlas gehört (Server, Job, bei Multibranch der
//   Branch); sonst gilt er als unbekannt. Rot bei fehlgeschlagenen Tests oder
//   Ergebnis FAILURE, gelb bei UNSTABLE ohne Testfehler, ABORTED, NOT_BUILT,
//   grün bei SUCCESS.
// - Abgleich: „lokal grün, Server rot“ und umgekehrt, nur wenn beide bekannt.
// - Liste: zuerst die lokalen Fehlschläge (mit Datei und Zeile), dann die nur
//   auf dem Server, höchstens welcomePage.tests.maxFailures; gibt es beide,
//   bleibt die Hälfte der Plätze für den Server. Gleiche Tests (gleicher
//   voller Name) stehen einmal da, mit beiden Marken.
// - Erneut ausführen: alle gespeicherten fehlgeschlagenen Tests des Projekts,
//   lokal und (sofern der Stand passt) vom Server, ohne Doppelte.
// - Abfrage: frühestens welcomePage.tests.ci.intervalMinutes nach dem letzten
//   Versuch (auch nach einem Fehler, damit ein nicht erreichbarer Server die
//   Seite nicht bei jedem Anzeigen aufhält).
// - Rot geworden: neuer Build (andere Nummer) desselben Jobs ist rot, der
//   vorige war es nicht. Beim ersten Abruf gibt es keine Meldung.

interface

uses
  System.SysUtils,
  Atlas.Core.CiBuild.Contract,
  Atlas.Core.Projects.Summary;

type
{$SCOPEDENUMS ON}
  /// <summary>Ampel: Unknown grau, Passed grün, Warning gelb, Failed rot.</summary>
  TAtlasTestLevel = (Unknown, Passed, Warning, Failed);
  TAtlasTestMismatch = (None, LocalGreenServerRed, LocalRedServerGreen);
{$SCOPEDENUMS OFF}

  /// <summary>Ein Projekt der Liste mit seiner Zusammenfassung und dem Job aus .atlas.</summary>
  TAtlasTestProject = record
    /// <summary>Projektdatei (.dproj, .groupproj).</summary>
    Project: string;
    Summary: TAtlasProjectSummary;
    /// <summary>Job aus .atlas (#486) mit dem Branch (#571); nicht Configured = kein Server.</summary>
    Job: TAtlasCiJob;
    /// <summary>Abfrage beim Server läuft gerade.</summary>
    Querying: Boolean;
  end;

  TAtlasTestRow = record
    /// <summary>Projektdatei; Schlüssel der Auswahl.</summary>
    Project: string;
    /// <summary>Name des Testprojekts, sonst des Projekts, ohne Endung.</summary>
    Name: string;
    /// <summary>Testprojekt des letzten Laufs (.dproj); '' ohne lokalen Lauf.</summary>
    TestProject: string;
    Local: TAtlasProjectTests;
    LocalLevel: TAtlasTestLevel;
    /// <summary>Für das Projekt ist ein Build-Server eingetragen (und welcomePage.tests.ci an).</summary>
    HasCi: Boolean;
    Job: TAtlasCiJob;
    /// <summary>Stand vom Server, nur wenn er zum Job passt; sonst Empty.</summary>
    Ci: TAtlasProjectCi;
    CiLevel: TAtlasTestLevel;
    /// <summary>Der letzte Abruf schlug fehl, gezeigt wird der Stand vom Ci.At.</summary>
    CiStale: Boolean;
    CiQuerying: Boolean;
    Mismatch: TAtlasTestMismatch;
    /// <summary>Höchste Ampel aus lokal und Server.</summary>
    function Level: TAtlasTestLevel;
  end;

  TAtlasTestFailureItem = record
    /// <summary>Voller Name (Unit.Fixture.Methode).</summary>
    Test: string;
    Message: string;
    /// <summary>Nur lokal: Datei (absolut) und Zeile ab 1; sonst '' und 0.</summary>
    FileName: string;
    Line: Integer;
    /// <summary>Im letzten lokalen Lauf fehlgeschlagen.</summary>
    Local: Boolean;
    /// <summary>Im letzten Build auf dem Server fehlgeschlagen.</summary>
    Server: Boolean;
  end;

  TAtlasTestResultsView = record
    Rows: TArray<TAtlasTestRow>;
    /// <summary>Index der gewählten Zeile; -1 ohne Zeilen.</summary>
    Selected: Integer;
    /// <summary>Fehlschläge der gewählten Zeile.</summary>
    Failures: TArray<TAtlasTestFailureItem>;
    /// <summary>Weitere Fehlschläge, die nicht in der Liste stehen.</summary>
    More: Integer;
    /// <summary>Namen für „Fehlgeschlagene erneut ausführen“.</summary>
    Rerun: TArray<string>;
    function Empty: Boolean;
    function SelectedRow(out ARow: TAtlasTestRow): Boolean;
  end;

  TAtlasTestResults = class
  public const
    cDefaultMaxFailures = 5;
    cMinMaxFailures = 1;
    cMaxMaxFailures = 50;
    cDefaultIntervalMinutes = 10;
    cMinIntervalMinutes = 1;
    /// <summary>Höchstens einmal am Tag.</summary>
    cMaxIntervalMinutes = 1440;
    /// <summary>Zeitlimit einer Abfrage beim Server (beide Aufrufe zusammen).</summary>
    cFetchTimeoutMs = 5000;
    cDefaultProvider = 'jenkins';
  private const
    cKeySeparator = '|';
    /// <summary>Spielraum von einer Sekunde (1/60 Minute), damit eine knapp frühe Abfrage schon zählt.</summary>
    cSecondsPerMinute = 60;
  private
    /// <summary>Index des Fehlschlags ATest in AItems (ASame: SameTest, sonst gleicher Name); -1 ohne.</summary>
    class function IndexOfTest(const AItems: TArray<TAtlasTestFailureItem>; const ATest: string;
      ASame: Boolean): Integer; static;
    /// <summary>Lokale Fehlschläge ohne leere und doppelte Namen.</summary>
    class function LocalFailures(const ALocal: TAtlasProjectTests): TArray<TAtlasTestFailureItem>; static;
    /// <summary>Fehlschläge nur auf dem Server; markiert die lokalen, die auch dort fehlschlagen.</summary>
    class function ServerOnlyFailures(var ALocals: TArray<TAtlasTestFailureItem>;
      const AServer: TAtlasCiBuild): TArray<TAtlasTestFailureItem>; static;
    /// <summary>Gezählte, aber nicht gespeicherte Fehlschläge.</summary>
    class function HiddenBeyond(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
      AUseServer: Boolean): Integer; static;
    /// <summary>Schlüssel einer Zeile: Testprojekt bzw. Projekt, mit Server samt Job.</summary>
    class function RowKey(const ARow: TAtlasTestRow): string; static;
    /// <summary>Zeilen mit lokalem Lauf oder Server, jeder Schlüssel einmal.</summary>
    class function Rows(const AProjects: TArray<TAtlasTestProject>; ACiEnabled: Boolean): TArray<TAtlasTestRow>;
      static;
  public
    class function LocalLevel(const ATests: TAtlasProjectTests): TAtlasTestLevel; static;
    class function CiLevel(const ABuild: TAtlasCiBuild): TAtlasTestLevel; static;
    class function Compare(ALocal, AServer: TAtlasTestLevel): TAtlasTestMismatch; static;
    /// <summary>Gleicher Test: gleicher voller Name, oder einer endet mit „.“ + dem anderen.</summary>
    class function SameTest(const AA, AB: string): Boolean; static;
    /// <summary>Liste der Fehlschläge; AServer nur mit AUseServer. AMore zählt, was nicht hineinpasst.</summary>
    class function MergeFailures(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
      AUseServer: Boolean; AMax: Integer; out AMore: Integer): TArray<TAtlasTestFailureItem>; static;
    class function RerunNames(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
      AUseServer: Boolean): TArray<string>; static;
    /// <summary>Server wieder fragen: ohne Versuch, nach Ablauf des Abstands oder wenn die Uhr zurückging.
    /// </summary>
    class function Due(ALastAttemptUtc, ANowUtc: TDateTime; AIntervalMinutes: Integer): Boolean; static;
    /// <summary>Stand nach einer Abfrage. Ohne Erfolg bleibt der letzte Build desselben Jobs stehen.</summary>
    class function Recorded(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob; ASucceeded: Boolean;
      const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError; ANowUtc: TDateTime): TAtlasProjectCi; static;
    /// <summary>Der neue Build ist rot und ersetzt einen nicht roten desselben Jobs.</summary>
    class function TurnedRed(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob;
      const ANew: TAtlasCiBuild): Boolean; static;
    /// <summary>Stand passend zu AJob (sonst Empty).</summary>
    class function CiFor(const ASummary: TAtlasProjectSummary; const AJob: TAtlasCiJob): TAtlasProjectCi; static;
    class function Row(const AProject: TAtlasTestProject; ACiEnabled: Boolean): TAtlasTestRow; static;
    /// <summary>Projekte mit lokalem Lauf oder (mit ACiEnabled) eingetragenem Server, gleiche Testprojekte
    /// einmal; ASelected wählt die Zeile (sonst die erste).</summary>
    class function View(const AProjects: TArray<TAtlasTestProject>; const ASelected: string;
      AMaxFailures: Integer; ACiEnabled: Boolean): TAtlasTestResultsView; static;
    /// <summary>Anbieter für die Anzeige: "jenkins" → "Jenkins".</summary>
    class function ProviderCaption(const AProvider: string): string; static;
    class function NormalizedMaxFailures(AValue: Integer): Integer; static;
    class function NormalizedInterval(AValue: Integer): Integer; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils;

{ TAtlasTestRow }

function TAtlasTestRow.Level: TAtlasTestLevel;
begin
  Result := LocalLevel;
  if Ord(CiLevel) > Ord(Result) then
  begin
    Result := CiLevel;
  end;
end;

{ TAtlasTestResultsView }

function TAtlasTestResultsView.Empty: Boolean;
begin
  Result := Length(Rows) = 0;
end;

function TAtlasTestResultsView.SelectedRow(out ARow: TAtlasTestRow): Boolean;
begin
  Result := (Selected >= 0) and (Selected < Length(Rows));
  if Result then
  begin
    ARow := Rows[Selected];
  end
  else
  begin
    ARow := Default(TAtlasTestRow);
  end;
end;

{ TAtlasTestResults }

class function TAtlasTestResults.LocalLevel(const ATests: TAtlasProjectTests): TAtlasTestLevel;
begin
  if not ATests.Known then
  begin
    Result := TAtlasTestLevel.Unknown;
  end
  else if (ATests.Failed > 0) or (ATests.Errors > 0) or (Length(ATests.Failures) > 0) then
  begin
    Result := TAtlasTestLevel.Failed;
  end
  else if ATests.Passed > 0 then
  begin
    Result := TAtlasTestLevel.Passed;
  end
  else
  begin
    Result := TAtlasTestLevel.Warning;
  end;
end;

class function TAtlasTestResults.CiLevel(const ABuild: TAtlasCiBuild): TAtlasTestLevel;
begin
  if ABuild.Number <= 0 then
  begin
    Exit(TAtlasTestLevel.Unknown);
  end;
  if (ABuild.TestsKnown and ((ABuild.Failed > 0) or (Length(ABuild.Failures) > 0))) or
    (ABuild.Outcome = TAtlasCiOutcome.Failure) then
  begin
    Exit(TAtlasTestLevel.Failed);
  end;
  case ABuild.Outcome of
    TAtlasCiOutcome.Success:
      Result := TAtlasTestLevel.Passed;
  else
    Result := TAtlasTestLevel.Warning;
  end;
end;

class function TAtlasTestResults.Compare(ALocal, AServer: TAtlasTestLevel): TAtlasTestMismatch;
begin
  Result := TAtlasTestMismatch.None;
  if (ALocal = TAtlasTestLevel.Passed) and (AServer = TAtlasTestLevel.Failed) then
  begin
    Result := TAtlasTestMismatch.LocalGreenServerRed;
  end
  else if (ALocal = TAtlasTestLevel.Failed) and (AServer = TAtlasTestLevel.Passed) then
  begin
    Result := TAtlasTestMismatch.LocalRedServerGreen;
  end;
end;

class function TAtlasTestResults.SameTest(const AA, AB: string): Boolean;

  function EndsWithName(const ALong, AShort: string): Boolean;
  begin
    Result := (Length(ALong) > Length(AShort)) and
      SameText(Copy(ALong, Length(ALong) - Length(AShort), MaxInt), '.' + AShort);
  end;

begin
  if (AA = '') or (AB = '') then
  begin
    Exit(False);
  end;
  // Der JUnit-Bericht von DUnitX kann den Unit-Namen weglassen; dann passt das Ende.
  Result := SameText(AA, AB) or EndsWithName(AA, AB) or EndsWithName(AB, AA);
end;

class function TAtlasTestResults.IndexOfTest(const AItems: TArray<TAtlasTestFailureItem>; const ATest: string;
  ASame: Boolean): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := 0 to High(AItems) do
  begin
    if (ASame and SameTest(AItems[mIndex].Test, ATest)) or (not ASame and SameText(AItems[mIndex].Test, ATest)) then
    begin
      Exit(mIndex);
    end;
  end;
end;

class function TAtlasTestResults.LocalFailures(const ALocal: TAtlasProjectTests): TArray<TAtlasTestFailureItem>;
var
  mItem: TAtlasTestFailureItem;
  mFailure: TAtlasProjectTestFailure;
begin
  Result := nil;
  if not ALocal.Known then
  begin
    Exit;
  end;
  for mFailure in ALocal.Failures do
  begin
    if (mFailure.Test <> '') and (IndexOfTest(Result, mFailure.Test, False) < 0) then
    begin
      mItem := Default(TAtlasTestFailureItem);
      mItem.Test := mFailure.Test;
      mItem.Message := mFailure.Message;
      mItem.FileName := mFailure.FileName;
      mItem.Line := mFailure.Line;
      mItem.Local := True;
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasTestResults.ServerOnlyFailures(var ALocals: TArray<TAtlasTestFailureItem>;
  const AServer: TAtlasCiBuild): TArray<TAtlasTestFailureItem>;
var
  mItem: TAtlasTestFailureItem;
  mCiFailure: TAtlasCiFailure;
  mIndex: Integer;
  mFound: Boolean;
begin
  Result := nil;
  for mCiFailure in AServer.Failures do
  begin
    if mCiFailure.Test = '' then
    begin
      Continue;
    end;
    // Lokal schon bekannt: dort als „auch auf dem Server“ markieren (jeder passende Eintrag).
    mFound := False;
    for mIndex := 0 to High(ALocals) do
    begin
      if SameTest(ALocals[mIndex].Test, mCiFailure.Test) then
      begin
        ALocals[mIndex].Server := True;
        mFound := True;
      end;
    end;
    if not mFound and (IndexOfTest(Result, mCiFailure.Test, False) < 0) then
    begin
      mItem := Default(TAtlasTestFailureItem);
      mItem.Test := mCiFailure.Test;
      mItem.Message := mCiFailure.Message;
      mItem.Server := True;
      Result := Result + [mItem];
    end;
  end;
end;

class function TAtlasTestResults.HiddenBeyond(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
  AUseServer: Boolean): Integer;
var
  mKnown: Integer;
begin
  // Über die gespeicherten hinaus gezählte Fehlschläge (je Datei höchstens 50).
  Result := 0;
  if ALocal.Known then
  begin
    mKnown := ALocal.Failed + ALocal.Errors;
    if mKnown > Length(ALocal.Failures) then
    begin
      Inc(Result, mKnown - Length(ALocal.Failures));
    end;
  end;
  if AUseServer and AServer.TestsKnown and (AServer.Failed > Length(AServer.Failures)) then
  begin
    Inc(Result, AServer.Failed - Length(AServer.Failures));
  end;
end;

class function TAtlasTestResults.MergeFailures(const ALocal: TAtlasProjectTests;
  const AServer: TAtlasCiBuild; AUseServer: Boolean; AMax: Integer; out AMore: Integer): TArray<TAtlasTestFailureItem>;
var
  mLocals, mServerOnly: TArray<TAtlasTestFailureItem>;
  mIndex, mReserve, mLocalTake, mServerTake: Integer;
begin
  Result := nil;
  mLocals := LocalFailures(ALocal);
  mServerOnly := nil;
  if AUseServer and AServer.TestsKnown then
  begin
    mServerOnly := ServerOnlyFailures(mLocals, AServer);
  end;
  // Server-Fehlschläge bekommen bis zur Hälfte der Plätze, der Rest geht an die lokalen.
  AMax := Max(AMax, 0);
  mReserve := Min(Length(mServerOnly), AMax div 2);
  mLocalTake := Min(Length(mLocals), AMax - mReserve);
  mServerTake := Min(Length(mServerOnly), AMax - mLocalTake);
  for mIndex := 0 to mLocalTake - 1 do
  begin
    Result := Result + [mLocals[mIndex]];
  end;
  for mIndex := 0 to mServerTake - 1 do
  begin
    Result := Result + [mServerOnly[mIndex]];
  end;
  AMore := Length(mLocals) + Length(mServerOnly) - mLocalTake - mServerTake + HiddenBeyond(ALocal, AServer, AUseServer);
end;

class function TAtlasTestResults.RerunNames(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
  AUseServer: Boolean): TArray<string>;
var
  mName: string;
  mFailure: TAtlasCiFailure;
  mSeen: Boolean;
begin
  Result := nil;
  if ALocal.Known then
  begin
    Result := ALocal.FailedTests;
  end;
  if not (AUseServer and AServer.TestsKnown) then
  begin
    Exit;
  end;
  for mFailure in AServer.Failures do
  begin
    if mFailure.Test = '' then
    begin
      Continue;
    end;
    mSeen := False;
    for mName in Result do
    begin
      if SameTest(mName, mFailure.Test) then
      begin
        mSeen := True;
      end;
    end;
    if not mSeen then
    begin
      Result := Result + [mFailure.Test];
    end;
  end;
end;

class function TAtlasTestResults.Due(ALastAttemptUtc, ANowUtc: TDateTime; AIntervalMinutes: Integer): Boolean;
begin
  if ALastAttemptUtc <= 0 then
  begin
    Exit(True);
  end;
  // Uhr zurückgestellt: nicht bis dahin warten.
  if ALastAttemptUtc > ANowUtc + OneMinute then
  begin
    Exit(True);
  end;
  // Eine Sekunde Spielraum gegen Rundung der Gleitkommazeit.
  Result := (ANowUtc - ALastAttemptUtc) * MinsPerDay + 1 / cSecondsPerMinute >= NormalizedInterval(AIntervalMinutes);
end;

class function TAtlasTestResults.Recorded(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob;
  ASucceeded: Boolean; const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError; ANowUtc: TDateTime): TAtlasProjectCi;
begin
  if AOld.Matches(AJob) then
  begin
    Result := AOld;
  end
  else
  begin
    Result := TAtlasProjectCi.Empty;
    Result.Known := True;
    Result.Provider := AJob.Provider;
    Result.Server := AJob.Server;
    Result.Job := AJob.Job;
    Result.Branch := AJob.JobBranch;
  end;
  Result.Attempt := ANowUtc;
  if ASucceeded then
  begin
    Result.Error := TAtlasCiFetchError.None;
    Result.At := ANowUtc;
    Result.Build := ABuild;
  end
  else
  begin
    Result.Error := AError;
    if Result.Error = TAtlasCiFetchError.None then
    begin
      Result.Error := TAtlasCiFetchError.Network;
    end;
  end;
end;

class function TAtlasTestResults.TurnedRed(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob;
  const ANew: TAtlasCiBuild): Boolean;
begin
  Result := AOld.Matches(AJob) and AOld.HasBuild and (ANew.Number > 0) and
    (ANew.Number <> AOld.Build.Number) and (CiLevel(AOld.Build) <> TAtlasTestLevel.Failed) and
    (CiLevel(ANew) = TAtlasTestLevel.Failed);
end;

class function TAtlasTestResults.CiFor(const ASummary: TAtlasProjectSummary;
  const AJob: TAtlasCiJob): TAtlasProjectCi;
begin
  if ASummary.Ci.Matches(AJob) then
  begin
    Result := ASummary.Ci;
  end
  else
  begin
    Result := TAtlasProjectCi.Empty;
  end;
end;

function NameOfPath(const APath: string): string;
var
  mIndex: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := APath;
  for mIndex := Length(Result) downto 1 do
  begin
    if CharInSet(Result[mIndex], ['\', '/']) then
    begin
      Result := Copy(Result, mIndex + 1, MaxInt);
      Break;
    end;
  end;
  for mIndex := Length(Result) downto 1 do
  begin
    if Result[mIndex] = '.' then
    begin
      Result := Copy(Result, 1, mIndex - 1);
      Break;
    end;
  end;
end;

class function TAtlasTestResults.Row(const AProject: TAtlasTestProject; ACiEnabled: Boolean): TAtlasTestRow;
begin
  Result := Default(TAtlasTestRow);
  Result.Project := AProject.Project;
  Result.Local := AProject.Summary.Tests;
  Result.LocalLevel := LocalLevel(Result.Local);
  if Result.Local.Known then
  begin
    Result.TestProject := Result.Local.Project;
  end;
  Result.Name := NameOfPath(Result.TestProject);
  if Result.Name = '' then
  begin
    Result.Name := NameOfPath(AProject.Project);
  end;
  Result.Job := AProject.Job;
  Result.HasCi := ACiEnabled and AProject.Job.Configured;
  Result.Ci := TAtlasProjectCi.Empty;
  Result.CiLevel := TAtlasTestLevel.Unknown;
  if not Result.HasCi then
  begin
    Exit;
  end;
  Result.Ci := CiFor(AProject.Summary, AProject.Job);
  Result.CiQuerying := AProject.Querying;
  if Result.Ci.HasBuild then
  begin
    Result.CiLevel := CiLevel(Result.Ci.Build);
    Result.CiStale := Result.Ci.Error <> TAtlasCiFetchError.None;
  end;
  Result.Mismatch := Compare(Result.LocalLevel, Result.CiLevel);
end;

class function TAtlasTestResults.RowKey(const ARow: TAtlasTestRow): string;
begin
  // Eine Projektgruppe und ihr Testprojekt tragen denselben Lauf: nur einmal zeigen.
  if ARow.Local.Known and (ARow.TestProject <> '') then
  begin
    Result := LowerCase(ARow.TestProject);
  end
  else
  begin
    Result := LowerCase(ARow.Project);
  end;
  if ARow.HasCi then
  begin
    Result := Result + cKeySeparator + ARow.Job.Key;
  end;
end;

class function TAtlasTestResults.Rows(const AProjects: TArray<TAtlasTestProject>;
  ACiEnabled: Boolean): TArray<TAtlasTestRow>;
var
  mProject: TAtlasTestProject;
  mItem: TAtlasTestRow;
  mKeys: TArray<string>;
  mKey: string;
begin
  Result := nil;
  mKeys := nil;
  for mProject in AProjects do
  begin
    mItem := Row(mProject, ACiEnabled);
    if mItem.Local.Known or mItem.HasCi then
    begin
      mKey := RowKey(mItem);
      if IndexStr(mKey, mKeys) < 0 then
      begin
        mKeys := mKeys + [mKey];
        Result := Result + [mItem];
      end;
    end;
  end;
end;

class function TAtlasTestResults.View(const AProjects: TArray<TAtlasTestProject>; const ASelected: string;
  AMaxFailures: Integer; ACiEnabled: Boolean): TAtlasTestResultsView;
var
  mIndex: Integer;
  mChosen: TAtlasTestRow;
  mUseServer: Boolean;
begin
  Result := Default(TAtlasTestResultsView);
  Result.Rows := Rows(AProjects, ACiEnabled);
  Result.Failures := nil;
  Result.Rerun := nil;
  Result.Selected := -1;
  if Length(Result.Rows) = 0 then
  begin
    Exit;
  end;
  Result.Selected := 0;
  for mIndex := 0 to High(Result.Rows) do
  begin
    if (ASelected <> '') and SameText(Result.Rows[mIndex].Project, ASelected) then
    begin
      Result.Selected := mIndex;
      Break;
    end;
  end;
  mChosen := Result.Rows[Result.Selected];
  mUseServer := mChosen.HasCi and mChosen.Ci.HasBuild;
  Result.Failures := MergeFailures(mChosen.Local, mChosen.Ci.Build, mUseServer, NormalizedMaxFailures(AMaxFailures),
    Result.More);
  Result.Rerun := RerunNames(mChosen.Local, mChosen.Ci.Build, mUseServer);
end;

class function TAtlasTestResults.ProviderCaption(const AProvider: string): string;
begin
  if SameText(AProvider, 'jenkins') then
  begin
    Result := 'Jenkins';
  end
  else if AProvider = '' then
  begin
    Result := '';
  end
  else
  begin
    Result := UpperCase(Copy(AProvider, 1, 1)) + Copy(AProvider, 2, MaxInt);
  end;
end;

class function TAtlasTestResults.NormalizedMaxFailures(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, cMinMaxFailures, cMaxMaxFailures);
end;

class function TAtlasTestResults.NormalizedInterval(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, cMinIntervalMinutes, cMaxIntervalMinutes);
end;

end.
