unit Atlas.Core.Completion.Controller;

// Ablauf der Vervollständigung ohne Fenster und ohne IDE (#410, #414): Start
// fragt die Datenquelle (#408), eintreffende Einträge werden lokal nach dem
// getippten Präfix gefiltert (#409) und an die Ansicht gegeben. Tasten
// verschieben die Auswahl, Enter/Tab übernehmen, Esc schließt. Ohne Treffer
// zeigt die Ansicht den leeren Zustand (#423), statt zu verschwinden.
//
// Alle öffentlichen Methoden laufen im Hauptthread. Einträge aus anderen
// Threads stellt die Senke über TAtlasMainThread.Queue in den Hauptthread
// (beim Entladen verworfen, Code-Review A-02); was nach
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

  TAtlasCommitEvent = reference to procedure(const AItem: TAtlasCompletionItem);

  TAtlasCompletionController = class
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
  private
    FProvider: IAtlasCompletionProvider;
    FView: IAtlasCompletionView;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    FGeneration: Integer;
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
    FListMode: TAtlasListMode;
    FListScope: TAtlasListScope;
    /// <summary>Mitgliederliste nach "." (#497).</summary>
    FMembers: Boolean;
    FIncomplete: Boolean;
    /// <summary>Hinweis bei unvollständigem Code (#457): gezeigt bzw. von der laufenden Abfrage gemeldet.</summary>
    FSyntax: TAtlasSyntaxNotice;
    FPendingSyntax: TAtlasSyntaxNotice;
    /// <summary>Die nächsten Einträge ersetzen die Liste (laufendes Requery).</summary>
    FReplace: Boolean;
    FOnCommit: TAtlasCommitEvent;
    FGroupInherited: Boolean;
    FChipsEnabled: Boolean;
    FChip: TAtlasChip;
    FUsage: TAtlasUsage;
    FFavorites: TAtlasFavorites;
    /// <summary>Zeichen, nach dem automatisch geöffnet wurde (#448).</summary>
    FTrigger: string;
    /// <summary>Im Mengenmodus schon umgeschaltet.</summary>
    FToggled: Boolean;
    /// <summary>Wort der offenen Liste: Datei, Zeile, Wortanfang (#414).</summary>
    FWordFile: string;
    FWordLine: Integer;
    FWordStart: Integer;
    /// <summary>Mit Esc geschlossenes Wort; FDismissedLine &lt; 0 ohne.</summary>
    FDismissedFile: string;
    FDismissedLine: Integer;
    FDismissedStart: Integer;
    procedure Dismiss;
    procedure ToggleSelected;
    procedure CommitSet;
    procedure ShowChips;
    function FirstItemFrom(APosition, ADirection: Integer): Integer;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TAtlasCompletionItems);
    /// <summary>Marken „zuletzt“/„häufig“ (#418) und Favorit (#458) ab AFrom setzen.</summary>
    procedure MarkItems(AFrom: Integer);
    procedure IncompleteArrived(AGeneration: Integer);
    procedure SyntaxArrived(AGeneration: Integer; const ANotice: TAtlasSyntaxNotice);
    /// <summary>FSyntax an eine Ansicht mit IAtlasCompletionSyntaxView.</summary>
    procedure ShowSyntax;
    procedure Query(const AContext: TAtlasContext);
    procedure SelectByName(const AName: string);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    procedure MoveSelection(APosition: Integer; ADirection: Integer = 1);
    function GetVisible: Boolean;
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
    property OnCommit: TAtlasCommitEvent read FOnCommit write FOnCommit;
    /// <summary>Filter-Chip wählen (#422); gilt bis zum Schließen.</summary>
    procedure SelectChip(AChip: TAtlasChip);
    /// <summary>Chip an Position AIndex (0-basiert) unter den angezeigten (Alt+1 … Alt+6).</summary>
    procedure SelectChipAt(AIndex: Integer);
    property Chip: TAtlasChip read FChip;
    /// <summary>Geerbte Member gruppieren (#419).</summary>
    property GroupInherited: Boolean read FGroupInherited write FGroupInherited;
    property ChipsEnabled: Boolean read FChipsEnabled write FChipsEnabled;
    /// <summary>Einträge ohne Treffer zeigen (#497); Filter = nur Treffer.</summary>
    property ListMode: TAtlasListMode read FListMode write FListMode;
    /// <summary>Wo ListMode gilt (#497).</summary>
    property ListScope: TAtlasListScope read FListScope write FListScope;
    /// <summary>Position des ersten Eintrags ohne Treffer in Order (#497); -1 ohne.</summary>
    property RestStart: Integer read FRestStart;
    /// <summary>Lernende Gewichtung (#418); nil = aus. Gehört dem Aufrufer.</summary>
    property Usage: TAtlasUsage read FUsage write FUsage;
    /// <summary>Angeheftete Favoriten (#458); nil = aus. Gehört dem Aufrufer.</summary>
    property Favorites: TAtlasFavorites read FFavorites write FFavorites;
    /// <summary>Eintrag an APosition (Anzeigereihenfolge) anheften bzw. lösen (Klick auf den Stern); AItem ist
    /// der Eintrag. Added bzw. Removed sortieren neu, die Auswahl bleibt auf dem gewählten Eintrag. NotAllowed
    /// ohne Favoriten, ohne Liste oder auf einer Überschrift.</summary>
    function ToggleFavorite(APosition: Integer; out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
    /// <summary>Wie ToggleFavorite für den gewählten Eintrag (Strg+D); NotAllowed, wenn nichts gewählt ist.</summary>
    function ToggleSelectedFavorite(out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
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
    Result := Result + ', automatisch'
  else
    Result := Result + ', Strg+Leer';
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
  Controller: TAtlasCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
  Items: TAtlasCompletionItems;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  Items := AItems;
  // Im Hauptthread läuft Queue sofort, sonst beim nächsten CheckSynchronize; beim Entladen verworfen (A-02).
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            Controller.ItemsArrived(Generation, Items);
          end);
    end);
end;

procedure TAtlasCompletionController.TControllerSink.MarkIncomplete;
var
  Controller: TAtlasCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            Controller.IncompleteArrived(Generation);
          end);
    end);
end;

procedure TAtlasCompletionController.TControllerSink.MarkSyntax(const ANotice: TAtlasSyntaxNotice);
var
  Controller: TAtlasCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
  Notice: TAtlasSyntaxNotice;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  Notice := ANotice;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            Controller.SyntaxArrived(Generation, Notice);
          end);
    end);
end;

procedure TAtlasCompletionController.TControllerSink.Complete;
var
  Controller: TAtlasCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  TAtlasMainThread.Queue(TAtlasFeature.Completion,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        TAtlasGuard.Run(TAtlasFeature.Completion,
          procedure
          begin
            Controller.Completed(Generation);
          end);
    end);
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
  FDismissedLine := -1;
end;

destructor TAtlasCompletionController.Destroy;
begin
  Close;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  inherited;
end;

function TAtlasCompletionController.GetVisible: Boolean;
begin
  Result := FActive and (FSelected >= 0) and (Length(FOrder) > 0);
end;

function TAtlasCompletionController.FirstItemFrom(APosition, ADirection: Integer): Integer;
begin
  // Nächster Eintrag ab APosition in Richtung ADirection, sonst in der Gegenrichtung; -1 ohne.
  Result := APosition;
  while (Result >= 0) and (Result <= High(FOrder)) and TAtlasRanking.IsHeader(FOrder[Result]) do
    Inc(Result, ADirection);
  if (Result >= 0) and (Result <= High(FOrder)) then
    Exit;
  Result := APosition;
  while (Result >= 0) and (Result <= High(FOrder)) and TAtlasRanking.IsHeader(FOrder[Result]) do
    Dec(Result, ADirection);
  if (Result < 0) or (Result > High(FOrder)) then
    Result := -1;
end;

procedure TAtlasCompletionController.ShowChips;
begin
  if FChipsEnabled then
    FView.ShowChips(TAtlasRanking.ChipCounts(FItems, FPrefix), FChip, Length(FItems) > 0)
  else
    FView.ShowChips(Default(TAtlasChipCounts), TAtlasChip.All, False);
end;

procedure TAtlasCompletionController.SelectChip(AChip: TAtlasChip);
begin
  if not FActive or (AChip = FChip) then
    Exit;
  FChip := AChip;
  Refresh(True);
end;

procedure TAtlasCompletionController.SelectChipAt(AIndex: Integer);
var
  Counts: TAtlasChipCounts;
  mChip: TAtlasChip;
begin
  // Wie angezeigt: nur Chips mit Treffern, "Alle" immer.
  Counts := TAtlasRanking.ChipCounts(FItems, FPrefix);
  for mChip := Low(TAtlasChip) to High(TAtlasChip) do
    if (mChip = TAtlasChip.All) or (Counts[mChip] > 0) then
    begin
      if AIndex = 0 then
      begin
        SelectChip(mChip);
        Exit;
      end;
      Dec(AIndex);
    end;
end;

function TAtlasCompletionController.Dismissed(const AContext: TAtlasContext): Boolean;
begin
  Result := (FDismissedLine >= 0) and (AContext.Line = FDismissedLine) and
    (AContext.Character - Length(AContext.Prefix) = FDismissedStart) and SameText(AContext.FileName, FDismissedFile);
end;

procedure TAtlasCompletionController.Dismiss;
begin
  FDismissedFile := FWordFile;
  FDismissedLine := FWordLine;
  FDismissedStart := FWordStart;
  Close;
end;

procedure TAtlasCompletionController.Start(const AContext: TAtlasContext);
begin
  Close;
  if AContext.Automatic and Dismissed(AContext) then
    Exit;
  // Ein anderes Wort oder Strg+Leer hebt die Sperre auf.
  FDismissedLine := -1;
  FWordFile := AContext.FileName;
  FWordLine := AContext.Line;
  FWordStart := AContext.Character - Length(AContext.Prefix);
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FChip := TAtlasChip.All;
  FPrefix := AContext.Prefix;
  FTrigger := AContext.Trigger;
  FMembers := AContext.Kind = TAtlasContextKind.MemberAccess;
  FRestStart := -1;
  FToggled := False;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  if TAtlasQueryTimings.Enabled and (TAtlasQueryTimings.Shared <> nil) then
    TAtlasQueryTimings.Shared.BeginQuery(AContext.Started, TimingKind(AContext), ExtractFileName(AContext.FileName));
  Query(AContext);
end;

procedure TAtlasCompletionController.Query(const AContext: TAtlasContext);
var
  Sink: IAtlasCompletionSink;
begin
  FIncomplete := False;
  FPendingSyntax := Default(TAtlasSyntaxNotice);
  FQueryPrefix := AContext.Prefix;
  Sink := TControllerSink.Create(Self, FFlag, FGeneration);
  FProvider.Query(AContext, Sink);
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
    FIncomplete := True;
end;

procedure TAtlasCompletionController.SyntaxArrived(AGeneration: Integer; const ANotice: TAtlasSyntaxNotice);
begin
  if not FActive or (AGeneration <> FGeneration) then
    Exit;
  FPendingSyntax := ANotice;
  FSyntax := ANotice;
  ShowSyntax;
end;

procedure TAtlasCompletionController.ShowSyntax;
var
  View: IAtlasCompletionSyntaxView;
begin
  if Supports(FView, IAtlasCompletionSyntaxView, View) then
    View.ShowSyntax(FSyntax);
end;

procedure TAtlasCompletionController.SelectByName(const AName: string);
var
  Position: Integer;
begin
  for Position := 0 to High(FOrder) do
    if not TAtlasRanking.IsHeader(FOrder[Position]) and (FItems[FOrder[Position]].Name = AName) then
    begin
      FSelected := Position;
      Exit;
    end;
end;

procedure TAtlasCompletionController.Close;
begin
  if not FActive then
    Exit;
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
  Item: TAtlasCompletionItem;
  SelectedName: string;
begin
  if not FActive or (AGeneration <> FGeneration) or (Length(AItems) = 0) then
    Exit;
  if FReplace then
  begin
    // Neue Liste nach Requery: ersetzen, die Auswahl bleibt auf demselben Eintrag.
    SelectedName := '';
    if SelectedItem(Item) then
      SelectedName := Item.Name;
    FReplace := False;
    FItems := AItems;
    MarkItems(0);
    Refresh(False);
    if (SelectedName <> '') and (Length(FOrder) > 0) then
    begin
      SelectByName(SelectedName);
      FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    end;
    Exit;
  end;
  FItems := FItems + AItems;
  MarkItems(Length(FItems) - Length(AItems));
  Refresh(True);
end;

procedure TAtlasCompletionController.MarkItems(AFrom: Integer);
var
  Index: Integer;
begin
  for Index := Max(0, AFrom) to High(FItems) do
  begin
    if FUsage <> nil then
      FItems[Index].Usage := FUsage.Mark(FItems[Index]);
    FItems[Index].Favorite := (FFavorites <> nil) and FFavorites.IsFavorite(FItems[Index]);
  end;
end;

function TAtlasCompletionController.ToggleFavorite(APosition: Integer;
  out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
begin
  Result := TAtlasFavoriteToggle.NotAllowed;
  AItem := Default(TAtlasCompletionItem);
  if (FFavorites = nil) or not FActive or (APosition < 0) or (APosition > High(FOrder)) or
    TAtlasRanking.IsHeader(FOrder[APosition]) then
    Exit;
  AItem := FItems[FOrder[APosition]];
  Result := FFavorites.Toggle(AItem);
  if (Result <> TAtlasFavoriteToggle.Added) and (Result <> TAtlasFavoriteToggle.Removed) then
    Exit;
  // Alle Einträge neu markieren: Derselbe Member kann aus mehreren Quellen kommen.
  MarkItems(0);
  AItem.Favorite := Result = TAtlasFavoriteToggle.Added;
  Refresh(True);
end;

function TAtlasCompletionController.ToggleSelectedFavorite(out AItem: TAtlasCompletionItem): TAtlasFavoriteToggle;
begin
  if not SelectedItem(AItem) then
    Exit(TAtlasFavoriteToggle.NotAllowed);
  Result := ToggleFavorite(FSelected, AItem);
end;

procedure TAtlasCompletionController.Completed(AGeneration: Integer);
begin
  if not FActive or (AGeneration <> FGeneration) then
    Exit;
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
    Refresh(False);
end;

procedure TAtlasCompletionController.Refresh(AKeepSelection: Boolean);
var
  SelectedIndex, Position, Shown: Integer;
  Options: TAtlasRankOptions;
  mUsage: TAtlasUsage;
  mItems: TAtlasCompletionItems;
  Timings: TAtlasQueryTimings;
  Stamp: Int64;
begin
  // Diagnosemodus (#479): nur an einen Zeitstempel nehmen.
  Timings := nil;
  Stamp := 0;
  if TAtlasQueryTimings.Enabled then
  begin
    Timings := TAtlasQueryTimings.Shared;
    Stamp := TAtlasQueryTimings.Stamp;
  end;
  SelectedIndex := -1;
  if AKeepSelection and not FPassive and (FSelected >= 0) and (FSelected < Length(FOrder)) then
    SelectedIndex := FOrder[FSelected];
  Options := TAtlasRankOptions.Defaults;
  Options.GroupInherited := FGroupInherited;
  if FChipsEnabled then
    Options.Chip := FChip;
  if FMembers or (FListScope = TAtlasListScope.Everywhere) then
    Options.ListMode := FListMode;
  if FUsage <> nil then
  begin
    mUsage := FUsage;
    mItems := FItems;
    Options.Boost :=
      function(AIndex: Integer): Integer
      begin
        Result := mUsage.Boost(mItems[AIndex]);
      end;
  end;
  FOrder := TAtlasRanking.Order(FItems, FPrefix, Options, FRestStart);
  if Timings <> nil then
  begin
    Shown := 0;
    for Position := 0 to High(FOrder) do
      if not TAtlasRanking.IsHeader(FOrder[Position]) then
        Inc(Shown);
    Timings.FilterSorted(TAtlasQueryTimings.MsSince(Stamp), Length(FItems), Shown);
  end;
  FSelected := FirstItemFrom(0, 1);
  // Hinweise (#466) stehen oben, gewählt ist der erste Eintrag danach.
  Position := FSelected;
  while (Position >= 0) and (Position <= High(FOrder)) and (TAtlasRanking.IsHeader(FOrder[Position]) or
    FItems[FOrder[Position]].Hint) do
    Inc(Position);
  if (FSelected >= 0) and (Position <= High(FOrder)) then
    FSelected := Position;
  ShowChips;
  if SelectedIndex >= 0 then
    for Position := 0 to High(FOrder) do
      if FOrder[Position] = SelectedIndex then
      begin
        FSelected := Position;
        Break;
      end;
  FEmpty := False;
  // Nur Deklarationen (#471): sichtbar, aber nicht gewählt, solange niemand eine Pfeiltaste drückt.
  // Ebenso, wenn oben kein Treffer steht, nur der Rest (#497).
  FPassive := (FSelected >= 0) and ((FItems[FOrder[FSelected]].Unknown <> '') or FItems[FOrder[FSelected]].Hint or
    ((FRestStart >= 0) and (FSelected >= FRestStart))) and ((SelectedIndex < 0) or (FOrder[FSelected] <> SelectedIndex));
  if (Timings <> nil) and (FSelected >= 0) then
    Timings.ListShown;
  if FPassive then
    FView.ShowList(FItems, FOrder, -1, FPrefix)
  else if FSelected >= 0 then
    FView.ShowList(FItems, FOrder, FSelected, FPrefix)
  else
  begin
    FSelected := -1;
    // Solange noch nichts da ist, nichts zeigen; sonst den leeren Zustand.
    if FLoading and (Length(FItems) = 0) then
      FView.HideList
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
    Exit;
  // Weitertippen verwirft das Angebot „Mit try…finally absichern“ (#489).
  if (APrefix <> '') and TAtlasItemPresentation.Guarding(FItems) then
  begin
    Close;
    Exit;
  end;
  FPrefix := APrefix;
  Refresh(False);
end;

procedure TAtlasCompletionController.MoveSelection(APosition: Integer; ADirection: Integer);
begin
  // Erste Pfeiltaste ohne Auswahl (#471): die erste Deklaration wählen.
  if FPassive then
  begin
    FPassive := False;
    FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    Exit;
  end;
  // Überschriften (#419) werden übersprungen.
  APosition := FirstItemFrom(EnsureRange(APosition, 0, High(FOrder)), ADirection);
  if (APosition < 0) or (APosition = FSelected) then
    Exit;
  FSelected := APosition;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

function TAtlasCompletionController.HandleKey(AKey: TAtlasNavigationKey): Boolean;
var
  Page: Integer;
begin
  // Leerer Zustand: nur Esc gehört dem Popup; Pfeile und Enter gehen an den Editor.
  if FActive and FEmpty and (AKey = TAtlasNavigationKey.Cancel) then
  begin
    Dismiss;
    Exit(True);
  end;
  if not GetVisible then
    Exit(False);
  Result := True;
  Page := Max(1, FView.PageSize - 1);
  case AKey of
    TAtlasNavigationKey.Up:
      MoveSelection(FSelected - 1, -1);
    TAtlasNavigationKey.Down:
      MoveSelection(FSelected + 1);
    TAtlasNavigationKey.PageUp:
      MoveSelection(FSelected - Page, -1);
    TAtlasNavigationKey.PageDown:
      MoveSelection(FSelected + Page);
    TAtlasNavigationKey.First:
      MoveSelection(0);
    TAtlasNavigationKey.Last:
      MoveSelection(High(FOrder), -1);
    TAtlasNavigationKey.Accept:
      if FPassive then
      begin
        Close;
        Result := False;
      end
      else if SetMode then
        CommitSet
      else
        CommitSelected;
    TAtlasNavigationKey.Cancel:
      Dismiss;
    TAtlasNavigationKey.Toggle:
      if SetMode then
        ToggleSelected
      else
        Result := False;
  end;
end;

function TAtlasCompletionController.SetMode: Boolean;
begin
  Result := FActive and TAtlasCompletionSets.Active(FItems);
end;

procedure TAtlasCompletionController.ToggleSelected;
var
  Index: Integer;
begin
  if (FSelected < 0) or (FSelected > High(FOrder)) or TAtlasRanking.IsHeader(FOrder[FSelected]) then
    Exit;
  Index := FOrder[FSelected];
  FItems[Index].Checked := not FItems[Index].Checked;
  FToggled := True;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

procedure TAtlasCompletionController.CommitSet;
var
  Item: TAtlasCompletionItem;
begin
  // Ohne Leertaste: Enter übernimmt den gewählten Wert zusätzlich zu den vorhandenen.
  if not FToggled and (FSelected >= 0) and (FSelected <= High(FOrder)) and
    not TAtlasRanking.IsHeader(FOrder[FSelected]) then
    FItems[FOrder[FSelected]].Checked := True;
  Item := TAtlasCompletionSets.CommitItem(FItems);
  Close;
  if Assigned(FOnCommit) then
    FOnCommit(Item);
end;

procedure TAtlasCompletionController.Select(APosition: Integer);
begin
  if GetVisible then
    MoveSelection(APosition);
end;

function TAtlasCompletionController.SelectedItem(out AItem: TAtlasCompletionItem): Boolean;
begin
  Result := GetVisible and not FPassive and (FSelected >= 0) and (FSelected < Length(FOrder));
  if Result then
    AItem := FItems[FOrder[FSelected]]
  else
    AItem := Default(TAtlasCompletionItem);
end;

function TAtlasCompletionController.CanCommitOnCharacter: Boolean;
var
  Item: TAtlasCompletionItem;
begin
  // Code-Vorlagen (#51) nur über Enter oder Tab: "while(" soll keine Schleife einsetzen.
  Result := (FPrefix <> '') and SelectedItem(Item) and (Item.Snippet = '') and
    (TAtlasCompletionMatcher.Score(FPrefix, Item.Name) >= TAtlasCompletionMatcher.ScoreWordStarts);
end;

function TAtlasCompletionController.NeedsQuery(const APrefix: string): Boolean;
begin
  Result := FActive and (FIncomplete or not APrefix.StartsWith(FQueryPrefix, True));
end;

procedure TAtlasCompletionController.CommitSelected;
var
  Item: TAtlasCompletionItem;
begin
  if not SelectedItem(Item) then
    Exit;
  // Alle Felder zuweisen mit vielen Feldern (#491): erst die Liste mit Kontrollkästchen, Enter übernimmt.
  if Length(Item.Assignments) > 0 then
  begin
    FItems := TAtlasCompletionSets.AssignItems(Item);
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
    FUsage.Record_(Item);
  Close;
  if Assigned(FOnCommit) then
    FOnCommit(Item);
end;

end.
