unit Atlas.Core.Status.FieldFlow;

// Ablauf des Atlas-Felds in der Statusleiste der Editorfenster (#591) ohne
// VCL und Open Tools API:
// - Zustand: sichtbare Zeilen der Registry, Kurztext, Tooltip und
//   Gesamtzustand (nach statusField.*), Zusatzfelder (SetExtra, z. B. das
//   Startprofil #575 und der Fehlerzähler #509) und die Plakette der
//   Benachrichtigungen (#601).
// - Aktualisierung nur auf Ereignisse: Änderungen der Registry (aus jedem
//   Thread) und Anlässe der Oberfläche fordern über
//   IAtlasStatusFieldSurface.RequestTick an; die Oberfläche fasst sie
//   zusammen und ruft OnTick im Hauptthread, dann zeigt Refresh. OnRefresh
//   läuft davor (feste Zeilen nachführen).
// - Ohne Atlas-Panel und ohne Zusatzfelder in der Statuszeile hängt die
//   Oberfläche die Leisten ganz aus. Zeigt die Atlas-Statusleiste das Element
//   status (Relocated, #1155), steht in der Statuszeile kein Atlas-Panel und
//   kein Zusatzfeld; die Leiste liest Text, State, Tooltip, Badge und
//   ExtraItems und klickt über OpenWindowAt, ContextAt, ClickBadge und
//   ClickExtra. Anchor fragt dann OnRelocatedAnchor.
// - Klicks: Ein Linksklick auf die Plakette öffnet die Liste der
//   Benachrichtigungen statt des Statusfensters, auf ein Zusatzfeld dessen
//   OnClick; ein zweiter Klick auf das Feld schließt das Statusfenster.
//   Rechtsklick bzw. Doppelklick öffnen die Schnellschalter (OnContext) nach
//   statusField.toggles. Rückrufe laufen unter dem Wächter.
// - Statuszeilen, Panels, Zeichnen und das Statusfenster übernimmt
//   IAtlasStatusFieldSurface: in der IDE der Adapter
//   Atlas.IDE.Status.Adapters.FieldSurface, in den Tests eine Fälschung.
// Bis auf RequestRefresh nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Types,
  Atlas.Core.Settings.Plugin,
  Atlas.Core.Status.Contract;

type
  /// <summary>Liefert die aktuellen Einstellungen des Plugins.</summary>
  TAtlasStatusFieldSettingsFunc = reference to function: TAtlasPluginSettings;

  TAtlasStatusFieldFlow = class
  private
    FRegistry: IAtlasStatusRegistry;
    FSurface: IAtlasStatusFieldSurface;
    FSettings: TAtlasStatusFieldSettingsFunc;
    FListener: Integer;
    FShown: TAtlasStatusShown;
    FEvents: TAtlasStatusFieldEvents;
    FExtras: TArray<TAtlasStatusExtra>;
    FBadge: TAtlasStatusBadge;
    /// <summary>Meldungen der Oberfläche an dieses Feld.</summary>
    function Input: TAtlasStatusFieldInput;
    /// <summary>Was das Feld nach ASettings zeigt; der Tooltip nennt auch die Plakette.</summary>
    function ShownState(const ASettings: TAtlasPluginSettings): TAtlasStatusShown;
    /// <summary>Was die Statuszeile zeigt: Atlas-Panel und Zusatzfelder, soweit nicht umgezogen.</summary>
    function ViewOf(const ASettings: TAtlasPluginSettings; ARelocated: Boolean): TAtlasStatusFieldView;
    function ExtraIndex(const AId: string): Integer;
  public
    /// <summary>ARegistry liefert die Zeilen, ASurface zeigt sie, ASettings die Einstellungen.</summary>
    constructor Create(const ARegistry: IAtlasStatusRegistry; const ASurface: IAtlasStatusFieldSurface;
      const ASettings: TAtlasStatusFieldSettingsFunc);
    /// <summary>Erst von der Registry abmelden, dann die Oberfläche lösen (Leisten aushängen).</summary>
    destructor Destroy; override;
    /// <summary>Neu zeichnen anfordern; aus jedem Thread, gesammelt von der Oberfläche.</summary>
    procedure RequestRefresh;
    /// <summary>OnRefresh, Zustand neu bestimmen, Statuszeilen und offenes Statusfenster nachführen.</summary>
    procedure Refresh;
    /// <summary>Linksklick in der Statuszeile (siehe TAtlasStatusFieldClickFunc); False, wenn er nicht Atlas
    /// gilt.</summary>
    function Click(AZone, AX, ABadgeLeft: Integer; const AFieldCorner, AZoneCorner: TPoint): Boolean;
    /// <summary>Öffnet AGesture über dem Atlas-Feld (AInPanel) die Schnellschalter?</summary>
    function OpensToggles(AGesture: TAtlasStatusFieldGesture; AInPanel, AFromKeyboard: Boolean): Boolean;
    /// <summary>Tooltip der Zone AZone: 0 Atlas-Feld, ab 1 Zusatzfeld, sonst ''.</summary>
    function HintOf(AZone: Integer): string;
    /// <summary>Linke Oberkante des Felds im obersten Editorfenster (Bildschirm); False ohne Feld. Umgezogen:
    /// OnRelocatedAnchor.</summary>
    function Anchor(out APoint: TPoint): Boolean;
    /// <summary>Zeigt die Atlas-Statusleiste das Element status (#1155)? Dann gibt es kein Panel.</summary>
    function Relocated: Boolean;
    /// <summary>Statusfenster über APoint (Bildschirm, linke Oberkante des Felds) öffnen; ein zweiter Aufruf
    /// schließt es.</summary>
    procedure OpenWindowAt(const APoint: TPoint);
    /// <summary>Schnellschalter über APoint wie beim Rechtsklick auf das Feld.</summary>
    procedure ContextAt(const APoint: TPoint);
    /// <summary>Zusatzfeld AExtra.Id setzen (Text, Tooltip, Zustand, Links- und Rechtsklick mit der linken
    /// Oberkante des Panels); Text '' entfernt es.</summary>
    procedure SetExtra(const AExtra: TAtlasStatusExtra);
    /// <summary>Plakette der Benachrichtigungen (#601): Count ungelesene (im Feld 0 = keine Plakette, in der
    /// Atlas-Statusleiste zählt Shown), Farbe nach State, Hint im Tooltip; Linksklick auf die Plakette ruft
    /// OnClick mit der linken Oberkante des Felds. Unverändert: kein neues Zeichnen.</summary>
    procedure SetBadge(const ABadge: TAtlasStatusBadge);
    /// <summary>Wie ein Klick auf die Plakette, Liste mit der linken Oberkante an APoint (#1234).</summary>
    procedure ClickBadge(const APoint: TPoint);
    /// <summary>Zusatzfelder in ihrer Reihenfolge, für die Atlas-Statusleiste.</summary>
    function ExtraItems: TArray<TAtlasStatusExtraItem>;
    /// <summary>Wie ein Klick (AContext: Rechtsklick) auf das Zusatzfeld AId mit der linken Oberkante an APoint;
    /// ohne Feld bzw. ohne passenden Klick nichts.</summary>
    procedure ClickExtra(const AId: string; const APoint: TPoint; AContext: Boolean);
    /// <summary>Kurztext, Gesamtzustand und Tooltip des letzten Refresh.</summary>
    property Text: string read FShown.Text;
    property State: TAtlasStatusState read FShown.State;
    property Tooltip: string read FShown.Tooltip;
    /// <summary>Plakette für die Atlas-Statusleiste (#1234).</summary>
    property Badge: TAtlasStatusBadge read FBadge;
    /// <summary>Vor jedem Zeichnen im Hauptthread.</summary>
    property OnRefresh: TProc read FEvents.OnRefresh write FEvents.OnRefresh;
    property OnOpenLog: TProc read FEvents.OnOpenLog write FEvents.OnOpenLog;
    property OnRestart: TProc read FEvents.OnRestart write FEvents.OnRestart;
    /// <summary>Rechtsklick und Doppelklick auf das Feld; Punkt = linke Oberkante des Felds (Bildschirm).</summary>
    property OnContext: TProc<TPoint> read FEvents.OnContext write FEvents.OnContext;
    property OnRelocatedAnchor: TAtlasStatusAnchorFunc read FEvents.OnRelocatedAnchor
      write FEvents.OnRelocatedAnchor;
  end;

implementation

uses
  Atlas.Plugin.Diagnostics.Guard,
  Atlas.Core.Status.Registry,
  Atlas.Core.Status.Lines,
  Atlas.Core.Status.FieldPlan;

/// <summary>AOnClick mit APoint unter dem Wächter; nichts ohne Handler.</summary>
procedure RunClick(const AOnClick: TProc<TPoint>; const APoint: TPoint);
var
  mOnClick: TProc<TPoint>;
  mPoint: TPoint;
begin
  if not Assigned(AOnClick) then
  begin
    Exit;
  end;
  mOnClick := AOnClick;
  mPoint := APoint;
  TAtlasGuard.Run(TAtlasFeature.Status,
    procedure
    begin
      mOnClick(mPoint);
    end);
end;

{ TAtlasStatusFieldFlow }

constructor TAtlasStatusFieldFlow.Create(const ARegistry: IAtlasStatusRegistry;
  const ASurface: IAtlasStatusFieldSurface; const ASettings: TAtlasStatusFieldSettingsFunc);
begin
  inherited Create;
  FRegistry := ARegistry;
  FSurface := ASurface;
  FSettings := ASettings;
  FSurface.Attach(Input);
  FListener := FRegistry.AddListener(
    procedure
    begin
      RequestRefresh;
    end);
  RequestRefresh;
end;

destructor TAtlasStatusFieldFlow.Destroy;
begin
  // Erst abmelden, dann lösen (#493).
  if FRegistry <> nil then
  begin
    FRegistry.RemoveListener(FListener);
  end;
  if FSurface <> nil then
  begin
    try
      FSurface.Detach;
    except
      on E: Exception do
        TAtlasGuard.Report(TAtlasFeature.Status, E);
    end;
  end;
  FSurface := nil;
  FRegistry := nil;
  inherited Destroy;
end;

function TAtlasStatusFieldFlow.Input: TAtlasStatusFieldInput;
begin
  Result := Default(TAtlasStatusFieldInput);
  Result.OnTick :=
    procedure
    begin
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          Refresh;
        end);
    end;
  Result.OnClick :=
    function(AZone, AX, ABadgeLeft: Integer; const AFieldCorner, AZoneCorner: TPoint): Boolean
    begin
      Result := Click(AZone, AX, ABadgeLeft, AFieldCorner, AZoneCorner);
    end;
  Result.OpensToggles :=
    function(AGesture: TAtlasStatusFieldGesture; AInPanel, AFromKeyboard: Boolean): Boolean
    begin
      Result := OpensToggles(AGesture, AInPanel, AFromKeyboard);
    end;
  Result.HintOf :=
    function(AZone: Integer): string
    begin
      Result := HintOf(AZone);
    end;
  Result.OnContext :=
    procedure(APoint: TPoint)
    var
      mPoint: TPoint;
    begin
      mPoint := APoint;
      TAtlasGuard.Run(TAtlasFeature.Status,
        procedure
        begin
          ContextAt(mPoint);
        end);
    end;
end;

function TAtlasStatusFieldFlow.ShownState(const ASettings: TAtlasPluginSettings): TAtlasStatusShown;
var
  mProgressId: string;
begin
  Result.Items := TAtlasStatusSummary.Visible(FRegistry.Items,
    TAtlasStatusSummary.ParseIds(ASettings.StatusFieldHidden));
  Result.State := TAtlasStatusSummary.Overall(Result.Items);
  mProgressId := '';
  if ASettings.IndexProgressInField then
  begin
    mProgressId := TAtlasStatusLines.cIndexId;
  end;
  Result.Text := TAtlasStatusSummary.FieldText(Result.Items, ASettings.StatusFieldSummary, mProgressId);
  Result.Tooltip := TAtlasStatusFieldPlan.Tooltip(TAtlasStatusSummary.Tooltip(Result.Items), FBadge.Count,
    FBadge.Hint);
end;

function TAtlasStatusFieldFlow.ViewOf(const ASettings: TAtlasPluginSettings;
  ARelocated: Boolean): TAtlasStatusFieldView;
var
  mIndex: Integer;
begin
  Result := Default(TAtlasStatusFieldView);
  Result.Panel := TAtlasStatusFieldPlan.PanelShown(ASettings, ARelocated);
  Result.Text := FShown.Text;
  Result.State := FShown.State;
  Result.BadgeCount := FBadge.Count;
  Result.BadgeState := FBadge.State;
  SetLength(Result.Extras, TAtlasStatusFieldPlan.ExtraPanels(Length(FExtras), ARelocated));
  for mIndex := 0 to High(Result.Extras) do
  begin
    Result.Extras[mIndex] := FExtras[mIndex].Text;
  end;
end;

function TAtlasStatusFieldFlow.ExtraIndex(const AId: string): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FExtras) do
  begin
    if FExtras[mIndex].Id = AId then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

procedure TAtlasStatusFieldFlow.RequestRefresh;
begin
  if FSurface <> nil then
  begin
    FSurface.RequestTick;
  end;
end;

procedure TAtlasStatusFieldFlow.Refresh;
var
  mSettings: TAtlasPluginSettings;
  mView: TAtlasStatusFieldView;
begin
  if FSurface = nil then
  begin
    Exit;
  end;
  if Assigned(FEvents.OnRefresh) then
  begin
    FEvents.OnRefresh();
  end;
  mSettings := FSettings();
  FShown := ShownState(mSettings);
  FSurface.WindowItems(FShown.Items);
  mView := ViewOf(mSettings, Relocated);
  // Ohne Atlas-Feld bleiben die Leisten nur für Zusatzfelder in der Statuszeile eingehängt (#575); ziehen sie mit
  // in die Atlas-Statusleiste um, braucht die Statuszeile nichts von Atlas.
  if TAtlasStatusFieldPlan.Hooked(mView.Panel, Length(mView.Extras)) then
  begin
    FSurface.Show(mView);
  end
  else
  begin
    FSurface.Unhook;
  end;
end;

function TAtlasStatusFieldFlow.Click(AZone, AX, ABadgeLeft: Integer; const AFieldCorner,
  AZoneCorner: TPoint): Boolean;
var
  mCorner: TPoint;
begin
  Result := True;
  case TAtlasStatusFieldPlan.Click(AZone, Length(FExtras), FBadge.Count, Assigned(FBadge.OnClick), AX,
    ABadgeLeft) of
    TAtlasStatusFieldClick.Badge:
      begin
        // Klick auf die Plakette (#601): Liste der Benachrichtigungen statt Statusfenster.
        FSurface.CloseWindow;
        RunClick(FBadge.OnClick, AFieldCorner);
      end;
    TAtlasStatusFieldClick.Window:
      begin
        mCorner := AFieldCorner;
        TAtlasGuard.Run(TAtlasFeature.Status,
          procedure
          begin
            OpenWindowAt(mCorner);
          end);
      end;
    TAtlasStatusFieldClick.Extra:
      RunClick(FExtras[AZone - 1].OnClick, AZoneCorner);
  else
    Result := False;
  end;
end;

function TAtlasStatusFieldFlow.OpensToggles(AGesture: TAtlasStatusFieldGesture; AInPanel,
  AFromKeyboard: Boolean): Boolean;
begin
  Result := TAtlasStatusFieldPlan.OpensToggles(AGesture, FSettings(), Assigned(FEvents.OnContext), AInPanel,
    AFromKeyboard);
end;

function TAtlasStatusFieldFlow.HintOf(AZone: Integer): string;
begin
  Result := '';
  if AZone = 0 then
  begin
    Result := FShown.Tooltip;
  end
  else if (AZone > 0) and (AZone <= Length(FExtras)) then
  begin
    Result := FExtras[AZone - 1].Hint;
  end;
end;

function TAtlasStatusFieldFlow.Anchor(out APoint: TPoint): Boolean;
begin
  APoint := Point(0, 0);
  if Relocated then
  begin
    Result := Assigned(FEvents.OnRelocatedAnchor) and FEvents.OnRelocatedAnchor(APoint);
    Exit;
  end;
  Result := (FSurface <> nil) and FSurface.FieldCorner(APoint);
end;

function TAtlasStatusFieldFlow.Relocated: Boolean;
begin
  Result := TAtlasStatusFieldPlan.Relocated(FSettings(), TAtlasGuard.Disabled(TAtlasFeature.StatusBar));
end;

procedure TAtlasStatusFieldFlow.OpenWindowAt(const APoint: TPoint);
begin
  if FSurface = nil then
  begin
    Exit;
  end;
  // Zweiter Klick schließt.
  if FSurface.WindowOpen then
  begin
    FSurface.CloseWindow;
    Exit;
  end;
  Refresh;
  FSurface.OpenWindow(FShown.Items, APoint, FEvents.OnOpenLog, FEvents.OnRestart);
end;

procedure TAtlasStatusFieldFlow.ContextAt(const APoint: TPoint);
begin
  if not Assigned(FEvents.OnContext) then
  begin
    Exit;
  end;
  if FSurface <> nil then
  begin
    FSurface.CloseWindow;
  end;
  FEvents.OnContext(APoint);
end;

procedure TAtlasStatusFieldFlow.SetExtra(const AExtra: TAtlasStatusExtra);
var
  mFound: Integer;
begin
  mFound := ExtraIndex(AExtra.Id);
  if AExtra.Text = '' then
  begin
    if mFound >= 0 then
    begin
      Delete(FExtras, mFound, 1);
    end;
  end
  else if mFound >= 0 then
  begin
    FExtras[mFound] := AExtra;
  end
  else
  begin
    SetLength(FExtras, Length(FExtras) + 1);
    FExtras[High(FExtras)] := AExtra;
  end;
  RequestRefresh;
end;

procedure TAtlasStatusFieldFlow.SetBadge(const ABadge: TAtlasStatusBadge);
var
  mCount: Integer;
begin
  mCount := ABadge.Count;
  if mCount < 0 then
  begin
    mCount := 0;
  end;
  FBadge.OnClick := ABadge.OnClick;
  // Unverändert: nicht neu zeichnen (die Zentrale meldet auch Änderungen ohne Wirkung auf die Plakette).
  if (ABadge.Shown = FBadge.Shown) and (mCount = FBadge.Count) and (ABadge.State = FBadge.State) and
    (ABadge.Hint = FBadge.Hint) then
  begin
    Exit;
  end;
  FBadge.Shown := ABadge.Shown;
  FBadge.Count := mCount;
  FBadge.State := ABadge.State;
  FBadge.Hint := ABadge.Hint;
  RequestRefresh;
end;

procedure TAtlasStatusFieldFlow.ClickBadge(const APoint: TPoint);
begin
  if FBadge.Shown and Assigned(FBadge.OnClick) then
  begin
    FBadge.OnClick(APoint);
  end;
end;

function TAtlasStatusFieldFlow.ExtraItems: TArray<TAtlasStatusExtraItem>;
var
  mIndex: Integer;
begin
  Result := nil;
  SetLength(Result, Length(FExtras));
  for mIndex := 0 to High(FExtras) do
  begin
    Result[mIndex].Id := FExtras[mIndex].Id;
    Result[mIndex].Text := FExtras[mIndex].Text;
    Result[mIndex].Hint := FExtras[mIndex].Hint;
    Result[mIndex].Clickable := Assigned(FExtras[mIndex].OnClick);
    Result[mIndex].State := FExtras[mIndex].State;
    Result[mIndex].HasContext := Assigned(FExtras[mIndex].OnContext);
  end;
end;

procedure TAtlasStatusFieldFlow.ClickExtra(const AId: string; const APoint: TPoint; AContext: Boolean);
var
  mFound: Integer;
begin
  mFound := ExtraIndex(AId);
  if mFound < 0 then
  begin
    Exit;
  end;
  if AContext then
  begin
    RunClick(FExtras[mFound].OnContext, APoint);
  end
  else
  begin
    RunClick(FExtras[mFound].OnClick, APoint);
  end;
end;

end.
