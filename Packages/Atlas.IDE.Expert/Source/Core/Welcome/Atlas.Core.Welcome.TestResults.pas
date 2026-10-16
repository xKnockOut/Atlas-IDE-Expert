unit Atlas.Core.Welcome.TestResults;

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
  Atlas.Core.Ci.Contract,
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

  TAtlasWelcomeTestResults = class
  public const
    DefaultMaxFailures = 5;
    MinMaxFailures = 1;
    MaxMaxFailures = 50;
    DefaultIntervalMinutes = 10;
    MinIntervalMinutes = 1;
    /// <summary>Höchstens einmal am Tag.</summary>
    MaxIntervalMinutes = 1440;
    /// <summary>Zeitlimit einer Abfrage beim Server (beide Aufrufe zusammen).</summary>
    FetchTimeoutMs = 5000;
    DefaultProvider = 'jenkins';
  public
    class function LocalLevel(const ATests: TAtlasProjectTests): TAtlasTestLevel; static;
    class function CiLevel(const ABuild: TAtlasCiBuild): TAtlasTestLevel; static;
    class function Compare(ALocal, AServer: TAtlasTestLevel): TAtlasTestMismatch; static;
    /// <summary>Gleicher Test: gleicher voller Name, oder einer endet mit „.“ + dem anderen.</summary>
    class function SameTest(const A, B: string): Boolean; static;
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
  System.DateUtils;

{ TAtlasTestRow }

function TAtlasTestRow.Level: TAtlasTestLevel;
begin
  Result := LocalLevel;
  if Ord(CiLevel) > Ord(Result) then
    Result := CiLevel;
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
    ARow := Rows[Selected]
  else
    ARow := Default(TAtlasTestRow);
end;

{ TAtlasWelcomeTestResults }

class function TAtlasWelcomeTestResults.LocalLevel(const ATests: TAtlasProjectTests): TAtlasTestLevel;
begin
  if not ATests.Known then
    Result := TAtlasTestLevel.Unknown
  else if (ATests.Failed > 0) or (ATests.Errors > 0) or (Length(ATests.Failures) > 0) then
    Result := TAtlasTestLevel.Failed
  else if ATests.Passed > 0 then
    Result := TAtlasTestLevel.Passed
  else
    Result := TAtlasTestLevel.Warning;
end;

class function TAtlasWelcomeTestResults.CiLevel(const ABuild: TAtlasCiBuild): TAtlasTestLevel;
begin
  if ABuild.Number <= 0 then
    Exit(TAtlasTestLevel.Unknown);
  if (ABuild.TestsKnown and ((ABuild.Failed > 0) or (Length(ABuild.Failures) > 0))) or
    (ABuild.Outcome = TAtlasCiOutcome.Failure) then
    Exit(TAtlasTestLevel.Failed);
  case ABuild.Outcome of
    TAtlasCiOutcome.Success:
      Result := TAtlasTestLevel.Passed;
  else
    Result := TAtlasTestLevel.Warning;
  end;
end;

class function TAtlasWelcomeTestResults.Compare(ALocal, AServer: TAtlasTestLevel): TAtlasTestMismatch;
begin
  Result := TAtlasTestMismatch.None;
  if (ALocal = TAtlasTestLevel.Passed) and (AServer = TAtlasTestLevel.Failed) then
    Result := TAtlasTestMismatch.LocalGreenServerRed
  else if (ALocal = TAtlasTestLevel.Failed) and (AServer = TAtlasTestLevel.Passed) then
    Result := TAtlasTestMismatch.LocalRedServerGreen;
end;

class function TAtlasWelcomeTestResults.SameTest(const A, B: string): Boolean;

  function EndsWithName(const ALong, AShort: string): Boolean;
  begin
    Result := (Length(ALong) > Length(AShort)) and
      SameText(Copy(ALong, Length(ALong) - Length(AShort), MaxInt), '.' + AShort);
  end;

begin
  if (A = '') or (B = '') then
    Exit(False);
  // Der JUnit-Bericht von DUnitX kann den Unit-Namen weglassen; dann passt das Ende.
  Result := SameText(A, B) or EndsWithName(A, B) or EndsWithName(B, A);
end;

class function TAtlasWelcomeTestResults.MergeFailures(const ALocal: TAtlasProjectTests;
  const AServer: TAtlasCiBuild; AUseServer: Boolean; AMax: Integer; out AMore: Integer): TArray<TAtlasTestFailureItem>;
var
  Locals, ServerOnly: TArray<TAtlasTestFailureItem>;
  Item: TAtlasTestFailureItem;
  Failure: TAtlasProjectTestFailure;
  CiFailure: TAtlasCiFailure;
  Index, Reserve, LocalTake, ServerTake, Known, Hidden: Integer;
  Found: Boolean;
begin
  Result := nil;
  AMore := 0;
  Locals := nil;
  ServerOnly := nil;
  if ALocal.Known then
    for Failure in ALocal.Failures do
    begin
      if Failure.Test = '' then
        Continue;
      Found := False;
      for Index := 0 to High(Locals) do
        if SameText(Locals[Index].Test, Failure.Test) then
          Found := True;
      if Found then
        Continue;
      Item := Default(TAtlasTestFailureItem);
      Item.Test := Failure.Test;
      Item.Message := Failure.Message;
      Item.FileName := Failure.FileName;
      Item.Line := Failure.Line;
      Item.Local := True;
      Locals := Locals + [Item];
    end;
  if AUseServer and AServer.TestsKnown then
    for CiFailure in AServer.Failures do
    begin
      if CiFailure.Test = '' then
        Continue;
      Found := False;
      for Index := 0 to High(Locals) do
        if SameTest(Locals[Index].Test, CiFailure.Test) then
        begin
          Locals[Index].Server := True;
          Found := True;
        end;
      for Index := 0 to High(ServerOnly) do
        if SameText(ServerOnly[Index].Test, CiFailure.Test) then
          Found := True;
      if Found then
        Continue;
      Item := Default(TAtlasTestFailureItem);
      Item.Test := CiFailure.Test;
      Item.Message := CiFailure.Message;
      Item.Server := True;
      ServerOnly := ServerOnly + [Item];
    end;
  AMax := Max(AMax, 0);
  Reserve := Min(Length(ServerOnly), AMax div 2);
  LocalTake := Min(Length(Locals), AMax - Reserve);
  ServerTake := Min(Length(ServerOnly), AMax - LocalTake);
  for Index := 0 to LocalTake - 1 do
    Result := Result + [Locals[Index]];
  for Index := 0 to ServerTake - 1 do
    Result := Result + [ServerOnly[Index]];
  Hidden := Length(Locals) + Length(ServerOnly) - LocalTake - ServerTake;
  // Über die gespeicherten hinaus gezählte Fehlschläge (je Datei höchstens 50).
  if ALocal.Known then
  begin
    Known := ALocal.Failed + ALocal.Errors;
    if Known > Length(ALocal.Failures) then
      Inc(Hidden, Known - Length(ALocal.Failures));
  end;
  if AUseServer and AServer.TestsKnown and (AServer.Failed > Length(AServer.Failures)) then
    Inc(Hidden, AServer.Failed - Length(AServer.Failures));
  AMore := Hidden;
end;

class function TAtlasWelcomeTestResults.RerunNames(const ALocal: TAtlasProjectTests; const AServer: TAtlasCiBuild;
  AUseServer: Boolean): TArray<string>;
var
  Name: string;
  Failure: TAtlasCiFailure;
  Seen: Boolean;
begin
  Result := nil;
  if ALocal.Known then
    Result := ALocal.FailedTests;
  if not (AUseServer and AServer.TestsKnown) then
    Exit;
  for Failure in AServer.Failures do
  begin
    if Failure.Test = '' then
      Continue;
    Seen := False;
    for Name in Result do
      if SameTest(Name, Failure.Test) then
        Seen := True;
    if not Seen then
      Result := Result + [Failure.Test];
  end;
end;

class function TAtlasWelcomeTestResults.Due(ALastAttemptUtc, ANowUtc: TDateTime; AIntervalMinutes: Integer): Boolean;
begin
  if ALastAttemptUtc <= 0 then
    Exit(True);
  // Uhr zurückgestellt: nicht bis dahin warten.
  if ALastAttemptUtc > ANowUtc + OneMinute then
    Exit(True);
  // Eine Sekunde Spielraum gegen Rundung der Gleitkommazeit.
  Result := (ANowUtc - ALastAttemptUtc) * MinsPerDay + 1 / 60 >= NormalizedInterval(AIntervalMinutes);
end;

class function TAtlasWelcomeTestResults.Recorded(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob;
  ASucceeded: Boolean; const ABuild: TAtlasCiBuild; AError: TAtlasCiFetchError; ANowUtc: TDateTime): TAtlasProjectCi;
begin
  if AOld.Matches(AJob) then
    Result := AOld
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
      Result.Error := TAtlasCiFetchError.Network;
  end;
end;

class function TAtlasWelcomeTestResults.TurnedRed(const AOld: TAtlasProjectCi; const AJob: TAtlasCiJob;
  const ANew: TAtlasCiBuild): Boolean;
begin
  Result := AOld.Matches(AJob) and AOld.HasBuild and (ANew.Number > 0) and
    (ANew.Number <> AOld.Build.Number) and (CiLevel(AOld.Build) <> TAtlasTestLevel.Failed) and
    (CiLevel(ANew) = TAtlasTestLevel.Failed);
end;

class function TAtlasWelcomeTestResults.CiFor(const ASummary: TAtlasProjectSummary;
  const AJob: TAtlasCiJob): TAtlasProjectCi;
begin
  if ASummary.Ci.Matches(AJob) then
    Result := ASummary.Ci
  else
    Result := TAtlasProjectCi.Empty;
end;

function NameOfPath(const APath: string): string;
var
  Index: Integer;
begin
  // Ohne ExtractFileName: Der Pfad hat immer „\“, auch wenn die Tests nicht unter Windows laufen.
  Result := APath;
  for Index := Length(Result) downto 1 do
    if CharInSet(Result[Index], ['\', '/']) then
    begin
      Result := Copy(Result, Index + 1, MaxInt);
      Break;
    end;
  for Index := Length(Result) downto 1 do
    if Result[Index] = '.' then
    begin
      Result := Copy(Result, 1, Index - 1);
      Break;
    end;
end;

class function TAtlasWelcomeTestResults.Row(const AProject: TAtlasTestProject; ACiEnabled: Boolean): TAtlasTestRow;
begin
  Result := Default(TAtlasTestRow);
  Result.Project := AProject.Project;
  Result.Local := AProject.Summary.Tests;
  Result.LocalLevel := LocalLevel(Result.Local);
  if Result.Local.Known then
    Result.TestProject := Result.Local.Project;
  Result.Name := NameOfPath(Result.TestProject);
  if Result.Name = '' then
    Result.Name := NameOfPath(AProject.Project);
  Result.Job := AProject.Job;
  Result.HasCi := ACiEnabled and AProject.Job.Configured;
  Result.Ci := TAtlasProjectCi.Empty;
  Result.CiLevel := TAtlasTestLevel.Unknown;
  if not Result.HasCi then
    Exit;
  Result.Ci := CiFor(AProject.Summary, AProject.Job);
  Result.CiQuerying := AProject.Querying;
  if Result.Ci.HasBuild then
  begin
    Result.CiLevel := CiLevel(Result.Ci.Build);
    Result.CiStale := Result.Ci.Error <> TAtlasCiFetchError.None;
  end;
  Result.Mismatch := Compare(Result.LocalLevel, Result.CiLevel);
end;

class function TAtlasWelcomeTestResults.View(const AProjects: TArray<TAtlasTestProject>; const ASelected: string;
  AMaxFailures: Integer; ACiEnabled: Boolean): TAtlasTestResultsView;
var
  Project: TAtlasTestProject;
  Item: TAtlasTestRow;
  Keys: TArray<string>;
  Key, Seen: string;
  Duplicate: Boolean;
  Index: Integer;
  Chosen: TAtlasTestRow;
  UseServer: Boolean;
begin
  Result := Default(TAtlasTestResultsView);
  Result.Rows := nil;
  Result.Failures := nil;
  Result.Rerun := nil;
  Result.Selected := -1;
  Keys := nil;
  for Project in AProjects do
  begin
    Item := Row(Project, ACiEnabled);
    if not Item.Local.Known and not Item.HasCi then
      Continue;
    // Eine Projektgruppe und ihr Testprojekt tragen denselben Lauf: nur einmal zeigen.
    Key := '';
    if Item.Local.Known and (Item.TestProject <> '') then
      Key := LowerCase(Item.TestProject)
    else
      Key := LowerCase(Item.Project);
    if Item.HasCi then
      Key := Key + '|' + Item.Job.Key;
    Duplicate := False;
    for Seen in Keys do
      if Seen = Key then
        Duplicate := True;
    if Duplicate then
      Continue;
    Keys := Keys + [Key];
    Result.Rows := Result.Rows + [Item];
  end;
  if Length(Result.Rows) = 0 then
    Exit;
  Result.Selected := 0;
  for Index := 0 to High(Result.Rows) do
    if (ASelected <> '') and SameText(Result.Rows[Index].Project, ASelected) then
    begin
      Result.Selected := Index;
      Break;
    end;
  Chosen := Result.Rows[Result.Selected];
  UseServer := Chosen.HasCi and Chosen.Ci.HasBuild;
  Result.Failures := MergeFailures(Chosen.Local, Chosen.Ci.Build, UseServer, NormalizedMaxFailures(AMaxFailures),
    Result.More);
  Result.Rerun := RerunNames(Chosen.Local, Chosen.Ci.Build, UseServer);
end;

class function TAtlasWelcomeTestResults.ProviderCaption(const AProvider: string): string;
begin
  if SameText(AProvider, 'jenkins') then
    Result := 'Jenkins'
  else if AProvider = '' then
    Result := ''
  else
    Result := UpperCase(Copy(AProvider, 1, 1)) + Copy(AProvider, 2, MaxInt);
end;

class function TAtlasWelcomeTestResults.NormalizedMaxFailures(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinMaxFailures, MaxMaxFailures);
end;

class function TAtlasWelcomeTestResults.NormalizedInterval(AValue: Integer): Integer;
begin
  Result := EnsureRange(AValue, MinIntervalMinutes, MaxIntervalMinutes);
end;

end.
