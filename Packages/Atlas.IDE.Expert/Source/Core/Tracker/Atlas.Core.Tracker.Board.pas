unit Atlas.Core.Tracker.Board;

// Board des Issue-Trackers (#1272), ohne VCL und Open Tools API.
// - Stand einer Abfrage (TAtlasBoardSnapshot): Boards zur Auswahl, das
//   gezeigte Board mit seinen Spalten (Werte des Spaltenfeldes je Spalte, wie
//   auf dem Board des Servers), Sprints, Karten und der eigene Anmeldename.
// - Zuordnung Zustand → Spalte über die Werte der Spalten (ohne Groß- und
//   Kleinschreibung); Karten ohne passende Spalte stehen unter -1.
// - Filter „Nur meine“ und Suche (Kennung, Titel, Zuständig; lokal).
// - Kürzel der Zuständigen ("Marco Bähring" → "MB"), Stufe der Priorität für
//   den Farbbalken, wenn der Tracker keine Farbe liefert.
// - Zwischenspeicher als JSON („Stand vom …“ ohne Netz): eine Datei je Tracker
//   im Ordner der Issue-Vorschau.
// Netz und Schreiben liegen beim Anbieter (IAtlasTrackerBoards); der Wechsel
// des Zustands nutzt dessen Schreibweg (#1266).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.Tracker.Contract,
  Atlas.Core.Tracker.Checklist;

type
{$SCOPEDENUMS ON}
  /// <summary>Herkunft des Boards: YouTrack-Agile-Board, GitHub-Projekt (v2) oder GitHub ohne Projekt
  /// (Spalten Offen und Geschlossen).</summary>
  TAtlasBoardKind = (Agile, Project, Repository);
{$SCOPEDENUMS OFF}

  /// <summary>Spalte eines Boards.</summary>
  TAtlasBoardColumn = record
    /// <summary>Beschriftung wie auf dem Board des Servers ("In Arbeit", "Zur Prüfung").</summary>
    Name: string;
    /// <summary>Werte des Spaltenfeldes, die in diese Spalte fallen; der erste wird beim Verschieben gesetzt.
    /// </summary>
    Values: TArray<string>;
    /// <summary>GitHub-Projekt: ID der Option des Feldes „Status“; sonst ''.</summary>
    OptionId: string;
    /// <summary>Spalte für erledigte Issues.</summary>
    Resolved: Boolean;
    class function Create(const AName: string; const AValues: TArray<string>; const AOptionId: string;
      AResolved: Boolean): TAtlasBoardColumn; static;
  end;

  /// <summary>Sprint bzw. Iteration.</summary>
  TAtlasBoardSprint = record
    Id: string;
    Name: string;
    /// <summary>UTC; 0 = unbekannt.</summary>
    Start: TDateTime;
    Finish: TDateTime;
    Archived: Boolean;
  end;

  /// <summary>Eintrag der Klappliste „Board“.</summary>
  TAtlasBoardRef = record
    Id: string;
    Name: string;
    class function Create(const AId, AName: string): TAtlasBoardRef; static;
  end;

  /// <summary>Karte je Issue.</summary>
  TAtlasBoardCard = record
  public const
    MaxTitle = 300;
  public
    /// <summary>"ATL-123" bzw. "#753"; aus einem anderen Repository "owner/repo#12".</summary>
    Key: string;
    Number: Integer;
    Title: string;
    /// <summary>Wert des Spaltenfeldes ("In Arbeit"; GitHub ohne Projekt "open"/"closed").</summary>
    State: string;
    /// <summary>Anzeigename der (ersten) Zuständigen; '' ohne.</summary>
    Assignee: string;
    /// <summary>Anmeldenamen aller Zuständigen.</summary>
    Logins: TArray<string>;
    Priority: string;
    /// <summary>Farbe der Priorität vom Tracker ("#e30000"); '' ohne.</summary>
    PriorityColor: string;
    /// <summary>Checkliste der Beschreibung (#1273).</summary>
    Checklist: TAtlasChecklistProgress;
    /// <summary>Ein offenes „hängt ab von“-Issue blockiert die Karte (#1279).</summary>
    Locked: Boolean;
    /// <summary>GitHub-Projekt: ID des Eintrags im Projekt; sonst ''.</summary>
    ItemId: string;
    /// <summary>Seite im Browser.</summary>
    Page: string;
    /// <summary>Für „Beginnen“ und die Vorschau.</summary>
    function Issue: TAtlasTrackerIssue;
  end;

  /// <summary>Stand eines Boards zu einem Zeitpunkt.</summary>
  TAtlasBoardSnapshot = record
  public const
    /// <summary>Höchstens so viele Karten werden gelesen.</summary>
    MaxCards = 300;
    /// <summary>Höchstens so viele Boards bzw. Sprints für die Klapplisten.</summary>
    MaxBoards = 50;
    MaxSprints = 50;
    /// <summary>Version des Zwischenspeichers.</summary>
    Version = 1;
  public
    Kind: TAtlasBoardKind;
    /// <summary>Boards bzw. Projekte zur Auswahl.</summary>
    Boards: TArray<TAtlasBoardRef>;
    /// <summary>Das gezeigte Board; Id '' ohne Board (GitHub ohne Projekt).</summary>
    Board: TAtlasBoardRef;
    /// <summary>Name des Spaltenfeldes ("State", "Status").</summary>
    Field: string;
    /// <summary>GitHub-Projekt: IDs von Projekt und Feld „Status“ für die Änderung.</summary>
    ProjectId: string;
    FieldId: string;
    Columns: TArray<TAtlasBoardColumn>;
    Sprints: TArray<TAtlasBoardSprint>;
    /// <summary>Gezeigter Sprint; Id '' ohne Sprints.</summary>
    Sprint: TAtlasBoardSprint;
    Cards: TArray<TAtlasBoardCard>;
    /// <summary>Anmeldename beim Tracker; '' unbekannt (dann filtert „Nur meine“ nicht).</summary>
    Me: string;
    /// <summary>GitHub: Projekte durften nicht gelesen werden (Token ohne „read:project“); das Board zeigt
    /// Offen/Geschlossen. Nicht im Zwischenspeicher.</summary>
    ProjectsDenied: Boolean;
    /// <summary>Zeitpunkt der Abfrage (UTC); für „Stand vom …“.</summary>
    Fetched: TDateTime;
    class function Empty: TAtlasBoardSnapshot; static;
    /// <summary>Spalte, in die AState fällt; -1 ohne.</summary>
    function ColumnOf(const AState: string): Integer;
    /// <summary>Karte mit der Kennung AKey; -1 ohne.</summary>
    function CardIndex(const AKey: string): Integer;
    /// <summary>Spalte der Karte ACard; -1 ohne.</summary>
    function CardColumn(ACard: Integer): Integer;
  end;

  /// <summary>Board lesen und Karten verschieben (#1272); optional neben IAtlasTrackerProvider. Im Hintergrund;
  /// zum Verschieben muss ATransport IAtlasCiSend können.</summary>
  IAtlasTrackerBoards = interface
    ['{4E7B2A93-5C1D-4F68-A0E2-9B3D6C8F1A57}']
    /// <summary>Board ABoardId ('' = das erste zum Projekt des Ziels) mit Sprint ASprintId ('' = aktueller) und
    /// dessen Karten, insgesamt höchstens ATimeoutMs. False mit AError, wenn nichts gelesen werden konnte.
    /// </summary>
    function LoadBoard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    /// <summary>ACard in die Spalte AColumn von ASnapshot verschieben, mit Kommentar AComment ('' = keiner).
    /// YouTrack: ein Befehl; GitHub: Kommentar, dann Feld „Status“ bzw. Zustand des Issues.</summary>
    function MoveCard(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ASnapshot: TAtlasBoardSnapshot; const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string;
      ATimeoutMs: Integer): TAtlasTrackerWriteResult;
  end;

  TAtlasTrackerBoard = class
  public const
    /// <summary>Zeitgrenze einer Abfrage des Boards.</summary>
    TimeoutMs = 10000;
    /// <summary>Zeitgrenze beim Verschieben.</summary>
    MoveTimeoutMs = 15000;
    /// <summary>Schmaler als so viele Pixel (bei 96 dpi): Spalten untereinander als einklappbare Gruppen.</summary>
    NarrowWidth = 360;
  public
    /// <summary>Kürzel aus einem Namen: Anfangsbuchstaben der ersten beiden Wörter ("Marco Bähring" → "MB"),
    /// bei einem Wort die ersten zwei Buchstaben ("anna" → "AN"); '' ohne Namen.</summary>
    class function Initials(const AName: string): string; static;
    /// <summary>Stufe der Priorität aus dem Namen: 4 kritisch, 3 hoch, 2 normal, 1 niedrig, 0 unbekannt (deutsche
    /// und englische Werte von YouTrack und GitHub).</summary>
    class function PriorityLevel(const APriority: string): Integer; static;
    /// <summary>ACard ist AMe zugewiesen; mit AMe = '' immer True (unbekannt, nicht filtern).</summary>
    class function Mine(const ACard: TAtlasBoardCard; const AMe: string): Boolean; static;
    /// <summary>ASearch (ohne Groß-/Kleinschreibung, Wörter mit Leerzeichen, alle müssen passen) kommt in Kennung,
    /// Titel oder Zuständig vor; '' passt immer.</summary>
    class function Matches(const ACard: TAtlasBoardCard; const ASearch: string): Boolean; static;
    /// <summary>Nummern der Karten, die nach „Nur meine“ und Suche sichtbar sind, in der Reihenfolge des Boards.
    /// </summary>
    class function Visible(const ASnapshot: TAtlasBoardSnapshot; AOnlyMine: Boolean;
      const ASearch: string): TArray<Integer>; static;
    /// <summary>Aus AVisible die Karten der Spalte AColumn (-1 = ohne Spalte).</summary>
    class function ColumnCards(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
      AColumn: Integer): TArray<Integer>; static;
    /// <summary>Karte ACard darf nach AColumn: andere Spalte mit einem Wert bzw. einer Option.</summary>
    class function CanMove(const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean; static;
    /// <summary>Sprint, der ANow (UTC) enthält; sonst der nächste künftige; sonst der letzte; -1 ohne Sprints.
    /// </summary>
    class function CurrentSprint(const ASprints: TArray<TAtlasBoardSprint>; ANow: TDateTime): Integer; static;
    class function KindKey(AKind: TAtlasBoardKind): string; static;
    class function KindOf(const AKey: string): TAtlasBoardKind; static;
    class function ToJson(const ASnapshot: TAtlasBoardSnapshot): string; static;
    /// <summary>False bei ungültigem JSON oder anderer Version.</summary>
    class function FromJson(const AJson: string; out ASnapshot: TAtlasBoardSnapshot): Boolean; static;
    /// <summary>Datei des Zwischenspeichers für ATarget in AFolder: "&lt;TrackerId&gt;-board.json"; '' ohne Ordner.
    /// </summary>
    class function CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget): string; static;
    /// <summary>ASnapshot als letzten Stand von ATarget merken; Fehler beim Schreiben werden übergangen.</summary>
    class procedure Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      const ASnapshot: TAtlasBoardSnapshot); static;
    /// <summary>Letzter Stand von ATarget; False ohne (lesbare) Datei.</summary>
    class function Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      out ASnapshot: TAtlasBoardSnapshot): Boolean; static;
  end;

implementation

uses
  System.Character,
  System.DateUtils,
  System.Generics.Collections,
  System.IOUtils,
  System.JSON,
  Atlas.Core.Tracker.IssueCache;

{ TAtlasBoardColumn }

class function TAtlasBoardColumn.Create(const AName: string; const AValues: TArray<string>; const AOptionId: string;
  AResolved: Boolean): TAtlasBoardColumn;
begin
  Result.Name := AName;
  Result.Values := AValues;
  Result.OptionId := AOptionId;
  Result.Resolved := AResolved;
end;

{ TAtlasBoardRef }

class function TAtlasBoardRef.Create(const AId, AName: string): TAtlasBoardRef;
begin
  Result.Id := AId;
  Result.Name := AName;
end;

{ TAtlasBoardCard }

function TAtlasBoardCard.Issue: TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := Key;
  Result.Number := Number;
  Result.Title := Copy(Title, 1, TAtlasTrackerIssue.MaxTitle);
  Result.State := State;
  Result.Priority := Priority;
end;

{ TAtlasBoardSnapshot }

class function TAtlasBoardSnapshot.Empty: TAtlasBoardSnapshot;
begin
  Result := Default(TAtlasBoardSnapshot);
end;

function TAtlasBoardSnapshot.ColumnOf(const AState: string): Integer;
var
  mColumn: Integer;
  mValue, mState: string;
begin
  Result := -1;
  mState := Trim(AState);
  if mState = '' then
    Exit;
  for mColumn := 0 to High(Columns) do
    for mValue in Columns[mColumn].Values do
      if SameText(Trim(mValue), mState) then
        Exit(mColumn);
end;

function TAtlasBoardSnapshot.CardIndex(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Cards) do
    if SameText(Cards[mIndex].Key, Trim(AKey)) then
      Exit(mIndex);
  Result := -1;
end;

function TAtlasBoardSnapshot.CardColumn(ACard: Integer): Integer;
begin
  Result := -1;
  if (ACard >= 0) and (ACard <= High(Cards)) then
    Result := ColumnOf(Cards[ACard].State);
end;

{ TAtlasTrackerBoard }

function IsLetter(AChar: Char): Boolean;
begin
  Result := AChar.IsLetterOrDigit;
end;

class function TAtlasTrackerBoard.Initials(const AName: string): string;
var
  mWords: TArray<string>;
  mWord, mText: string;
  mIndex: Integer;
begin
  Result := '';
  mText := Trim(AName);
  // "Marco B. (mb)": nur der Name; Anmeldenamen mit Punkt oder Unterstrich als Wörter.
  mIndex := Pos('(', mText);
  if mIndex > 1 then
    mText := Trim(Copy(mText, 1, mIndex - 1));
  mText := StringReplace(StringReplace(StringReplace(mText, '.', ' ', [rfReplaceAll]), '_', ' ', [rfReplaceAll]), '-',
    ' ', [rfReplaceAll]);
  mWords := nil;
  for mWord in mText.Split([' ', #9]) do
    if (mWord <> '') and IsLetter(mWord[1]) then
      mWords := mWords + [mWord];
  if Length(mWords) = 0 then
    Exit;
  if Length(mWords) = 1 then
  begin
    Result := mWords[0][1];
    if (Length(mWords[0]) > 1) and IsLetter(mWords[0][2]) then
      Result := Result + mWords[0][2];
  end
  else
    Result := mWords[0][1] + mWords[1][1];
  Result := UpperCase(Result);
end;

function NameIn(const AName: string; const ANames: array of string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
    if SameText(AName, mName) then
      Exit(True);
end;

class function TAtlasTrackerBoard.PriorityLevel(const APriority: string): Integer;
var
  mName: string;
begin
  mName := Trim(APriority);
  // GitHub-Projekte: "P0" … "P3"; Labels "priority:high".
  if Pos(':', mName) > 0 then
    mName := Trim(Copy(mName, Pos(':', mName) + 1, MaxInt));
  if NameIn(mName, ['Show-stopper', 'Critical', 'Kritisch', 'Blocker', 'Urgent', 'Dringend', 'P0']) then
    Result := 4
  else if NameIn(mName, ['Major', 'High', 'Hoch', 'Wichtig', 'P1']) then
    Result := 3
  else if NameIn(mName, ['Normal', 'Medium', 'Mittel', 'P2']) then
    Result := 2
  else if NameIn(mName, ['Minor', 'Low', 'Niedrig', 'Gering', 'Trivial', 'P3', 'P4']) then
    Result := 1
  else
    Result := 0;
end;

class function TAtlasTrackerBoard.Mine(const ACard: TAtlasBoardCard; const AMe: string): Boolean;
var
  mLogin: string;
begin
  Result := Trim(AMe) = '';
  if Result then
    Exit;
  for mLogin in ACard.Logins do
    if SameText(Trim(mLogin), Trim(AMe)) then
      Exit(True);
end;

class function TAtlasTrackerBoard.Matches(const ACard: TAtlasBoardCard; const ASearch: string): Boolean;
var
  mText, mWord: string;
begin
  Result := True;
  mText := LowerCase(ACard.Key + ' ' + ACard.Title + ' ' + ACard.Assignee + ' ' + string.Join(' ', ACard.Logins));
  for mWord in LowerCase(Trim(ASearch)).Split([' ', #9]) do
    if (mWord <> '') and (Pos(mWord, mText) = 0) then
      Exit(False);
end;

class function TAtlasTrackerBoard.Visible(const ASnapshot: TAtlasBoardSnapshot; AOnlyMine: Boolean;
  const ASearch: string): TArray<Integer>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to High(ASnapshot.Cards) do
  begin
    if AOnlyMine and not Mine(ASnapshot.Cards[mIndex], ASnapshot.Me) then
      Continue;
    if not Matches(ASnapshot.Cards[mIndex], ASearch) then
      Continue;
    Result := Result + [mIndex];
  end;
end;

class function TAtlasTrackerBoard.ColumnCards(const ASnapshot: TAtlasBoardSnapshot; const AVisible: TArray<Integer>;
  AColumn: Integer): TArray<Integer>;
var
  mCard: Integer;
begin
  Result := nil;
  for mCard in AVisible do
    if ASnapshot.CardColumn(mCard) = AColumn then
      Result := Result + [mCard];
end;

class function TAtlasTrackerBoard.CanMove(const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean;
begin
  Result := (ACard >= 0) and (ACard <= High(ASnapshot.Cards)) and (AColumn >= 0) and
    (AColumn <= High(ASnapshot.Columns)) and (ASnapshot.CardColumn(ACard) <> AColumn);
  if not Result then
    Exit;
  case ASnapshot.Kind of
    TAtlasBoardKind.Project:
      Result := (ASnapshot.Columns[AColumn].OptionId <> '') and (ASnapshot.Cards[ACard].ItemId <> '');
  else
    Result := Length(ASnapshot.Columns[AColumn].Values) > 0;
  end;
end;

class function TAtlasTrackerBoard.CurrentSprint(const ASprints: TArray<TAtlasBoardSprint>; ANow: TDateTime): Integer;
var
  mIndex, mNext: Integer;
begin
  Result := -1;
  mNext := -1;
  for mIndex := 0 to High(ASprints) do
  begin
    if (ASprints[mIndex].Start > 0) and (ASprints[mIndex].Start <= ANow) and
      ((ASprints[mIndex].Finish = 0) or (ANow < ASprints[mIndex].Finish)) then
      Exit(mIndex);
    if (ASprints[mIndex].Start > ANow) and ((mNext < 0) or (ASprints[mIndex].Start < ASprints[mNext].Start)) then
      mNext := mIndex;
  end;
  if mNext >= 0 then
    Exit(mNext);
  Result := High(ASprints);
end;

{ JSON }

class function TAtlasTrackerBoard.KindKey(AKind: TAtlasBoardKind): string;
begin
  case AKind of
    TAtlasBoardKind.Project:
      Result := 'project';
    TAtlasBoardKind.Repository:
      Result := 'repository';
  else
    Result := 'agile';
  end;
end;

class function TAtlasTrackerBoard.KindOf(const AKey: string): TAtlasBoardKind;
begin
  if SameText(AKey, 'project') then
    Result := TAtlasBoardKind.Project
  else if SameText(AKey, 'repository') then
    Result := TAtlasBoardKind.Repository
  else
    Result := TAtlasBoardKind.Agile;
end;

function TimeText(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
    Result := DateToISO8601(AValue, True);
end;

function TimeValue(const AText: string): TDateTime;
begin
  Result := 0;
  if (AText = '') or not TryISO8601ToDate(AText, Result, True) then
    Result := 0;
end;

function Texts(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
    Result.Add(mItem);
end;

function SprintJson(const ASprint: TAtlasBoardSprint): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', ASprint.Id);
  Result.AddPair('name', ASprint.Name);
  Result.AddPair('start', TimeText(ASprint.Start));
  Result.AddPair('finish', TimeText(ASprint.Finish));
  Result.AddPair('archived', TJSONBool.Create(ASprint.Archived));
end;

class function TAtlasTrackerBoard.ToJson(const ASnapshot: TAtlasBoardSnapshot): string;
var
  mRoot, mItem: TJSONObject;
  mList: TJSONArray;
  mBoard: TAtlasBoardRef;
  mColumn: TAtlasBoardColumn;
  mSprint: TAtlasBoardSprint;
  mCard: TAtlasBoardCard;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(TAtlasBoardSnapshot.Version));
    mRoot.AddPair('kind', KindKey(ASnapshot.Kind));
    mRoot.AddPair('fetched', TimeText(ASnapshot.Fetched));
    mRoot.AddPair('me', ASnapshot.Me);
    mRoot.AddPair('boardId', ASnapshot.Board.Id);
    mRoot.AddPair('boardName', ASnapshot.Board.Name);
    mRoot.AddPair('field', ASnapshot.Field);
    mRoot.AddPair('projectId', ASnapshot.ProjectId);
    mRoot.AddPair('fieldId', ASnapshot.FieldId);
    mList := TJSONArray.Create;
    for mBoard in ASnapshot.Boards do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('id', mBoard.Id);
      mItem.AddPair('name', mBoard.Name);
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('boards', mList);
    mList := TJSONArray.Create;
    for mColumn in ASnapshot.Columns do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('name', mColumn.Name);
      mItem.AddPair('values', Texts(mColumn.Values));
      mItem.AddPair('optionId', mColumn.OptionId);
      mItem.AddPair('resolved', TJSONBool.Create(mColumn.Resolved));
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('columns', mList);
    mList := TJSONArray.Create;
    for mSprint in ASnapshot.Sprints do
      mList.AddElement(SprintJson(mSprint));
    mRoot.AddPair('sprints', mList);
    mRoot.AddPair('sprint', SprintJson(ASnapshot.Sprint));
    mList := TJSONArray.Create;
    for mCard in ASnapshot.Cards do
    begin
      mItem := TJSONObject.Create;
      mItem.AddPair('key', mCard.Key);
      mItem.AddPair('number', TJSONNumber.Create(mCard.Number));
      mItem.AddPair('title', mCard.Title);
      mItem.AddPair('state', mCard.State);
      mItem.AddPair('assignee', mCard.Assignee);
      mItem.AddPair('logins', Texts(mCard.Logins));
      mItem.AddPair('priority', mCard.Priority);
      mItem.AddPair('priorityColor', mCard.PriorityColor);
      mItem.AddPair('done', TJSONNumber.Create(mCard.Checklist.Done));
      mItem.AddPair('total', TJSONNumber.Create(mCard.Checklist.Total));
      mItem.AddPair('locked', TJSONBool.Create(mCard.Locked));
      mItem.AddPair('itemId', mCard.ItemId);
      mItem.AddPair('page', mCard.Page);
      mList.AddElement(mItem);
    end;
    mRoot.AddPair('cards', mList);
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
end;

function TextOf(AObject: TJSONObject; const AName: string): string;
var
  mValue: TJSONValue;
begin
  Result := '';
  mValue := AObject.Values[AName];
  if mValue is TJSONString then
    Result := TJSONString(mValue).Value;
end;

function IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if (mValue is TJSONNumber) and not TryStrToInt(TJSONNumber(mValue).Value, Result) then
    Result := 0;
end;

function FlagOf(AObject: TJSONObject; const AName: string): Boolean;
var
  mValue: TJSONValue;
begin
  mValue := AObject.Values[AName];
  Result := (mValue is TJSONBool) and TJSONBool(mValue).AsBoolean;
end;

function TextsOf(AObject: TJSONObject; const AName: string): TArray<string>;
var
  mValue, mItem: TJSONValue;
begin
  Result := nil;
  mValue := AObject.Values[AName];
  if mValue is TJSONArray then
    for mItem in TJSONArray(mValue) do
      if mItem is TJSONString then
        Result := Result + [TJSONString(mItem).Value];
end;

function SprintOf(AValue: TJSONValue): TAtlasBoardSprint;
var
  mObject: TJSONObject;
begin
  Result := Default(TAtlasBoardSprint);
  if not (AValue is TJSONObject) then
    Exit;
  mObject := TJSONObject(AValue);
  Result.Id := TextOf(mObject, 'id');
  Result.Name := TextOf(mObject, 'name');
  Result.Start := TimeValue(TextOf(mObject, 'start'));
  Result.Finish := TimeValue(TextOf(mObject, 'finish'));
  Result.Archived := FlagOf(mObject, 'archived');
end;

class function TAtlasTrackerBoard.FromJson(const AJson: string; out ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue, mItem: TJSONValue;
  mRoot, mObject: TJSONObject;
  mColumn: TAtlasBoardColumn;
  mCard: TAtlasBoardCard;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
      Exit;
    mRoot := TJSONObject(mValue);
    if IntOf(mRoot, 'version') <> TAtlasBoardSnapshot.Version then
      Exit;
    ASnapshot.Kind := KindOf(TextOf(mRoot, 'kind'));
    ASnapshot.Fetched := TimeValue(TextOf(mRoot, 'fetched'));
    ASnapshot.Me := TextOf(mRoot, 'me');
    ASnapshot.Board := TAtlasBoardRef.Create(TextOf(mRoot, 'boardId'), TextOf(mRoot, 'boardName'));
    ASnapshot.Field := TextOf(mRoot, 'field');
    ASnapshot.ProjectId := TextOf(mRoot, 'projectId');
    ASnapshot.FieldId := TextOf(mRoot, 'fieldId');
    if mRoot.Values['boards'] is TJSONArray then
      for mItem in TJSONArray(mRoot.Values['boards']) do
        if mItem is TJSONObject then
          ASnapshot.Boards := ASnapshot.Boards + [TAtlasBoardRef.Create(TextOf(TJSONObject(mItem), 'id'),
            TextOf(TJSONObject(mItem), 'name'))];
    if mRoot.Values['columns'] is TJSONArray then
      for mItem in TJSONArray(mRoot.Values['columns']) do
        if mItem is TJSONObject then
        begin
          mObject := TJSONObject(mItem);
          mColumn := TAtlasBoardColumn.Create(TextOf(mObject, 'name'), TextsOf(mObject, 'values'),
            TextOf(mObject, 'optionId'), FlagOf(mObject, 'resolved'));
          ASnapshot.Columns := ASnapshot.Columns + [mColumn];
        end;
    if mRoot.Values['sprints'] is TJSONArray then
      for mItem in TJSONArray(mRoot.Values['sprints']) do
        ASnapshot.Sprints := ASnapshot.Sprints + [SprintOf(mItem)];
    ASnapshot.Sprint := SprintOf(mRoot.Values['sprint']);
    if mRoot.Values['cards'] is TJSONArray then
      for mItem in TJSONArray(mRoot.Values['cards']) do
      begin
        if not (mItem is TJSONObject) then
          Continue;
        mObject := TJSONObject(mItem);
        mCard := Default(TAtlasBoardCard);
        mCard.Key := TextOf(mObject, 'key');
        mCard.Number := IntOf(mObject, 'number');
        mCard.Title := TextOf(mObject, 'title');
        mCard.State := TextOf(mObject, 'state');
        mCard.Assignee := TextOf(mObject, 'assignee');
        mCard.Logins := TextsOf(mObject, 'logins');
        mCard.Priority := TextOf(mObject, 'priority');
        mCard.PriorityColor := TextOf(mObject, 'priorityColor');
        mCard.Checklist := TAtlasChecklistProgress.Create(IntOf(mObject, 'done'), IntOf(mObject, 'total'));
        mCard.Locked := FlagOf(mObject, 'locked');
        mCard.ItemId := TextOf(mObject, 'itemId');
        mCard.Page := TextOf(mObject, 'page');
        if (mCard.Key <> '') and (Length(ASnapshot.Cards) < TAtlasBoardSnapshot.MaxCards) then
          ASnapshot.Cards := ASnapshot.Cards + [mCard];
      end;
    Result := True;
  finally
    mValue.Free;
  end;
end;

{ Zwischenspeicher }

class function TAtlasTrackerBoard.CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget): string;
begin
  Result := '';
  if (AFolder <> '') and (ATarget.Server <> '') then
    Result := TPath.Combine(AFolder, TAtlasTrackerIssueCache.TrackerId(ATarget) + '-board.json');
end;

class procedure TAtlasTrackerBoard.Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ASnapshot: TAtlasBoardSnapshot);
var
  mFile: string;
begin
  mFile := CacheFile(AFolder, ATarget);
  if mFile = '' then
    Exit;
  try
    TDirectory.CreateDirectory(AFolder);
    TFile.WriteAllText(mFile, ToJson(ASnapshot), TEncoding.UTF8);
  except
    // Kein Platz, keine Rechte: Das Board zeigt ohne Netz dann eben nichts.
    on Exception do
      Exit;
  end;
end;

class function TAtlasTrackerBoard.Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  out ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mFile, mText: string;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  Result := False;
  mFile := CacheFile(AFolder, ATarget);
  if (mFile = '') or not TFile.Exists(mFile) then
    Exit;
  try
    mText := TFile.ReadAllText(mFile, TEncoding.UTF8);
  except
    // Gesperrte oder kaputte Datei: als fehlend werten.
    on Exception do
      Exit;
  end;
  Result := FromJson(mText, ASnapshot);
end;

end.
