unit Atlas.IDE.Welcome.State;

// Zustandskachel „Atlas“ in der IDE (#754): Quelle des Bereichs
// (IAtlasStateSource) und Anmeldung als Bereich atlas.state der
// Willkommensseite (bzw. des Fensters „Atlas-Start“).
// - Die Zeilen liest die Kachel aus der Registry des Atlas-Statusfelds
//   (#591): Server und Index (TAtlasIdeStatusLines), Version
//   (TAtlasIdeUpdates, #495), Einrichtung (TAtlasIdeSetupChecklist, #625),
//   Diagnosemodus (TAtlasIdeDiagnosticMode, #479). Ein Klick auf eine Zeile
//   führt die Aktion der Statusfeld-Zeile aus.
// - Knöpfe über TAtlasStateActions aus der Komposition: Server neu starten,
//   Einstellungen (#227), Log-Ordner im Explorer, Jetzt aktualisieren (#495).
// - Neu gezeichnet wird bei einer Zustandsänderung: Ein Beobachter der
//   Registry vergleicht im Hauptthread den Fingerabdruck der Zeilen und meldet
//   nur echte Änderungen (Bereich neu zeichnen bzw. bei
//   welcomePage.statusTile.onlyProblems ein- oder ausblenden); kein
//   Zeitgeber.
// - Schalter welcomePage.statusTile; die Kachel liest nur, was schon da ist,
//   und startet keinen Server.

interface

uses
  System.SysUtils,
  Atlas.Core.Status.Contract,
  Atlas.Core.Welcome.Sections,
  Atlas.Core.Welcome.State,
  Atlas.UI.Welcome.State;

type
  /// <summary>Knöpfe der Kachel; gesetzt von der Komposition. nil = Knopf ohne Wirkung.</summary>
  TAtlasStateActions = record
    Restart: TProc;
    Settings: TProc;
    LogFolder: TProc;
    Update: TProc;
  end;

  TAtlasIdeWelcomeState = class(TInterfacedObject, IAtlasStateSource)
  public const
    /// <summary>Reihenfolge außerhalb des Atlas-Layouts.</summary>
    Order = 10;
  private
    FRegistry: IAtlasStatusRegistry;
    FActions: TAtlasStateActions;
    FListener: Integer;
    FStopped: Boolean;
    // Zuletzt gemeldeter Stand: Fingerabdruck der Zeilen und ob die Kachel sichtbar war.
    FSignature: string;
    FShown: Boolean;
    procedure Check;
    function ShouldShow(const ARows: TAtlasStateRows): Boolean;
  public
    constructor Create(const ARegistry: IAtlasStatusRegistry; const AActions: TAtlasStateActions);
    destructor Destroy; override;
    /// <summary>Bereich, Fabrik und Beobachter anmelden.</summary>
    procedure Start;
    /// <summary>Alles abmelden (beim Entladen); danach wirkungslos.</summary>
    procedure Stop;
    function Section: TAtlasWelcomeSection;
    { IAtlasStateSource }
    function Rows: TAtlasStateRows;
    procedure RunRow(const AId: string);
    procedure Run(AButton: TAtlasStateButton);
  end;

implementation

uses
  Atlas.Core.Diagnostics.MainThread,
  System.Classes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.IDE.Foundation.Settings;

var
  // Laufende Quelle; für Arbeit, die über die Nachrichtenschleife kommt.
  Current: TAtlasIdeWelcomeState;
  // Eine Prüfung ist schon unterwegs (Beobachter melden auch aus Hintergrund-Threads).
  Queued: Integer;

{ TAtlasIdeWelcomeState }

constructor TAtlasIdeWelcomeState.Create(const ARegistry: IAtlasStatusRegistry; const AActions: TAtlasStateActions);
begin
  inherited Create;
  FRegistry := ARegistry;
  FActions := AActions;
  FListener := -1;
end;

destructor TAtlasIdeWelcomeState.Destroy;
begin
  Stop;
  inherited;
end;

procedure TAtlasIdeWelcomeState.Start;
var
  Keep: IAtlasStateSource;
begin
  FStopped := False;
  Current := Self;
  Keep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.State,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeStateFrame;
    begin
      Frame := TAtlasWelcomeStateFrame.Create(AOwner);
      Frame.Source := Keep;
      Result := Frame;
    end);
  FSignature := TAtlasWelcomeState.Signature(Rows);
  FShown := ShouldShow(Rows);
  TAtlasWelcomeSections.Default.Add(Section);
  if FRegistry <> nil then
    FListener := FRegistry.AddListener(
      procedure
      begin
        // Aus jedem Thread: verglichen und gemeldet wird im Hauptthread, höchstens eine Prüfung unterwegs.
        if AtomicCmpExchange(Queued, 1, 0) <> 0 then
          Exit;
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomePage,
          procedure
          begin
            AtomicExchange(Queued, 0);
            if Current <> nil then
              TAtlasGuard.Run(TAtlasFeature.WelcomePage,
                procedure
                begin
                  if Current <> nil then
                    Current.Check;
                end);
          end);
      end);
end;

procedure TAtlasIdeWelcomeState.Stop;
begin
  if FStopped then
    Exit;
  FStopped := True;
  if Current = Self then
    Current := nil;
  if (FRegistry <> nil) and (FListener >= 0) then
    FRegistry.RemoveListener(FListener);
  FListener := -1;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.State);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.State);
end;

function TAtlasIdeWelcomeState.ShouldShow(const ARows: TAtlasStateRows): Boolean;
var
  Settings: TAtlasPluginSettings;
begin
  Settings := TAtlasIdeSettings.Current;
  Result := TAtlasWelcomeState.Visible(Settings.WelcomePageStatusTile, Settings.WelcomePageStatusTileOnlyProblems,
    ARows);
end;

function TAtlasIdeWelcomeState.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.State, TAtlasStrings.Text(TAtlasTextId.WelcomeStateTitle),
    Order, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      // welcomePage.statusTile; mit onlyProblems nur bei einer gelben oder roten Zeile.
      Result := (Current <> nil) and Current.ShouldShow(Current.Rows);
      // Was die Willkommensseite zuletzt gefragt hat (auch nach geänderten Einstellungen), ist der Stand für Check.
      if Current <> nil then
        Current.FShown := Result;
    end);
end;

procedure TAtlasIdeWelcomeState.Check;
var
  Next: TAtlasStateRows;
  Signature: string;
  Shown: Boolean;
begin
  if FStopped then
    Exit;
  // Ausgeschaltet: nichts zu tun; die Willkommensseite fragt den Schalter beim nächsten Sync selbst.
  if not TAtlasIdeSettings.Current.WelcomePageStatusTile then
    Exit;
  Next := Rows;
  Signature := TAtlasWelcomeState.Signature(Next);
  Shown := ShouldShow(Next);
  if Shown <> FShown then
  begin
    // onlyProblems: Die Kachel erscheint oder verschwindet; die Willkommensseite ordnet neu.
    FShown := Shown;
    FSignature := Signature;
    TAtlasWelcomeSections.Default.Changed;
    Exit;
  end;
  if Signature = FSignature then
    Exit;
  FSignature := Signature;
  // Nur dieser Bereich: Die Frames lesen die Zeilen neu und zeichnen (Invalidate).
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.State);
end;

function TAtlasIdeWelcomeState.Rows: TAtlasStateRows;
begin
  Result := nil;
  if FRegistry <> nil then
    Result := TAtlasWelcomeState.Rows(FRegistry.Items);
end;

procedure TAtlasIdeWelcomeState.RunRow(const AId: string);
var
  Item: IAtlasStatusItem;
begin
  if FStopped or (FRegistry = nil) then
    Exit;
  Item := FRegistry.Find(AId);
  if (Item = nil) or not Item.HasAction then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Item.Execute;
    end);
end;

procedure TAtlasIdeWelcomeState.Run(AButton: TAtlasStateButton);
var
  Action: TProc;
begin
  if FStopped then
    Exit;
  case AButton of
    TAtlasStateButton.Restart:
      Action := FActions.Restart;
    TAtlasStateButton.Settings:
      Action := FActions.Settings;
    TAtlasStateButton.LogFolder:
      Action := FActions.LogFolder;
  else
    Action := FActions.Update;
  end;
  if not Assigned(Action) then
    Exit;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      Action();
    end);
end;

end.
