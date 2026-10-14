unit Atlas.Core.Completion.Controller;

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
// Der Server liefert nur Namen, die zum Präfix der Anfrage passen (#616). Eine Liste gilt daher nur, solange
// das getippte Wort mit diesem Präfix beginnt; kürzer oder anders (Rücktaste) heißt neu fragen (NeedsQuery).
// Teilergebnisse (#616) kommen als mehrere AddItems: Das erste ersetzt bei Requery die Liste, die weiteren
// hängen an.
//
// Rangfolge über TAtlasRanking: Lernzuschlag (#418, Usage), Gruppen geerbter
// Member mit Überschriften (#419; Header in der Reihenfolge, die Auswahl
// überspringt sie), Filter-Chips (#422).
//
// Mengenmodus (#448, TAtlasCompletionSets): Toggle (Leertaste) hakt den gewählten Wert an oder ab, Accept
// übernimmt die ganze Klammer. Hat niemand umgeschaltet, nimmt Enter den gewählten Wert dazu. Nach "[" geöffnet
// (Trigger) und ohne Einträge schließt die Liste still, statt den leeren Zustand zu zeigen.
//
// Unbekannter Name (#471): Stehen nur Deklarationen in der Liste, ist nichts gewählt (Passive). Enter gehört dann
// dem Editor und schließt die Liste, damit ein neuer Name nicht ungefragt deklariert wird; eine Pfeiltaste wählt
// die erste Deklaration. Ebenso, wenn oben nur ein Hinweis „n Methoden von I fehlen“ (#466) steht und sonst nichts:
// Der Hinweis wird nie vorgewählt, die Auswahl beginnt beim ersten Eintrag danach.

interface

uses
  System.SysUtils,
  System.Classes,
  Atlas.Core.Completion.Contract,
  Atlas.Core.Completion.Ranking,
  Atlas.Core.Completion.Usage;

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
    FIncomplete: Boolean;
    /// <summary>Die nächsten Einträge ersetzen die Liste (laufendes Requery).</summary>
    FReplace: Boolean;
    FOnCommit: TAtlasCommitEvent;
    FGroupInherited: Boolean;
    FChipsEnabled: Boolean;
    FChip: TAtlasChip;
    FUsage: TAtlasUsage;
    /// <summary>Zeichen, nach dem automatisch geöffnet wurde (#448).</summary>
    FTrigger: string;
    /// <summary>Im Mengenmodus schon umgeschaltet.</summary>
    FToggled: Boolean;
    procedure ToggleSelected;
    procedure CommitSet;
    procedure ShowChips;
    function FirstItemFrom(APosition, ADirection: Integer): Integer;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TAtlasCompletionItems);
    procedure IncompleteArrived(AGeneration: Integer);
    procedure Query(const AContext: TAtlasContext);
    procedure SelectByName(const AName: string);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    procedure MoveSelection(APosition: Integer; ADirection: Integer = 1);
    function GetVisible: Boolean;
  public
    constructor Create(const AProvider: IAtlasCompletionProvider; const AView: IAtlasCompletionView);
    destructor Destroy; override;
    /// <summary>Neue Vervollständigung an AContext; schließt eine offene.</summary>
    procedure Start(const AContext: TAtlasContext);
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
    /// <summary>Lernende Gewichtung (#418); nil = aus. Gehört dem Aufrufer.</summary>
    property Usage: TAtlasUsage read FUsage write FUsage;
  end;

implementation

uses
  Atlas.Core.Diagnostics.Guard,
  System.Math,
  Atlas.Core.Completion.Matching,
  Atlas.Core.Completion.Sets;

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
  // Im Hauptthread läuft Queue sofort, sonst beim nächsten CheckSynchronize.
  TThread.Queue(nil,
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
  TThread.Queue(nil,
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
  TThread.Queue(nil,
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
  Chip: TAtlasChip;
begin
  // Wie angezeigt: nur Chips mit Treffern, "Alle" immer.
  Counts := TAtlasRanking.ChipCounts(FItems, FPrefix);
  for Chip := Low(TAtlasChip) to High(TAtlasChip) do
    if (Chip = TAtlasChip.All) or (Counts[Chip] > 0) then
    begin
      if AIndex = 0 then
      begin
        SelectChip(Chip);
        Exit;
      end;
      Dec(AIndex);
    end;
end;

procedure TAtlasCompletionController.Start(const AContext: TAtlasContext);
begin
  Close;
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FChip := TAtlasChip.All;
  FPrefix := AContext.Prefix;
  FTrigger := AContext.Trigger;
  FToggled := False;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  Query(AContext);
end;

procedure TAtlasCompletionController.Query(const AContext: TAtlasContext);
var
  Sink: IAtlasCompletionSink;
begin
  FIncomplete := False;
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
  FReplace := False;
  Inc(FGeneration);
  FProvider.Cancel;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  FPassive := False;
  FView.HideList;
end;

procedure TAtlasCompletionController.ItemsArrived(AGeneration: Integer; const AItems: TAtlasCompletionItems);
var
  Item: TAtlasCompletionItem;
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

procedure TAtlasCompletionController.Completed(AGeneration: Integer);
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
  SelectedIndex, Position: Integer;
  Options: TAtlasRankOptions;
  Usage: TAtlasUsage;
  Items: TAtlasCompletionItems;
begin
  SelectedIndex := -1;
  if AKeepSelection and not FPassive and (FSelected >= 0) and (FSelected < Length(FOrder)) then
    SelectedIndex := FOrder[FSelected];
  Options := TAtlasRankOptions.Defaults;
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
  FOrder := TAtlasRanking.Order(FItems, FPrefix, Options);
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
  FPassive := (FSelected >= 0) and ((FItems[FOrder[FSelected]].Unknown <> '') or FItems[FOrder[FSelected]].Hint) and
    ((SelectedIndex < 0) or (FOrder[FSelected] <> SelectedIndex));
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
    Close;
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
      Close;
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
  Result := (FPrefix <> '') and SelectedItem(Item) and
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
  if FUsage <> nil then
    FUsage.Record_(Item);
  Close;
  if Assigned(FOnCommit) then
    FOnCommit(Item);
end;

end.
