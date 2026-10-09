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

interface

uses
  System.SysUtils,
  System.Classes,
  Argus.Core.Completion.Contract;

{$SCOPEDENUMS ON}

type
  TArgusNavigationKey = (Up, Down, PageUp, PageDown, First, Last, Accept, Cancel);

  /// <summary>Anzeige der Liste; umgesetzt vom Popup (Argus.UI) bzw. von Tests.</summary>
  IArgusCompletionView = interface
    ['{8D2F4B61-3E9A-4C57-A1D0-6B7E2F9C3A15}']
    /// <summary>Zeigt bzw. aktualisiert die Liste. AOrder: Indizes in AItems in Anzeigereihenfolge;
    /// ASelected: Position in AOrder.</summary>
    procedure ShowList(const AItems: TArgusCompletionItems; const AOrder: TArray<Integer>; ASelected: Integer);
    procedure HideList;
    /// <summary>Leerer Zustand (#423): keine Treffer für APrefix unter ATotal Einträgen.</summary>
    procedure ShowEmpty(const APrefix: string; ATotal: Integer);
    /// <summary>Zahl der sichtbaren Zeilen für Bild auf/ab.</summary>
    function PageSize: Integer;
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
    FOnCommit: TArgusCommitEvent;
    procedure ItemsArrived(AGeneration: Integer; const AItems: TArgusCompletionItems);
    procedure Completed(AGeneration: Integer);
    procedure Refresh(AKeepSelection: Boolean);
    procedure MoveSelection(APosition: Integer);
    function GetVisible: Boolean;
  public
    constructor Create(const AProvider: IArgusCompletionProvider; const AView: IArgusCompletionView);
    destructor Destroy; override;
    /// <summary>Neue Vervollständigung an AContext; schließt eine offene.</summary>
    procedure Start(const AContext: TArgusContext);
    /// <summary>Das Wort unter dem Cursor hat sich geändert: neu filtern.</summary>
    procedure UpdatePrefix(const APrefix: string);
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
    property Prefix: string read FPrefix;
    property Items: TArgusCompletionItems read FItems;
    property Order: TArray<Integer> read FOrder;
    property Selected: Integer read FSelected;
    property OnCommit: TArgusCommitEvent read FOnCommit write FOnCommit;
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
  Result := FActive and (Length(FOrder) > 0);
end;

procedure TArgusCompletionController.Start(const AContext: TArgusContext);
var
  Sink: IArgusCompletionSink;
begin
  Close;
  Inc(FGeneration);
  FActive := True;
  FLoading := True;
  FPrefix := AContext.Prefix;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  Sink := TControllerSink.Create(Self, FFlag, FGeneration);
  FProvider.Query(AContext, Sink);
end;

procedure TArgusCompletionController.Close;
begin
  if not FActive then
    Exit;
  FActive := False;
  FLoading := False;
  Inc(FGeneration);
  FProvider.Cancel;
  FItems := nil;
  FOrder := nil;
  FSelected := -1;
  FEmpty := False;
  FView.HideList;
end;

procedure TArgusCompletionController.ItemsArrived(AGeneration: Integer; const AItems: TArgusCompletionItems);
begin
  if not FActive or (AGeneration <> FGeneration) or (Length(AItems) = 0) then
    Exit;
  FItems := FItems + AItems;
  Refresh(True);
end;

procedure TArgusCompletionController.Completed(AGeneration: Integer);
begin
  if not FActive or (AGeneration <> FGeneration) then
    Exit;
  FLoading := False;
  // Nichts gefunden: leerer Zustand statt kommentarlos zu verschwinden (#423).
  if Length(FItems) = 0 then
    Refresh(False);
end;

procedure TArgusCompletionController.Refresh(AKeepSelection: Boolean);
var
  SelectedIndex, Position: Integer;
begin
  SelectedIndex := -1;
  if AKeepSelection and (FSelected >= 0) and (FSelected < Length(FOrder)) then
    SelectedIndex := FOrder[FSelected];
  FOrder := TArgusCompletionMatcher.Filter(FItems, FPrefix);
  FSelected := 0;
  if SelectedIndex >= 0 then
    for Position := 0 to High(FOrder) do
      if FOrder[Position] = SelectedIndex then
      begin
        FSelected := Position;
        Break;
      end;
  FEmpty := False;
  if Length(FOrder) > 0 then
    FView.ShowList(FItems, FOrder, FSelected)
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

procedure TArgusCompletionController.MoveSelection(APosition: Integer);
begin
  APosition := EnsureRange(APosition, 0, High(FOrder));
  if APosition = FSelected then
    Exit;
  FSelected := APosition;
  FView.ShowList(FItems, FOrder, FSelected);
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
      MoveSelection(FSelected - 1);
    TArgusNavigationKey.Down:
      MoveSelection(FSelected + 1);
    TArgusNavigationKey.PageUp:
      MoveSelection(FSelected - Page);
    TArgusNavigationKey.PageDown:
      MoveSelection(FSelected + Page);
    TArgusNavigationKey.First:
      MoveSelection(0);
    TArgusNavigationKey.Last:
      MoveSelection(High(FOrder));
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
  Close;
  if Assigned(FOnCommit) then
    FOnCommit(Item);
end;

end.
