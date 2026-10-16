unit Atlas.UI.Welcome.Frame;

// Frames der Atlas-Willkommensseite (#753):
// - TAtlasWelcomeFrame: Basis mit .dfm; abgeleitete Frames (Kopf, Bereiche,
//   Atlas-Layout) brauchen dadurch keine eigene. Der Name aus der .dfm wird
//   gelöscht, damit mehrere Frames denselben Besitzer haben dürfen.
// - TAtlasWelcomeSectionFrame: Bereich mit Titelzeile (nur im Atlas-Layout und
//   im Fenster „Atlas-Start“; auf der Willkommensseite der IDE trägt der
//   Rahmen der IDE den Titel) und Inhaltsfläche Body. Bereiche aus späteren
//   Issues leiten davon ab und überschreiben UpdateContent und PreferredHeight.
// - TAtlasWelcomeViews: Kennung → Fabrik der Frames. Jeder Bereich meldet seine
//   Fabrik an; Willkommensseite und „Atlas-Start“ erzeugen daraus ihre Frames.

interface

uses
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.Forms,
  Vcl.StdCtrls,
  Vcl.ExtCtrls,
  Vcl.Graphics;

type
  /// <summary>Zeichenfläche der Bereiche ohne Flackern. Eine TPaintBox auf Panels mit ParentBackground lässt
  /// Windows vor jedem Neuzeichnen den Hintergrund der Eltern holen; beim Hovern (Schnellaktionen #764) blitzt
  /// das. Hier kommen Hintergrund der Eltern und Inhalt zusammen in einen Puffer, gelöscht wird nie.</summary>
  TAtlasWelcomeCanvas = class(TCustomControl)
  private
    FOnPaint: TNotifyEvent;
    procedure WMEraseBkgnd(var Message: TWMEraseBkgnd); message WM_ERASEBKGND;
  protected
    procedure Paint; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Hintergrund im aktuellen IDE-Thema (clWindow des Stils).</summary>
    class function BackgroundOf(AControl: TControl): TColor; static;
    property Canvas;
    property ShowHint;
    property PopupMenu;
    property OnPaint: TNotifyEvent read FOnPaint write FOnPaint;
    property OnDblClick;
    property OnMouseDown;
    property OnMouseMove;
    property OnMouseUp;
    property OnMouseLeave;
  end;

  TAtlasWelcomeFrame = class(TFrame)
  private
    FPendingUpdate: Boolean;
  protected
    procedure CreateWnd; override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Inhalt neu lesen und zeichnen; im Hauptthread.</summary>
    procedure UpdateContent; virtual;
    /// <summary>Hängt der Frame an einem Fenster? Vorher kein Messen von Text: Beschriftungen
    /// holen ihren Gerätekontext vom Elternfenster („kein übergeordnetes Fenster“). Ohne Fenster
    /// holt CreateWnd das UpdateContent nach.</summary>
    function HasWindow: Boolean;
  end;

  TAtlasWelcomeSectionFrame = class(TAtlasWelcomeFrame)
  public const
    TitleHeight = 24;
    /// <summary>Höhe ohne eigene Angabe (logische Pixel).</summary>
    DefaultBodyHeight = 120;
  private
    FSectionId: string;
    FTitleBar: TPanel;
    FTitle: TLabel;
    FBody: TPanel;
    FOnHeightChanged: TNotifyEvent;
    function GetShowTitle: Boolean;
    procedure SetShowTitle(AValue: Boolean);
    function GetTitle: string;
    procedure SetTitle(const AValue: string);
  protected
    /// <summary>Höhe des Inhalts in Pixeln bei der aktuellen Skalierung.</summary>
    function BodyHeight: Integer; virtual;
    /// <summary>Der Inhalt braucht eine andere Höhe (z. B. aufgeklappt, #756); meldet OnHeightChanged.</summary>
    procedure HeightChanged;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Höhe, die der Frame im Atlas-Layout braucht (Titel plus Inhalt).</summary>
    function PreferredHeight: Integer;
    property SectionId: string read FSectionId write FSectionId;
    property Title: string read GetTitle write SetTitle;
    property ShowTitle: Boolean read GetShowTitle write SetShowTitle;
    /// <summary>Hierhin legen Bereiche ihren Inhalt.</summary>
    property Body: TPanel read FBody;
    property TitleLabel: TLabel read FTitle;
    /// <summary>Der Frame „Atlas“ ordnet daraufhin die Spalten neu.</summary>
    property OnHeightChanged: TNotifyEvent read FOnHeightChanged write FOnHeightChanged;
  end;

  TAtlasWelcomeViewFactory = reference to function(AOwner: TComponent): TAtlasWelcomeSectionFrame;

  TAtlasWelcomeViews = class
  private class var
    FFactories: TDictionary<string, TAtlasWelcomeViewFactory>;
  public
    class procedure Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory); static;
    class procedure Unregister(const AId: string); static;
    class function Exists(const AId: string): Boolean; static;
    /// <summary>Neuer Frame für AId mit SectionId; nil ohne Fabrik.</summary>
    class function CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame; static;
    /// <summary>Beim Entladen: alle Fabriken vergessen.</summary>
    class procedure Release; static;
  end;

implementation

{$R *.dfm}

uses
  Vcl.Themes;

{ TAtlasWelcomeCanvas }

constructor TAtlasWelcomeCanvas.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  DoubleBuffered := True;
end;

procedure TAtlasWelcomeCanvas.WMEraseBkgnd(var Message: TWMEraseBkgnd);
begin
  // Paint deckt alles ab, auch den Hintergrund.
  Message.Result := 1;
end;

type
  TColoredControl = class(TControl);
  TBackgroundControl = class(TWinControl);

class function TAtlasWelcomeCanvas.BackgroundOf(AControl: TControl): TColor;
begin
  // Direkt aus dem Stil, wie die Schriftfarben der Bereiche (clWindowText). Die Farbe der Vorfahren war nach
  // einem Wechsel veraltet und bei „Windows-Design anpassen“ fest weiß.
  Result := StyleServices(AControl).GetSystemColor(clWindow);
end;

procedure TAtlasWelcomeCanvas.Paint;
var
  Color_: TColor;
  Owner_: TWinControl;
begin
  Color_ := BackgroundOf(Self);
  // Panels, Frames und den Rollbereich darüber auf dieselbe Farbe: Mit ParentBackground blieb unter den
  // IDE-Stilen nach einem Themenwechsel (und bei „Windows-Design anpassen“) das alte Bild stehen. Beim
  // Zeichnen, weil der Stil erst dann sicher feststeht; geändert wird nur, was abweicht.
  Owner_ := Parent;
  while (Owner_ is TCustomPanel) or (Owner_ is TScrollBox) or (Owner_ is TCustomFrame) do
  begin
    if TBackgroundControl(Owner_).ParentBackground or (TColoredControl(Owner_).Color <> Color_) then
    begin
      TBackgroundControl(Owner_).ParentBackground := False;
      Owner_.StyleElements := Owner_.StyleElements - [seClient];
      TColoredControl(Owner_).Color := Color_;
    end;
    if Owner_ is TScrollBox then
      Break;
    Owner_ := Owner_.Parent;
  end;
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := Color_;
  Canvas.FillRect(ClientRect);
  if Assigned(FOnPaint) then
    FOnPaint(Self);
end;

{ TAtlasWelcomeFrame }

constructor TAtlasWelcomeFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Mehrere Frames unter einem Besitzer: kein fester Name aus der .dfm.
  Name := '';
  ParentBackground := True;
end;

procedure TAtlasWelcomeFrame.UpdateContent;
begin
  Invalidate;
end;

function TAtlasWelcomeFrame.HasWindow: Boolean;
var
  Control: TWinControl;
begin
  Control := Self;
  while Control <> nil do
  begin
    if Control.HandleAllocated or (Control.ParentWindow <> 0) or (Control is TCustomForm) then
      Exit(True);
    Control := Control.Parent;
  end;
  FPendingUpdate := True;
  Result := False;
end;

procedure TAtlasWelcomeFrame.CreateWnd;
begin
  inherited;
  if FPendingUpdate then
  begin
    FPendingUpdate := False;
    UpdateContent;
  end;
end;

{ TAtlasWelcomeSectionFrame }

constructor TAtlasWelcomeSectionFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FTitleBar := TPanel.Create(Self);
  FTitleBar.Parent := Self;
  FTitleBar.Align := alTop;
  FTitleBar.BevelOuter := bvNone;
  FTitleBar.ParentBackground := True;
  FTitleBar.Height := TitleHeight;
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FTitleBar;
  FTitle.Left := 2;
  FTitle.Top := 4;
  FTitle.Font.Style := [fsBold];
  FBody := TPanel.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BevelOuter := bvNone;
  FBody.ParentBackground := True;
end;

function TAtlasWelcomeSectionFrame.GetShowTitle: Boolean;
begin
  Result := FTitleBar.Visible;
end;

procedure TAtlasWelcomeSectionFrame.SetShowTitle(AValue: Boolean);
begin
  FTitleBar.Visible := AValue;
end;

function TAtlasWelcomeSectionFrame.GetTitle: string;
begin
  Result := FTitle.Caption;
end;

procedure TAtlasWelcomeSectionFrame.SetTitle(const AValue: string);
begin
  FTitle.Caption := AValue;
end;

function TAtlasWelcomeSectionFrame.BodyHeight: Integer;
begin
  Result := DefaultBodyHeight;
end;

procedure TAtlasWelcomeSectionFrame.HeightChanged;
begin
  if Assigned(FOnHeightChanged) then
    FOnHeightChanged(Self);
end;

function TAtlasWelcomeSectionFrame.PreferredHeight: Integer;
begin
  Result := BodyHeight;
  if ShowTitle then
    Inc(Result, FTitleBar.Height);
end;

{ TAtlasWelcomeViews }

class procedure TAtlasWelcomeViews.Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory);
begin
  if FFactories = nil then
    FFactories := TDictionary<string, TAtlasWelcomeViewFactory>.Create;
  FFactories.AddOrSetValue(LowerCase(AId), AFactory);
end;

class procedure TAtlasWelcomeViews.Unregister(const AId: string);
begin
  if FFactories <> nil then
    FFactories.Remove(LowerCase(AId));
end;

class function TAtlasWelcomeViews.Exists(const AId: string): Boolean;
begin
  Result := (FFactories <> nil) and FFactories.ContainsKey(LowerCase(AId));
end;

class function TAtlasWelcomeViews.CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame;
var
  Factory: TAtlasWelcomeViewFactory;
begin
  Result := nil;
  if (FFactories = nil) or not FFactories.TryGetValue(LowerCase(AId), Factory) then
    Exit;
  Result := Factory(AOwner);
  if Result <> nil then
    Result.SectionId := AId;
end;

class procedure TAtlasWelcomeViews.Release;
begin
  FreeAndNil(FFactories);
end;

end.
