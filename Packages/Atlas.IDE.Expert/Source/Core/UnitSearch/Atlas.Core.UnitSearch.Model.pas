unit Atlas.Core.UnitSearch.Model;

// Fenster „Units suchen“ (#777), Teil ohne VCL und Open Tools API:
//   - Einträge aus atlas.server.units lesen; Herkunft „Aktives Projekt“ oder
//     „Projektgruppe“ entscheidet das aktive Projekt der IDE.
//   - Tippsyntax p:<Projekt>, t:form|frame|dm|unit|test|inc, mit Minus
//     ausschließend (-t:test); der Rest ist der Suchtext.
//   - Rangfolge wie die Befehlspalette (#502, #229): unscharf, CamelCase,
//     zuletzt Teilfolge; bei Gleichstand offene Units, dann Units des aktiven
//     Projekts, dann der Name.
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
    class function FromJson(const AValue: TJSONValue; const AUriToPath: TFunc<string, string>): TAtlasUnitPreview; static;
  end;

  TAtlasUnitSearch = class
  public const
    ScoreSubsequence = 100;
  public
    /// <summary>Einträge aus der Antwort von atlas.server.units; AActiveProject ist der Name des aktiven
    /// Projekts ('' = keins).</summary>
    class function FromJson(const AValue: TJSONValue; const AActiveProject: string;
      const AUriToPath: TFunc<string, string>): TAtlasUnitEntries; static;
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
    /// <summary>Zeilen aus der Reihenfolge. ACollapsed: eingeklappte Gruppen (Schlüssel in Kleinschrift);
    /// ASearching: Gruppen nach dem besten Treffer statt alphabetisch (aktives Projekt zuerst).</summary>
    class function Rows(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>;
      AGrouping: TAtlasUnitGrouping; const ARoot, AActiveProject: string; const ACollapsed: TArray<string>;
      ASearching: Boolean): TAtlasUnitRows; static;
    /// <summary>Text mit höchstens AMax Zeichen; zu lang wird er in der Mitte durch „…“ ersetzt.</summary>
    class function MiddleEllipsis(const AText: string; AMax: Integer): string; static;
    /// <summary>Pfad für die zweite Zeile: relativ zu ARoot (außerhalb absolut), gekürzt oder absolut.</summary>
    class function DisplayPath(const AFileName, ARoot: string; AStyle: TAtlasUnitPathStyle; AMax: Integer): string; static;
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
  KindTexts: array[TAtlasUnitKind] of string = ('unit', 'form', 'frame', 'dm', 'test', 'inc');

function Contains(const AList: TArray<string>; const AValue: string): Boolean;
var
  Item: string;
begin
  for Item in AList do
    if SameText(Item, AValue) then
      Exit(True);
  Result := False;
end;

function ProjectMatches(const AEntry: TAtlasUnitEntry; const AFilter: string): Boolean;
var
  Item: string;
begin
  // Teilstring ohne Groß-/Kleinschreibung: p:ide trifft Atlas.IDE.Expert.
  for Item in AEntry.Projects do
    if ContainsText(Item, AFilter) then
      Exit(True);
  Result := False;
end;

{ TAtlasUnitQuery }

class function TAtlasUnitQuery.IsFilter(const AToken: string): Boolean;
var
  Token, Value: string;
  Part: string;
  Kind: TAtlasUnitKind;
begin
  Token := AToken;
  if Token.StartsWith('-') then
    Token := Copy(Token, 2, MaxInt);
  if (Length(Token) < 3) or (Token[2] <> ':') then
    Exit(False);
  Value := Copy(Token, 3, MaxInt);
  case UpCase(Token[1]) of
    'P':
      Result := Value <> '';
    'T':
      begin
        Result := Value <> '';
        for Part in Value.Split(['|']) do
          if not TAtlasUnitSearch.KindFromText(Part, Kind) then
            Exit(False);
      end;
  else
    Result := False;
  end;
end;

class function TAtlasUnitQuery.Parse(const AInput: string; ASyntax: Boolean): TAtlasUnitQuery;
var
  Token, Value, Part: string;
  Negative: Boolean;
  Kind: TAtlasUnitKind;
begin
  Result := Default(TAtlasUnitQuery);
  for Token in AInput.Split([' ', #9], TStringSplitOptions.ExcludeEmpty) do
  begin
    if not ASyntax or not IsFilter(Token) then
    begin
      Result.Words := Result.Words + [Token];
      Continue;
    end;
    Negative := Token.StartsWith('-');
    Value := Copy(Token, 3 + Ord(Negative), MaxInt);
    if UpCase(Token[1 + Ord(Negative)]) = 'P' then
    begin
      if Negative then
        Result.NotProjects := Result.NotProjects + [Value]
      else
        Result.Projects := Result.Projects + [Value];
      Continue;
    end;
    for Part in Value.Split(['|']) do
      if TAtlasUnitSearch.KindFromText(Part, Kind) then
      begin
        if Negative then
          Include(Result.NotKinds, Kind)
        else
          Include(Result.Kinds, Kind);
      end;
  end;
end;

function TAtlasUnitQuery.Accepts(const AEntry: TAtlasUnitEntry): Boolean;
var
  Filter: string;
  Any: Boolean;
begin
  if (Kinds <> []) and not (AEntry.Kind in Kinds) then
    Exit(False);
  if AEntry.Kind in NotKinds then
    Exit(False);
  for Filter in NotProjects do
    if ProjectMatches(AEntry, Filter) then
      Exit(False);
  if Length(Projects) = 0 then
    Exit(True);
  Any := False;
  for Filter in Projects do
    if ProjectMatches(AEntry, Filter) then
      Any := True;
  Result := Any;
end;

function TAtlasUnitQuery.HasWords: Boolean;
begin
  Result := Length(Words) > 0;
end;

function SameNames(const A, B: TArray<string>): Boolean;
var
  Index: Integer;
begin
  Result := Length(A) = Length(B);
  if Result then
    for Index := 0 to High(A) do
      if not SameText(A[Index], B[Index]) then
        Exit(False);
end;

function TAtlasUnitQuery.Narrows(const APrevious: TAtlasUnitQuery): Boolean;
var
  Index: Integer;
begin
  // Jede Regel des Matchers setzt eine Teilfolge voraus, und jede Teilfolge zählt (ScoreSubsequence):
  // Was das längere Wort trifft, traf auch das kürzere.
  Result := (Kinds = APrevious.Kinds) and (NotKinds = APrevious.NotKinds) and
    SameNames(Projects, APrevious.Projects) and SameNames(NotProjects, APrevious.NotProjects) and
    (Length(Words) >= Length(APrevious.Words));
  if Result then
    for Index := 0 to High(APrevious.Words) do
      if not StartsText(APrevious.Words[Index], Words[Index]) then
        Exit(False);
end;

{ TAtlasUnitPreview }

class function TAtlasUnitPreview.FromJson(const AValue: TJSONValue;
  const AUriToPath: TFunc<string, string>): TAtlasUnitPreview;
var
  Answer, Form: TJSONObject;
  Items, Row: TJSONArray;
  Item: TJSONValue;
  Text: string;
  Number: Integer;
  TypeEntry: TAtlasUnitType;
  Sketch: TAtlasUnitSketchItem;
begin
  Result := Default(TAtlasUnitPreview);
  Result.UsedBy := -1;
  if not (AValue is TJSONObject) then
    Exit;
  Answer := TJSONObject(AValue);
  if Answer.TryGetValue<string>('uri', Text) and Assigned(AUriToPath) then
    Result.FileName := AUriToPath(Text);
  Answer.TryGetValue<string>('header', Result.Header);
  Answer.TryGetValue<Integer>('lines', Result.Lines);
  if Answer.TryGetValue<string>('modified', Text) then
    try
      Result.Modified := ISO8601ToDate(Text, False);
    except
      on EConvertError do
        Result.Modified := 0;
    end;
  Answer.TryGetValue<string>('git', Result.Git);
  if Answer.TryGetValue<TJSONArray>('types', Items) then
    for Item in Items do
      if Item is TJSONObject then
      begin
        TypeEntry := Default(TAtlasUnitType);
        TJSONObject(Item).TryGetValue<string>('name', TypeEntry.Name);
        TJSONObject(Item).TryGetValue<string>('kind', TypeEntry.Kind);
        Result.Types := Result.Types + [TypeEntry];
      end;
  Result.TypeCount := Length(Result.Types);
  if Answer.TryGetValue<Integer>('typeCount', Number) and (Number > Result.TypeCount) then
    Result.TypeCount := Number;
  if Answer.TryGetValue<TJSONArray>('uses', Items) then
    for Item in Items do
      Result.Uses_ := Result.Uses_ + [Item.Value];
  if Answer.TryGetValue<Integer>('usedBy', Number) then
    Result.UsedBy := Number;
  if Answer.TryGetValue<TJSONArray>('usedByUnits', Items) then
    for Item in Items do
      Result.UsedByUnits := Result.UsedByUnits + [Item.Value];
  if Answer.TryGetValue<TJSONObject>('form', Form) then
  begin
    Result.HasForm := True;
    Form.TryGetValue<string>('class', Result.FormClass);
    Form.TryGetValue<string>('caption', Result.FormCaption);
    Form.TryGetValue<Integer>('width', Result.FormWidth);
    Form.TryGetValue<Integer>('height', Result.FormHeight);
    if Form.TryGetValue<TJSONArray>('items', Items) then
      for Item in Items do
      begin
        if not (Item is TJSONArray) or (TJSONArray(Item).Count < 8) then
          Continue;
        Row := TJSONArray(Item);
        Sketch := Default(TAtlasUnitSketchItem);
        Sketch.Name := Row.Items[0].Value;
        Sketch.TypeName := Row.Items[1].Value;
        Sketch.Caption := Row.Items[2].Value;
        Sketch.Left := StrToIntDef(Row.Items[3].Value, 0);
        Sketch.Top := StrToIntDef(Row.Items[4].Value, 0);
        Sketch.Width := StrToIntDef(Row.Items[5].Value, 0);
        Sketch.Height := StrToIntDef(Row.Items[6].Value, 0);
        Sketch.Depth := StrToIntDef(Row.Items[7].Value, 1);
        Result.FormItems := Result.FormItems + [Sketch];
      end;
  end;
end;

{ TAtlasUnitSearch }

class function TAtlasUnitSearch.KindFromText(const AText: string; out AKind: TAtlasUnitKind): Boolean;
var
  Kind: TAtlasUnitKind;
  Text: string;
begin
  Text := LowerCase(Trim(AText));
  // Lange Schreibweisen zusätzlich zu den Kürzeln.
  if (Text = 'datamodule') or (Text = 'datenmodul') then
    Text := 'dm'
  else if Text = 'include' then
    Text := 'inc';
  for Kind := Low(TAtlasUnitKind) to High(TAtlasUnitKind) do
    if KindTexts[Kind] = Text then
    begin
      AKind := Kind;
      Exit(True);
    end;
  AKind := TAtlasUnitKind.Unit_;
  Result := False;
end;

class function TAtlasUnitSearch.KindText(AKind: TAtlasUnitKind): string;
begin
  Result := KindTexts[AKind];
end;

class function TAtlasUnitSearch.GroupingFromText(const AText: string): TAtlasUnitGrouping;
begin
  if SameText(AText, 'folder') then
    Result := TAtlasUnitGrouping.Folder
  else if SameText(AText, 'none') then
    Result := TAtlasUnitGrouping.None
  else
    Result := TAtlasUnitGrouping.Project;
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
    Result := TAtlasUnitPathStyle.Compact
  else if SameText(AText, 'absolute') then
    Result := TAtlasUnitPathStyle.Absolute
  else
    Result := TAtlasUnitPathStyle.Relative;
end;

class function TAtlasUnitSearch.OriginsForScope(const AScope: string): TAtlasUnitOrigins;
begin
  if SameText(AScope, 'project') then
    Result := [TAtlasUnitOrigin.Active]
  else if SameText(AScope, 'searchPath') then
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group, TAtlasUnitOrigin.SearchPath]
  else if SameText(AScope, 'library') then
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group, TAtlasUnitOrigin.SearchPath,
      TAtlasUnitOrigin.Library_]
  else
    Result := [TAtlasUnitOrigin.Active, TAtlasUnitOrigin.Group];
end;

class function TAtlasUnitSearch.FromJson(const AValue: TJSONValue; const AActiveProject: string;
  const AUriToPath: TFunc<string, string>): TAtlasUnitEntries;
var
  Units, Projects: TJSONArray;
  Item, ProjectValue: TJSONValue;
  Entry: TAtlasUnitEntry;
  Text: string;
  List: TList<TAtlasUnitEntry>;
begin
  Result := nil;
  if not (AValue is TJSONObject) or not TJSONObject(AValue).TryGetValue<TJSONArray>('units', Units) then
    Exit;
  List := TList<TAtlasUnitEntry>.Create;
  try
    List.Capacity := Units.Count;
    for Item in Units do
    begin
      if not (Item is TJSONObject) then
        Continue;
      Entry := Default(TAtlasUnitEntry);
      TJSONObject(Item).TryGetValue<string>('name', Entry.Name);
      if TJSONObject(Item).TryGetValue<string>('uri', Text) and Assigned(AUriToPath) then
        Entry.FileName := AUriToPath(Text);
      if TJSONObject(Item).TryGetValue<string>('kind', Text) then
        KindFromText(Text, Entry.Kind);
      if TJSONObject(Item).TryGetValue<TJSONArray>('projects', Projects) then
        for ProjectValue in Projects do
          Entry.Projects := Entry.Projects + [ProjectValue.Value];
      if (AActiveProject <> '') and Contains(Entry.Projects, AActiveProject) then
        Entry.Project := AActiveProject
      else if Length(Entry.Projects) > 0 then
        Entry.Project := Entry.Projects[0];
      Text := '';
      TJSONObject(Item).TryGetValue<string>('origin', Text);
      if SameText(Text, 'library') then
        Entry.Origin := TAtlasUnitOrigin.Library_
      else if SameText(Text, 'searchPath') then
        Entry.Origin := TAtlasUnitOrigin.SearchPath
      else if (AActiveProject <> '') and Contains(Entry.Projects, AActiveProject) then
        Entry.Origin := TAtlasUnitOrigin.Active
      else if (AActiveProject = '') and (Length(Entry.Projects) > 0) then
        // Ohne aktives Projekt gilt jedes Projekt der Gruppe als aktiv.
        Entry.Origin := TAtlasUnitOrigin.Active
      else
        Entry.Origin := TAtlasUnitOrigin.Group;
      if Entry.Name <> '' then
        List.Add(Entry);
    end;
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

class function TAtlasUnitSearch.ProjectsFromJson(const AValue: TJSONValue): TArray<string>;
var
  Projects: TJSONArray;
  Item: TJSONValue;
  Name: string;
begin
  Result := nil;
  if not (AValue is TJSONObject) or not TJSONObject(AValue).TryGetValue<TJSONArray>('projects', Projects) then
    Exit;
  for Item in Projects do
    if (Item is TJSONObject) and TJSONObject(Item).TryGetValue<string>('name', Name) then
      Result := Result + [Name];
end;

function IsSubsequence(const APattern, AText: string): Boolean;
var
  PatternIndex, TextIndex: Integer;
begin
  PatternIndex := 1;
  for TextIndex := 1 to Length(AText) do
    if (PatternIndex <= Length(APattern)) and (UpCase(AText[TextIndex]) = UpCase(APattern[PatternIndex])) then
      Inc(PatternIndex);
  Result := PatternIndex > Length(APattern);
end;

const
  /// <summary>Längster Namensteil, den SegmentScore ohne Speicheranforderung prüft.</summary>
  MaxFastLength = 255;

/// <summary>Stimmt AName ab AStart mit APattern überein (APattern ganz, AName darf länger sein)?</summary>
function SameAt(const APattern, AName: string; AStart: Integer): Boolean;
var
  Index: Integer;
begin
  if AStart + Length(APattern) - 1 > Length(AName) then
    Exit(False);
  for Index := 1 to Length(APattern) do
    if AName[AStart + Index - 1] <> APattern[Index] then
      Exit(False);
  Result := True;
end;

/// <summary>Regeln von TAtlasCompletionMatcher.Score für den Teil AName[AStart..] (AStart zählt als Wortanfang),
/// aber ohne Kopien und Speicheranforderungen je Aufruf: Die Großschreibung von Wort und Name kommt vom
/// Aufrufer, die Teilfolge mit Wortgrenzen läuft über Felder auf dem Stack. Gleiches Ergebnis wie
/// TAtlasCompletionMatcher.Score(AWord, Copy(AName, AStart, MaxInt)).</summary>
function SegmentScore(const AWord, AWordUpper, AName, AUpper: string; AStart: Integer): Integer;
var
  Len, Index, PatternIndex: Integer;
  Starts, Reached, Next: array[0..MaxFastLength] of Boolean;
  Previous, Found: Boolean;
begin
  Len := Length(AName) - AStart + 1;
  if AWord = '' then
    Exit(TAtlasCompletionMatcher.ScoreSubsequence);
  if Length(AWord) > Len then
    Exit(TAtlasCompletionMatcher.NoMatch);
  if Len > MaxFastLength then
    Exit(TAtlasCompletionMatcher.Score(AWord, Copy(AName, AStart, MaxInt)));
  if (Length(AWord) = Len) and SameAt(AWordUpper, AUpper, AStart) then
    Exit(TAtlasCompletionMatcher.ScoreExact);
  if SameAt(AWord, AName, AStart) then
    Exit(TAtlasCompletionMatcher.ScorePrefixCase);
  if SameAt(AWordUpper, AUpper, AStart) then
    Exit(TAtlasCompletionMatcher.ScorePrefix);
  // Wortanfänge des Teils einmal bestimmen; das erste Zeichen ist immer einer.
  Starts[1] := True;
  for Index := 2 to Len do
    Starts[Index] := TAtlasCompletionMatcher.IsWordStart(AName, AStart + Index - 1);
  PatternIndex := 1;
  for Index := 1 to Len do
    if (PatternIndex <= Length(AWord)) and Starts[Index] and
      (AUpper[AStart + Index - 1] = AWordUpper[PatternIndex]) then
      Inc(PatternIndex);
  if PatternIndex > Length(AWord) then
    Exit(TAtlasCompletionMatcher.ScoreWordStarts);
  if Pos(AWordUpper, AUpper, AStart) > 0 then
    Exit(TAtlasCompletionMatcher.ScoreSubstring);
  // Teilfolge mit Wortgrenzen wie MatchesSubsequence des Matchers.
  Reached[0] := False;
  for Index := 1 to Len do
    Reached[Index] := Starts[Index] and (AUpper[AStart + Index - 1] = AWordUpper[1]);
  for PatternIndex := 2 to Length(AWord) do
  begin
    Previous := False;
    Next[0] := False;
    Found := False;
    for Index := 1 to Len do
    begin
      Next[Index] := (AUpper[AStart + Index - 1] = AWordUpper[PatternIndex]) and
        (Reached[Index - 1] or (Previous and Starts[Index]));
      Previous := Previous or Reached[Index - 1];
      Found := Found or Next[Index];
    end;
    if not Found then
      Exit(TAtlasCompletionMatcher.NoMatch);
    Reached := Next;
  end;
  for Index := 1 to Len do
    if Reached[Index] then
      Exit(TAtlasCompletionMatcher.ScoreSubsequence);
  Result := TAtlasCompletionMatcher.NoMatch;
end;

/// <summary>Score mit vorab großgeschriebenem Wort und Namen.</summary>
function FastScore(const AWord, AWordUpper, AName, AUpper: string): Integer;
var
  Dot: Integer;
begin
  // Schneller Ausschluss: Ohne Teilfolge passt keine Regel des Matchers (die meisten Units je Tastendruck).
  if not IsSubsequence(AWordUpper, AUpper) then
    Exit(TAtlasCompletionMatcher.NoMatch);
  Result := SegmentScore(AWord, AWordUpper, AName, AUpper, 1);
  // Der letzte Teil des Namens zählt wie ein eigener Name ("binform" in Atlas.Common.Dfm.BinaryForm).
  Dot := LastDelimiter('.', AName);
  if (Dot > 0) and (Dot < Length(AName)) then
    Result := Max(Result, SegmentScore(AWord, AWordUpper, AName, AUpper, Dot + 1) - 1);
  if Result = TAtlasCompletionMatcher.NoMatch then
    Result := TAtlasUnitSearch.ScoreSubsequence;
end;

class function TAtlasUnitSearch.Score(const AWord, AName: string): Integer;
begin
  Result := FastScore(AWord, AWord.ToUpper, AName, AName.ToUpper);
end;

class function TAtlasUnitSearch.Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
  AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds): TArray<Integer>;
var
  All: TArray<Integer>;
  Index: Integer;
begin
  SetLength(All, Length(AEntries));
  for Index := 0 to High(All) do
    All[Index] := Index;
  Result := Order(AEntries, AQuery, AOrigins, AKinds, All);
end;

class function TAtlasUnitSearch.Order(const AEntries: TAtlasUnitEntries; const AQuery: TAtlasUnitQuery;
  AOrigins: TAtlasUnitOrigins; AKinds: TAtlasUnitKinds; const ACandidates: TArray<Integer>): TArray<Integer>;
var
  Scores: TArray<Integer>;
  List: TList<Integer>;
  Index, Total, Points, WordIndex: Integer;
  Upper: string;
  Uppers: TArray<string>;
  Entries: TAtlasUnitEntries;
begin
  Entries := AEntries;
  SetLength(Scores, Length(AEntries));
  SetLength(Uppers, Length(AQuery.Words));
  for WordIndex := 0 to High(AQuery.Words) do
    Uppers[WordIndex] := AQuery.Words[WordIndex].ToUpper;
  List := TList<Integer>.Create;
  try
    for Index in ACandidates do
    begin
      if (Index < 0) or (Index > High(AEntries)) then
        Continue;
      if not (AEntries[Index].Origin in AOrigins) then
        Continue;
      if (AKinds <> []) and not (AEntries[Index].Kind in AKinds) then
        Continue;
      if not AQuery.Accepts(AEntries[Index]) then
        Continue;
      Total := 0;
      Upper := AEntries[Index].UpperName;
      if (Upper = '') and (Length(AQuery.Words) > 0) then
        Upper := AEntries[Index].Name.ToUpper;
      for WordIndex := 0 to High(AQuery.Words) do
      begin
        Points := FastScore(AQuery.Words[WordIndex], Uppers[WordIndex], AEntries[Index].Name, Upper);
        if Points < 0 then
        begin
          Total := -1;
          Break;
        end;
        Inc(Total, Points);
      end;
      if Total < 0 then
        Continue;
      Scores[Index] := Total;
      List.Add(Index);
    end;
    List.Sort(TComparer<Integer>.Construct(
      function(const A, B: Integer): Integer
      begin
        Result := Scores[B] - Scores[A];
        if Result = 0 then
          Result := Ord(Entries[B].IsOpen) - Ord(Entries[A].IsOpen);
        if Result = 0 then
          Result := Ord(Entries[B].Origin = TAtlasUnitOrigin.Active) - Ord(Entries[A].Origin = TAtlasUnitOrigin.Active);
        // Dann die Reihenfolge der Einträge (FromJson sortiert nach Name und Datei).
        if Result = 0 then
          Result := A - B;
      end));
    Result := List.ToArray;
  finally
    List.Free;
  end;
end;

/// <summary>Ordner mit „\“ am Ende (das Plugin läuft nur unter Windows).</summary>
function WithSlash(const AFolder: string): string;
begin
  Result := AFolder;
  if (Result <> '') and not Result.EndsWith('\') then
    Result := Result + '\';
end;

function WithoutSlash(const AFolder: string): string;
begin
  Result := AFolder;
  while (Length(Result) > 3) and Result.EndsWith('\') do
    SetLength(Result, Length(Result) - 1);
end;

function RelativeTo(const AFileName, ARoot: string): string;
var
  Root: string;
begin
  Root := WithSlash(ARoot);
  if (ARoot <> '') and StartsText(Root, AFileName) then
    Result := Copy(AFileName, Length(Root) + 1, MaxInt)
  else
    Result := AFileName;
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

class function TAtlasUnitSearch.Rows(const AEntries: TAtlasUnitEntries; const AOrder: TArray<Integer>;
  AGrouping: TAtlasUnitGrouping; const ARoot, AActiveProject: string; const ACollapsed: TArray<string>;
  ASearching: Boolean): TAtlasUnitRows;
var
  Groups: TObjectDictionary<string, TList<Integer>>;
  Keys: TList<string>;
  Index: Integer;
  Key: string;
  Members: TList<Integer>;
  Row: TAtlasUnitRow;
  Collapsed: Boolean;
  List: TList<TAtlasUnitRow>;
  Active, Root, Lower, Name: string;
  Slash: Integer;
begin
  if AGrouping = TAtlasUnitGrouping.None then
  begin
    SetLength(Result, Length(AOrder));
    for Index := 0 to High(AOrder) do
    begin
      Result[Index] := Default(TAtlasUnitRow);
      Result[Index].Entry := AOrder[Index];
    end;
    Exit;
  end;
  Active := AActiveProject;
  Groups := TObjectDictionary<string, TList<Integer>>.Create([doOwnsValues]);
  Keys := TList<string>.Create;
  List := TList<TAtlasUnitRow>.Create;
  try
    // Reihenfolge der ersten Treffer = beste Gruppe zuerst. Wie GroupOf, aber ohne Kopien je Eintrag,
    // weil Rows bei jedem Tastendruck läuft.
    Root := WithSlash(ARoot);
    for Index in AOrder do
    begin
      if AGrouping = TAtlasUnitGrouping.Project then
        Key := AEntries[Index].Project
      else
      begin
        Name := AEntries[Index].FileName;
        Slash := LastDelimiter('\', Name);
        if (ARoot <> '') and (Length(Name) > Length(Root)) and StartsText(Root, Name) then
          Key := Copy(Name, Length(Root) + 1, Slash - Length(Root) - 1)
        else
          Key := Copy(Name, 1, Slash - 1);
      end;
      Lower := LowerCase(Key);
      if not Groups.TryGetValue(Lower, Members) then
      begin
        Members := TList<Integer>.Create;
        Groups.Add(Lower, Members);
        Keys.Add(Key);
      end;
      Members.Add(Index);
    end;
    if not ASearching then
      Keys.Sort(TComparer<string>.Construct(
        function(const A, B: string): Integer
        begin
          // Aktives Projekt oben, Einträge ohne Gruppe unten, sonst alphabetisch.
          Result := Ord(SameText(B, Active)) - Ord(SameText(A, Active));
          if Result = 0 then
            Result := Ord(A = '') - Ord(B = '');
          if Result = 0 then
            Result := CompareText(A, B);
        end));
    for Key in Keys do
    begin
      Members := Groups[LowerCase(Key)];
      Collapsed := Contains(ACollapsed, LowerCase(Key));
      Row := Default(TAtlasUnitRow);
      Row.IsGroup := True;
      Row.Group := Key;
      Row.Count := Members.Count;
      Row.Collapsed := Collapsed;
      Row.Entry := -1;
      List.Add(Row);
      if Collapsed then
        Continue;
      for Index in Members do
      begin
        Row := Default(TAtlasUnitRow);
        Row.Group := Key;
        Row.Entry := Index;
        List.Add(Row);
      end;
    end;
    Result := List.ToArray;
  finally
    List.Free;
    Keys.Free;
    Groups.Free;
  end;
end;

class function TAtlasUnitSearch.MiddleEllipsis(const AText: string; AMax: Integer): string;
var
  Head, Tail: Integer;
begin
  if (AMax <= 0) or (Length(AText) <= AMax) then
    Exit(AText);
  if AMax <= 1 then
    Exit('…');
  // Das Ende unterscheidet (Dateiname, letzter Ordner) und bekommt etwas mehr Platz.
  Tail := (AMax - 1 + 1) div 2;
  Head := AMax - 1 - Tail;
  Result := Copy(AText, 1, Head) + '…' + Copy(AText, Length(AText) - Tail + 1, Tail);
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
  FileName, Folder: string;
begin
  Result := '';
  for FileName in AFiles do
  begin
    Folder := Copy(FileName, 1, LastDelimiter('\', FileName));
    if Result = '' then
    begin
      Result := Folder;
      Continue;
    end;
    while (Result <> '') and not StartsText(Result, Folder) do
    begin
      Result := Copy(Result, 1, Length(Result) - 1);
      Result := Copy(Result, 1, LastDelimiter('\', Result));
    end;
  end;
  Result := WithoutSlash(Result);
end;

class procedure TAtlasUnitSearch.SortByName(var AEntries: TAtlasUnitEntries);
var
  Index: Integer;
begin
  for Index := 0 to High(AEntries) do
    AEntries[Index].UpperName := AEntries[Index].Name.ToUpper;
  TArray.Sort<TAtlasUnitEntry>(AEntries, TComparer<TAtlasUnitEntry>.Construct(
    function(const A, B: TAtlasUnitEntry): Integer
    begin
      Result := CompareText(A.Name, B.Name);
      if Result = 0 then
        Result := CompareText(A.FileName, B.FileName);
    end));
end;

end.
