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
    cOrder = 10;
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
    /// <summary>Kachel mit den Zeilen des Statusfelds und den Knöpfen über die Dienste von Base (TAtlasIdeHost,
    /// #1455).</summary>
    class function CreateForHost: TAtlasIdeWelcomeState; static;
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
  Atlas.UI.Welcome.Strings,
  Atlas.UI.Welcome.Frame,
  Atlas.Core.Status.Registry,
  Atlas.IDE.Foundation.Host,
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
  mKeep: IAtlasStateSource;
begin
  FStopped := False;
  Current := Self;
  mKeep := Self;
  TAtlasWelcomeViews.Register(TAtlasWelcomeIds.cState,
    function(AOwner: TComponent): TAtlasWelcomeSectionFrame
    var
      Frame: TAtlasWelcomeStateFrame;
    begin
      Frame := TAtlasWelcomeStateFrame.Create(AOwner);
      Frame.Source := mKeep;
      Result := Frame;
    end);
  FSignature := TAtlasWelcomeState.Signature(Rows);
  FShown := ShouldShow(Rows);
  TAtlasWelcomeSections.Default.Add(Section);
  if FRegistry <> nil then
  begin
    FListener := FRegistry.AddListener(
      procedure
      begin
        // Aus jedem Thread: verglichen und gemeldet wird im Hauptthread, höchstens eine Prüfung unterwegs.
        if AtomicCmpExchange(Queued, 1, 0) <> 0 then
        begin
          Exit;
        end;
        TAtlasMainThread.ForceQueue(TAtlasFeature.WelcomeUpdates,
          procedure
          begin
            AtomicExchange(Queued, 0);
            if Current <> nil then
            begin
              TAtlasGuard.Run(TAtlasFeature.WelcomeUpdates,
                procedure
                begin
                  if Current <> nil then
                  begin
                    Current.Check;
                  end;
                end);
            end;
          end);
      end);
  end;
end;

procedure TAtlasIdeWelcomeState.Stop;
begin
  if FStopped then
  begin
    Exit;
  end;
  FStopped := True;
  if Current = Self then
  begin
    Current := nil;
  end;
  if (FRegistry <> nil) and (FListener >= 0) then
  begin
    FRegistry.RemoveListener(FListener);
  end;
  FListener := -1;
  TAtlasWelcomeViews.Unregister(TAtlasWelcomeIds.cState);
  TAtlasWelcomeSections.Default.Remove(TAtlasWelcomeIds.cState);
end;

function TAtlasIdeWelcomeState.ShouldShow(const ARows: TAtlasStateRows): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := TAtlasWelcomeState.Visible(mSettings.WelcomePageStatusTile, mSettings.WelcomePageStatusTileOnlyProblems,
    ARows);
end;

function TAtlasIdeWelcomeState.Section: TAtlasWelcomeSection;
begin
  Result := TAtlasWelcomeSection.Create(TAtlasWelcomeIds.cState,
    TAtlasWelcomeStrings.Text(TAtlasWelcomeTextId.WelcomeStateTitle),
    cOrder, TAtlasWelcomeColumn.Right,
    function: Boolean
    begin
      // welcomePage.statusTile; mit onlyProblems nur bei einer gelben oder roten Zeile.
      Result := (Current <> nil) and Current.ShouldShow(Current.Rows);
      // Was die Willkommensseite zuletzt gefragt hat (auch nach geänderten Einstellungen), ist der Stand für Check.
      if Current <> nil then
      begin
        Current.FShown := Result;
      end;
    end);
end;

procedure TAtlasIdeWelcomeState.Check;
var
  mNext: TAtlasStateRows;
  mSignature: string;
  mShown: Boolean;
begin
  if FStopped then
  begin
    Exit;
  end;
  // Ausgeschaltet: nichts zu tun; die Willkommensseite fragt den Schalter beim nächsten Sync selbst.
  if not TAtlasIdeSettings.Current.WelcomePageStatusTile then
  begin
    Exit;
  end;
  mNext := Rows;
  mSignature := TAtlasWelcomeState.Signature(mNext);
  mShown := ShouldShow(mNext);
  if mShown <> FShown then
  begin
    // onlyProblems: Die Kachel erscheint oder verschwindet; die Willkommensseite ordnet neu.
    FShown := mShown;
    FSignature := mSignature;
    TAtlasWelcomeSections.Default.Changed;
    Exit;
  end;
  if mSignature = FSignature then
  begin
    Exit;
  end;
  FSignature := mSignature;
  // Nur dieser Bereich: Die Frames lesen die Zeilen neu und zeichnen (Invalidate).
  TAtlasWelcomeSections.Default.Changed(TAtlasWelcomeIds.cState);
end;

function TAtlasIdeWelcomeState.Rows: TAtlasStateRows;
begin
  Result := nil;
  if FRegistry <> nil then
  begin
    Result := TAtlasWelcomeState.Rows(FRegistry.Items);
  end;
end;

procedure TAtlasIdeWelcomeState.RunRow(const AId: string);
var
  mItem: IAtlasStatusItem;
begin
  if FStopped or (FRegistry = nil) then
  begin
    Exit;
  end;
  mItem := FRegistry.Find(AId);
  if (mItem = nil) or not mItem.HasAction then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mItem.Execute;
    end);
end;

procedure TAtlasIdeWelcomeState.Run(AButton: TAtlasStateButton);
var
  mAction: TProc;
begin
  if FStopped then
  begin
    Exit;
  end;
  case AButton of
    TAtlasStateButton.Restart:
      mAction := FActions.Restart;
    TAtlasStateButton.Settings:
      mAction := FActions.Settings;
    TAtlasStateButton.LogFolder:
      mAction := FActions.LogFolder;
  else
    mAction := FActions.Update;
  end;
  if not Assigned(mAction) then
  begin
    Exit;
  end;
  TAtlasGuard.Run(TAtlasFeature.WelcomePage,
    procedure
    begin
      mAction();
    end);
end;

class function TAtlasIdeWelcomeState.CreateForHost: TAtlasIdeWelcomeState;
var
  mActions: TAtlasStateActions;
begin
  mActions := Default(TAtlasStateActions);
  mActions.Restart :=
    procedure
    begin
      TAtlasIdeHost.RestartServer;
    end;
  mActions.Settings :=
    procedure
    begin
      TAtlasIdeHost.OpenOptions;
    end;
  mActions.LogFolder :=
    procedure
    begin
      TAtlasIdeHost.OpenLogFolder;
    end;
  mActions.Update :=
    procedure
    begin
      TAtlasIdeHost.OpenUpdate;
    end;
  Result := TAtlasIdeWelcomeState.Create(TAtlasStatusRegistry.Default, mActions);
end;

end.
