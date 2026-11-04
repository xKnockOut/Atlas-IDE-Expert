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
//   im Ordner der Issue-Vorschau; die Sprint-Kachel (#1277) legt mit eigenem
//   Namen daneben ab.
// - Für den Burndown (#1277) trägt jede Karte den Zeitpunkt der Erledigung und
//   die Schätzung aus dem Schätzfeld des Boards (PointsField).
// Netz und Schreiben liegen beim Anbieter (IAtlasTrackerBoards); der Wechsel
// des Zustands nutzt dessen Schreibweg (#1266).

interface

uses
  System.SysUtils,
  Atlas.Core.Ci.Contract,
  Atlas.Core.CiBuild.Contract,
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
    /// <summary>Erledigt seit (UTC, #1277); 0 = offen bzw. unbekannt.</summary>
    ResolvedAt: TDateTime;
    /// <summary>Schätzung aus dem Schätzfeld des Boards (#1277); nur mit HasPoints.</summary>
    Points: Double;
    HasPoints: Boolean;
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
    /// <summary>Schätzfeld des Boards ("Story points", "Estimate"); '' ohne Schätzung (#1277).</summary>
    PointsField: string;
    /// <summary>Board im Browser (#1277); '' unbekannt.</summary>
    Page: string;
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
    class function CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget): string; overload; static;
    /// <summary>Wie oben mit eigenem Namen: "&lt;TrackerId&gt;-&lt;AName&gt;.json" (AName nur Buchstaben, Ziffern,
    /// '-' und '_'); '' ohne Ordner oder bei anderem Namen.</summary>
    class function CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      const AName: string): string; overload; static;
    /// <summary>ASnapshot als letzten Stand von ATarget merken; Fehler beim Schreiben werden übergangen.</summary>
    class procedure Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      const ASnapshot: TAtlasBoardSnapshot); overload; static;
    class procedure Save(const AFolder: string; const ATarget: TAtlasTrackerTarget; const AName: string;
      const ASnapshot: TAtlasBoardSnapshot); overload; static;
    /// <summary>Letzter Stand von ATarget; False ohne (lesbare) Datei.</summary>
    class function Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
      out ASnapshot: TAtlasBoardSnapshot): Boolean; overload; static;
    class function Load(const AFolder: string; const ATarget: TAtlasTrackerTarget; const AName: string;
      out ASnapshot: TAtlasBoardSnapshot): Boolean; overload; static;
    /// <summary>Text in AFile schreiben bzw. lesen, Fehler übergangen ('' bzw. False); für die Sprint-Kachel.
    /// </summary>
    class procedure WriteText(const AFile, AText: string); static;
    class function ReadText(const AFile: string; out AText: string): Boolean; static;
    /// <summary>Zeit als ISO 8601 (UTC) bzw. zurück; '' bzw. 0 ohne.</summary>
    class function TimeText(AValue: TDateTime): string; static;
    class function TimeValue(const AText: string): TDateTime; static;
  end;

implementation

uses
  System.Character,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Tracker.Files,
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
  begin
    Exit;
  end;
  for mColumn := 0 to High(Columns) do
  begin
    for mValue in Columns[mColumn].Values do
    begin
      if SameText(Trim(mValue), mState) then
      begin
        Exit(mColumn);
      end;
    end;
  end;
end;

function TAtlasBoardSnapshot.CardIndex(const AKey: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(Cards) do
  begin
    if SameText(Cards[mIndex].Key, Trim(AKey)) then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

function TAtlasBoardSnapshot.CardColumn(ACard: Integer): Integer;
begin
  Result := -1;
  if (ACard >= 0) and (ACard <= High(Cards)) then
  begin
    Result := ColumnOf(Cards[ACard].State);
  end;
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
  begin
    mText := Trim(Copy(mText, 1, mIndex - 1));
  end;
  mText := StringReplace(StringReplace(StringReplace(mText, '.', ' ', [rfReplaceAll]), '_', ' ', [rfReplaceAll]), '-',
    ' ', [rfReplaceAll]);
  mWords := nil;
  for mWord in mText.Split([' ', #9]) do
  begin
    if (mWord <> '') and IsLetter(mWord[1]) then
    begin
      mWords := mWords + [mWord];
    end;
  end;
  if Length(mWords) = 0 then
  begin
    Exit;
  end;
  if Length(mWords) = 1 then
  begin
    Result := mWords[0][1];
    if (Length(mWords[0]) > 1) and IsLetter(mWords[0][2]) then
    begin
      Result := Result + mWords[0][2];
    end;
  end
  else
  begin
    Result := mWords[0][1] + mWords[1][1];
  end;
  Result := UpperCase(Result);
end;

function NameIn(const AName: string; const ANames: array of string): Boolean;
var
  mName: string;
begin
  Result := False;
  for mName in ANames do
  begin
    if SameText(AName, mName) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTrackerBoard.PriorityLevel(const APriority: string): Integer;
var
  mName: string;
begin
  mName := Trim(APriority);
  // GitHub-Projekte: "P0" … "P3"; Labels "priority:high".
  if Pos(':', mName) > 0 then
  begin
    mName := Trim(Copy(mName, Pos(':', mName) + 1, MaxInt));
  end;
  if NameIn(mName, ['Show-stopper', 'Critical', 'Kritisch', 'Blocker', 'Urgent', 'Dringend', 'P0']) then
  begin
    Result := 4;
  end
  else if NameIn(mName, ['Major', 'High', 'Hoch', 'Wichtig', 'P1']) then
  begin
    Result := 3;
  end
  else if NameIn(mName, ['Normal', 'Medium', 'Mittel', 'P2']) then
  begin
    Result := 2;
  end
  else if NameIn(mName, ['Minor', 'Low', 'Niedrig', 'Gering', 'Trivial', 'P3', 'P4']) then
  begin
    Result := 1;
  end
  else
  begin
    Result := 0;
  end;
end;

class function TAtlasTrackerBoard.Mine(const ACard: TAtlasBoardCard; const AMe: string): Boolean;
var
  mLogin: string;
begin
  Result := Trim(AMe) = '';
  if Result then
  begin
    Exit;
  end;
  for mLogin in ACard.Logins do
  begin
    if SameText(Trim(mLogin), Trim(AMe)) then
    begin
      Exit(True);
    end;
  end;
end;

class function TAtlasTrackerBoard.Matches(const ACard: TAtlasBoardCard; const ASearch: string): Boolean;
var
  mText, mWord: string;
begin
  Result := True;
  mText := LowerCase(ACard.Key + ' ' + ACard.Title + ' ' + ACard.Assignee + ' ' + string.Join(' ', ACard.Logins));
  for mWord in LowerCase(Trim(ASearch)).Split([' ', #9]) do
  begin
    if (mWord <> '') and (Pos(mWord, mText) = 0) then
    begin
      Exit(False);
    end;
  end;
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
    begin
      Continue;
    end;
    if not Matches(ASnapshot.Cards[mIndex], ASearch) then
    begin
      Continue;
    end;
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
  begin
    if ASnapshot.CardColumn(mCard) = AColumn then
    begin
      Result := Result + [mCard];
    end;
  end;
end;

class function TAtlasTrackerBoard.CanMove(const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean;
begin
  Result := (ACard >= 0) and (ACard <= High(ASnapshot.Cards)) and (AColumn >= 0) and
    (AColumn <= High(ASnapshot.Columns)) and (ASnapshot.CardColumn(ACard) <> AColumn);
  if not Result then
  begin
    Exit;
  end;
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
  mNext := -1;
  for mIndex := 0 to High(ASprints) do
  begin
    if (ASprints[mIndex].Start > 0) and (ASprints[mIndex].Start <= ANow) and
      ((ASprints[mIndex].Finish = 0) or (ANow < ASprints[mIndex].Finish)) then
    begin
      Exit(mIndex);
    end;
    if (ASprints[mIndex].Start > ANow) and ((mNext < 0) or (ASprints[mIndex].Start < ASprints[mNext].Start)) then
    begin
      mNext := mIndex;
    end;
  end;
  if mNext >= 0 then
  begin
    Exit(mNext);
  end;
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
  begin
    Result := TAtlasBoardKind.Project;
  end
  else if SameText(AKey, 'repository') then
  begin
    Result := TAtlasBoardKind.Repository;
  end
  else
  begin
    Result := TAtlasBoardKind.Agile;
  end;
end;

class function TAtlasTrackerBoard.TimeText(AValue: TDateTime): string;
begin
  Result := '';
  if AValue > 0 then
  begin
    Result := DateToISO8601(AValue, True);
  end;
end;

class function TAtlasTrackerBoard.TimeValue(const AText: string): TDateTime;
begin
  Result := 0;
  if (AText = '') or not TryISO8601ToDate(AText, Result, True) then
  begin
    Result := 0;
  end;
end;

function Texts(const AItems: TArray<string>): TJSONArray;
var
  mItem: string;
begin
  Result := TJSONArray.Create;
  for mItem in AItems do
  begin
    Result.Add(mItem);
  end;
end;

function SprintJson(const ASprint: TAtlasBoardSprint): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('id', ASprint.Id);
  Result.AddPair('name', ASprint.Name);
  Result.AddPair('start', TAtlasTrackerBoard.TimeText(ASprint.Start));
  Result.AddPair('finish', TAtlasTrackerBoard.TimeText(ASprint.Finish));
  Result.AddPair('archived', TJSONBool.Create(ASprint.Archived));
end;

function BoardsJson(const ABoards: TArray<TAtlasBoardRef>): TJSONArray;
var
  mItem: TJSONObject;
  mBoard: TAtlasBoardRef;
begin
  Result := TJSONArray.Create;
  for mBoard in ABoards do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('id', mBoard.Id);
    mItem.AddPair('name', mBoard.Name);
    Result.AddElement(mItem);
  end;
end;

function ColumnsJson(const AColumns: TArray<TAtlasBoardColumn>): TJSONArray;
var
  mItem: TJSONObject;
  mColumn: TAtlasBoardColumn;
begin
  Result := TJSONArray.Create;
  for mColumn in AColumns do
  begin
    mItem := TJSONObject.Create;
    mItem.AddPair('name', mColumn.Name);
    mItem.AddPair('values', Texts(mColumn.Values));
    mItem.AddPair('optionId', mColumn.OptionId);
    mItem.AddPair('resolved', TJSONBool.Create(mColumn.Resolved));
    Result.AddElement(mItem);
  end;
end;

function SprintsJson(const ASprints: TArray<TAtlasBoardSprint>): TJSONArray;
var
  mSprint: TAtlasBoardSprint;
begin
  Result := TJSONArray.Create;
  for mSprint in ASprints do
  begin
    Result.AddElement(SprintJson(mSprint));
  end;
end;

function CardJson(const ACard: TAtlasBoardCard): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('key', ACard.Key);
  Result.AddPair('number', TJSONNumber.Create(ACard.Number));
  Result.AddPair('title', ACard.Title);
  Result.AddPair('state', ACard.State);
  Result.AddPair('assignee', ACard.Assignee);
  Result.AddPair('logins', Texts(ACard.Logins));
  Result.AddPair('priority', ACard.Priority);
  Result.AddPair('priorityColor', ACard.PriorityColor);
  Result.AddPair('done', TJSONNumber.Create(ACard.Checklist.Done));
  Result.AddPair('total', TJSONNumber.Create(ACard.Checklist.Total));
  Result.AddPair('locked', TJSONBool.Create(ACard.Locked));
  Result.AddPair('itemId', ACard.ItemId);
  Result.AddPair('page', ACard.Page);
  Result.AddPair('resolvedAt', TAtlasTrackerBoard.TimeText(ACard.ResolvedAt));
  if ACard.HasPoints then
  begin
    Result.AddPair('points', TJSONNumber.Create(ACard.Points));
  end;
end;

function CardsJson(const ACards: TArray<TAtlasBoardCard>): TJSONArray;
var
  mCard: TAtlasBoardCard;
begin
  Result := TJSONArray.Create;
  for mCard in ACards do
  begin
    Result.AddElement(CardJson(mCard));
  end;
end;

class function TAtlasTrackerBoard.ToJson(const ASnapshot: TAtlasBoardSnapshot): string;
var
  mRoot: TJSONObject;
begin
  mRoot := TJSONObject.Create;
  try
    mRoot.AddPair('version', TJSONNumber.Create(TAtlasBoardSnapshot.Version));
    mRoot.AddPair('kind', KindKey(ASnapshot.Kind));
    mRoot.AddPair('fetched', TimeText(ASnapshot.Fetched));
    mRoot.AddPair('me', ASnapshot.Me);
    mRoot.AddPair('pointsField', ASnapshot.PointsField);
    mRoot.AddPair('page', ASnapshot.Page);
    mRoot.AddPair('boardId', ASnapshot.Board.Id);
    mRoot.AddPair('boardName', ASnapshot.Board.Name);
    mRoot.AddPair('field', ASnapshot.Field);
    mRoot.AddPair('projectId', ASnapshot.ProjectId);
    mRoot.AddPair('fieldId', ASnapshot.FieldId);
    mRoot.AddPair('boards', BoardsJson(ASnapshot.Boards));
    mRoot.AddPair('columns', ColumnsJson(ASnapshot.Columns));
    mRoot.AddPair('sprints', SprintsJson(ASnapshot.Sprints));
    mRoot.AddPair('sprint', SprintJson(ASnapshot.Sprint));
    mRoot.AddPair('cards', CardsJson(ASnapshot.Cards));
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
  begin
    Result := TJSONString(mValue).Value;
  end;
end;

function IntOf(AObject: TJSONObject; const AName: string): Integer;
var
  mValue: TJSONValue;
begin
  Result := 0;
  mValue := AObject.Values[AName];
  if (mValue is TJSONNumber) and not TryStrToInt(TJSONNumber(mValue).Value, Result) then
  begin
    Result := 0;
  end;
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
  begin
    for mItem in TJSONArray(mValue) do
    begin
      if mItem is TJSONString then
      begin
        Result := Result + [TJSONString(mItem).Value];
      end;
    end;
  end;
end;

function SprintOf(AValue: TJSONValue): TAtlasBoardSprint;
var
  mObject: TJSONObject;
begin
  Result := Default(TAtlasBoardSprint);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AValue);
  Result.Id := TextOf(mObject, 'id');
  Result.Name := TextOf(mObject, 'name');
  Result.Start := TAtlasTrackerBoard.TimeValue(TextOf(mObject, 'start'));
  Result.Finish := TAtlasTrackerBoard.TimeValue(TextOf(mObject, 'finish'));
  Result.Archived := FlagOf(mObject, 'archived');
end;

function BoardsOf(AValue: TJSONValue): TArray<TAtlasBoardRef>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONObject then
      begin
        Result := Result + [TAtlasBoardRef.Create(TextOf(TJSONObject(mItem), 'id'),
          TextOf(TJSONObject(mItem), 'name'))];
      end;
    end;
  end;
end;

function ColumnsOf(AValue: TJSONValue): TArray<TAtlasBoardColumn>;
var
  mItem: TJSONValue;
  mObject: TJSONObject;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      if mItem is TJSONObject then
      begin
        mObject := TJSONObject(mItem);
        Result := Result + [TAtlasBoardColumn.Create(TextOf(mObject, 'name'), TextsOf(mObject, 'values'),
          TextOf(mObject, 'optionId'), FlagOf(mObject, 'resolved'))];
      end;
    end;
  end;
end;

function SprintsOf(AValue: TJSONValue): TArray<TAtlasBoardSprint>;
var
  mItem: TJSONValue;
begin
  Result := nil;
  if AValue is TJSONArray then
  begin
    for mItem in TJSONArray(AValue) do
    begin
      Result := Result + [SprintOf(mItem)];
    end;
  end;
end;

function CardOf(AObject: TJSONObject): TAtlasBoardCard;
begin
  Result := Default(TAtlasBoardCard);
  Result.Key := TextOf(AObject, 'key');
  Result.Number := IntOf(AObject, 'number');
  Result.Title := TextOf(AObject, 'title');
  Result.State := TextOf(AObject, 'state');
  Result.Assignee := TextOf(AObject, 'assignee');
  Result.Logins := TextsOf(AObject, 'logins');
  Result.Priority := TextOf(AObject, 'priority');
  Result.PriorityColor := TextOf(AObject, 'priorityColor');
  Result.Checklist := TAtlasChecklistProgress.Create(IntOf(AObject, 'done'), IntOf(AObject, 'total'));
  Result.Locked := FlagOf(AObject, 'locked');
  Result.ItemId := TextOf(AObject, 'itemId');
  Result.Page := TextOf(AObject, 'page');
  Result.ResolvedAt := TAtlasTrackerBoard.TimeValue(TextOf(AObject, 'resolvedAt'));
  Result.HasPoints := AObject.Values['points'] is TJSONNumber;
  if Result.HasPoints then
  begin
    Result.Points := TJSONNumber(AObject.Values['points']).AsDouble;
  end;
end;

/// <summary>Karten mit Kennung, höchstens MaxCards.</summary>
function CardsOf(AValue: TJSONValue): TArray<TAtlasBoardCard>;
var
  mItem: TJSONValue;
  mCard: TAtlasBoardCard;
begin
  Result := nil;
  if not (AValue is TJSONArray) then
  begin
    Exit;
  end;
  for mItem in TJSONArray(AValue) do
  begin
    if mItem is TJSONObject then
    begin
      mCard := CardOf(TJSONObject(mItem));
      if (mCard.Key <> '') and (Length(Result) < TAtlasBoardSnapshot.MaxCards) then
      begin
        Result := Result + [mCard];
      end;
    end;
  end;
end;

class function TAtlasTrackerBoard.FromJson(const AJson: string; out ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mValue: TJSONValue;
  mRoot: TJSONObject;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  Result := False;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    if not (mValue is TJSONObject) then
    begin
      Exit;
    end;
    mRoot := TJSONObject(mValue);
    if IntOf(mRoot, 'version') <> TAtlasBoardSnapshot.Version then
    begin
      Exit;
    end;
    ASnapshot.Kind := KindOf(TextOf(mRoot, 'kind'));
    ASnapshot.Fetched := TimeValue(TextOf(mRoot, 'fetched'));
    ASnapshot.Me := TextOf(mRoot, 'me');
    ASnapshot.PointsField := TextOf(mRoot, 'pointsField');
    ASnapshot.Page := TextOf(mRoot, 'page');
    ASnapshot.Board := TAtlasBoardRef.Create(TextOf(mRoot, 'boardId'), TextOf(mRoot, 'boardName'));
    ASnapshot.Field := TextOf(mRoot, 'field');
    ASnapshot.ProjectId := TextOf(mRoot, 'projectId');
    ASnapshot.FieldId := TextOf(mRoot, 'fieldId');
    ASnapshot.Boards := BoardsOf(mRoot.Values['boards']);
    ASnapshot.Columns := ColumnsOf(mRoot.Values['columns']);
    ASnapshot.Sprints := SprintsOf(mRoot.Values['sprints']);
    ASnapshot.Sprint := SprintOf(mRoot.Values['sprint']);
    ASnapshot.Cards := CardsOf(mRoot.Values['cards']);
    Result := True;
  finally
    mValue.Free;
  end;
end;

{ Zwischenspeicher }

class function TAtlasTrackerBoard.CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget): string;
begin
  Result := CacheFile(AFolder, ATarget, 'board');
end;

class function TAtlasTrackerBoard.CacheFile(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const AName: string): string;
var
  mIndex: Integer;
begin
  Result := '';
  if (AFolder = '') or (ATarget.Server = '') or (AName = '') then
  begin
    Exit;
  end;
  // Der Name kommt auch aus IDs des Trackers (Sprints): nur harmlose Zeichen in den Dateinamen.
  for mIndex := 1 to Length(AName) do
  begin
    if not CharInSet(AName[mIndex], ['A'..'Z', 'a'..'z', '0'..'9', '-', '_']) then
    begin
      Exit;
    end;
  end;
  Result := TAtlasTrackerFiles.Join(AFolder, TAtlasTrackerIssueCache.TrackerId(ATarget) + '-' + AName + '.json');
end;

class procedure TAtlasTrackerBoard.WriteText(const AFile, AText: string);
begin
  if AFile = '' then
  begin
    Exit;
  end;
  // Kein Platz, keine Rechte: Ohne Netz fehlt dann eben der letzte Stand.
  TAtlasTrackerFiles.Files.WriteText(AFile, AText);
end;

class function TAtlasTrackerBoard.ReadText(const AFile: string; out AText: string): Boolean;
begin
  // Fehlende, gesperrte oder kaputte Datei: als fehlend werten.
  Result := (AFile <> '') and TAtlasTrackerFiles.Files.ReadText(AFile, AText);
  if not Result then
  begin
    AText := '';
  end;
end;

class procedure TAtlasTrackerBoard.Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const ASnapshot: TAtlasBoardSnapshot);
begin
  Save(AFolder, ATarget, 'board', ASnapshot);
end;

class procedure TAtlasTrackerBoard.Save(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const AName: string; const ASnapshot: TAtlasBoardSnapshot);
begin
  WriteText(CacheFile(AFolder, ATarget, AName), ToJson(ASnapshot));
end;

class function TAtlasTrackerBoard.Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  out ASnapshot: TAtlasBoardSnapshot): Boolean;
begin
  Result := Load(AFolder, ATarget, 'board', ASnapshot);
end;

class function TAtlasTrackerBoard.Load(const AFolder: string; const ATarget: TAtlasTrackerTarget;
  const AName: string; out ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mText: string;
begin
  ASnapshot := TAtlasBoardSnapshot.Empty;
  Result := ReadText(CacheFile(AFolder, ATarget, AName), mText) and FromJson(mText, ASnapshot);
end;

end.
