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
    cMaxMacros = 3;
    /// <summary>Höchstens so viele Funde stehen in der Karte; der Rest als „… und n weitere“.</summary>
    cMaxLines = 6;
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
    /// relativ zu AProject, je Liste höchstens TAtlasProjectSetup.cMaxFindings.</summary>
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
  begin
    Exit;
  end;
  Result := Integer((ANow - AStarted) div 1000);
end;

class function TAtlasWelcomeSetup.Lines(const ASetup: TAtlasProjectSetup; AMax: Integer;
  out AMore: Integer): TArray<TAtlasSetupLine>;

  procedure Add(AKind: TAtlasSetupFindingKind; const AFinding: TAtlasSetupFinding; var AList: TArray<TAtlasSetupLine>);
  var
    mLine: TAtlasSetupLine;
  begin
    mLine.Kind := AKind;
    mLine.Name := AFinding.Name;
    mLine.Project := AFinding.Project;
    mLine.Uncertain := AFinding.Uncertain;
    mLine.Macros := '';
    if mLine.Uncertain then
    begin
      mLine.Macros := TAtlasWelcomeSetup.MacroList(ASetup.SkippedMacros);
    end;
    mLine.FileName := AFinding.FileName;
    mLine.Line := AFinding.Line;
    mLine.Count := AFinding.Count;
    mLine.Note := AFinding.Note;
    AList := AList + [mLine];
  end;

var
  mFinding: TAtlasSetupFinding;
  mList: TArray<TAtlasSetupLine>;
begin
  mList := nil;
  AMore := 0;
  // Bei einer Gruppe stehen Funde schon da, bevor alle Projekte geprüft sind.
  if not ASetup.Checked and (Length(ASetup.MissingUnits) + Length(ASetup.UndefinedDefines) = 0) then
  begin
    Exit(nil);
  end;
  for mFinding in ASetup.MissingUnits do
  begin
    if Length(mList) < AMax then
    begin
      Add(TAtlasSetupFindingKind.MissingUnit, mFinding, mList);
    end;
  end;
  for mFinding in ASetup.UndefinedDefines do
  begin
    if Length(mList) < AMax then
    begin
      Add(TAtlasSetupFindingKind.UndefinedDefine, mFinding, mList);
    end;
  end;
  // Hinweise zu requires-Packages (#759) zuletzt; sie sind keine Fehler.
  for mFinding in ASetup.Hints do
  begin
    if Length(mList) < AMax then
    begin
      Add(TAtlasSetupFindingKind.Hint, mFinding, mList);
    end;
  end;
  AMore := ASetup.MissingUnitCount + ASetup.UndefinedDefineCount + Length(ASetup.Hints) - Length(mList);
  if AMore < 0 then
  begin
    AMore := 0;
  end;
  Result := mList;
end;

class function TAtlasWelcomeSetup.Relative(const AProject, AFileName: string): string;
var
  mFolder: string;
  mIndex: Integer;
begin
  Result := AFileName;
  mFolder := '';
  for mIndex := Length(AProject) downto 1 do
  begin
    if CharInSet(AProject[mIndex], ['\', '/']) then
    begin
      mFolder := Copy(AProject, 1, mIndex);
      Break;
    end;
  end;
  if (mFolder <> '') and SameText(Copy(AFileName, 1, Length(mFolder)), mFolder) then
  begin
    Result := Copy(AFileName, Length(mFolder) + 1, MaxInt);
  end;
end;

class function TAtlasWelcomeSetup.NameOf(const AProject: string): string;
var
  mSummary: TAtlasProjectSummary;
begin
  mSummary := TAtlasProjectSummary.Create(AProject);
  Result := mSummary.Name;
end;

class function TAtlasWelcomeSetup.Checked(const APrevious: TAtlasProjectSetup; const AProject: string;
  const AResult: TAtlasPathCheckResult; AAtUtc: TDateTime): TAtlasProjectSetup;

  function Findings(const AList: TArray<TAtlasPathFinding>): TArray<TAtlasSetupFinding>;
  var
    mItem: TAtlasPathFinding;
    mFinding: TAtlasSetupFinding;
  begin
    Result := nil;
    for mItem in AList do
    begin
      if Length(Result) >= TAtlasProjectSetup.cMaxFindings then
      begin
        Break;
      end;
      mFinding := Default(TAtlasSetupFinding);
      mFinding.Name := mItem.Name;
      mFinding.FileName := Relative(AProject, mItem.FileName);
      mFinding.Line := mItem.Line;
      mFinding.Count := mItem.Count;
      mFinding.Uncertain := mItem.Uncertain;
      mFinding.Note := mItem.Note;
      Result := Result + [mFinding];
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
  mIndex: Integer;
begin
  Result := '';
  for mIndex := Length(AFileName) downto 1 do
  begin
    if CharInSet(AFileName[mIndex], ['\', '/']) then
    begin
      Exit(Copy(AFileName, 1, mIndex));
    end;
  end;
end;

function IsAbsolutePath(const APath: string): Boolean;
begin
  Result := ((Length(APath) >= 2) and (APath[2] = ':')) or APath.StartsWith('\\') or APath.StartsWith('/');
end;

/// <summary>Zähler von APart zu ATotal.</summary>
procedure AddCounts(var ATotal: TAtlasProjectSetup; const APart: TAtlasProjectSetup);
begin
  Inc(ATotal.Files, APart.Files);
  Inc(ATotal.Unreadable, APart.Unreadable);
  Inc(ATotal.MissingUnitCount, APart.MissingUnitCount);
  Inc(ATotal.UndefinedDefineCount, APart.UndefinedDefineCount);
  Inc(ATotal.UncertainUnitCount, APart.UncertainUnitCount);
  Inc(ATotal.UncertainDefineCount, APart.UncertainDefineCount);
end;

/// <summary>Makros aus AFrom an AList, die dort noch nicht stehen (ohne Groß-/Kleinschreibung).</summary>
procedure AddMacros(var AList: TArray<string>; const AFrom: TArray<string>);
var
  mMacro, mKnown: string;
  mSeen: Boolean;
begin
  for mMacro in AFrom do
  begin
    mSeen := False;
    for mKnown in AList do
    begin
      mSeen := mSeen or SameText(mKnown, mMacro);
    end;
    if not mSeen then
    begin
      AList := AList + [mMacro];
    end;
  end;
end;

class function TAtlasWelcomeSetup.Combined(const AGroupProject: string; const AGroup: TAtlasProjectSetup;
  const AMembers: TArray<TAtlasSetupMember>; out AChecked: Integer): TAtlasProjectSetup;

  procedure AddAll(const AMember: TAtlasSetupMember; const AFrom: TArray<TAtlasSetupFinding>;
    var AList: TArray<TAtlasSetupFinding>);
  var
    mFinding: TAtlasSetupFinding;
  begin
    for mFinding in AFrom do
    begin
      if Length(AList) >= TAtlasProjectSetup.cMaxFindings then
      begin
        Exit;
      end;
      AList := AList + [mFinding];
      AList[High(AList)].Project := TAtlasWelcomeSetup.NameOf(AMember.Project);
      // Relativ zum Projekt gespeichert, für die Karte relativ zur Gruppe.
      if (mFinding.FileName <> '') and not IsAbsolutePath(mFinding.FileName) then
      begin
        AList[High(AList)].FileName := TAtlasWelcomeSetup.Relative(AGroupProject,
          FolderWithSlash(AMember.Project) + mFinding.FileName);
      end;
    end;
  end;

var
  mMember: TAtlasSetupMember;
begin
  Result := TAtlasProjectSetup.Empty;
  Result.Known := AGroup.Known;
  Result.Dismissed := AGroup.Dismissed;
  Result.DismissedAt := AGroup.DismissedAt;
  AChecked := 0;
  for mMember in AMembers do
  begin
    if not mMember.Setup.Checked then
    begin
      Continue;
    end;
    Inc(AChecked);
    if mMember.Setup.CheckedAt > Result.CheckedAt then
    begin
      Result.CheckedAt := mMember.Setup.CheckedAt;
    end;
    AddCounts(Result, mMember.Setup);
    AddAll(mMember, mMember.Setup.MissingUnits, Result.MissingUnits);
    AddAll(mMember, mMember.Setup.UndefinedDefines, Result.UndefinedDefines);
    AddAll(mMember, mMember.Setup.Hints, Result.Hints);
    AddMacros(Result.SkippedMacros, mMember.Setup.SkippedMacros);
  end;
  // Erledigt erst, wenn jedes Projekt geprüft ist.
  Result.Checked := (Length(AMembers) > 0) and (AChecked = Length(AMembers));
  if Result.Checked or (AChecked > 0) then
  begin
    Result.Known := True;
  end;
end;

class function TAtlasWelcomeSetup.MacroList(const AMacros: TArray<string>): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(AMacros) do
  begin
    if mIndex >= cMaxMacros then
    begin
      Result := Result + ', …';
      Break;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + '$(' + AMacros[mIndex] + ')';
  end;
end;

end.
