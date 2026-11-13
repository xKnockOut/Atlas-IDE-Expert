unit Atlas.Core.Completion.Controller;

// Ablauf der Vervollständigung ohne Fenster und ohne IDE (#410, #414): Start
// fragt die Datenquelle (#408), eintreffende Einträge werden lokal nach dem
// getippten Präfix gefiltert (#409) und an die Ansicht gegeben. Tasten
// verschieben die Auswahl, Enter/Tab übernehmen, Esc schließt. Ohne Treffer
// zeigt die Ansicht den leeren Zustand (#423), statt zu verschwinden.
//
// Alle öffentlichen Methoden laufen im Hauptthread. Einträge aus anderen
// Threads stellt die Senke über TAtlasMainThread.Queue in den Hauptthread
// (beim Entladen verworfen); was nach
// Close, einem neuen Start oder dem Freigeben ankommt, wird verworfen.
//
// Gekürzte Listen (#431, LSP isIncomplete): Beim Weitertippen filtert Requery
// sofort lokal und fragt im Hintergrund neu; die neue Liste ersetzt die alte,
// sobald sie eintrifft, und die Auswahl bleibt auf demselben Eintrag.
// Der Server liefert nur Namen, die zum Präfix der Anfrage passen (#616). Eine Liste gilt daher nur, solange
// das getippte Wort mit diesem Präfix beginnt; kürzer oder anders (Rücktaste) heißt neu fragen (NeedsQuery).
// Teilergebnisse (#616) kommen als mehrere AddItems: Das erste ersetzt bei Requery die Liste, die weiteren
// hängen an.
//
// Rangfolge über TAtlasRanking: Lernzuschlag (#418, Usage), Gruppen geerbter
// Member mit Überschriften (#419; Header in der Reihenfolge, die Auswahl
// überspringt sie), Filter-Chips (#422).
//
// Favoriten (#458, Favorites): Eintreffende Einträge bekommen Favorite gesetzt; ToggleFavorite heftet den
// Eintrag an einer Position an bzw. löst ihn, sortiert neu und lässt die Auswahl auf dem gewählten Eintrag.
// Gespeichert wird vom Aufrufer (IDE-Schicht).
//
// Mengenmodus (#448, TAtlasCompletionSets): Toggle (Leertaste) hakt den gewählten Wert an oder ab, Accept
// übernimmt die ganze Klammer. Hat niemand umgeschaltet, nimmt Enter den gewählten Wert dazu. Nach "[" geöffnet
// (Trigger) und ohne Einträge schließt die Liste still, statt den leeren Zustand zu zeigen.
//
// Unbekannter Name (#471): Stehen nur Deklarationen in der Liste, ist nichts gewählt (Passive). Enter gehört dann
// dem Editor und schließt die Liste, damit ein neuer Name nicht ungefragt deklariert wird; eine Pfeiltaste wählt
// die erste Deklaration. Ebenso, wenn oben nur ein Hinweis „n Methoden von I fehlen“ (#466) steht und sonst nichts:
// Der Hinweis wird nie vorgewählt, die Auswahl beginnt beim ersten Eintrag danach.
//
// Listenmodus (#497, TAtlasListMode): Mit All bzw. Rest bleiben beim Tippen auch die Einträge ohne Treffer
// sichtbar, je nach ListScope nur in Mitgliederlisten nach "." oder überall. Steht kein Treffer oben, ist nichts
// gewählt (wie bei #471): Enter gehört dem Editor, eine Pfeiltaste wählt den ersten Eintrag.
//
// Freigabe absichern (#489): Steht nur dieses Angebot in der Liste, schließt jedes getippte Zeichen sie.
//
// Hinweis bei unvollständigem Code (#457): Meldet die Quelle MarkSyntax, gibt der Controller den Hinweis an eine
// Ansicht mit IAtlasCompletionSyntaxView, sofort und noch einmal beim Abschluss der Abfrage (ohne Meldung dann
// „sicher“, damit ein alter Hinweis nach Requery verschwindet).
//
// Esc (#414): Nach dem Schließen mit Esc öffnet ein automatischer Start im selben Wort (Datei, Zeile,
// Wortanfang) die Liste nicht wieder; Strg+Leer öffnet sie und hebt die Sperre auf.
//
// Diagnosemodus (#479): Ist TAtlasQueryTimings.Enabled, beginnt Start eine gemessene Abfrage (Kontext ab
// AContext.Started, Art des Kontexts, nur der Dateiname), Refresh meldet die Dauer von Filtern und Sortieren
// samt Anzahl der Einträge und die erste sichtbare Liste. Aus wird nichts gemessen.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Usage,
  Atlas.Core.Completion.Favorites;

{$SCOPEDENUMS ON}

type
  TAtlasNavigationKey = (Up, Down, PageUp, PageDown, First, Last, Accept, Cancel, Toggle);

  /// <summary>Anzeige der Liste; umgesetzt vom Popup (Atlas.UI) bzw. von Tests.</summary>
  IAtlasCompletionView = interface
    ['{8D2F4B61-3E9A-4C57-A1D0-6B7E2F9C3A15}']
    /// <summary>Zeigt bzw. aktualisiert die Liste. AOrder: Indizes in AItems in Anzeigereihenfolge;
    /// ASelected: Position in AOrder; APattern: getippter Anfang, zum Hervorheben der Treffer.</summary>
    procedure ShowList(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    /// <summary>Leerer Zustand (#423): keine Treffer für APrefix unter ATotal Einträgen.</summary>
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    /// <summary>Zahl der sichtbaren Zeilen für Bild auf/ab.</summary>
    function PageSize: Integer;
    /// <summary>Filter-Chips (#422): Treffer je Art, gewählter Chip; AVisible = False blendet sie aus.</summary>
    procedure ShowChips(const ACounts: TAtlasChipCounts; AActive: TAtlasChip; AVisible: Boolean);
  end;

  /// <summary>Ansicht mit Hinweis bei unvollständigem Code (#457); das Popup, wahlweise auch Tests.</summary>
  IAtlasCompletionSyntaxView = interface
    ['{2C6E9B41-7A3D-4E85-B0F2-9D1C5A8E3B76}']
    /// <summary>Warnleiste bzw. Hinweis im leeren Zustand; Trust Sure blendet ihn aus.</summary>
    procedure ShowSyntax(const ANotice: TAtlasSyntaxNotice);
  end;

  /// <summary>Ansicht, die nur wegen der Sichtbarkeit fehlende Treffer nennt (#2108); das Popup, wahlweise auch
  /// Tests.</summary>
  IAtlasCompletionHiddenView = interface
    ['{6B1F3D84-92C5-4E7A-8D36-1F0A5C9E2B47}']
    /// <summary>AItems: passende Mitglieder mit Inaccessible, die die Liste noch nicht zeigt; leer ohne. Vor jedem
    /// Zeigen der Liste bzw. des leeren Zustands.</summary>
    procedure ShowInaccessible(const AItems: TAtlasCompletionItems);
  end;

  TAtlasCommitEvent = reference to procedure(const AItem: TAtlasCompletionItem);

  /// <summary>Einstellungen der Vervollständigung, die der Aufrufer setzt (#418, #419, #422, #458, #497).
  /// </summary>
  TAtlasCompletionSettings = class
  private
    FOnCommit: TAtlasCommitEvent;
    FGroupInherited: Boolean;
    FChipsEnabled: Boolean;
    FListMode: TAtlasListMode;
    FListScope: TAtlasListScope;
    FUsage: TAtlasUsage;
    FFavorites: TAtlasFavorites;
    /// <summary>Nicht sichtbare Mitglieder zeigen (#2108); bis zum nächsten Start.</summary>
    FShowInaccessible: Boolean;
    /// <summary>Marken „zuletzt“/„häufig“ (#418) und Favorit (#458) in AItems ab AFrom setzen.</summary>
    procedure MarkItems(var AItems: TAtlasCompletionItems; AFrom: Integer);
    /// <summary>Optionen für TAtlasRanking: Chip, Listenmodus (AMembers: Mitgliederliste nach ".") und
    /// Lernzuschlag für AItems.</summary>
    function RankOptions(AChip: TAtlasChip; AMembers: Boolean;
      const AItems: TAtlasCompletionItems): TAtlasRankOptions;
  public
    property OnCommit: TAtlasCommitEvent read FOnCommit write FOnCommit;
    /// <summary>Geerbte Member gruppieren (#419).</summary>
    property GroupInherited: Boolean read FGroupInherited write FGroupInherited;
    property ChipsEnabled: Boolean read FChipsEnabled write FChipsEnabled;
    /// <summary>Einträge ohne Treffer zeigen (#497); Filter = nur Treffer.</summary>
    property ListMode: TAtlasListMode read FListMode write FListMode;
    /// <summary>Wo ListMode gilt (#497).</summary>
    property ListScope: TAtlasListScope read FListScope write FListScope;
    /// <summary>Lernende Gewichtung (#418); nil = aus. Gehört dem Aufrufer.</summary>
    property Usage: TAtlasUsage read FUsage write FUsage;
    /// <summary>Angeheftete Favoriten (#458); nil = aus. Gehört dem Aufrufer.</summary>
    property Favorites: TAtlasFavorites read FFavorites write FFavorites;
  end;

  /// <summary>Stand der offenen Liste: Einträge, Reihenfolge, Auswahl und Zustand der Abfrage.</summary>
  TAtlasCompletionState = class(TAtlasCompletionSettings)
  private
    FActive: Boolean;
    FLoading: Boolean;
    FItems: TAtlasCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FPrefix: string;
    /// <summary>Präfix, mit dem die aktuelle Liste angefragt wurde (#616).</summary>
    FQueryPrefix: string;
    FEmpty: Boolean;
    /// <summary>Nur Deklarationen eines unbekannten Namens, noch keine gewählt (#471).</summary>
    FPassive: Boolean;
    /// <summary>Position des ersten Eintrags ohne Treffer (#497); -1 ohne.</summary>
    FRestStart: Integer;
    /// <summary>Mitgliederliste nach "." (#497).</summary>
    FMembers: Boolean;
    FIncomplete: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457): gezeigt bzw. von der laufenden Abfrage gemeldet.</summary>
    FSyntax: TAtlasSyntaxNotice;
    FPendingSyntax: TAtlasSyntaxNotice;
    /// <summary>Die nächsten Einträge ersetzen die Liste (laufendes Requery).</summary>
    FReplace: Boolean;
    FChip: TAtlasChip;
    /// <summary>Zeichen, nach dem automatisch geöffnet wurde (#448).</summary>
    FTrigger: string;
    /// <summary>Im Mengenmodus schon umgeschaltet.</summary>
    FToggled: Boolean;
    function GetVisible: Boolean;
    procedure SelectByName(const AName: string);
  public
    function SelectedItem(out AItem: TAtlasCompletionItem): Boolean;
    /// <summary>Ein Commit-Zeichen (#429) darf übernehmen: Liste offen und der gewählte Eintrag
    /// trifft das Präfix klar (genau, Anfang, Wortanfänge), nicht nur unscharf.</summary>
    function CanCommitOnCharacter: Boolean;
    /// <summary>Für APrefix neu fragen statt lokal filtern (#616): Liste gekürzt, oder APrefix beginnt nicht
    /// mit dem Präfix der Anfrage (der Server hat nach diesem gefiltert).</summary>
    function NeedsQuery(const APrefix: string): Boolean;
    /// <summary>Mengenmodus (#448): Kontrollkästchen statt einfacher Auswahl.</summary>
    function SetMode: Boolean;
    property Active: Boolean read FActive;
    property Loading: Boolean read FLoading;
    /// <summary>Liste ist offen und hat Treffer.</summary>
    property Visible: Boolean read GetVisible;
    /// <summary>Leerer Zustand wird gezeigt (#423).</summary>
    property Empty: Boolean read FEmpty;
    /// <summary>Nichts gewählt, weil nur Deklarationen eines unbekannten Namens passen (#471); Enter gehört dem
    /// Editor.</summary>
    property Passive: Boolean read FPassive;
    /// <summary>Die Quelle hat gekürzt; beim Weitertippen Requery statt UpdatePrefix.</summary>
    property Incomplete: Boolean read FIncomplete;
    /// <summary>Gezeigter Hinweis bei unvollständigem Code (#457); Trust Sure ohne.</summary>
    property Syntax: TAtlasSyntaxNotice read FSyntax;
    property Prefix: string read FPrefix;
    property Items: TAtlasCompletionItems read FItems;
    property Order: TArray<Integer> read FOrder;
    property Selected: Integer read FSelected;
    /// <summary>Position des ersten Eintrags ohne Treffer in Order (#497); -1 ohne.</summary>
    property RestStart: Integer read FRestStart;
  end;

  /// <summary>Ablauf der Vervollständigung; Einstellungen und Stand in den Vorfahren.</summary>
  TAtlasCompletionController = class(TAtlasCompletionState)
  private type
    /// <summary>Lebt, solange eine Senke oder ein eingereihter Aufruf ihn hält.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;

    TControllerSink = class(TInterfacedObject, IAtlasCompletionSink)
    private
      FController: TAtlasCompletionController;
      FFlag: TAliveFlag;
      FFlagRef: IInterface;
      FGeneration: Integer;
    public
      constructor Create(AController: TAtlasCompletionController; AFlag: TAliveFlag; AGeneration: Integer);
      procedure AddItems(const AItems: TAtlasCompletionItems);
      procedure MarkIncomplete;
      procedure MarkSyntax(const ANotice: TAtlasSyntaxNotice);
      procedure Complete;
    end;

    /// <summary>Wort im Editor: Datei, Zeile, Wortanfang (#414); Line &lt; 0 ohne.</summary>
    TWordPlace = record
      FileName: string;
      Line: Integer;
      Start: Integer;
      class function At(const AContext: TAtlasContext): TWordPlace; static;
      function Matches(const AContext: TAtlasContext): Boolean;
    end;
  private
    FProvider: IAtlasCompletionProvider;
    FView: IAtlasCompletionView;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    FGeneration: Integer;
    /// <summary>Wort der offenen Liste (#414).</summary>
    FWord: TWordPlace;
    /// <summary>Mit Esc geschlossenes Wort; Line &lt; 0 ohne.</summary>
    FDismissed: TWordPlace;
    procedure Dismiss;
    procedure ToggleSelected;
    procedure CommitSet;
    procedure ShowChips;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TAtlasCompletionItems);
    procedure IncompleteArrived(AGeneration: Integer);
    procedure SyntaxArrived(AGeneration: Integer; const ANotice: TAtlasSyntaxNotice);
    /// <summary>FSyntax an eine Ansicht mit IAtlasCompletionSyntaxView.</summary>
    procedure ShowSyntax;
    procedure Query(const AContext: TAtlasContext);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    /// <summary>Liste, Liste ohne Auswahl (Passive) oder leeren Zustand zeigen.</summary>
    procedure ShowResult;
    procedure MoveSelection(APosition, ADirection: Integer); overload;
    procedure MoveSelection(APosition: Integer); overload;
    /// <summary>Pfeile, Bild auf/ab, Pos1, Ende; False bei anderen Tasten.</summary>
    function MoveByKey(AKey: TAtlasNavigationKey; APage: Integer): Boolean;
    function AcceptKey: Boolean;
    function ToggleKey: Boolean;
  public
    constructor Create(const AProvider: IAtlasCompletionProvider; const AView: IAtlasCompletionView);
    destructor Destroy; override;
    /// <summary>Neue Vervollständigung an AContext; schließt eine offene. Ein automatischer Start im mit Esc
    /// geschlossenen Wort öffnet nichts (#414).</summary>
    procedure Start(const AContext: TAtlasContext);
    /// <summary>Wurde die Liste im Wort von AContext mit Esc geschlossen (#414)?</summary>
    function Dismissed(const AContext: TAtlasContext): Boolean;
    /// <summary>Das Wort unter dem Cursor hat sich geändert: neu filtern.</summary>
    procedure UpdatePrefix(const APrefix: string);
    /// <summary>Wie UpdatePrefix, fragt aber zusätzlich neu an (gekürzte Liste, #431).</summary>
    procedure Requery(const AContext: TAtlasContext);
    procedure Close;
    /// <summary>True, wenn die Taste verbraucht wurde; nur bei sichtbarer Liste.</summary>
    function HandleKey(AKey: TAtlasNavigationKey): Boolean;
    /// <summary>Auswahl per Maus; APosition in der Anzeigereihenfolge.</summary>
    procedure Select(APosition: Integer);
    procedure CommitSelected;
    /// <summary>Filter-Chip wählen (#422); gilt bis zum Schließen.</summary>
    procedure SelectChip(AChip: TAtlasChip);
    /// <summary>Chip an Position AIndex (0-basiert) unter den angezeigten (Alt+1 … Alt+6).</summary>
    procedure SelectChipAt(AIndex: Integer);
    /// <summary>Eintrag an APosition (Anzeigereihenfolge) anheften bzw. lösen (Klick auf den Stern); AItem ist
    /// der Eintrag. Added bzw. Removed sortieren neu, die Auswahl bleibt auf dem gewählten Eintrag. NotAllowed
    /// ohne Favoriten, ohne Liste oder auf einer Überschrift.</summary>
    function ToggleFavorite(APosition: Integer; out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
    /// <summary>Wie ToggleFavorite für den gewählten Eintrag (Strg+D); NotAllowed, wenn nichts gewählt ist.</summary>
    function ToggleSelectedFavorite(out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
    /// <summary>Gibt es passende Mitglieder, die nur wegen der Sichtbarkeit fehlen und noch nicht gezeigt sind
    /// (#2108)?</summary>
    function CanRevealInaccessible: Boolean;
    /// <summary>Zweites Strg+Leertaste (#2108): die nicht sichtbaren Mitglieder ausgegraut am Ende der Liste
    /// zeigen. False, wenn es keine gibt.</summary>
    function RevealInaccessible: Boolean;
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.Timing,
  System.Math,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Presentation,
  Atlas.Core.Completion.Sets;

/// <summary>Art des Kontexts für den Diagnosemodus (#479); nie Text aus dem Editor.</summary>
function TimingKind(const AContext: TAtlasContext): string;
begin
  case AContext.Kind of
    TAtlasContextKind.MemberAccess:
      Result := 'Member';
    TAtlasContextKind.ClassDeclaration:
      Result := 'Klassendeklaration';
    TAtlasContextKind.EventAssignment:
      Result := 'Ereigniszuweisung';
    TAtlasContextKind.Directive:
      Result := 'Direktive';
    TAtlasContextKind.XmlDoc:
      Result := 'XMLDoc';
  else
    Result := 'Bezeichner';
  end;
  if AContext.Automatic then
  begin
    Result := Result + ', automatisch';
  end
  else
  begin
    Result := Result + ', Strg+Leer';
  end;
end;

/// <summary>Nächster Eintrag (keine Überschrift) ab APosition in Richtung ADirection, sonst in der Gegenrichtung;
/// -1 ohne.</summary>
function FirstItemIn(const AOrder: TArray<Integer>; APosition, ADirection: Integer): Integer;
begin
  Result := APosition;
  while (Result >= 0) and (Result <= High(AOrder)) and TAtlasRanking.IsHeader(AOrder[Result]) do
  begin
    Inc(Result, ADirection);
  end;
  if (Result >= 0) and (Result <= High(AOrder)) then
  begin
    Exit;
  end;
  Result := APosition;
  while (Result >= 0) and (Result <= High(AOrder)) and TAtlasRanking.IsHeader(AOrder[Result]) do
  begin
    Dec(Result, ADirection);
  end;
  if (Result < 0) or (Result > High(AOrder)) then
  begin
    Result := -1;
  end;
end;

/// <summary>Erster wählbarer Eintrag: Hinweise (#466) stehen oben, gewählt ist der erste Eintrag danach.</summary>
function FirstSelection(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>): Integer;
var
  mPosition: Integer;
begin
  Result := FirstItemIn(AOrder, 0, 1);
  mPosition := Result;
  while (mPosition >= 0) and (mPosition <= High(AOrder)) and (TAtlasRanking.IsHeader(AOrder[mPosition]) or
    AItems[AOrder[mPosition]].Hint) do
  begin
    Inc(mPosition);
  end;
  if (Result >= 0) and (mPosition <= High(AOrder)) then
  begin
    Result := mPosition;
  end;
end;

/// <summary>Index des gewählten Eintrags, der nach dem Neusortieren gewählt bleiben soll; -1 ohne.</summary>
function KeptIndex(const AOrder: TArray<Integer>; ASelected: Integer; AKeep, APassive: Boolean): Integer;
begin
  Result := -1;
  if AKeep and not APassive and (ASelected >= 0) and (ASelected < Length(AOrder)) then
  begin
    Result := AOrder[ASelected];
  end;
end;

/// <summary>Position des Eintrags AIndex in AOrder; ADefault ohne AIndex (&lt; 0) oder wenn er fehlt.</summary>
function PositionOf(const AOrder: TArray<Integer>; AIndex, ADefault: Integer): Integer;
var
  mPosition: Integer;
begin
  Result := ADefault;
  if AIndex < 0 then
  begin
    Exit;
  end;
  for mPosition := 0 to High(AOrder) do
  begin
    if AOrder[mPosition] = AIndex then
    begin
      Exit(mPosition);
    end;
  end;
end;

/// <summary>Deklaration eines unbekannten Namens (#471), Hinweis (#466) oder Rest ohne Treffer (#497)?</summary>
function IsPassiveItem(const AItem: TAtlasCompletionItem; ASelected, ARestStart: Integer): Boolean;
begin
  Result := (AItem.Unknown <> '') or AItem.Hint or ((ARestStart >= 0) and (ASelected >= ARestStart));
end;

/// <summary>Nur Deklarationen (#471): sichtbar, aber nicht gewählt, solange niemand eine Pfeiltaste drückt.
/// Ebenso, wenn oben kein Treffer steht, nur der Rest (#497). Ein behaltener Eintrag (AKept) bleibt gewählt.
/// </summary>
function IsPassive(const AItems: TAtlasCompletionItems; const AOrder: TArray<Integer>;
  ASelected, ARestStart, AKept: Integer): Boolean;
begin
  if ASelected < 0 then
  begin
    Exit(False);
  end;
  Result := IsPassiveItem(AItems[AOrder[ASelected]], ASelected, ARestStart) and
    ((AKept < 0) or (AOrder[ASelected] <> AKept));
end;

/// <summary>Lernzuschlag (#418) für AItems; eigene Routine, damit die Methodenreferenz nur das Nötige hält.
/// </summary>
function BoostOf(AUsage: TAtlasUsage; const AItems: TAtlasCompletionItems): TAtlasBoostFunc;
var
  mItems: TAtlasCompletionItems;
begin
  mItems := AItems;
  Result :=
    function(AIndex: Integer): Integer
    begin
      Result := AUsage.Boost(mItems[AIndex]);
    end;
end;

{ TAtlasCompletionSettings }

procedure TAtlasCompletionSettings.MarkItems(var AItems: TAtlasCompletionItems; AFrom: Integer);
var
  mIndex: Integer;
begin
  for mIndex := Max(0, AFrom) to High(AItems) do
  begin
    if FUsage <> nil then
    begin
      AItems[mIndex].Usage := FUsage.Mark(AItems[mIndex]);
    end;
    AItems[mIndex].Favorite := (FFavorites <> nil) and FFavorites.IsFavorite(AItems[mIndex]);
  end;
end;

function TAtlasCompletionSettings.RankOptions(AChip: TAtlasChip; AMembers: Boolean;
  const AItems: TAtlasCompletionItems): TAtlasRankOptions;
begin
  Result := TAtlasRankOptions.Defaults;
  Result.GroupInherited := FGroupInherited;
  if FChipsEnabled then
  begin
    Result.Chip := AChip;
  end;
  if AMembers or (FListScope = TAtlasListScope.Everywhere) then
  begin
    Result.ListMode := FListMode;
  end;
  if FUsage <> nil then
  begin
    Result.Boost := BoostOf(FUsage, AItems);
  end;
  Result.ShowInaccessible := FShowInaccessible;
end;

{ TAtlasCompletionState }

function TAtlasCompletionState.GetVisible: Boolean;
begin
  Result := FActive and (FSelected >= 0) and (Length(FOrder) > 0);
end;

procedure TAtlasCompletionState.SelectByName(const AName: string);
var
  mPosition: Integer;
begin
  for mPosition := 0 to High(FOrder) do
  begin
    if not TAtlasRanking.IsHeader(FOrder[mPosition]) and (FItems[FOrder[mPosition]].Name = AName) then
    begin
      FSelected := mPosition;
      Exit;
    end;
  end;
end;

function TAtlasCompletionState.SetMode: Boolean;
begin
  Result := FActive and TAtlasCompletionSets.Active(FItems);
end;

function TAtlasCompletionState.SelectedItem(out AItem: TAtlasCompletionItem): Boolean;
begin
  Result := GetVisible and not FPassive and (FSelected >= 0) and (FSelected < Length(FOrder));
  if Result then
  begin
    AItem := FItems[FOrder[FSelected]];
  end
  else
  begin
    AItem := Default(TAtlasCompletionItem);
  end;
end;

function TAtlasCompletionState.CanCommitOnCharacter: Boolean;
var
  mItem: TAtlasCompletionItem;
begin
  // Code-Vorlagen (#51) nur über Enter oder Tab: "while(" soll keine Schleife einsetzen.
  Result := (FPrefix <> '') and SelectedItem(mItem) and (mItem.Snippet = '') and (mItem.Inaccessible = '') and
    (TAtlasCompletionMatcher.Score(FPrefix, mItem.Name) >= TAtlasCompletionMatcher.cScoreWordStarts);
end;

function TAtlasCompletionState.NeedsQuery(const APrefix: string): Boolean;
begin
  Result := FActive and (FIncomplete or not APrefix.StartsWith(FQueryPrefix, True));
end;

{ TAtlasCompletionController.TWordPlace }

class function TAtlasCompletionController.TWordPlace.At(const AContext: TAtlasContext): TWordPlace;
begin
  Result.FileName := AContext.FileName;
  Result.Line := AContext.Line;
  Result.Start := AContext.Character - Length(AContext.Prefix);
end;

function TAtlasCompletionController.TWordPlace.Matches(const AContext: TAtlasContext): Boolean;
begin
  Result := (Line >= 0) and (AContext.Line = Line) and (AContext.Character - Length(AContext.Prefix) = Start) and
    SameText(AContext.FileName, FileName);
end;

{ TAtlasCompletionController.TControllerSink }

constructor TAtlasCompletionController.TControllerSink.Create(AController: TAtlasCompletionController;
  AFlag: TAliveFlag; AGeneration: Integer);
begin
  inherited Create;
  FController := AController;
  FFlag := AFlag;
  FFlagRef := AFlag;
  FGeneration := AGeneration;
end;

procedure TAtlasCompletionController.TControllerSink.AddItems(const AItems: TAtlasCompletionItems);
var
  mController: TAtlasCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
  mItems: TAtlasCompletionItems;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  mItems := AItems;
  // Im Hauptthread läuft Queue sofort, sonst beim nächsten CheckSynchronize; beim Entladen verworfen.
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            mController.ItemsArrived(mGeneration, mItems);
          end);
      end;
    end);
end;

procedure TAtlasCompletionController.TControllerSink.MarkIncomplete;
var
  mController: TAtlasCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            mController.IncompleteArrived(mGeneration);
          end);
      end;
    end);
end;

procedure TAtlasCompletionController.TControllerSink.MarkSyntax(const ANotice: TAtlasSyntaxNotice);
var
  mController: TAtlasCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
  mNotice: TAtlasSyntaxNotice;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  mNotice := ANotice;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            mController.SyntaxArrived(mGeneration, mNotice);
          end);
      end;
    end);
end;

procedure TAtlasCompletionController.TControllerSink.Complete;
var
  mController: TAtlasCompletionController;
  mFlag: TAliveFlag;
  mFlagRef: IInterface;
  mGeneration: Integer;
begin
  mController := FController;
  mFlag := FFlag;
  mFlagRef := FFlagRef;
  mGeneration := FGeneration;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if mFlag.Alive and (mFlagRef <> nil) then
      begin
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            mController.Completed(mGeneration);
          end);
      end;
    end);
end;

/// <summary>Passende nicht sichtbare Mitglieder an eine Ansicht mit IAtlasCompletionHiddenView (#2108); leer,
/// wenn AShown (die Liste zeigt sie schon).</summary>
procedure ShowInaccessibleIn(const AView: IAtlasCompletionView; const AItems: TAtlasCompletionItems;
  const APrefix: string; AShown: Boolean);
var
  mView: IAtlasCompletionHiddenView;
  mItems: TAtlasCompletionItems;
  mIndex: Integer;
begin
  if not Supports(AView, IAtlasCompletionHiddenView, mView) then
  begin
    Exit;
  end;
  mItems := nil;
  if not AShown then
  begin
    for mIndex in TAtlasRanking.Inaccessible(AItems, APrefix) do
    begin
      mItems := mItems + [AItems[mIndex]];
    end;
  end;
  mView.ShowInaccessible(mItems);
end;

{ TAtlasCompletionController }

constructor TAtlasCompletionController.Create(const AProvider: IAtlasCompletionProvider;
  const AView: IAtlasCompletionView);
begin
  inherited Create;
  FProvider := AProvider;
  FView := AView;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
  FSelected := -1;
  FRestStart := -1;
  FDismissed.Line := -1;
end;

destructor TAtlasCompletionController.Destroy;
begin
  Close;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  inherited;
end;

procedure TAtlasCompletionController.ShowChips;
begin
  if FChipsEnabled then
  begin
    FView.ShowChips(TAtlasRanking.ChipCounts(FItems, FPrefix), FChip, Length(FItems) > 0);
  end
  else
  begin
    FView.ShowChips(Default(TAtlasChipCounts), TAtlasChip.All, False);
  end;
end;

procedure TAtlasCompletionController.SelectChip(AChip: TAtlasChip);
begin
  if not FActive or (AChip = FChip) then
  begin
    Exit;
  end;
  FChip := AChip;
  Refresh(True);
end;

procedure TAtlasCompletionController.SelectChipAt(AIndex: Integer);
var
  mCounts: TAtlasChipCounts;
  mChip: TAtlasChip;
begin
  // Wie angezeigt: nur Chips mit Treffern, "Alle" immer.
  mCounts := TAtlasRanking.ChipCounts(FItems, FPrefix);
  for mChip := Low(TAtlasChip) to High(TAtlasChip) do
  begin
    if (mChip = TAtlasChip.All) or (mCounts[mChip] > 0) then
    begin
      if AIndex = 0 then
      begin
        SelectChip(mChip);
        Exit;
      end;
      Dec(AIndex);
    end;
  end;
end;

function TAtlasCompletionController.Dismissed(const AContext: TAtlasContext): Boolean;
begin
  Result := FDismissed.Matches(AContext);
end;

procedure TAtlasCompletionController.Dismiss;
begin
  FDismissed := FWord;
  Close;
end;

procedure TAtlasCompletionController.Start(const AContext: TAtlasContext);
begin
  Close;
  if AContext.Automatic and Dismissed(AContext) then
  begin
    Exit;
  end;
  // Ein anderes Wort oder Strg+Leer hebt die Sperre auf.
  FDismissed.Line := -1;
  FWord := TWordPlace.At(AContext);
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FChip := TAtlasChip.All;
  FPrefix := AContext.Prefix;
  FTrigger := AContext.Trigger;
  FMembers := AContext.Kind = TAtlasContextKind.MemberAccess;
  FRestStart := -1;
  FToggled := False;
  FShowInaccessible := False;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  if TAtlasQueryTimings.Enabled and (TAtlasQueryTimings.Shared <> nil) then
  begin
    TAtlasQueryTimings.Shared.BeginQuery(AContext.Started, TimingKind(AContext), ExtractFileName(AContext.FileName));
  end;
  Query(AContext);
end;

procedure TAtlasCompletionController.Query(const AContext: TAtlasContext);
var
  mSink: IAtlasCompletionSink;
begin
  FIncomplete := False;
  FPendingSyntax := Default(TAtlasSyntaxNotice);
  FQueryPrefix := AContext.Prefix;
  mSink := TControllerSink.Create(Self, FFlag, FGeneration);
  FProvider.Query(AContext, mSink);
end;

procedure TAtlasCompletionController.Requery(const AContext: TAtlasContext);
begin
  if not FActive then
  begin
    Start(AContext);
    Exit;
  end;
  // Sofort lokal filtern, damit das Popup ohne Warten folgt (#409) ...
  UpdatePrefix(AContext.Prefix);
  // ... und im Hintergrund die vollständigere Liste holen; ältere Antworten verfallen.
  Inc(FGeneration);
  FLoading := True;
  FReplace := True;
  Query(AContext);
end;

procedure TAtlasCompletionController.IncompleteArrived(AGeneration: Integer);
begin
  if FActive and (AGeneration = FGeneration) then
  begin
    FIncomplete := True;
  end;
end;

procedure TAtlasCompletionController.SyntaxArrived(AGeneration: Integer; const ANotice: TAtlasSyntaxNotice);
begin
  if not FActive or (AGeneration <> FGeneration) then
  begin
    Exit;
  end;
  FPendingSyntax := ANotice;
  FSyntax := ANotice;
  ShowSyntax;
end;

procedure TAtlasCompletionController.ShowSyntax;
var
  mView: IAtlasCompletionSyntaxView;
begin
  if Supports(FView, IAtlasCompletionSyntaxView, mView) then
  begin
    mView.ShowSyntax(FSyntax);
  end;
end;

function TAtlasCompletionController.CanRevealInaccessible: Boolean;
begin
  Result := FActive and not FShowInaccessible and (Length(TAtlasRanking.Inaccessible(FItems, FPrefix)) > 0);
end;

function TAtlasCompletionController.RevealInaccessible: Boolean;
begin
  Result := CanRevealInaccessible;
  if Result then
  begin
    FShowInaccessible := True;
    Refresh(True);
  end;
end;

procedure TAtlasCompletionController.Close;
begin
  if not FActive then
  begin
    Exit;
  end;
  FActive := False;
  FLoading := False;
  FIncomplete := False;
  FSyntax := Default(TAtlasSyntaxNotice);
  FPendingSyntax := FSyntax;
  FReplace := False;
  Inc(FGeneration);
  FProvider.Cancel;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  FPassive := False;
  FRestStart := -1;
  FView.HideList;
end;

procedure TAtlasCompletionController.ItemsArrived(AGeneration: Integer; const AItems: TAtlasCompletionItems);
var
  mItem: TAtlasCompletionItem;
  mSelectedName: string;
begin
  if not FActive or (AGeneration <> FGeneration) or (Length(AItems) = 0) then
  begin
    Exit;
  end;
  if FReplace then
  begin
    // Neue Liste nach Requery: ersetzen, die Auswahl bleibt auf demselben Eintrag.
    mSelectedName := '';
    if SelectedItem(mItem) then
    begin
      mSelectedName := mItem.Name;
    end;
    FReplace := False;
    FItems := AItems;
    MarkItems(FItems, 0);
    Refresh(False);
    if (mSelectedName <> '') and (Length(FOrder) > 0) then
    begin
      SelectByName(mSelectedName);
      FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    end;
    Exit;
  end;
  FItems := FItems + AItems;
  MarkItems(FItems, Length(FItems) - Length(AItems));
  Refresh(True);
end;

function TAtlasCompletionController.ToggleFavorite(APosition: Integer;
  out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
begin
  Result := TAtlasFavoriteToggle.NotAllowed;
  AItem := Default(TAtlasCompletionItem);
  if (FFavorites = nil) or not FActive or (APosition < 0) or (APosition > High(FOrder)) or
    TAtlasRanking.IsHeader(FOrder[APosition]) then
  begin
    Exit;
  end;
  AItem := FItems[FOrder[APosition]];
  Result := FFavorites.Toggle(AItem);
  if (Result <> TAtlasFavoriteToggle.Added) and (Result <> TAtlasFavoriteToggle.Removed) then
  begin
    Exit;
  end;
  // Alle Einträge neu markieren: Derselbe Member kann aus mehreren Quellen kommen.
  MarkItems(FItems, 0);
  AItem.Favorite := Result = TAtlasFavoriteToggle.Added;
  Refresh(True);
end;

function TAtlasCompletionController.ToggleSelectedFavorite(out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
begin
  if not SelectedItem(AItem) then
  begin
    Exit(TAtlasFavoriteToggle.NotAllowed);
  end;
  Result := ToggleFavorite(FSelected, AItem);
end;

procedure TAtlasCompletionController.Completed(AGeneration: Integer);
begin
  if not FActive or (AGeneration <> FGeneration) then
  begin
    Exit;
  end;
  FLoading := False;
  // Der Hinweis gilt für die Liste dieser Abfrage (#457).
  FSyntax := FPendingSyntax;
  ShowSyntax;
  // Requery ohne Einträge: Die alte Liste gilt nicht mehr.
  if FReplace then
  begin
    FReplace := False;
    FItems := nil;
  end;
  // Automatisch nach "[" geöffnet, aber keine Menge (#448): still schließen.
  if (Length(FItems) = 0) and (FTrigger <> '') then
  begin
    Close;
    Exit;
  end;
  // Nichts gefunden: leerer Zustand statt kommentarlos zu verschwinden (#423).
  if Length(FItems) = 0 then
  begin
    Refresh(False);
  end;
end;

procedure TAtlasCompletionController.Refresh(AKeepSelection: Boolean);
var
  mKept: Integer;
  mTimings: TAtlasQueryTimings;
  mStamp: Int64;
begin
  // Diagnosemodus (#479): nur an einen Zeitstempel nehmen.
  mTimings := nil;
  mStamp := 0;
  if TAtlasQueryTimings.Enabled then
  begin
    mTimings := TAtlasQueryTimings.Shared;
    mStamp := TAtlasQueryTimings.Stamp;
  end;
  mKept := KeptIndex(FOrder, FSelected, AKeepSelection, FPassive);
  FOrder := TAtlasRanking.Order(FItems, FPrefix, RankOptions(FChip, FMembers, FItems), FRestStart);
  if mTimings <> nil then
  begin
    mTimings.FilterSorted(TAtlasQueryTimings.MsSince(mStamp), Length(FItems), TAtlasRanking.ItemCount(FOrder));
  end;
  FSelected := FirstSelection(FItems, FOrder);
  ShowChips;
  FSelected := PositionOf(FOrder, mKept, FSelected);
  FEmpty := False;
  FPassive := IsPassive(FItems, FOrder, FSelected, FRestStart, mKept);
  if (mTimings <> nil) and (FSelected >= 0) then
  begin
    mTimings.ListShown;
  end;
  ShowResult;
end;

procedure TAtlasCompletionController.ShowResult;
begin
  ShowInaccessibleIn(FView, FItems, FPrefix, FShowInaccessible);
  if FPassive then
  begin
    FView.ShowList(FItems, FOrder, -1, FPrefix);
  end
  else if FSelected >= 0 then
  begin
    FView.ShowList(FItems, FOrder, FSelected, FPrefix);
  end
  else
  begin
    FSelected := -1;
    // Solange noch nichts da ist, nichts zeigen; sonst den leeren Zustand.
    if FLoading and (Length(FItems) = 0) then
    begin
      FView.HideList;
    end
    else
    begin
      FEmpty := True;
      FView.ShowEmpty(FPrefix, Length(FItems));
    end;
  end;
end;

procedure TAtlasCompletionController.UpdatePrefix(const APrefix: string);
begin
  if not FActive or (APrefix = FPrefix) then
  begin
    Exit;
  end;
  // Weitertippen verwirft das Angebot „Mit try…finally absichern“ (#489).
  if (APrefix <> '') and TAtlasItemPresentation.Guarding(FItems) then
  begin
    Close;
    Exit;
  end;
  FPrefix := APrefix;
  Refresh(False);
end;

procedure TAtlasCompletionController.MoveSelection(APosition: Integer);
begin
  MoveSelection(APosition, 1);
end;

procedure TAtlasCompletionController.MoveSelection(APosition, ADirection: Integer);
begin
  // Erste Pfeiltaste ohne Auswahl (#471): die erste Deklaration wählen.
  if FPassive then
  begin
    FPassive := False;
    FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    Exit;
  end;
  // Überschriften (#419) werden übersprungen.
  APosition := FirstItemIn(FOrder, EnsureRange(APosition, 0, High(FOrder)), ADirection);
  if (APosition < 0) or (APosition = FSelected) then
  begin
    Exit;
  end;
  FSelected := APosition;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

function TAtlasCompletionController.MoveByKey(AKey: TAtlasNavigationKey; APage: Integer): Boolean;
begin
  Result := True;
  case AKey of
    TAtlasNavigationKey.Up:
      MoveSelection(FSelected - 1, -1);
    TAtlasNavigationKey.Down:
      MoveSelection(FSelected + 1);
    TAtlasNavigationKey.PageUp:
      MoveSelection(FSelected - APage, -1);
    TAtlasNavigationKey.PageDown:
      MoveSelection(FSelected + APage);
    TAtlasNavigationKey.First:
      MoveSelection(0);
    TAtlasNavigationKey.Last:
      MoveSelection(High(FOrder), -1);
  else
    Result := False;
  end;
end;

function TAtlasCompletionController.AcceptKey: Boolean;
begin
  Result := True;
  if FPassive then
  begin
    Close;
    Result := False;
  end
  else if SetMode then
  begin
    CommitSet;
  end
  else
  begin
    CommitSelected;
  end;
end;

function TAtlasCompletionController.ToggleKey: Boolean;
begin
  Result := SetMode;
  if Result then
  begin
    ToggleSelected;
  end;
end;

function TAtlasCompletionController.HandleKey(AKey: TAtlasNavigationKey): Boolean;
var
  mPage: Integer;
begin
  // Leerer Zustand: nur Esc gehört dem Popup; Pfeile und Enter gehen an den Editor.
  if FActive and FEmpty and (AKey = TAtlasNavigationKey.Cancel) then
  begin
    Dismiss;
    Exit(True);
  end;
  if not GetVisible then
  begin
    Exit(False);
  end;
  mPage := Max(1, FView.PageSize - 1);
  Result := True;
  if MoveByKey(AKey, mPage) then
  begin
    Exit;
  end;
  case AKey of
    TAtlasNavigationKey.Accept:
      Result := AcceptKey;
    TAtlasNavigationKey.Cancel:
      Dismiss;
    TAtlasNavigationKey.Toggle:
      Result := ToggleKey;
  else
    // Bewegungen hat MoveByKey genommen.
  end;
end;

procedure TAtlasCompletionController.ToggleSelected;
var
  mIndex: Integer;
begin
  if (FSelected < 0) or (FSelected > High(FOrder)) or TAtlasRanking.IsHeader(FOrder[FSelected]) then
  begin
    Exit;
  end;
  mIndex := FOrder[FSelected];
  FItems[mIndex].Checked := not FItems[mIndex].Checked;
  FToggled := True;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

procedure TAtlasCompletionController.CommitSet;
var
  mItem: TAtlasCompletionItem;
begin
  // Ohne Leertaste: Enter übernimmt den gewählten Wert zusätzlich zu den vorhandenen.
  if not FToggled and (FSelected >= 0) and (FSelected <= High(FOrder)) and
    not TAtlasRanking.IsHeader(FOrder[FSelected]) then
  begin
    FItems[FOrder[FSelected]].Checked := True;
  end;
  mItem := TAtlasCompletionSets.CommitItem(FItems);
  Close;
  if Assigned(FOnCommit) then
  begin
    FOnCommit(mItem);
  end;
end;

procedure TAtlasCompletionController.Select(APosition: Integer);
begin
  if GetVisible then
  begin
    MoveSelection(APosition);
  end;
end;

procedure TAtlasCompletionController.CommitSelected;
var
  mItem: TAtlasCompletionItem;
begin
  // Nicht sichtbare Mitglieder (#2108) lassen sich nicht einsetzen; die Liste bleibt offen.
  if not SelectedItem(mItem) or (mItem.Inaccessible <> '') then
  begin
    Exit;
  end;
  // Alle Felder zuweisen mit vielen Feldern (#491): erst die Liste mit Kontrollkästchen, Enter übernimmt.
  if Length(mItem.Assignments) > 0 then
  begin
    FItems := TAtlasCompletionSets.AssignItems(mItem);
    FToggled := True;
    // Die Liste zeigt alle Felder, auch wenn hinter dem Punkt schon etwas getippt ist; späte Antworten der
    // alten Anfrage gehören nicht mehr dazu.
    FPrefix := '';
    FChip := TAtlasChip.All;
    Inc(FGeneration);
    FLoading := False;
    Refresh(False);
    Exit;
  end;
  if FUsage <> nil then
  begin
    FUsage.Record_(mItem);
  end;
  Close;
  if Assigned(FOnCommit) then
  begin
    FOnCommit(mItem);
  end;
end;

end.
