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
// - Swimlanes wie auf dem Board des Servers (Swimlanes): jede Karte trägt den
//   Wert des Swimlane-Feldes (Lane, LaneId); Zeilen bildet
//   TAtlasBoardLanes.
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

  /// <summary>Übergang einer Zustandsmaschine (Workflow von YouTrack): Ereignis mit Kennung und Anzeigename.
  /// </summary>
  TAtlasBoardTransition = record
    /// <summary>Kennung des Ereignisses ("in-progress").</summary>
    Id: string;
    /// <summary>Anzeigename ("In Progress", "Beginnen").</summary>
    Name: string;
    class function Create(const AId, AName: string): TAtlasBoardTransition; static;
  end;

  /// <summary>Regeln des Spaltenfeldes einer Karte. Steuert eine Zustandsmaschine das Feld (YouTrack
  /// „StateMachineIssueCustomField“), sind ab dem aktuellen Wert nur die Übergänge in Transitions erlaubt.</summary>
  TAtlasBoardWorkflow = record
    /// <summary>Das Spaltenfeld steht unter einer Zustandsmaschine.</summary>
    StateMachine: Boolean;
    /// <summary>ID des Feldes am Issue ("82-11"), um einen Übergang auszulösen; '' unbekannt.</summary>
    FieldId: string;
    /// <summary>Übergänge ab dem aktuellen Wert.</summary>
    Transitions: TArray<TAtlasBoardTransition>;
  end;

  /// <summary>Swimlanes des Boards nach einem Feld (YouTrack „AttributeBasedSwimlaneSettings“); ohne Fields
  /// keine.</summary>
  TAtlasBoardSwimlanes = record
    /// <summary>Namen des Swimlane-Feldes, unter denen es an einer Karte stehen kann ("Assignee"); leer = keine
    /// Swimlanes.</summary>
    Fields: TArray<string>;
    /// <summary>Beschriftung über den Zeilennamen ("Zugewiesen an").</summary>
    Caption: string;
    /// <summary>Werte in der Reihenfolge des Boards; weitere Werte der Karten folgen dahinter.</summary>
    Values: TArray<string>;
    /// <summary>Zeile der Karten ohne Wert oben statt unten.</summary>
    OrphansAtTop: Boolean;
    /// <summary>Karten ohne Wert werden nicht gezeigt.</summary>
    HideOrphans: Boolean;
    function Active: Boolean;
  end;

  /// <summary>Karte je Issue.</summary>
  TAtlasBoardCard = record
  public const
    cMaxTitle = 300;
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
    /// <summary>Wert des Swimlane-Feldes zur Anzeige ("Bähring, Marco"); '' ohne Wert.</summary>
    Lane: string;
    /// <summary>Kennung des Werts (Anmeldename bzw. Name), um ihn den Werten des Boards zuzuordnen.</summary>
    LaneId: string;
    /// <summary>Workflow-Regeln des Spaltenfeldes (YouTrack); ohne Zustandsmaschine leer. Nicht im
    /// Zwischenspeicher, ohne Netz wird ohnehin nicht verschoben.</summary>
    Workflow: TAtlasBoardWorkflow;
    /// <summary>Für „Beginnen“ und die Vorschau.</summary>
    function Issue: TAtlasTrackerIssue;
  end;

  /// <summary>Stand eines Boards zu einem Zeitpunkt.</summary>
  TAtlasBoardSnapshot = record
  public const
    /// <summary>Höchstens so viele Karten werden gelesen.</summary>
    cMaxCards = 300;
    /// <summary>Höchstens so viele Boards bzw. Sprints für die Klapplisten.</summary>
    cMaxBoards = 50;
    cMaxSprints = 50;
    /// <summary>Version des Zwischenspeichers (2: Spalten nach ordinal, Swimlanes).</summary>
    cVersion = 2;
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
    /// <summary>Swimlanes des Boards; ohne Fields keine.</summary>
    Swimlanes: TAtlasBoardSwimlanes;
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

  /// <summary>Anfrage an IAtlasTrackerBoards.LoadBoard: Board BoardId ('' = das erste zum Projekt des Ziels) mit
  /// Sprint SprintId ('' = aktueller), insgesamt höchstens TimeoutMs.</summary>
  TAtlasBoardRequest = record
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    BoardId: string;
    SprintId: string;
    TimeoutMs: Integer;
    class function Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ABoardId, ASprintId: string; ATimeoutMs: Integer): TAtlasBoardRequest; static;
  end;

  /// <summary>Auftrag an IAtlasTrackerBoards.MoveCard: Card in die Spalte Column, mit Kommentar Comment
  /// ('' = keiner), höchstens TimeoutMs.</summary>
  TAtlasBoardMove = record
    Target: TAtlasTrackerTarget;
    Transport: IAtlasCiTransport;
    Card: TAtlasBoardCard;
    Column: Integer;
    Comment: string;
    TimeoutMs: Integer;
    class function Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
      const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string; ATimeoutMs: Integer): TAtlasBoardMove;
      static;
  end;

  /// <summary>Board lesen und Karten verschieben (#1272); optional neben IAtlasTrackerProvider. Im Hintergrund;
  /// zum Verschieben muss der Transport IAtlasCiSend können.</summary>
  IAtlasTrackerBoards = interface
    ['{4E7B2A93-5C1D-4F68-A0E2-9B3D6C8F1A57}']
    /// <summary>Board und Sprint nach ARequest mit den Karten des Sprints. False mit AError, wenn nichts gelesen
    /// werden konnte.</summary>
    function LoadBoard(const ARequest: TAtlasBoardRequest; out ASnapshot: TAtlasBoardSnapshot;
      out AError: TAtlasCiFetchError): Boolean;
    /// <summary>Karte nach AMove in eine Spalte von ASnapshot verschieben. YouTrack: ein Befehl; GitHub:
    /// Kommentar, dann Feld „Status“ bzw. Zustand des Issues.</summary>
    function MoveCard(const AMove: TAtlasBoardMove; const ASnapshot: TAtlasBoardSnapshot): TAtlasTrackerWriteResult;
  end;

  TAtlasTrackerBoard = class
  public const
    /// <summary>Zeitgrenze einer Abfrage des Boards.</summary>
    cTimeoutMs = 10000;
    /// <summary>Zeitgrenze beim Verschieben.</summary>
    cMoveTimeoutMs = 15000;
    /// <summary>Schmaler als so viele Pixel (bei 96 dpi): Spalten untereinander als einklappbare Gruppen.</summary>
    cNarrowWidth = 360;
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

  /// <summary>Workflow-Regeln beim Verschieben: welcher Übergang einer Zustandsmaschine in eine Spalte führt und
  /// ob eine Spalte nach den Regeln des Trackers erreichbar ist.</summary>
  TAtlasBoardTransitions = class
  public
    /// <summary>Übergang von ACard, der in AColumn führt: Kennung oder Name gleich einem Wert der Spalte oder ihrer
    /// Beschriftung (ohne Groß- und Kleinschreibung, '-' und '_' wie Leerzeichen); -1 ohne.</summary>
    class function Into(const ACard: TAtlasBoardCard; const AColumn: TAtlasBoardColumn): Integer; static;
    /// <summary>Die Zustandsmaschine legt die erreichbaren Spalten sicher fest: Jeder Übergang der Karte ist nach
    /// einer Spalte des Boards benannt (oder es gibt keinen). Ohne Zustandsmaschine False. Benannte Ereignisse
    /// ("Beginnen") verraten ihr Ziel nicht; dann entscheidet der Tracker beim Verschieben.</summary>
    class function Known(const ASnapshot: TAtlasBoardSnapshot; ACard: Integer): Boolean; static;
    /// <summary>TAtlasTrackerBoard.CanMove und, wenn Known gilt, ein Übergang in die Spalte.</summary>
    class function Allowed(const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean; static;
    /// <summary>Namen der Übergänge von ACard mit ", " verbunden; '' ohne.</summary>
    class function Names(const ACard: TAtlasBoardCard): string; static;
  end;

implementation

uses
  System.Character,
  System.DateUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Core.Tracker.Files,
  Atlas.Core.Tracker.IssueCache,
  Atlas.Text.Json;

class function TAtlasBoardRequest.Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ABoardId, ASprintId: string; ATimeoutMs: Integer): TAtlasBoardRequest;
begin
  Result.Target := ATarget;
  Result.Transport := ATransport;
  Result.BoardId := ABoardId;
  Result.SprintId := ASprintId;
  Result.TimeoutMs := ATimeoutMs;
end;

class function TAtlasBoardMove.Create(const ATarget: TAtlasTrackerTarget; const ATransport: IAtlasCiTransport;
  const ACard: TAtlasBoardCard; AColumn: Integer; const AComment: string; ATimeoutMs: Integer): TAtlasBoardMove;
begin
  Result.Target := ATarget;
  Result.Transport := ATransport;
  Result.Card := ACard;
  Result.Column := AColumn;
  Result.Comment := AComment;
  Result.TimeoutMs := ATimeoutMs;
end;

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

{ TAtlasBoardTransition }

class function TAtlasBoardTransition.Create(const AId, AName: string): TAtlasBoardTransition;
begin
  Result.Id := AId;
  Result.Name := AName;
end;

{ TAtlasBoardCard }

function TAtlasBoardSwimlanes.Active: Boolean;
begin
  Result := Length(Fields) > 0;
end;

function TAtlasBoardCard.Issue: TAtlasTrackerIssue;
begin
  Result := TAtlasTrackerIssue.Empty;
  Result.Key := Key;
  Result.Number := Number;
  Result.Title := Copy(Title, 1, TAtlasTrackerIssue.cMaxTitle);
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

{ TAtlasBoardTransitions }

/// <summary>Vergleichsform: klein, ohne Rand, '-' und '_' als Leerzeichen.</summary>
function Plain(const AText: string): string;
begin
  Result := LowerCase(Trim(StringReplace(StringReplace(AText, '-', ' ', [rfReplaceAll]), '_', ' ',
    [rfReplaceAll])));
end;

/// <summary>ATransition führt nach Kennung oder Name in AColumn.</summary>
function LeadsInto(const ATransition: TAtlasBoardTransition; const AColumn: TAtlasBoardColumn): Boolean;
var
  mValues: TArray<string>;
  mValue, mPlain: string;
begin
  Result := False;
  mValues := AColumn.Values + [AColumn.Name];
  for mValue in mValues do
  begin
    mPlain := Plain(mValue);
    if (mPlain <> '') and ((mPlain = Plain(ATransition.Name)) or (mPlain = Plain(ATransition.Id))) then
    begin
      Result := True;
    end;
  end;
end;

class function TAtlasBoardTransitions.Into(const ACard: TAtlasBoardCard; const AColumn: TAtlasBoardColumn): Integer;
var
  mIndex: Integer;
begin
  Result := -1;
  for mIndex := High(ACard.Workflow.Transitions) downto 0 do
  begin
    if LeadsInto(ACard.Workflow.Transitions[mIndex], AColumn) then
    begin
      Result := mIndex;
    end;
  end;
end;

/// <summary>ATransition führt in irgendeine Spalte von ASnapshot.</summary>
function LeadsAnywhere(const ATransition: TAtlasBoardTransition; const ASnapshot: TAtlasBoardSnapshot): Boolean;
var
  mColumn: TAtlasBoardColumn;
begin
  Result := False;
  for mColumn in ASnapshot.Columns do
  begin
    Result := Result or LeadsInto(ATransition, mColumn);
  end;
end;

class function TAtlasBoardTransitions.Known(const ASnapshot: TAtlasBoardSnapshot; ACard: Integer): Boolean;
var
  mTransition: TAtlasBoardTransition;
begin
  Result := (ACard >= 0) and (ACard <= High(ASnapshot.Cards)) and ASnapshot.Cards[ACard].Workflow.StateMachine;
  if not Result then
  begin
    Exit;
  end;
  for mTransition in ASnapshot.Cards[ACard].Workflow.Transitions do
  begin
    Result := Result and LeadsAnywhere(mTransition, ASnapshot);
  end;
end;

class function TAtlasBoardTransitions.Allowed(const ASnapshot: TAtlasBoardSnapshot; ACard, AColumn: Integer): Boolean;
begin
  Result := TAtlasTrackerBoard.CanMove(ASnapshot, ACard, AColumn);
  if Result and Known(ASnapshot, ACard) then
  begin
    Result := Into(ASnapshot.Cards[ACard], ASnapshot.Columns[AColumn]) >= 0;
  end;
end;

class function TAtlasBoardTransitions.Names(const ACard: TAtlasBoardCard): string;
var
  mTransition: TAtlasBoardTransition;
  mName: string;
begin
  Result := '';
  for mTransition in ACard.Workflow.Transitions do
  begin
    mName := mTransition.Name;
    if mName = '' then
    begin
      mName := mTransition.Id;
    end;
    if Result <> '' then
    begin
      Result := Result + ', ';
    end;
    Result := Result + mName;
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
  Result.AddPair('lane', ACard.Lane);
  Result.AddPair('laneId', ACard.LaneId);
  if ACard.HasPoints then
  begin
    Result.AddPair('points', TJSONNumber.Create(ACard.Points));
  end;
end;

function SwimlanesJson(const ASwimlanes: TAtlasBoardSwimlanes): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('fields', Texts(ASwimlanes.Fields));
  Result.AddPair('caption', ASwimlanes.Caption);
  Result.AddPair('values', Texts(ASwimlanes.Values));
  Result.AddPair('orphansAtTop', TJSONBool.Create(ASwimlanes.OrphansAtTop));
  Result.AddPair('hideOrphans', TJSONBool.Create(ASwimlanes.HideOrphans));
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
    mRoot.AddPair('version', TJSONNumber.Create(TAtlasBoardSnapshot.cVersion));
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
    mRoot.AddPair('swimlanes', SwimlanesJson(ASnapshot.Swimlanes));
    mRoot.AddPair('sprints', SprintsJson(ASnapshot.Sprints));
    mRoot.AddPair('sprint', SprintJson(ASnapshot.Sprint));
    mRoot.AddPair('cards', CardsJson(ASnapshot.Cards));
    Result := mRoot.ToJSON;
  finally
    mRoot.Free;
  end;
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
  Result.Id := TJsonRead.Text(mObject, 'id');
  Result.Name := TJsonRead.Text(mObject, 'name');
  Result.Start := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mObject, 'start'));
  Result.Finish := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(mObject, 'finish'));
  Result.Archived := TJsonRead.Flag(mObject, 'archived');
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
        Result := Result + [TAtlasBoardRef.Create(TJsonRead.Text(TJSONObject(mItem), 'id'),
          TJsonRead.Text(TJSONObject(mItem), 'name'))];
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
        Result := Result + [TAtlasBoardColumn.Create(TJsonRead.Text(mObject, 'name'), TextsOf(mObject, 'values'),
          TJsonRead.Text(mObject, 'optionId'), TJsonRead.Flag(mObject, 'resolved'))];
      end;
    end;
  end;
end;

function SwimlanesOf(AValue: TJSONValue): TAtlasBoardSwimlanes;
var
  mObject: TJSONObject;
begin
  Result := Default(TAtlasBoardSwimlanes);
  if not (AValue is TJSONObject) then
  begin
    Exit;
  end;
  mObject := TJSONObject(AValue);
  Result.Fields := TextsOf(mObject, 'fields');
  Result.Caption := TJsonRead.Text(mObject, 'caption');
  Result.Values := TextsOf(mObject, 'values');
  Result.OrphansAtTop := TJsonRead.Flag(mObject, 'orphansAtTop');
  Result.HideOrphans := TJsonRead.Flag(mObject, 'hideOrphans');
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
  Result.Key := TJsonRead.Text(AObject, 'key');
  Result.Number := TJsonRead.Int(AObject, 'number');
  Result.Title := TJsonRead.Text(AObject, 'title');
  Result.State := TJsonRead.Text(AObject, 'state');
  Result.Assignee := TJsonRead.Text(AObject, 'assignee');
  Result.Logins := TextsOf(AObject, 'logins');
  Result.Priority := TJsonRead.Text(AObject, 'priority');
  Result.PriorityColor := TJsonRead.Text(AObject, 'priorityColor');
  Result.Checklist := TAtlasChecklistProgress.Create(TJsonRead.Int(AObject, 'done'), TJsonRead.Int(AObject, 'total'));
  Result.Locked := TJsonRead.Flag(AObject, 'locked');
  Result.ItemId := TJsonRead.Text(AObject, 'itemId');
  Result.Page := TJsonRead.Text(AObject, 'page');
  Result.ResolvedAt := TAtlasTrackerBoard.TimeValue(TJsonRead.Text(AObject, 'resolvedAt'));
  Result.Lane := TJsonRead.Text(AObject, 'lane');
  Result.LaneId := TJsonRead.Text(AObject, 'laneId');
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
      if (mCard.Key <> '') and (Length(Result) < TAtlasBoardSnapshot.cMaxCards) then
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
    if TJsonRead.Int(mRoot, 'version') <> TAtlasBoardSnapshot.cVersion then
    begin
      Exit;
    end;
    ASnapshot.Kind := KindOf(TJsonRead.Text(mRoot, 'kind'));
    ASnapshot.Fetched := TimeValue(TJsonRead.Text(mRoot, 'fetched'));
    ASnapshot.Me := TJsonRead.Text(mRoot, 'me');
    ASnapshot.PointsField := TJsonRead.Text(mRoot, 'pointsField');
    ASnapshot.Page := TJsonRead.Text(mRoot, 'page');
    ASnapshot.Board := TAtlasBoardRef.Create(TJsonRead.Text(mRoot, 'boardId'), TJsonRead.Text(mRoot, 'boardName'));
    ASnapshot.Field := TJsonRead.Text(mRoot, 'field');
    ASnapshot.ProjectId := TJsonRead.Text(mRoot, 'projectId');
    ASnapshot.FieldId := TJsonRead.Text(mRoot, 'fieldId');
    ASnapshot.Boards := BoardsOf(mRoot.Values['boards']);
    ASnapshot.Columns := ColumnsOf(mRoot.Values['columns']);
    ASnapshot.Swimlanes := SwimlanesOf(mRoot.Values['swimlanes']);
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
