unit Atlas.Core.UnitSearch.Model;

// Fenster „Units suchen“ (#777), Teil ohne VCL und Open Tools API:
//   - Einträge aus atlas.server.units lesen; Herkunft „Aktives Projekt“ oder
//     „Projektgruppe“ entscheidet das aktive Projekt der IDE.
//   - Tippsyntax p:<Projekt>, t:form|frame|dm|unit|test|inc, mit Minus
//     ausschließend (-t:test); der Rest ist der Suchtext.
//   - Rangfolge wie die Befehlspalette (#502, #229): unscharf, CamelCase,
//     zuletzt Teilfolge; bei Gleichstand offene Units, dann Units des aktiven
//     Projekts, dann der Name. Ein Suchwort passt auch als Teiltext der
//     Caption eines Formulars (#1310), gewertet zwischen Teiltext und
//     Teilfolge im Namen.
//   - Gruppen nach Projekt oder Ordner mit Trefferzahl, einklappbar; bei
//     aktiver Suche nur Gruppen mit Treffern, die beste oben.
//   - Pfadanzeige relativ zur Projektgruppe, in der Mitte gekürzt oder absolut.
//   - Vorschau aus atlas.server.unitPreview.

interface

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections;

type
{$SCOPEDENUMS ON}
  TAtlasUnitKind = (Unit_, Form, Frame, DataModule, Test, Include);
  TAtlasUnitOrigin = (Active, Group, SearchPath, Library_);
  TAtlasUnitGrouping = (None, Project, Folder);
  TAtlasUnitPathStyle = (Relative, Compact, Absolute);
{$SCOPEDENUMS OFF}
  TAtlasUnitKinds = set of TAtlasUnitKind;
  TAtlasUnitOrigins = set of TAtlasUnitOrigin;

  TAtlasUnitEntry = record
    Name: string;
    FileName: string;
    /// <summary>Projekt für Gruppe und Kennzeichen: das aktive, wenn die Unit dazugehört, sonst das erste.</summary>
    Project: string;
    Projects: TArray<string>;
    Origin: TAtlasUnitOrigin;
    Kind: TAtlasUnitKind;
    /// <summary>Im Editor geöffnet (setzt die IDE-Schicht).</summary>
    IsOpen: Boolean;
    /// <summary>Name in Großschrift für die Suche (setzt SortByName; sonst bestimmt Order ihn je Aufruf).</summary>
    UpperName: string;
    /// <summary>Caption des Formulars (#1310); '' ohne oder wenn die Suche sie nicht abfragt.</summary>
    Caption: string;
    /// <summary>Caption in Großschrift (setzt SortByName wie UpperName).</summary>
    UpperCaption: string;
  end;
  TAtlasUnitEntries = TArray<TAtlasUnitEntry>;

  TAtlasUnitQuery = record
    /// <summary>Suchwörter ohne Filter; jedes muss passen.</summary>
    Words: TArray<string>;
    Projects: TArray<string>;
    NotProjects: TArray<string>;
    Kinds: TAtlasUnitKinds;
    NotKinds: TAtlasUnitKinds;
    /// <summary>Zerlegt AInput; ohne ASyntax ist alles Suchtext.</summary>
    class function Parse(const AInput: string; ASyntax: Boolean): TAtlasUnitQuery; static;
    /// <summary>Ist AToken ein vollständiger Filter (p:x, -t:test …)?</summary>
    class function IsFilter(const AToken: string): Boolean; static;
    /// <summary>Filter von Projekt und Art (ohne Suchwörter).</summary>
    function Accepts(const AEntry: TAtlasUnitEntry): Boolean;
    function HasWords: Boolean;
    /// <summary>Engt die Anfrage APrevious nur ein (gleiche Filter, Wörter verlängert oder hinzugekommen)?
    /// Dann sind ihre Treffer eine Teilmenge der vorigen, und Order braucht nur diese zu prüfen.</summary>
    function Narrows(const APrevious: TAtlasUnitQuery): Boolean;
  end;

  /// <summary>Zeile der Liste: Gruppenkopf oder Eintrag.</summary>
  TAtlasUnitRow = record
    IsGroup: Boolean;
    /// <summary>Schlüssel der Gruppe (Projektname bzw. relativer Ordner; '' = ohne).</summary>
    Group: string;
    /// <summary>Treffer der Gruppe (nur beim Kopf).</summary>
    Count: Integer;
    Collapsed: Boolean;
    /// <summary>Index in die Einträge; -1 beim Kopf.</summary>
    Entry: Integer;
  end;
  TAtlasUnitRows = TArray<TAtlasUnitRow>;

  /// <summary>Gruppierung der Zeilen für TAtlasUnitSearch.Rows.</summary>
  TAtlasUnitLayout = record
    Grouping: TAtlasUnitGrouping;
    /// <summary>Wurzel für Ordnergruppen (Projektgruppe).</summary>
    Root: string;
    ActiveProject: string;
    /// <summary>Eingeklappte Gruppen (Schlüssel in Kleinschrift).</summary>
    Collapsed: TArray<string>;
    /// <summary>Gruppen nach dem besten Treffer statt alphabetisch (aktives Projekt zuerst).</summary>
    Searching: Boolean;
    class function Create(AGrouping: TAtlasUnitGrouping; const ARoot, AActiveProject: string;
      const ACollapsed: TArray<string>; ASearching: Boolean): TAtlasUnitLayout; static;
  end;

  TAtlasUnitSketchItem = record
    Name: string;
    TypeName: string;
    Caption: string;
    Left, Top, Width, Height, Depth: Integer;
  end;

  TAtlasUnitType = record
    Name: string;
    /// <summary>class, record, interface, enum, helper, object, type.</summary>
    Kind: string;
  end;

  TAtlasUnitPreview = record
    FileName: string;
    Header: string;
    Lines: Integer;
    /// <summary>0 wenn unbekannt.</summary>
    Modified: TDateTime;
    /// <summary>clean, modified, added, deleted, renamed, untracked, conflict; '' ohne Git.</summary>
    Git: string;
    Types: TArray<TAtlasUnitType>;
    /// <summary>Alle Typen im interface; Types kann gekürzt sein (#876).</summary>
    TypeCount: Integer;
    /// <summary>uses beider Abschnitte (#876).</summary>
    Uses_: TArray<string>;
    /// <summary>-1 wenn nicht abgefragt.</summary>
    UsedBy: Integer;
    UsedByUnits: TArray<string>;
    HasForm: Boolean;
    FormClass: string;
    FormCaption: string;
    FormWidth, FormHeight: Integer;
    FormItems: TArray<TAtlasUnitSketchItem>;
    class function FromJson(const AValue: TJSONValue;
      const AUriToPath: TFunc<string, string>): TAtlasUnitPreview; static;
  end;

  TAtlasUnitSearch = class
  public const
    cScoreSubsequence = 100;
    /// <summary>Suchwort als Teiltext der Caption (#1310): unter Teiltext im Namen, über jeder Teilfolge.</summary>
    cScoreCaption = 300;
  public
    /// <summary>Einträge aus der Antwort von atlas.server.units; AActiveProject ist der Name des aktiven
    /// Projekts ('' = keins).</summary>
    class function FromJson(const AValue: TJSONValue; const AActiveProject: string;
      const AUriToPath: TFunc<string, string>): TAtlasUnitEntries; static;
    /// <summary>Argumente für atlas.server.units: mit ACaptions die Captions der Formulare (#1310).</summary>
    class function UnitsArguments(ACaptions: Boolean): string; static;
    /// <summary>Namen der Projekte aus der Antwort.</summary>
    class function ProjectsFromJson(const AValue: TJSONValue): TArray<string>; static;
    class function KindFromText(const AText: string; out AKind: TAtlasUnitKind): Boolean; static;
    class function KindText(AKind: TAtlasUnitKind): string; static;
    class function GroupingFromText(const AText: string): TAtlasUnitGrouping; static;
    class function GroupingText(AGrouping: TAtlasUnitGrouping): string; static;
    class function PathStyleFromText(const AText: string): TAtlasUnitPathStyle; static;
    /// <summary>Herkünfte zur Einstellung unitSearch.defaultScope: project = nur das aktive Projekt,
    /// group = alle Projekte, searchPath = dazu die Suchpfade, library = alles.</summary>
    class function OriginsForScope(const AScope: string): TAtlasUnitOrigins; static;
    /// <summary>Punkte von AName für ein Suchwort; -1 wenn es nicht passt.</summary>
    class function Score(const AWord, AName: string): Integer; static;
    /// <summary>Einträge nach Name und Datei ordnen; einmal nach dem Laden, damit Order Gleichstände ohne
    /// Namensvergleich je Tastendruck auflöst.</summary>
    class procedure SortByName(var AEntries: TAtlasUnitEntries); static;
    /// <summary>Passende Einträge, beste zuerst; bei Gleichstand offene, aktives Projekt, dann die Reihenfolge
    /// von AEntries (nach SortByName also der Name).</summary>
    class function Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
      AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds): TArray<Integer>; overload; static;
    /// <summary>Wie oben, prüft aber nur ACandidates (Indizes in AEntries), etwa die Treffer der vorigen
    /// Anfrage, wenn die neue sie nur einengt (TAtlasUnitQuery.Narrows).</summary>
    class function Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
      AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds; const ACandidates: TArray<Integer>): TArray<Integer>;
      overload; static;
    /// <summary>Gruppe eines Eintrags.</summary>
    class function GroupOf(const AEntry: TAtlasUnitEntry; AGrouping: TAtlasUnitGrouping;
      const ARoot: string): string; static;
    /// <summary>Zeilen aus der Reihenfolge, gruppiert nach ALayout.</summary>
    class function Rows(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>;
      const ALayout: TAtlasUnitLayout): TAtlasUnitRows; static;
    /// <summary>Text mit höchstens AMax Zeichen; zu lang wird er in der Mitte durch „…“ ersetzt.</summary>
    class function MiddleEllipsis(const AText: string; AMax: Integer): string; static;
    /// <summary>Pfad für die zweite Zeile: relativ zu ARoot (außerhalb absolut), gekürzt oder absolut.</summary>
    class function DisplayPath(const AFileName, ARoot: string; AStyle: TAtlasUnitPathStyle;
      AMax: Integer): string; static;
    /// <summary>Gemeinsamer Ordner aller Dateien ('' ohne); Ersatz, wenn die IDE keine Projektgruppe kennt.</summary>
    class function CommonRoot(const AFiles: TArray<string>): string; static;
  end;

implementation

uses
  System.Math,
  System.StrUtils,
  System.DateUtils,
  System.Generics.Defaults,
  Atlas.Core.Completion.Matching;

const
  cKindTexts: array[TAtlasUnitKind] of string = ('unit', 'form', 'frame', 'dm', 'test', 'inc');

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  mItem: string;
begin
  for mItem in AList do
  begin
    if SameText(mItem, AValue) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function ProjectMatches(const AEntry: TAtlasUnitEntry; const AFilter: string): Boolean;
var
  mItem: string;
begin
  // Teilstring ohne Groß-/Kleinschreibung: p:ide trifft Atlas.IDE.Expert.
  for mItem in AEntry.Projects do
  begin
    if ContainsText(mItem, AFilter) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

{ TAtlasUnitQuery }

class function TAtlasUnitQuery.IsFilter(const AToken: string): Boolean;
var
  mToken, mValue: string;
  mPart: string;
  mKind: TAtlasUnitKind;
begin
  mToken := AToken;
  if mToken.StartsWith('-') then
  begin
    mToken := Copy(mToken, 2, MaxInt);
  end;
  if (Length(mToken) < 3) or (mToken[2] <> ':') then
  begin
    Exit(False);
  end;
  mValue := Copy(mToken, 3, MaxInt);
  case UpCase(mToken[1]) of
    'P':
      Result := mValue <> '';
    'T':
      begin
        Result := mValue <> '';
        for mPart in mValue.Split(['|']) do
        begin
          if not TAtlasUnitSearch.KindFromText(mPart, mKind) then
          begin
            Exit(False);
          end;
        end;
      end;
  else
    Result := False;
  end;
end;

/// <summary>Arten aus „form|frame“ in AKinds aufnehmen; unbekannte zählen nicht.</summary>
procedure AddKinds(var AKinds: TAtlasUnitKinds; const AValue: string);
var
  mPart: string;
  mKind: TAtlasUnitKind;
begin
  for mPart in AValue.Split(['|']) do
  begin
    if TAtlasUnitSearch.KindFromText(mPart, mKind) then
    begin
      Include(AKinds, mKind);
    end;
  end;
end;

/// <summary>Vollständigen Filter (p:x, -t:test …) in die Anfrage aufnehmen.</summary>
procedure AddFilter(var AQuery: TAtlasUnitQuery; const AToken: string);
var
  mNegative: Boolean;
  mValue: string;
begin
  mNegative := AToken.StartsWith('-');
  mValue := Copy(AToken, 3 + Ord(mNegative), MaxInt);
  if UpCase(AToken[1 + Ord(mNegative)]) <> 'P' then
  begin
    if mNegative then
    begin
      AddKinds(AQuery.NotKinds, mValue);
    end
    else
    begin
      AddKinds(AQuery.Kinds, mValue);
    end;
  end
  else if mNegative then
  begin
    AQuery.NotProjects := AQuery.NotProjects + [mValue];
  end
  else
  begin
    AQuery.Projects := AQuery.Projects + [mValue];
  end;
end;

class function TAtlasUnitQuery.Parse(const AInput: string; ASyntax: Boolean): TAtlasUnitQuery;
var
  mToken: string;
begin
  Result := Default(TAtlasUnitQuery);
  for mToken in AInput.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    if ASyntax and IsFilter(mToken) then
    begin
      AddFilter(Result, mToken);
    end
    else
    begin
      Result.Words := Result.Words + [mToken];
    end;
  end;
end;

function TAtlasUnitQuery.Accepts(const AEntry: TAtlasUnitEntry): Boolean;
var
  mFilter: string;
  mAny: Boolean;
begin
  if (Kinds <> []) and not (AEntry.Kind in Kinds) then
  begin
    Exit(False);
  end;
  if AEntry.Kind in NotKinds then
  begin
    Exit(False);
  end;
  for mFilter in NotProjects do
  begin
    if ProjectMatches(AEntry, mFilter) then
    begin
      Exit(False);
    end;
  end;
  if Length(Projects) = 0 then
  begin
    Exit(True);
  end;
  mAny := False;
  for mFilter in Projects do
  begin
    if ProjectMatches(AEntry, mFilter) then
    begin
      mAny := True;
    end;
  end;
  Result := mAny;
end;

function TAtlasUnitQuery.HasWords: Boolean;
begin
  Result := Length(Words) > 0;
end;

function SameNames(const A, B: TArray<string>): Boolean;
var
  mIndex: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
  begin
    for mIndex := 0 to High(A) do
    begin
      if not SameText(A[mIndex], B[mIndex]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

function TAtlasUnitQuery.Narrows(const APrevious: TAtlasUnitQuery): Boolean;
var
  mIndex: Integer;
begin
  // Jede Regel des Matchers setzt eine Teilfolge voraus, und jede Teilfolge zählt (ScoreSubsequence):
  // Was das längere Wort trifft, traf auch das kürzere.
  Result := (Kinds = APrevious.Kinds) and (NotKinds = APrevious.NotKinds) and
    SameNames(Projects, APrevious.Projects) and SameNames(NotProjects, APrevious.NotProjects) and
    (Length(Words) >= Length(APrevious.Words));
  if Result then
  begin
    for mIndex := 0 to High(APrevious.Words) do
    begin
      if not StartsText(APrevious.Words[mIndex], Words[mIndex]) then
      begin
        Exit(False);
      end;
    end;
  end;
end;

{ TAtlasUnitPreview }

/// <summary>Texte aller Einträge des Arrays AName (leer ohne).</summary>
function ValuesOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if AObject.TryGetValue<TJSONArray>(AName, mItems) then
  begin
    for mItem in mItems do
    begin
      Result := Result + [mItem.Value];
    end;
  end;
end;

/// <summary>Zeitpunkt aus "modified" (ISO 8601); 0 ohne oder bei ungültigem Wert.</summary>
function ModifiedOf(AObject: TJSONObject): TDateTime;
var
  mText: string;
begin
  Result := 0;
  if AObject.TryGetValue<string>('modified', mText) then
  begin
    try
      Result := ISO8601ToDate(mText, False);
    except
      on EConvertError do
      begin
        Result := 0;
      end;
    end;
  end;
end;

function TypesOf(AObject: TJSONObject): TArray<TAtlasUnitType>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
  mType: TAtlasUnitType;
begin
  Result := nil;
  if not AObject.TryGetValue<TJSONArray>('types', mItems) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if mItem is TJSONObject then
    begin
      mType := Default(TAtlasUnitType);
      TJSONObject(mItem).TryGetValue<string>('name', mType.Name);
      TJSONObject(mItem).TryGetValue<string>('kind', mType.Kind);
      Result := Result + [mType];
    end;
  end;
end;

/// <summary>Steuerelement der Skizze aus [Name, Typ, Caption, Left, Top, Width, Height, Tiefe].</summary>
function SketchItemOf(ARow: TJSONArray): TAtlasUnitSketchItem;
begin
  Result := Default(TAtlasUnitSketchItem);
  Result.Name := ARow.Items[0].Value;
  Result.TypeName := ARow.Items[1].Value;
  Result.Caption := ARow.Items[2].Value;
  Result.Left := StrToIntDef(ARow.Items[3].Value, 0);
  Result.Top := StrToIntDef(ARow.Items[4].Value, 0);
  Result.Width := StrToIntDef(ARow.Items[5].Value, 0);
  Result.Height := StrToIntDef(ARow.Items[6].Value, 0);
  Result.Depth := StrToIntDef(ARow.Items[7].Value, 1);
end;

function SketchItemsOf(AForm: TJSONObject): TArray<TAtlasUnitSketchItem>;
var
  mItems: TJSONArray;
  mItem: TJSONValue;
begin
  Result := nil;
  if not AForm.TryGetValue<TJSONArray>('items', mItems) then
  begin
    Exit;
  end;
  for mItem in mItems do
  begin
    if (mItem is TJSONArray) and (TJSONArray(mItem).Count >= 8) then
    begin
      Result := Result + [SketchItemOf(TJSONArray(mItem))];
    end;
  end;
end;

/// <summary>Formular der Vorschau aus "form" in APreview.</summary>
procedure ReadForm(AForm: TJSONObject; var APreview: TAtlasUnitPreview);
begin
  APreview.HasForm := True;
  AForm.TryGetValue<string>('class', APreview.FormClass);
  AForm.TryGetValue<string>('caption', APreview.FormCaption);
  AForm.TryGetValue<Integer>('width', APreview.FormWidth);
  AForm.TryGetValue<Integer>('height', APreview.FormHeight);
  APreview.FormItems := SketchItemsOf(AForm);
end;

class function TAtlasUnitPreview.FromJson(const AValue: TJSONValue;
  const AUriToPath: TFunc<string, string>): TAtlasUnitPreview;
var
  mAnswer, mForm: TJSONObject;
  mText: string;
  mNumber: Integer;
begin
  Result := Default(TAtlasUnitPreview);
  Result.UsedBy := -1;
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mAnswer := TJSONObject(AValue);
  if mAnswer.TryGetValue<string>('uri', mText) and Assigned(AUriToPath) then
  begin
    Result.FileName := AUriToPath(mText);
  end;
  mAnswer.TryGetValue<string>('header', Result.Header);
  mAnswer.TryGetValue<Integer>('lines', Result.Lines);
  Result.Modified := ModifiedOf(mAnswer);
  mAnswer.TryGetValue<string>('git', Result.Git);
  Result.Types := TypesOf(mAnswer);
  Result.TypeCount := Length(Result.Types);
  if mAnswer.TryGetValue<Integer>('typeCount', mNumber) and (mNumber > Result.TypeCount) then
  begin
    Result.TypeCount := mNumber;
  end;
  Result.Uses_ := ValuesOf(mAnswer, 'uses');
  if mAnswer.TryGetValue<Integer>('usedBy', mNumber) then
  begin
    Result.UsedBy := mNumber;
  end;
  Result.UsedByUnits := ValuesOf(mAnswer, 'usedByUnits');
  if mAnswer.TryGetValue<TJSONObject>('form', mForm) then
  begin
    ReadForm(mForm, Result);
  end;
end;

{ TAtlasUnitSearch }

class function TAtlasUnitSearch.KindFromText(const AText: string; out AKind: TAtlasUnitKind): Boolean;
var
  mKind: TAtlasUnitKind;
  mText: string;
begin
  mText := LowerCase(Trim(AText));
  // Lange Schreibweisen zusätzlich zu den Kürzeln.
  if (mText = 'datamodule') or (mText = 'datenmodul') then
  begin
    mText := 'dm';
  end
  else if mText = 'include' then
  begin
    mText := 'inc';
  end;
  for mKind := Low(TAtlasUnitKind) to High(TAtlasUnitKind) do
  begin
    if cKindTexts[mKind] = mText then
    begin
      AKind := mKind;
      Exit(True);
    end;
  end;
  AKind := TAtlasUnitKind.Unit_;
  Result := False;
end;

class function TAtlasUnitSearch.KindText(AKind: TAtlasUnitKind): string;
begin
  Result := cKindTexts[AKind];
end;

class function TAtlasUnitSearch.GroupingFromText(const AText: string): TAtlasUnitGrouping;
begin
  if SameText(AText, 'folder') then
  begin
    Result := TAtlasUnitGrouping.Folder;
  end
  else if SameText(AText, 'none') then
  begin
    Result := TAtlasUnitGrouping.None;
  end
  else
  begin
    Result := TAtlasUnitGrouping.Project;
  end;
end;

class function TAtlasUnitSearch.GroupingText(AGrouping: TAtlasUnitGrouping): string;
begin
  case AGrouping of
    TAtlasUnitGrouping.Folder: Result := 'folder';
    TAtlasUnitGrouping.None: Result := 'none';
  else
    Result := 'project';
  end;
end;

class function TAtlasUnitSearch.PathStyleFromText(const AText: string): TAtlasUnitPathStyle;
begin
  if SameText(AText, 'compact') then
  begin
    Result := TAtlasUnitPathStyle.Compact;
  end
  else if SameText(AText, 'absolute') then
  begin
    Result := TAtlasUnitPathStyle.Absolute;
  end
  else
  begin
    Result := TAtlasUnitPathStyle.Relative;
  end;
end;

class function TAtlasUnitSearch.OriginsForScope(const AScope: string): TAtlasUnitOrigins;
begin
  if SameText(AScope, 'project') then
  begin
    Result := [TAtlasUnitOrigin.Active];
  end
  else if SameText(AScope, 'searchPath') then
  begin
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group, TAtlasUnitOrigin.SearchPath];
  end
  else if SameText(AScope, 'library') then
  begin
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group, TAtlasUnitOrigin.SearchPath,
      TAtlasUnitOrigin.Library_];
  end
  else
  begin
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group];
  end;
end;

/// <summary>Herkunft eines Eintrags: Bibliothek und Suchpfad nennt der Server, sonst entscheidet das aktive
/// Projekt.</summary>
function OriginOf(const AText: string; const AEntry: TAtlasUnitEntry; const AActiveProject: string): TAtlasUnitOrigin;
begin
  if SameText(AText, 'library') then
  begin
    Result := TAtlasUnitOrigin.Library_;
  end
  else if SameText(AText, 'searchPath') then
  begin
    Result := TAtlasUnitOrigin.SearchPath;
  end
  else if (AActiveProject <> '') and Contains(AEntry.Projects, AActiveProject) then
  begin
    Result := TAtlasUnitOrigin.Active;
  end
  else if (AActiveProject = '') and (Length(AEntry.Projects) > 0) then
  begin
    // Ohne aktives Projekt gilt jedes Projekt der Gruppe als aktiv.
    Result := TAtlasUnitOrigin.Active;
  end
  else
  begin
    Result := TAtlasUnitOrigin.Group;
  end;
end;

/// <summary>Projekt für Gruppe und Kennzeichen: das aktive, wenn die Unit dazugehört, sonst das erste.</summary>
function ProjectOf(const AEntry: TAtlasUnitEntry; const AActiveProject: string): string;
begin
  Result := '';
  if (AActiveProject <> '') and Contains(AEntry.Projects, AActiveProject) then
  begin
    Result := AActiveProject;
  end
  else if Length(AEntry.Projects) > 0 then
  begin
    Result := AEntry.Projects[0];
  end;
end;

function EntryOf(AItem: TJSONObject; const AActiveProject: string;
  const AUriToPath: TFunc<string, string>): TAtlasUnitEntry;
var
  mText: string;
begin
  Result := Default(TAtlasUnitEntry);
  AItem.TryGetValue<string>('name', Result.Name);
  if AItem.TryGetValue<string>('uri', mText) and Assigned(AUriToPath) then
  begin
    Result.FileName := AUriToPath(mText);
  end;
  if AItem.TryGetValue<string>('kind', mText) then
  begin
    TAtlasUnitSearch.KindFromText(mText, Result.Kind);
  end;
  AItem.TryGetValue<string>('caption', Result.Caption);
  Result.Projects := ValuesOf(AItem, 'projects');
  Result.Project := ProjectOf(Result, AActiveProject);
  mText := '';
  AItem.TryGetValue<string>('origin', mText);
  Result.Origin := OriginOf(mText, Result, AActiveProject);
end;

class function TAtlasUnitSearch.FromJson(const AValue: TJSONValue; const AActiveProject: string;
  const AUriToPath: TFunc<string, string>): TAtlasUnitEntries;
var
  mUnits: TJSONArray;
  mItem: TJSONValue;
  mEntry: TAtlasUnitEntry;
  mList: TList<TAtlasUnitEntry>;
begin
  Result := nil;
  if not (AValue is TJSONObject) or not TJSONObject(AValue).TryGetValue<TJSONArray>('units', mUnits) then
  begin
    Exit;
  end;
  mList := TList<TAtlasUnitEntry>.Create;
  try
    mList.Capacity := mUnits.Count;
    for mItem in mUnits do
    begin
      if mItem is TJSONObject then
      begin
        mEntry := EntryOf(TJSONObject(mItem), AActiveProject, AUriToPath);
        if mEntry.Name <> '' then
        begin
          mList.Add(mEntry);
        end;
      end;
    end;
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

class function TAtlasUnitSearch.UnitsArguments(ACaptions: Boolean): string;
begin
  Result := '[]';
  if ACaptions then
  begin
    Result := '[{"captions":true}]';
  end;
end;

class function TAtlasUnitSearch.ProjectsFromJson(const AValue: TJSONValue): TArray<string>;
var
  mProjects: TJSONArray;
  mItem: TJSONValue;
  mName: string;
begin
  Result := nil;
  if not (AValue is TJSONObject) or not TJSONObject(AValue).TryGetValue<TJSONArray>('projects', mProjects) then
  begin
    Exit;
  end;
  for mItem in mProjects do
  begin
    if (mItem is TJSONObject) and TJSONObject(mItem).TryGetValue<string>('name', mName) then
    begin
      Result := Result + [mName];
    end;
  end;
end;

function IsSubsequence(const APattern, AText: string): Boolean;
var
  mPatternIndex, mTextIndex: Integer;
begin
  mPatternIndex := 1;
  for mTextIndex := 1 to Length(AText) do
  begin
    if (mPatternIndex <= Length(APattern)) and (UpCase(AText[mTextIndex]) = UpCase(APattern[mPatternIndex])) then
    begin
      Inc(mPatternIndex);
    end;
  end;
  Result := mPatternIndex > Length(APattern);
end;

const
  /// <summary>Längster Namensteil, den SegmentScore ohne Speicheranforderung prüft.</summary>
  cMaxFastLength = 255;

/// <summary>Stimmt AName ab AStart mit APattern überein (APattern ganz, AName darf länger sein)?</summary>
function SameAt(const APattern, AName: string; AStart: Integer): Boolean;
var
  mIndex: Integer;
begin
  if AStart + Length(APattern) - 1 > Length(AName) then
  begin
    Exit(False);
  end;
  for mIndex := 1 to Length(APattern) do
  begin
    if AName[AStart + mIndex - 1] <> APattern[mIndex] then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

type
  TFastFlags = array[0..cMaxFastLength] of Boolean;

  /// <summary>Teil AName[Start..] (Len Zeichen) für SegmentScore; Wort und Name auch in Großschrift.</summary>
  TScoreSegment = record
    Word, WordUpper, Name, Upper: string;
    Start, Len: Integer;
    /// <summary>Wortanfänge des Teils (1-basiert, setzt FindStarts); das erste Zeichen ist immer einer.</summary>
    Starts: TFastFlags;
    function UpperAt(AIndex: Integer): Char;
    /// <summary>Gleich, Präfix mit und ohne Groß-/Kleinschreibung; NoMatch, wenn keine dieser Regeln passt.
    /// </summary>
    function PrefixScore: Integer;
    procedure FindStarts;
    function MatchesWordStarts: Boolean;
    /// <summary>Nächste Stufe der Teilfolge: ANext[i], wenn Zeichen i zu Word[APattern] passt und auf eine
    /// erreichte Stelle folgt; False, wenn keines passt.</summary>
    function StepSubsequence(const AReached: TFastFlags; APattern: Integer; out ANext: TFastFlags): Boolean;
    /// <summary>Teilfolge mit Wortgrenzen wie MatchesSubsequence des Matchers.</summary>
    function MatchesSubsequence: Boolean;
    function Score: Integer;
  end;

function TScoreSegment.UpperAt(AIndex: Integer): Char;
begin
  Result := Upper[Start + AIndex - 1];
end;

function TScoreSegment.PrefixScore: Integer;
begin
  if (Length(Word) = Len) and SameAt(WordUpper, Upper, Start) then
  begin
    Result := TAtlasCompletionMatcher.ScoreExact;
  end
  else if SameAt(Word, Name, Start) then
  begin
    Result := TAtlasCompletionMatcher.ScorePrefixCase;
  end
  else if SameAt(WordUpper, Upper, Start) then
  begin
    Result := TAtlasCompletionMatcher.ScorePrefix;
  end
  else
  begin
    Result := TAtlasCompletionMatcher.NoMatch;
  end;
end;

procedure TScoreSegment.FindStarts;
var
  mIndex: Integer;
begin
  Starts[1] := True;
  for mIndex := 2 to Len do
  begin
    Starts[mIndex] := TAtlasCompletionMatcher.IsWordStart(Name, Start + mIndex - 1);
  end;
end;

function TScoreSegment.MatchesWordStarts: Boolean;
var
  mIndex, mPattern: Integer;
begin
  mPattern := 1;
  for mIndex := 1 to Len do
  begin
    if (mPattern <= Length(Word)) and Starts[mIndex] and (UpperAt(mIndex) = WordUpper[mPattern]) then
    begin
      Inc(mPattern);
    end;
  end;
  Result := mPattern > Length(Word);
end;

function TScoreSegment.StepSubsequence(const AReached: TFastFlags; APattern: Integer;
  out ANext: TFastFlags): Boolean;
var
  mIndex: Integer;
  mPrevious: Boolean;
begin
  Result := False;
  mPrevious := False;
  ANext[0] := False;
  for mIndex := 1 to Len do
  begin
    ANext[mIndex] := (UpperAt(mIndex) = WordUpper[APattern]) and
      (AReached[mIndex - 1] or (mPrevious and Starts[mIndex]));
    mPrevious := mPrevious or AReached[mIndex - 1];
    Result := Result or ANext[mIndex];
  end;
end;

function TScoreSegment.MatchesSubsequence: Boolean;
var
  mReached, mNext: TFastFlags;
  mIndex, mPattern: Integer;
begin
  mReached[0] := False;
  for mIndex := 1 to Len do
  begin
    mReached[mIndex] := Starts[mIndex] and (UpperAt(mIndex) = WordUpper[1]);
  end;
  Result := True;
  mPattern := 2;
  while Result and (mPattern <= Length(Word)) do
  begin
    Result := StepSubsequence(mReached, mPattern, mNext);
    mReached := mNext;
    Inc(mPattern);
  end;
  if Result then
  begin
    // Das letzte Zeichen des Worts muss irgendwo erreicht sein.
    Result := False;
    for mIndex := 1 to Len do
    begin
      Result := Result or mReached[mIndex];
    end;
  end;
end;

function TScoreSegment.Score: Integer;
begin
  Result := PrefixScore;
  if Result <> TAtlasCompletionMatcher.NoMatch then
  begin
    Exit;
  end;
  // Wortanfänge des Teils einmal bestimmen.
  FindStarts;
  if MatchesWordStarts then
  begin
    Result := TAtlasCompletionMatcher.ScoreWordStarts;
  end
  else if Pos(WordUpper, Upper, Start) > 0 then
  begin
    Result := TAtlasCompletionMatcher.ScoreSubstring;
  end
  else if MatchesSubsequence then
  begin
    Result := TAtlasCompletionMatcher.ScoreSubsequence;
  end;
end;

/// <summary>Regeln von TAtlasCompletionMatcher.Score für den Teil AName[AStart..] (AStart zählt als Wortanfang),
/// aber ohne Kopien und Speicheranforderungen je Aufruf: Die Großschreibung von Wort und Name kommt vom
/// Aufrufer, die Teilfolge mit Wortgrenzen läuft über Felder auf dem Stack. Gleiches Ergebnis wie
/// TAtlasCompletionMatcher.Score(AWord, Copy(AName, AStart, MaxInt)).</summary>
function SegmentScore(const AWord, AWordUpper, AName, AUpper: string; AStart: Integer): Integer;
var
  mSegment: TScoreSegment;
begin
  mSegment.Len := Length(AName) - AStart + 1;
  if AWord = '' then
  begin
    Result := TAtlasCompletionMatcher.ScoreSubsequence;
  end
  else if Length(AWord) > mSegment.Len then
  begin
    Result := TAtlasCompletionMatcher.NoMatch;
  end
  else if mSegment.Len > cMaxFastLength then
  begin
    Result := TAtlasCompletionMatcher.Score(AWord, Copy(AName, AStart, MaxInt));
  end
  else
  begin
    mSegment.Word := AWord;
    mSegment.WordUpper := AWordUpper;
    mSegment.Name := AName;
    mSegment.Upper := AUpper;
    mSegment.Start := AStart;
    Result := mSegment.Score;
  end;
end;

/// <summary>Score mit vorab großgeschriebenem Wort und Namen.</summary>
function FastScore(const AWord, AWordUpper, AName, AUpper: string): Integer;
var
  mDot: Integer;
begin
  // Schneller Ausschluss: Ohne Teilfolge passt keine Regel des Matchers (die meisten Units je Tastendruck).
  if not IsSubsequence(AWordUpper, AUpper) then
  begin
    Exit(TAtlasCompletionMatcher.NoMatch);
  end;
  Result := SegmentScore(AWord, AWordUpper, AName, AUpper, 1);
  // Der letzte Teil des Namens zählt wie ein eigener Name ("binform" in Atlas.Common.Dfm.BinaryForm).
  mDot := LastDelimiter('.', AName);
  if (mDot > 0) and (mDot < Length(AName)) then
  begin
    Result := Max(Result, SegmentScore(AWord, AWordUpper, AName, AUpper, mDot + 1) - 1);
  end;
  if Result = TAtlasCompletionMatcher.NoMatch then
  begin
    Result := TAtlasUnitSearch.cScoreSubsequence;
  end;
end;

class function TAtlasUnitSearch.Score(const AWord, AName: string): Integer;
begin
  Result := FastScore(AWord, AWord.ToUpper, AName, AName.ToUpper);
end;

class function TAtlasUnitSearch.Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
  AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds): TArray<Integer>;
var
  mAll: TArray<Integer>;
  mIndex: Integer;
begin
  SetLength(mAll, Length(AEntries));
  for mIndex := 0 to High(mAll) do
  begin
    mAll[mIndex] := mIndex;
  end;
  Result := Order(AEntries, AQuery, AOrigins, AKinds, mAll);
end;

function UppersOf(const AWords: TArray<string>): TArray<string>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AWords));
  for mIndex := 0 to High(AWords) do
  begin
    Result[mIndex] := AWords[mIndex].ToUpper;
  end;
end;

/// <summary>Lassen Herkunft, Art und Filter der Anfrage den Eintrag zu?</summary>
function Admits(const AEntry: TAtlasUnitEntry; const AQuery: TAtlasUnitQuery; AOrigins: TAtlasUnitOrigins;
  AKinds: TAtlasUnitKinds): Boolean;
begin
  Result := (AEntry.Origin in AOrigins) and ((AKinds = []) or (AEntry.Kind in AKinds)) and AQuery.Accepts(AEntry);
end;

/// <summary>Punkte eines Suchworts für den Eintrag (AUpper, AUpperCaption: Name und Caption in Großschrift);
/// als Teiltext der Caption mindestens cScoreCaption (#1310).</summary>
function WordScore(const AWord, AWordUpper: string; const AEntry: TAtlasUnitEntry;
  const AUpper, AUpperCaption: string): Integer;
begin
  Result := FastScore(AWord, AWordUpper, AEntry.Name, AUpper);
  if (Result < TAtlasUnitSearch.cScoreCaption) and (AUpperCaption <> '') and
    (Pos(AWordUpper, AUpperCaption) > 0) then
  begin
    Result := TAtlasUnitSearch.cScoreCaption;
  end;
end;

/// <summary>Summe der Punkte aller Suchwörter (AUppers in Großschrift); -1, wenn eines nicht passt.</summary>
function EntryScore(const AEntry: TAtlasUnitEntry; const AWords, AUppers: TArray<string>): Integer;
var
  mUpper, mUpperCaption: string;
  mIndex, mPoints: Integer;
begin
  Result := 0;
  if Length(AWords) = 0 then
  begin
    Exit;
  end;
  mUpper := AEntry.UpperName;
  if mUpper = '' then
  begin
    mUpper := AEntry.Name.ToUpper;
  end;
  mUpperCaption := AEntry.UpperCaption;
  if mUpperCaption = '' then
  begin
    mUpperCaption := AEntry.Caption.ToUpper;
  end;
  mIndex := 0;
  while (Result >= 0) and (mIndex <= High(AWords)) do
  begin
    mPoints := WordScore(AWords[mIndex], AUppers[mIndex], AEntry, mUpper, mUpperCaption);
    if mPoints < 0 then
    begin
      Result := -1;
    end
    else
    begin
      Inc(Result, mPoints);
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Beste Punkte zuerst; bei Gleichstand offene, aktives Projekt, dann die Reihenfolge der Einträge
/// (FromJson sortiert nach Name und Datei).</summary>
function ScoreComparer(const AScores: TArray<Integer>; const AEntries: TAtlasUnitEntries): IComparer<Integer>;
var
  mScores: TArray<Integer>;
  mEntries: TAtlasUnitEntries;
begin
  mScores := AScores;
  mEntries := AEntries;
  Result := TComparer<Integer>.Construct(
    function(const A, B: Integer): Integer
    begin
      Result := mScores[B] - mScores[A];
      if Result = 0 then
      begin
        Result := Ord(mEntries[B].IsOpen) - Ord(mEntries[A].IsOpen);
      end;
      if Result = 0 then
      begin
        Result := Ord(mEntries[B].Origin = TAtlasUnitOrigin.Active) - Ord(mEntries[A].Origin = TAtlasUnitOrigin.Active);
      end;
      if Result = 0 then
      begin
        Result := A - B;
      end;
    end);
end;

class function TAtlasUnitSearch.Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
  AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds; const ACandidates: TArray<Integer>): TArray<Integer>;
var
  mScores: TArray<Integer>;
  mUppers: TArray<string>;
  mList: TList<Integer>;
  mIndex, mTotal: Integer;
begin
  SetLength(mScores, Length(AEntries));
  mUppers := UppersOf(AQuery.Words);
  mList := TList<Integer>.Create;
  try
    for mIndex in ACandidates do
    begin
      if (mIndex < 0) or (mIndex > High(AEntries)) or not Admits(AEntries[mIndex], AQuery, AOrigins, AKinds) then
      begin
        Continue;
      end;
      mTotal := EntryScore(AEntries[mIndex], AQuery.Words, mUppers);
      if mTotal >= 0 then
      begin
        mScores[mIndex] := mTotal;
        mList.Add(mIndex);
      end;
    end;
    mList.Sort(ScoreComparer(mScores, AEntries));
    Result := mList.ToArray;
  finally
    mList.Free;
  end;
end;

/// <summary>Ordner mit „\“ am Ende (das Plugin läuft nur unter Windows).</summary>
function WithSlash(const AFolder: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not Result.EndsWith('\') then
  begin
    Result := Result + '\';
  end;
end;

function WithoutSlash(const AFolder: string): string;
begin
  Result := AFolder;
  while (Length(Result) > 3) and Result.EndsWith('\') do
  begin
    SetLength(Result, Length(Result) - 1);
  end;
end;

function RelativeTo(const AFileName, ARoot: string): string;
var
  mRoot: string;
begin
  mRoot := WithSlash(ARoot);
  if (ARoot <> '') and StartsText(mRoot, AFileName) then
  begin
    Result := Copy(AFileName, Length(mRoot) + 1, MaxInt);
  end
  else
  begin
    Result := AFileName;
  end;
end;

class function TAtlasUnitSearch.GroupOf(const AEntry: TAtlasUnitEntry; AGrouping: TAtlasUnitGrouping;
  const ARoot: string): string;
begin
  case AGrouping of
    TAtlasUnitGrouping.Project:
      Result := AEntry.Project;
    TAtlasUnitGrouping.Folder:
      begin
        Result := RelativeTo(AEntry.FileName, ARoot);
        Result := Copy(Result, 1, LastDelimiter('\', Result) - 1);
      end;
  else
    Result := '';
  end;
end;

{ TAtlasUnitLayout }

class function TAtlasUnitLayout.Create(AGrouping: TAtlasUnitGrouping; const ARoot, AActiveProject: string;
  const ACollapsed: TArray<string>; ASearching: Boolean): TAtlasUnitLayout;
begin
  Result.Grouping := AGrouping;
  Result.Root := ARoot;
  Result.ActiveProject := AActiveProject;
  Result.Collapsed := ACollapsed;
  Result.Searching := ASearching;
end;

/// <summary>Gruppe wie GroupOf, aber ohne Kopien je Eintrag, weil Rows bei jedem Tastendruck läuft. ARootSlash
/// ist ALayout.Root mit „\“ am Ende.</summary>
function RowGroup(const AEntry: TAtlasUnitEntry; const ALayout: TAtlasUnitLayout; const ARootSlash: string): string;
var
  mName: string;
  mSlash: Integer;
begin
  if ALayout.Grouping = TAtlasUnitGrouping.Project then
  begin
    Exit(AEntry.Project);
  end;
  mName := AEntry.FileName;
  mSlash := LastDelimiter('\', mName);
  if (ALayout.Root <> '') and (Length(mName) > Length(ARootSlash)) and StartsText(ARootSlash, mName) then
  begin
    Result := Copy(mName, Length(ARootSlash) + 1, mSlash - Length(ARootSlash) - 1);
  end
  else
  begin
    Result := Copy(mName, 1, mSlash - 1);
  end;
end;

/// <summary>Ohne Gruppierung: eine Zeile je Treffer.</summary>
function FlatRows(const AOrder: TArray<Integer>): TAtlasUnitRows;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(AOrder));
  for mIndex := 0 to High(AOrder) do
  begin
    Result[mIndex] := Default(TAtlasUnitRow);
    Result[mIndex].Entry := AOrder[mIndex];
  end;
end;

/// <summary>Aktives Projekt oben, Einträge ohne Gruppe unten, sonst alphabetisch.</summary>
function GroupComparer(const AActiveProject: string): IComparer<string>;
var
  mActive: string;
begin
  mActive := AActiveProject;
  Result := TComparer<string>.Construct(
    function(const A, B: string): Integer
    begin
      Result := Ord(SameText(B, mActive)) - Ord(SameText(A, mActive));
      if Result = 0 then
      begin
        Result := Ord(A = '') - Ord(B = '');
      end;
      if Result = 0 then
      begin
        Result := CompareText(A, B);
      end;
    end);
end;

/// <summary>Kopf der Gruppe und, wenn sie nicht eingeklappt ist, ihre Einträge.</summary>
procedure AddGroupRows(AList: TList<TAtlasUnitRow>; const AKey: string; AMembers: TList<Integer>;
  const ACollapsed: TArray<string>);
var
  mRow: TAtlasUnitRow;
  mIndex: Integer;
begin
  mRow := Default(TAtlasUnitRow);
  mRow.IsGroup := True;
  mRow.Group := AKey;
  mRow.Count := AMembers.Count;
  mRow.Collapsed := Contains(ACollapsed, LowerCase(AKey));
  mRow.Entry := -1;
  AList.Add(mRow);
  if mRow.Collapsed then
  begin
    Exit;
  end;
  for mIndex in AMembers do
  begin
    mRow := Default(TAtlasUnitRow);
    mRow.Group := AKey;
    mRow.Entry := mIndex;
    AList.Add(mRow);
  end;
end;

class function TAtlasUnitSearch.Rows(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>;
  const ALayout: TAtlasUnitLayout): TAtlasUnitRows;
var
  mGroups: TObjectDictionary<string, TList<Integer>>;
  mKeys: TList<string>;
  mRows: TList<TAtlasUnitRow>;
  mMembers: TList<Integer>;
  mIndex: Integer;
  mKey, mRootSlash: string;
begin
  if ALayout.Grouping = TAtlasUnitGrouping.None then
  begin
    Exit(FlatRows(AOrder));
  end;
  mGroups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  mKeys := TList<string>.Create;
  mRows := TList<TAtlasUnitRow>.Create;
  try
    // Reihenfolge der ersten Treffer = beste Gruppe zuerst.
    mRootSlash := WithSlash(ALayout.Root);
    for mIndex in AOrder do
    begin
      mKey := RowGroup(AEntries[mIndex], ALayout, mRootSlash);
      if not mGroups.TryGetValue(LowerCase(mKey), mMembers) then
      begin
        mMembers := TList<Integer>.Create;
        mGroups.Add(LowerCase(mKey), mMembers);
        mKeys.Add(mKey);
      end;
      mMembers.Add(mIndex);
    end;
    if not ALayout.Searching then
    begin
      mKeys.Sort(GroupComparer(ALayout.ActiveProject));
    end;
    for mKey in mKeys do
    begin
      AddGroupRows(mRows, mKey, mGroups[LowerCase(mKey)], ALayout.Collapsed);
    end;
    Result := mRows.ToArray;
  finally
    mRows.Free;
    mKeys.Free;
    mGroups.Free;
  end;
end;

class function TAtlasUnitSearch.MiddleEllipsis(const AText: string; AMax: Integer): string;
var
  mHead, mTail: Integer;
begin
  if (AMax <= 0) or (Length(AText) <= AMax) then
  begin
    Exit(AText);
  end;
  if AMax <= 1 then
  begin
    Exit('…');
  end;
  // Das Ende unterscheidet (Dateiname, letzter Ordner) und bekommt etwas mehr Platz.
  mTail := (AMax - 1 + 1) div 2;
  mHead := AMax - 1 - mTail;
  Result := Copy(AText, 1, mHead) + '…' + Copy(AText, Length(AText) - mTail + 1, mTail);
end;

class function TAtlasUnitSearch.DisplayPath(const AFileName, ARoot: string; AStyle: TAtlasUnitPathStyle;
  AMax: Integer): string;
begin
  case AStyle of
    TAtlasUnitPathStyle.Absolute:
      Result := AFileName;
    TAtlasUnitPathStyle.Compact:
      Result := MiddleEllipsis(RelativeTo(AFileName, ARoot), AMax);
  else
    Result := RelativeTo(AFileName, ARoot);
  end;
end;

class function TAtlasUnitSearch.CommonRoot(const AFiles: TArray<string>): string;
var
  mFileName, mFolder: string;
begin
  Result := '';
  for mFileName in AFiles do
  begin
    mFolder := Copy(mFileName, 1, LastDelimiter('\', mFileName));
    if Result = '' then
    begin
      Result := mFolder;
      Continue;
    end;
    while (Result <> '') and not StartsText(Result, mFolder) do
    begin
      Result := Copy(Result, 1, Length(Result) - 1);
      Result := Copy(Result, 1, LastDelimiter('\', Result));
    end;
  end;
  Result := WithoutSlash(Result);
end;

class procedure TAtlasUnitSearch.SortByName(var AEntries: TAtlasUnitEntries);
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AEntries) do
  begin
    AEntries[mIndex].UpperName := AEntries[mIndex].Name.ToUpper;
    AEntries[mIndex].UpperCaption := AEntries[mIndex].Caption.ToUpper;
  end;
  TArray.Sort<TAtlasUnitEntry>(AEntries, TComparer<TAtlasUnitEntry>.Construct(
    function(const A, B: TAtlasUnitEntry): Integer
    begin
      Result := CompareText(A.Name, B.Name);
      if Result = 0 then
      begin
        Result := CompareText(A.FileName, B.FileName);
      end;
    end));
end;

end.
