unit Atlas.Core.Welcome.Setup;

// Bereich „<Projekt> für Atlas einrichten“ der Willkommensseite (#759), ohne
// VCL und Open Tools API: Zustand der Karte, wann Karte und Knöpfe „Neu mit
// Atlas“ erscheinen, Laufzeit der Schritte und die Zeilen der Pfadprüfung.
//
// Ziel ist das aktive Projekt der IDE, ohne offenes Projekt das oberste der
// Liste „Projekte“ (das auch eine Projektgruppe sein kann). Die Karte
// erscheint, wenn welcomePage.projectSetup an ist und das Ziel nicht
// vollständig eingerichtet und nicht abgewählt ist (TAtlasProjectSetups.
// NeedsCard). Die Knöpfe „Neu mit Atlas“ brauchen welcomePage.newFromTemplate
// und ein offenes Projekt; sie stehen auch ohne Karte da (Titel dann „Neu mit
// Atlas“). welcomePage.projectSetup aus schaltet beides ab.
//
// Projektgruppe: Die Pfadprüfung läuft für jedes Projekt der Gruppe, die Funde
// stehen je Projekt in dessen Zusammenfassung. Combined fasst sie für die
// Karte zusammen (Zahlen summiert, Funde mit Projektname, Pfade relativ zum
// Ordner der Gruppe); erledigt ist der Schritt erst, wenn jedes Projekt
// geprüft ist und keins einen sicheren Fund hat.
// Unsichere Funde (Suchpfad mit unbekanntem Makro übersprungen) stehen mit
// den Makros in der Karte, zählen aber nicht als offener Schritt.

interface

uses
  System.SysUtils,
  Atlas.Core.Projects.Summary,
  Atlas.Core.Projects.Setup,
  Atlas.Core.Projects.PathCheck;

type
{$SCOPEDENUMS ON}
  /// <summary>Lauf eines Schritts in dieser Sitzung (Baseline, Pfadprüfung).</summary>
  TAtlasSetupRun = (Idle, Running, Done, Failed);
  TAtlasSetupFindingKind = (MissingUnit, UndefinedDefine, Hint);
{$SCOPEDENUMS OFF}

  /// <summary>Zeile unter „Suchpfade und Defines prüfen“.</summary>
  TAtlasSetupLine = record
    Kind: TAtlasSetupFindingKind;
    Name: string;
    /// <summary>Projekt bei einer Projektgruppe; '' sonst.</summary>
    Project: string;
    /// <summary>Kein sicherer Fund; Macros nennt die übersprungenen Makros („$(A), $(B)“).</summary>
    Uncertain: Boolean;
    Macros: string;
    /// <summary>Relativ zum Projektordner.</summary>
    FileName: string;
    /// <summary>Ab 1; 0 = ohne.</summary>
    Line: Integer;
    Count: Integer;
    /// <summary>Define: Vorschlag (Tippfehler?); Hinweis: Unit im Suchpfad, '' = Package ohne Quelle.</summary>
    Note: string;
  end;

  TAtlasSetupCard = record
    /// <summary>Projektdatei des Ziels; '' = kein Projekt.</summary>
    Project: string;
    /// <summary>Dateiname ohne Endung, für den Titel.</summary>
    ProjectName: string;
    /// <summary>Das Ziel ist in der IDE geöffnet (Baseline und Pfadprüfung brauchen das).</summary>
    ProjectOpen: Boolean;
    Facts: TAtlasSetupFacts;
    /// <summary>Projektgruppe: Zahl ihrer Projekte und davon geprüfte; 0 = keine Gruppe.</summary>
    GroupProjects: Integer;
    GroupChecked: Integer;
    /// <summary>Name der vorhandenen Konfiguration (atlas.json bzw. delphi-lsp.json); '' ohne.</summary>
    ConfigName: string;
    ShowCard: Boolean;
    ShowNew: Boolean;
    Baseline: TAtlasSetupRun;
    /// <summary>Start des laufenden Schritts (Millisekunden-Zähler der Quelle).</summary>
    BaselineStarted: UInt64;
    /// <summary>Nach einem erfolgreichen Lauf: Treffer und Dateien in der neuen Baseline.</summary>
    BaselineTotal: Integer;
    BaselineFiles: Integer;
    /// <summary>Neue Regeltreffer seit der Baseline aus der Projekt-Zusammenfassung (nach dem Erzeugen 0);
    /// -1 = unbekannt.</summary>
    BaselineNewHits: Integer;
    /// <summary>Grund bei Failed (Sprache der Oberfläche).</summary>
    BaselineError: string;
    Paths: TAtlasSetupRun;
    PathsStarted: UInt64;
    PathsError: string;
    class function Empty: TAtlasSetupCard; static;
    function StepDone(AStep: TAtlasSetupStep): Boolean;
    /// <summary>Bereich zeigen (Karte oder Knöpfe).</summary>
    function Visible: Boolean;
  end;

  /// <summary>Projekt einer Gruppe mit seinem Abschnitt "setup".</summary>
  TAtlasSetupMember = record
    Project: string;
    Setup: TAtlasProjectSetup;
  end;

  TAtlasWelcomeSetup = class
  public const
    /// <summary>Höchstens so viele Makros nennt MacroList, dann „…“.</summary>
    MaxMacros = 3;
    /// <summary>Höchstens so viele Funde stehen in der Karte; der Rest als „… und n weitere“.</summary>
    MaxLines = 6;
  public
    /// <summary>Karte zeigen? ASetupOn = welcomePage.projectSetup.</summary>
    class function ShowCard(ASetupOn: Boolean; const AFacts: TAtlasSetupFacts): Boolean; static;
    /// <summary>Knöpfe „Neu mit Atlas“ zeigen? Brauchen ein offenes Projekt.</summary>
    class function ShowNew(ASetupOn, ANewOn, AProjectOpen: Boolean): Boolean; static;
    /// <summary>Ganze Sekunden seit AStarted (Millisekunden-Zähler); 0 bei Zählerüberlauf.</summary>
    class function Elapsed(AStarted, ANow: UInt64): Integer; static;
    /// <summary>Funde der letzten Prüfung: fehlende Units, dann Defines ohne Quelle, höchstens AMax; AMore =
    /// übrige Funde (auch über die gespeicherten hinaus). Unsichere Funde mit den übersprungenen Makros.
    /// </summary>
    class function Lines(const ASetup: TAtlasProjectSetup; AMax: Integer; out AMore: Integer):
      TArray<TAtlasSetupLine>; static;
    /// <summary>AFileName relativ zum Ordner von AProject, wenn er darin liegt; sonst unverändert.</summary>
    class function Relative(const AProject, AFileName: string): string; static;
    /// <summary>Dateiname ohne Ordner und Endung.</summary>
    class function NameOf(const AProject: string): string; static;
    /// <summary>Abschnitt "setup" nach einer Prüfung: „nicht mehr fragen“ aus APrevious bleibt, Funde mit Pfaden
    /// relativ zu AProject, je Liste höchstens TAtlasProjectSetup.MaxFindings.</summary>
    class function Checked(const APrevious: TAtlasProjectSetup; const AProject: string;
      const AResult: TAtlasPathCheckResult; AAtUtc: TDateTime): TAtlasProjectSetup; static;
    /// <summary>Abschnitt "rules" nach dem Erzeugen der Baseline: Alle Treffer stehen darin, neue gibt es keine.
    /// </summary>
    class procedure BaselineWritten(var ARules: TAtlasProjectRules; AAtUtc: TDateTime); static;
    /// <summary>.groupproj?</summary>
    class function IsGroup(const AProject: string): Boolean; static;
    /// <summary>Abschnitt "setup" einer Gruppe für die Karte: „nicht mehr fragen“ aus AGroup, Prüfung aus
    /// AMembers zusammengefasst (Pfade relativ zum Ordner von AGroupProject, Projektname je Fund). Geprüft
    /// nur, wenn alle Projekte geprüft sind; AChecked = Zahl der geprüften.</summary>
    class function Combined(const AGroupProject: string; const AGroup: TAtlasProjectSetup;
      const AMembers: TArray<TAtlasSetupMember>; out AChecked: Integer): TAtlasProjectSetup; static;
    /// <summary>„$(A), $(B), $(C), …“ für die Karte.</summary>
    class function MacroList(const AMacros: TArray<string>): string; static;
  end;

implementation

{ TAtlasSetupCard }

class function TAtlasSetupCard.Empty: TAtlasSetupCard;
begin
  Result := Default(TAtlasSetupCard);
  Result.Facts := Default(TAtlasSetupFacts);
  Result.Facts.Setup := TAtlasProjectSetup.Empty;
  Result.BaselineNewHits := -1;
end;

function TAtlasSetupCard.StepDone(AStep: TAtlasSetupStep): Boolean;
begin
  Result := TAtlasProjectSetups.StepDone(AStep, Facts);
end;

function TAtlasSetupCard.Visible: Boolean;
begin
  Result := ShowCard or ShowNew;
end;

{ TAtlasWelcomeSetup }

class function TAtlasWelcomeSetup.ShowCard(ASetupOn: Boolean; const AFacts: TAtlasSetupFacts): Boolean;
begin
  Result := ASetupOn and TAtlasProjectSetups.NeedsCard(AFacts);
end;

class function TAtlasWelcomeSetup.ShowNew(ASetupOn, ANewOn, AProjectOpen: Boolean): Boolean;
begin
  Result := ASetupOn and ANewOn and AProjectOpen;
end;

class function TAtlasWelcomeSetup.Elapsed(AStarted, ANow: UInt64): Integer;
begin
  Result := 0;
  if (AStarted = 0) or (ANow < AStarted) then
    Exit;
  Result := Integer((ANow - AStarted) div 1000);
end;

class function TAtlasWelcomeSetup.Lines(const ASetup: TAtlasProjectSetup; AMax: Integer;
  out AMore: Integer): TArray<TAtlasSetupLine>;

  procedure Add(AKind: TAtlasSetupFindingKind; const AFinding: TAtlasSetupFinding; var AList: TArray<TAtlasSetupLine>);
  var
    Line: TAtlasSetupLine;
  begin
    Line.Kind := AKind;
    Line.Name := AFinding.Name;
    Line.Project := AFinding.Project;
    Line.Uncertain := AFinding.Uncertain;
    Line.Macros := '';
    if Line.Uncertain then
      Line.Macros := TAtlasWelcomeSetup.MacroList(ASetup.SkippedMacros);
    Line.FileName := AFinding.FileName;
    Line.Line := AFinding.Line;
    Line.Count := AFinding.Count;
    Line.Note := AFinding.Note;
    AList := AList + [Line];
  end;

var
  Finding: TAtlasSetupFinding;
  List: TArray<TAtlasSetupLine>;
begin
  List := nil;
  AMore := 0;
  // Bei einer Gruppe stehen Funde schon da, bevor alle Projekte geprüft sind.
  if not ASetup.Checked and (Length(ASetup.MissingUnits) + Length(ASetup.UndefinedDefines) = 0) then
    Exit(nil);
  for Finding in ASetup.MissingUnits do
    if Length(List) < AMax then
      Add(TAtlasSetupFindingKind.MissingUnit, Finding, List);
  for Finding in ASetup.UndefinedDefines do
    if Length(List) < AMax then
      Add(TAtlasSetupFindingKind.UndefinedDefine, Finding, List);
  // Hinweise zu requires-Packages (#759) zuletzt; sie sind keine Fehler.
  for Finding in ASetup.Hints do
    if Length(List) < AMax then
      Add(TAtlasSetupFindingKind.Hint, Finding, List);
  AMore := ASetup.MissingUnitCount + ASetup.UndefinedDefineCount + Length(ASetup.Hints) - Length(List);
  if AMore < 0 then
    AMore := 0;
  Result := List;
end;

class function TAtlasWelcomeSetup.Relative(const AProject, AFileName: string): string;
var
  Folder: string;
  Index: Integer;
begin
  Result := AFileName;
  Folder := '';
  for Index := Length(AProject) downto 1 do
    if CharInSet(AProject[Index], ['\', '/']) then
    begin
      Folder := Copy(AProject, 1, Index);
      Break;
    end;
  if (Folder <> '') and SameText(Copy(AFileName, 1, Length(Folder)), Folder) then
    Result := Copy(AFileName, Length(Folder) + 1, MaxInt);
end;

class function TAtlasWelcomeSetup.NameOf(const AProject: string): string;
var
  Summary: TAtlasProjectSummary;
begin
  Summary := TAtlasProjectSummary.Create(AProject);
  Result := Summary.Name;
end;

class function TAtlasWelcomeSetup.Checked(const APrevious: TAtlasProjectSetup; const AProject: string;
  const AResult: TAtlasPathCheckResult; AAtUtc: TDateTime): TAtlasProjectSetup;

  function Findings(const AList: TArray<TAtlasPathFinding>): TArray<TAtlasSetupFinding>;
  var
    Item: TAtlasPathFinding;
    Finding: TAtlasSetupFinding;
  begin
    Result := nil;
    for Item in AList do
    begin
      if Length(Result) >= TAtlasProjectSetup.MaxFindings then
        Break;
      Finding := Default(TAtlasSetupFinding);
      Finding.Name := Item.Name;
      Finding.FileName := Relative(AProject, Item.FileName);
      Finding.Line := Item.Line;
      Finding.Count := Item.Count;
      Finding.Uncertain := Item.Uncertain;
      Finding.Note := Item.Note;
      Result := Result + [Finding];
    end;
  end;

begin
  Result := APrevious;
  Result.Known := True;
  Result.Checked := True;
  Result.CheckedAt := AAtUtc;
  Result.Files := AResult.Files;
  Result.Unreadable := AResult.Unreadable;
  Result.MissingUnitCount := Length(AResult.MissingUnits);
  Result.UndefinedDefineCount := Length(AResult.UndefinedDefines);
  Result.MissingUnits := Findings(AResult.MissingUnits);
  Result.UndefinedDefines := Findings(AResult.UndefinedDefines);
  Result.Hints := Findings(AResult.Hints);
  Result.UncertainUnitCount := TAtlasPathCheckResult.UncertainIn(AResult.MissingUnits);
  Result.UncertainDefineCount := TAtlasPathCheckResult.UncertainIn(AResult.UndefinedDefines);
  Result.SkippedMacros := AResult.SkippedMacros;
end;

class procedure TAtlasWelcomeSetup.BaselineWritten(var ARules: TAtlasProjectRules; AAtUtc: TDateTime);
begin
  ARules.Known := True;
  ARules.At := AAtUtc;
  ARules.NewHits := 0;
end;

class function TAtlasWelcomeSetup.IsGroup(const AProject: string): Boolean;
begin
  Result := SameText(Copy(AProject, Length(AProject) - 9, 10), '.groupproj');
end;

/// <summary>Ordner von AFileName mit abschließendem Trenner; '' ohne.</summary>
function FolderWithSlash(const AFileName: string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := Length(AFileName) downto 1 do
    if CharInSet(AFileName[Index], ['\', '/']) then
      Exit(Copy(AFileName, 1, Index));
end;

function IsAbsolutePath(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or APath.StartsWith('\\') or APath.StartsWith('/');
end;

class function TAtlasWelcomeSetup.Combined(const AGroupProject: string; const AGroup: TAtlasProjectSetup;
  const AMembers: TArray<TAtlasSetupMember>; out AChecked: Integer): TAtlasProjectSetup;

  procedure AddAll(const AMember: TAtlasSetupMember; const AFrom: TArray<TAtlasSetupFinding>;
    var AList: TArray<TAtlasSetupFinding>);
  var
    Finding: TAtlasSetupFinding;
  begin
    for Finding in AFrom do
    begin
      if Length(AList) >= TAtlasProjectSetup.MaxFindings then
        Exit;
      AList := AList + [Finding];
      AList[High(AList)].Project := TAtlasWelcomeSetup.NameOf(AMember.Project);
      // Relativ zum Projekt gespeichert, für die Karte relativ zur Gruppe.
      if (Finding.FileName <> '') and not IsAbsolutePath(Finding.FileName) then
        AList[High(AList)].FileName := TAtlasWelcomeSetup.Relative(AGroupProject,
          FolderWithSlash(AMember.Project) + Finding.FileName);
    end;
  end;

var
  Member: TAtlasSetupMember;
  Macro, Known: string;
  Seen: Boolean;
begin
  Result := TAtlasProjectSetup.Empty;
  Result.Known := AGroup.Known;
  Result.Dismissed := AGroup.Dismissed;
  Result.DismissedAt := AGroup.DismissedAt;
  AChecked := 0;
  for Member in AMembers do
  begin
    if not Member.Setup.Checked then
      Continue;
    Inc(AChecked);
    if Member.Setup.CheckedAt > Result.CheckedAt then
      Result.CheckedAt := Member.Setup.CheckedAt;
    Inc(Result.Files, Member.Setup.Files);
    Inc(Result.Unreadable, Member.Setup.Unreadable);
    Inc(Result.MissingUnitCount, Member.Setup.MissingUnitCount);
    Inc(Result.UndefinedDefineCount, Member.Setup.UndefinedDefineCount);
    Inc(Result.UncertainUnitCount, Member.Setup.UncertainUnitCount);
    Inc(Result.UncertainDefineCount, Member.Setup.UncertainDefineCount);
    AddAll(Member, Member.Setup.MissingUnits, Result.MissingUnits);
    AddAll(Member, Member.Setup.UndefinedDefines, Result.UndefinedDefines);
    AddAll(Member, Member.Setup.Hints, Result.Hints);
    for Macro in Member.Setup.SkippedMacros do
    begin
      Seen := False;
      for Known in Result.SkippedMacros do
        if SameText(Known, Macro) then
          Seen := True;
      if not Seen then
        Result.SkippedMacros := Result.SkippedMacros + [Macro];
    end;
  end;
  // Erledigt erst, wenn jedes Projekt geprüft ist.
  Result.Checked := (Length(AMembers) > 0) and (AChecked = Length(AMembers));
  if Result.Checked or (AChecked > 0) then
    Result.Known := True;
end;

class function TAtlasWelcomeSetup.MacroList(const AMacros: TArray<string>): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(AMacros) do
  begin
    if Index >= MaxMacros then
    begin
      Result := Result + ', …';
      Break;
    end;
    if Result <> '' then
      Result := Result + ', ';
    Result := Result + '$(' + AMacros[Index] + ')';
  end;
end;

end.
