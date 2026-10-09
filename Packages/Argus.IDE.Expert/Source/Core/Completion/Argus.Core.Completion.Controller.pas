unit Argus.Core.Completion.Controller;

// Ablauf der Vervollständigung ohne Fenster und ohne IDE (#410, #414): Start
// fragt die Datenquelle (#408), eintreffende Einträge werden lokal nach dem
// getippten Präfix gefiltert (#409) und an die Ansicht gegeben. Tasten
// verschieben die Auswahl, Enter/Tab übernehmen, Esc schließt. Ohne Treffer
// zeigt die Ansicht den leeren Zustand (#423), statt zu verschwinden.
//
// Alle öffentlichen Methoden laufen im Hauptthread. Einträge aus anderen
// Threads stellt die Senke über TThread.Queue in den Hauptthread; was nach
// Close, einem neuen Start oder dem Freigeben ankommt, wird verworfen.
//
// Gekürzte Listen (#431, LSP isIncomplete): Beim Weitertippen filtert Requery
// sofort lokal und fragt im Hintergrund neu; die neue Liste ersetzt die alte,
// sobald sie eintrifft, und die Auswahl bleibt auf demselben Eintrag.
//
// Rangfolge über TArgusRanking: Lernzuschlag (#418, Usage), Gruppen geerbter
// Member mit Überschriften (#419; Header in der Reihenfolge, die Auswahl
// überspringt sie), Filter-Chips (#422).

interface

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Completion.Contract,
  Argus.Core.Completion.Ranking,
  Argus.Core.Completion.Usage;

{$SCOPEDENUMS ON}

type
  TArgusNavigationKey = (Up, Down, PageUp, PageDown, First, Last, Accept, Cancel);

  /// <summary>Anzeige der Liste; umgesetzt vom Popup (Argus.UI) bzw. von Tests.</summary>
  IArgusCompletionView = interface
    ['{8D2F4B61-3E9A-4C57-A1D0-6B7E2F9C3A15}']
    /// <summary>Zeigt bzw. aktualisiert die Liste. AOrder: Indizes in AItems in Anzeigereihenfolge;
    /// ASelected: Position in AOrder; APattern: getippter Anfang, zum Hervorheben der Treffer.</summary>
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer;
      const APattern: string);
    procedure HideList;
    /// <summary>Leerer Zustand (#423): keine Treffer für APrefix unter ATotal Einträgen.</summary>
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    /// <summary>Zahl der sichtbaren Zeilen für Bild auf/ab.</summary>
    function PageSize: Integer;
    /// <summary>Filter-Chips (#422): Treffer je Art, gewählter Chip; AVisible = False blendet sie aus.</summary>
    procedure ShowChips(const ACounts: TArgusChipCounts; AActive: TArgusChip; AVisible: Boolean);
  end;

  TArgusCommitEvent = reference to procedure(const AItem: TArgusCompletionItem);

  TArgusCompletionController = class
  private type
    /// <summary>Lebt, solange eine Senke oder ein eingereihter Aufruf ihn hält.</summary>
    TAliveFlag = class(TInterfacedObject)
    public
      Alive: Boolean;
    end;

    TControllerSink = class(TInterfacedObject, IArgusCompletionSink)
    private
      FController: TArgusCompletionController;
      FFlag: TAliveFlag;
      FFlagRef: IInterface;
      FGeneration: Integer;
    public
      constructor Create(AController: TArgusCompletionController; AFlag: TAliveFlag; AGeneration: Integer);
      procedure AddItems(const AItems: TArgusCompletionItems);
      procedure MarkIncomplete;
      procedure Complete;
    end;
  private
    FProvider: IArgusCompletionProvider;
    FView: IArgusCompletionView;
    FFlag: TAliveFlag;
    FFlagRef: IInterface;
    FGeneration: Integer;
    FActive: Boolean;
    FLoading: Boolean;
    FItems: TArgusCompletionItems;
    FOrder: TArray<Integer>;
    FSelected: Integer;
    FPrefix: string;
    FEmpty: Boolean;
    FIncomplete: Boolean;
    /// <summary>Die nächsten Einträge ersetzen die Liste (laufendes Requery).</summary>
    FReplace: Boolean;
    FOnCommit: TArgusCommitEvent;
    FGroupInherited: Boolean;
    FChipsEnabled: Boolean;
    FChip: TArgusChip;
    FUsage: TArgusUsage;
    procedure ShowChips;
    function FirstItemFrom(APosition, ADirection: Integer): Integer;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TArgusCompletionItems);
    procedure IncompleteArrived(AGeneration: Integer);
    procedure Query(const AContext: TArgusContext);
    procedure SelectByName(const AName: string);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    procedure MoveSelection(APosition: Integer; ADirection: Integer = 1);
    function GetVisible: Boolean;
  public
    constructor Create(const AProvider: IArgusCompletionProvider; const AView: IArgusCompletionView);
    destructor Destroy; override;
    /// <summary>Neue Vervollständigung an AContext; schließt eine offene.</summary>
    procedure Start(const AContext: TArgusContext);
    /// <summary>Das Wort unter dem Cursor hat sich geändert: neu filtern.</summary>
    procedure UpdatePrefix(const APrefix: string);
    /// <summary>Wie UpdatePrefix, fragt aber zusätzlich neu an (gekürzte Liste, #431).</summary>
    procedure Requery(const AContext: TArgusContext);
    procedure Close;
    /// <summary>True, wenn die Taste verbraucht wurde; nur bei sichtbarer Liste.</summary>
    function HandleKey(AKey: TArgusNavigationKey): Boolean;
    /// <summary>Auswahl per Maus; APosition in der Anzeigereihenfolge.</summary>
    procedure Select(APosition: Integer);
    procedure CommitSelected;
    function SelectedItem(out AItem: TArgusCompletionItem): Boolean;
    /// <summary>Ein Commit-Zeichen (#429) darf übernehmen: Liste offen und der gewählte Eintrag
    /// trifft das Präfix klar (genau, Anfang, Wortanfänge), nicht nur unscharf.</summary>
    function CanCommitOnCharacter: Boolean;
    property Active: Boolean read FActive;
    property Loading: Boolean read FLoading;
    /// <summary>Liste ist offen und hat Treffer.</summary>
    property Visible: Boolean read GetVisible;
    /// <summary>Leerer Zustand wird gezeigt (#423).</summary>
    property Empty: Boolean read FEmpty;
    /// <summary>Die Quelle hat gekürzt; beim Weitertippen Requery statt UpdatePrefix.</summary>
    property Incomplete: Boolean read FIncomplete;
    property Prefix: string read FPrefix;
    property Items: TArgusCompletionItems read FItems;
    property Order: TArray<Integer> read FOrder;
    property Selected: Integer read FSelected;
    property OnCommit: TArgusCommitEvent read FOnCommit write FOnCommit;
    /// <summary>Filter-Chip wählen (#422); gilt bis zum Schließen.</summary>
    procedure SelectChip(AChip: TArgusChip);
    /// <summary>Chip an Position AIndex (0-basiert) unter den angezeigten (Alt+1 … Alt+6).</summary>
    procedure SelectChipAt(AIndex: Integer);
    property Chip: TArgusChip read FChip;
    /// <summary>Geerbte Member gruppieren (#419).</summary>
    property GroupInherited: Boolean read FGroupInherited write FGroupInherited;
    property ChipsEnabled: Boolean read FChipsEnabled write FChipsEnabled;
    /// <summary>Lernende Gewichtung (#418); nil = aus. Gehört dem Aufrufer.</summary>
    property Usage: TArgusUsage read FUsage write FUsage;
  end;

implementation

uses
  System.Math,
  Argus.Core.Completion.Matching;

{ TArgusCompletionController.TControllerSink }

constructor TArgusCompletionController.TControllerSink.Create(AController: TArgusCompletionController;
  AFlag: TAliveFlag; AGeneration: Integer);
begin
  inherited Create;
  FController := AController;
  FFlag := AFlag;
  FFlagRef := AFlag;
  FGeneration := AGeneration;
end;

procedure TArgusCompletionController.TControllerSink.AddItems(const AItems: TArgusCompletionItems);
var
  Controller: TArgusCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
  Items: TArgusCompletionItems;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  Items := AItems;
  // Im Hauptthread läuft Queue sofort, sonst beim nächsten CheckSynchronize.
  TThread.Queue(nil,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        Controller.ItemsArrived(Generation, Items);
    end);
end;

procedure TArgusCompletionController.TControllerSink.MarkIncomplete;
var
  Controller: TArgusCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  TThread.Queue(nil,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        Controller.IncompleteArrived(Generation);
    end);
end;

procedure TArgusCompletionController.TControllerSink.Complete;
var
  Controller: TArgusCompletionController;
  Flag: TAliveFlag;
  FlagRef: IInterface;
  Generation: Integer;
begin
  Controller := FController;
  Flag := FFlag;
  FlagRef := FFlagRef;
  Generation := FGeneration;
  TThread.Queue(nil,
    procedure
    begin
      if Flag.Alive and (FlagRef <> nil) then
        Controller.Completed(Generation);
    end);
end;

{ TArgusCompletionController }

constructor TArgusCompletionController.Create(const AProvider: IArgusCompletionProvider;
  const AView: IArgusCompletionView);
begin
  inherited Create;
  FProvider := AProvider;
  FView := AView;
  FFlag := TAliveFlag.Create;
  FFlag.Alive := True;
  FFlagRef := FFlag;
  FSelected := -1;
end;

destructor TArgusCompletionController.Destroy;
begin
  Close;
  // Eingereihte Aufrufe halten den Merker selbst und sehen dann Alive = False.
  FFlag.Alive := False;
  FFlagRef := nil;
  inherited;
end;

function TArgusCompletionController.GetVisible: Boolean;
begin
  Result := FActive and (FSelected >= 0) and (Length(FOrder) > 0);
end;

function TArgusCompletionController.FirstItemFrom(APosition, ADirection: Integer): Integer;
begin
  // Nächster Eintrag ab APosition in Richtung ADirection, sonst in der Gegenrichtung; -1 ohne.
  Result := APosition;
  while (Result >= 0) and (Result <= High(FOrder)) and (FOrder[Result] = TArgusRanking.Header) do
    Inc(Result, ADirection);
  if (Result >= 0) and (Result <= High(FOrder)) then
    Exit;
  Result := APosition;
  while (Result >= 0) and (Result <= High(FOrder)) and (FOrder[Result] = TArgusRanking.Header) do
    Dec(Result, ADirection);
  if (Result < 0) or (Result > High(FOrder)) then
    Result := -1;
end;

procedure TArgusCompletionController.ShowChips;
begin
  if FChipsEnabled then
    FView.ShowChips(TArgusRanking.ChipCounts(FItems, FPrefix), FChip, Length(FItems) > 0)
  else
    FView.ShowChips(Default(TArgusChipCounts), TArgusChip.All, False);
end;

procedure TArgusCompletionController.SelectChip(AChip: TArgusChip);
begin
  if not FActive or (AChip = FChip) then
    Exit;
  FChip := AChip;
  Refresh(True);
end;

procedure TArgusCompletionController.SelectChipAt(AIndex: Integer);
var
  Counts: TArgusChipCounts;
  Chip: TArgusChip;
begin
  // Wie angezeigt: nur Chips mit Treffern, "Alle" immer.
  Counts := TArgusRanking.ChipCounts(FItems, FPrefix);
  for Chip := Low(TArgusChip) to High(TArgusChip) do
    if (Chip = TArgusChip.All) or (Counts[Chip] > 0) then
    begin
      if AIndex = 0 then
      begin
        SelectChip(Chip);
        Exit;
      end;
      Dec(AIndex);
    end;
end;

procedure TArgusCompletionController.Start(const AContext: TArgusContext);
begin
  Close;
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FChip := TArgusChip.All;
  FPrefix := AContext.Prefix;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  Query(AContext);
end;

procedure TArgusCompletionController.Query(const AContext: TArgusContext);
var
  Sink: IArgusCompletionSink;
begin
  FIncomplete := False;
  Sink := TControllerSink.Create(Self, FFlag, FGeneration);
  FProvider.Query(AContext, Sink);
end;

procedure TArgusCompletionController.Requery(const AContext: TArgusContext);
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

procedure TArgusCompletionController.IncompleteArrived(AGeneration: Integer);
begin
  if FActive and (AGeneration = FGeneration) then
    FIncomplete := True;
end;

procedure TArgusCompletionController.SelectByName(const AName: string);
var
  Position: Integer;
begin
  for Position := 0 to High(FOrder) do
    if (FOrder[Position] <> TArgusRanking.Header) and (FItems[FOrder[Position]].Name = AName) then
    begin
      FSelected := Position;
      Exit;
    end;
end;

procedure TArgusCompletionController.Close;
begin
  if not FActive then
    Exit;
  FActive := False;
  FLoading := False;
  FIncomplete := False;
  FReplace := False;
  Inc(FGeneration);
  FProvider.Cancel;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  FView.HideList;
end;

procedure TArgusCompletionController.ItemsArrived(AGeneration: Integer; const AItems: TArgusCompletionItems);
var
  Item: TArgusCompletionItem;
  SelectedName: string;
  Index: Integer;
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
    if FUsage <> nil then
      for Index := 0 to High(FItems) do
        FItems[Index].Usage := FUsage.Mark(FItems[Index]);
    Refresh(False);
    if (SelectedName <> '') and (Length(FOrder) > 0) then
    begin
      SelectByName(SelectedName);
      FView.ShowList(FItems, FOrder, FSelected, FPrefix);
    end;
    Exit;
  end;
  FItems := FItems + AItems;
  if FUsage <> nil then
    for Index := Length(FItems) - Length(AItems) to High(FItems) do
      FItems[Index].Usage := FUsage.Mark(FItems[Index]);
  Refresh(True);
end;

procedure TArgusCompletionController.Completed(AGeneration: Integer);
begin
  if not FActive or (AGeneration <> FGeneration) then
    Exit;
  FLoading := False;
  // Requery ohne Einträge: Die alte Liste gilt nicht mehr.
  if FReplace then
  begin
    FReplace := False;
    FItems := nil;
  end;
  // Nichts gefunden: leerer Zustand statt kommentarlos zu verschwinden (#423).
  if Length(FItems) = 0 then
    Refresh(False);
end;

procedure TArgusCompletionController.Refresh(AKeepSelection: Boolean);
var
  SelectedIndex, Position: Integer;
  Options: TArgusRankOptions;
  Usage: TArgusUsage;
  Items: TArgusCompletionItems;
begin
  SelectedIndex := -1;
  if AKeepSelection and (FSelected >= 0) and (FSelected < Length(FOrder)) then
    SelectedIndex := FOrder[FSelected];
  Options := TArgusRankOptions.Defaults;
  Options.GroupInherited := FGroupInherited;
  if FChipsEnabled then
    Options.Chip := FChip;
  if FUsage <> nil then
  begin
    Usage := FUsage;
    Items := FItems;
    Options.Boost :=
      function(AIndex: Integer): Integer
      begin
        Result := Usage.Boost(Items[AIndex]);
      end;
  end;
  FOrder := TArgusRanking.Order(FItems, FPrefix, Options);
  FSelected := FirstItemFrom(0, 1);
  ShowChips;
  if SelectedIndex >= 0 then
    for Position := 0 to High(FOrder) do
      if FOrder[Position] = SelectedIndex then
      begin
        FSelected := Position;
        Break;
      end;
  FEmpty := False;
  if FSelected >= 0 then
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

procedure TArgusCompletionController.UpdatePrefix(const APrefix: string);
begin
  if not FActive or (APrefix = FPrefix) then
    Exit;
  FPrefix := APrefix;
  Refresh(False);
end;

procedure TArgusCompletionController.MoveSelection(APosition: Integer; ADirection: Integer);
begin
  // Überschriften (#419) werden übersprungen.
  APosition := FirstItemFrom(EnsureRange(APosition, 0, High(FOrder)), ADirection);
  if (APosition < 0) or (APosition = FSelected) then
    Exit;
  FSelected := APosition;
  FView.ShowList(FItems, FOrder, FSelected, FPrefix);
end;

function TArgusCompletionController.HandleKey(AKey: TArgusNavigationKey): Boolean;
var
  Page: Integer;
begin
  // Leerer Zustand: nur Esc gehört dem Popup; Pfeile und Enter gehen an den Editor.
  if FActive and FEmpty and (AKey = TArgusNavigationKey.Cancel) then
  begin
    Close;
    Exit(True);
  end;
  if not GetVisible then
    Exit(False);
  Result := True;
  Page := Max(1, FView.PageSize - 1);
  case AKey of
    TArgusNavigationKey.Up:
      MoveSelection(FSelected - 1, -1);
    TArgusNavigationKey.Down:
      MoveSelection(FSelected + 1);
    TArgusNavigationKey.PageUp:
      MoveSelection(FSelected - Page, -1);
    TArgusNavigationKey.PageDown:
      MoveSelection(FSelected + Page);
    TArgusNavigationKey.First:
      MoveSelection(0);
    TArgusNavigationKey.Last:
      MoveSelection(High(FOrder), -1);
    TArgusNavigationKey.Accept:
      CommitSelected;
    TArgusNavigationKey.Cancel:
      Close;
  end;
end;

procedure TArgusCompletionController.Select(APosition: Integer);
begin
  if GetVisible then
    MoveSelection(APosition);
end;

function TArgusCompletionController.SelectedItem(out AItem: TArgusCompletionItem): Boolean;
begin
  Result := GetVisible and (FSelected >= 0) and (FSelected < Length(FOrder));
  if Result then
    AItem := FItems[FOrder[FSelected]]
  else
    AItem := Default(TArgusCompletionItem);
end;

function TArgusCompletionController.CanCommitOnCharacter: Boolean;
var
  Item: TArgusCompletionItem;
begin
  Result := (FPrefix <> '') and SelectedItem(Item) and
    (TArgusCompletionMatcher.Score(FPrefix, Item.Name) >= TArgusCompletionMatcher.ScoreWordStarts);
end;

procedure TArgusCompletionController.CommitSelected;
var
  Item: TArgusCompletionItem;
begin
  if not SelectedItem(Item) then
    Exit;
  if FUsage <> nil then
    FUsage.Record_(Item);
  Close;
  if Assigned(FOnCommit) then
    FOnCommit(Item);
end;

end.
