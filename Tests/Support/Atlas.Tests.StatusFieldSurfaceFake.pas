unit Atlas.Tests.StatusFieldSurfaceFake;

// Fälschung für IAtlasStatusFieldSurface: hängt keine Statusleiste ein und
// zeichnet nichts, sondern schreibt mit, was das Atlas-Feld verlangt („attach“,
// „detach“, „show“, „unhook“, „open“, „close“), zählt angeforderte
// Aktualisierungen (Ticks) und merkt sich die letzte Ansicht (View). Die Tests
// spielen die Oberfläche über Tick, Click, Gesture, Hint und Context nach;
// HasCorner und Corner legen fest, was FieldCorner liefert.

interface

uses
  System.SysUtils,
  System.Types,
  System.Classes,
  Atlas.Plugin.Status.Contract;

type
  TAtlasStatusFieldSurfaceFake = class(TInterfacedObject, IAtlasStatusFieldSurface)
  private
    FCalls: TStringList;
    FInput: TAtlasStatusFieldInput;
    FView: TAtlasStatusFieldView;
    FTicks: Integer;
    FWindowOpen: Boolean;
    FWindowItems: Integer;
    FWindowAt: TPoint;
    FOnOpenLog: TProc;
    FHasCorner: Boolean;
    FCorner: TPoint;
  public
    constructor Create;
    destructor Destroy; override;
    { IAtlasStatusFieldSurface }
    procedure Attach(const AInput: TAtlasStatusFieldInput);
    procedure Detach;
    procedure RequestTick;
    procedure Show(const AView: TAtlasStatusFieldView);
    procedure Unhook;
    function FieldCorner(out APoint: TPoint): Boolean;
    function WindowOpen: Boolean;
    procedure OpenWindow(const AItems: TArray<IAtlasStatusItem>; const APoint: TPoint;
      const AOnOpenLog, AOnRestart: TProc);
    procedure CloseWindow;
    procedure WindowItems(const AItems: TArray<IAtlasStatusItem>);
    /// <summary>Wie der Zeitgeber der IDE: OnTick des Felds, falls angefordert; setzt Ticks zurück.</summary>
    procedure Tick;
    /// <summary>Linksklick in AZone an AX mit der Plakette ab ABadgeLeft; Feld bei (10, 20), Zone bei (30, 20).
    /// </summary>
    function Click(AZone, AX, ABadgeLeft: Integer): Boolean;
    function Gesture(AGesture: TAtlasStatusFieldGesture; AInPanel, AFromKeyboard: Boolean): Boolean;
    function Hint(AZone: Integer): string;
    /// <summary>Wie die Nachricht nach Rechtsklick oder Doppelklick.</summary>
    procedure Context(const APoint: TPoint);
    /// <summary>Aufrufe, durch Komma getrennt.</summary>
    function CallText: string;
    /// <summary>Hat das Feld Rückrufe angemeldet (zwischen Attach und Detach)?</summary>
    function Attached: Boolean;
    property Calls: TStringList read FCalls;
    property View: TAtlasStatusFieldView read FView;
    /// <summary>Seit dem letzten Tick angeforderte Aktualisierungen.</summary>
    property Ticks: Integer read FTicks;
    property WindowAt: TPoint read FWindowAt;
    /// <summary>Zeilen des Statusfensters beim Öffnen bzw. letzten Nachführen.</summary>
    property WindowItemCount: Integer read FWindowItems;
    property OnOpenLog: TProc read FOnOpenLog;
    property HasCorner: Boolean read FHasCorner write FHasCorner;
    property Corner: TPoint read FCorner write FCorner;
  end;

implementation

{ TAtlasStatusFieldSurfaceFake }

constructor TAtlasStatusFieldSurfaceFake.Create;
begin
  inherited Create;
  FCalls := TStringList.Create;
end;

destructor TAtlasStatusFieldSurfaceFake.Destroy;
begin
  FreeAndNil(FCalls);
  inherited Destroy;
end;

procedure TAtlasStatusFieldSurfaceFake.Attach(const AInput: TAtlasStatusFieldInput);
begin
  FInput := AInput;
  FCalls.Add('attach');
end;

procedure TAtlasStatusFieldSurfaceFake.Detach;
begin
  FInput := Default(TAtlasStatusFieldInput);
  FOnOpenLog := nil;
  FView := Default(TAtlasStatusFieldView);
  FWindowOpen := False;
  FCalls.Add('detach');
end;

procedure TAtlasStatusFieldSurfaceFake.RequestTick;
begin
  Inc(FTicks);
end;

procedure TAtlasStatusFieldSurfaceFake.Show(const AView: TAtlasStatusFieldView);
begin
  FView := AView;
  FView.Extras := Copy(AView.Extras);
  FCalls.Add('show');
end;

procedure TAtlasStatusFieldSurfaceFake.Unhook;
begin
  FView := Default(TAtlasStatusFieldView);
  FCalls.Add('unhook');
end;

function TAtlasStatusFieldSurfaceFake.FieldCorner(out APoint: TPoint): Boolean;
begin
  APoint := FCorner;
  Result := FHasCorner;
end;

function TAtlasStatusFieldSurfaceFake.WindowOpen: Boolean;
begin
  Result := FWindowOpen;
end;

procedure TAtlasStatusFieldSurfaceFake.OpenWindow(const AItems: TArray<IAtlasStatusItem>; const APoint: TPoint;
  const AOnOpenLog, AOnRestart: TProc);
begin
  FWindowOpen := True;
  FWindowAt := APoint;
  FWindowItems := Length(AItems);
  FOnOpenLog := AOnOpenLog;
  FCalls.Add('open');
end;

procedure TAtlasStatusFieldSurfaceFake.CloseWindow;
begin
  if not FWindowOpen then
  begin
    Exit;
  end;
  FWindowOpen := False;
  FCalls.Add('close');
end;

procedure TAtlasStatusFieldSurfaceFake.WindowItems(const AItems: TArray<IAtlasStatusItem>);
begin
  if FWindowOpen then
  begin
    FWindowItems := Length(AItems);
  end;
end;

procedure TAtlasStatusFieldSurfaceFake.Tick;
begin
  if (FTicks > 0) and Assigned(FInput.OnTick) then
  begin
    FTicks := 0;
    FInput.OnTick();
  end;
end;

function TAtlasStatusFieldSurfaceFake.Click(AZone, AX, ABadgeLeft: Integer): Boolean;
begin
  Result := Assigned(FInput.OnClick) and FInput.OnClick(AZone, AX, ABadgeLeft, Point(10, 20), Point(30, 20));
end;

function TAtlasStatusFieldSurfaceFake.Gesture(AGesture: TAtlasStatusFieldGesture; AInPanel,
  AFromKeyboard: Boolean): Boolean;
begin
  Result := Assigned(FInput.OpensToggles) and FInput.OpensToggles(AGesture, AInPanel, AFromKeyboard);
end;

function TAtlasStatusFieldSurfaceFake.Hint(AZone: Integer): string;
begin
  Result := '';
  if Assigned(FInput.HintOf) then
  begin
    Result := FInput.HintOf(AZone);
  end;
end;

procedure TAtlasStatusFieldSurfaceFake.Context(const APoint: TPoint);
begin
  if Assigned(FInput.OnContext) then
  begin
    FInput.OnContext(APoint);
  end;
end;

function TAtlasStatusFieldSurfaceFake.CallText: string;
begin
  FCalls.StrictDelimiter := True;
  FCalls.Delimiter := ',';
  Result := FCalls.DelimitedText;
end;

function TAtlasStatusFieldSurfaceFake.Attached: Boolean;
begin
  Result := Assigned(FInput.OnTick);
end;

end.
