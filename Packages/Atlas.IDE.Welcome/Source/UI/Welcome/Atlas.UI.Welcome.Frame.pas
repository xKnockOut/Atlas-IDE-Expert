unit Atlas.UI.Welcome.Frame;

// Frames der Atlas-Willkommensseite (#753):
// - TAtlasWelcomeCanvas: Zeichenfläche, Alias von TAtlasStyledCanvas aus Base.
// - TAtlasWelcomeRow, TAtlasWelcomeMarks: gemeinsame Maße und Markenfarben der Bereiche.
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
  Vcl.Graphics,
  Atlas.Vcl.Theme.Canvas;

type
  /// <summary>Zeichenfläche der Bereiche ohne Flackern (Atlas.Vcl.Theme.Canvas).</summary>
  TAtlasWelcomeCanvas = TAtlasStyledCanvas;

  /// <summary>Maße der zweizeiligen Einträge (Projekte, Weiterarbeiten, Ungesichert) in logischen Pixeln bei
  /// 96 dpi, gezählt ab der Oberkante des Eintrags; skaliert über ScaleValue des Frames.</summary>
  TAtlasWelcomeRow = record
  public const
    /// <summary>Erste Zeile (fetter Name) von oben bis unten.</summary>
    cNameTop = 3;
    cNameBottom = 21;
    /// <summary>Zweite Zeile (Detail) von oben bis unten.</summary>
    cDetailTop = 23;
    cDetailBottom = 41;
    /// <summary>Oberkante der farbigen Marke vor dem Namen und Abstand zwischen Marke und Text.</summary>
    cDotTop = 6;
    cDotGap = 6;
    /// <summary>Abstand nach dem fetten Namen bis zum Zusatz (Zweig).</summary>
    cNameGap = 8;
    /// <summary>Radius der Ecken der Knöpfe in einem Eintrag.</summary>
    cButtonRadius = 6;
    /// <summary>Oberkante des Hinweises, wenn es keine Einträge gibt.</summary>
    cEmptyTop = 4;
    /// <summary>Platz links der Schnellaktionen, der für den Namen mindestens bleibt.</summary>
    cQuickActionsLeft = 80;
    /// <summary>Breite des Balkens am linken Rand des gewählten Eintrags.</summary>
    cSelectionBar = 3;
  end;

  /// <summary>Farben der Marken (#592): kräftige Töne mit weißer Schrift, lesbar im hellen und im dunklen
  /// Thema; grün, gelb, rot, grau.</summary>
  TAtlasWelcomeMarks = record
  public const
    cGood = TColor($0043A02E);
    cWarning = TColor($001A8CC9);
    cError = TColor($002E22CF);
    cNeutral = TColor($00817666);
  end;

  /// <summary>Steuerelement der Willkommensseite, das Tasten vor den Tastenkürzeln des Hauptfensters in HandleKey
  /// sieht; nicht behandelte gehen den üblichen Weg. Mit FSystemKeys auch Tasten mit Alt.</summary>
  TAtlasWelcomeKeyControl = class(TCustomControl)
  private
    procedure CNKeyDown(var Message: TWMKeyDown); message CN_KEYDOWN;
    procedure CNSysKeyDown(var Message: TWMKeyDown); message CN_SYSKEYDOWN;
  protected
    FSystemKeys: Boolean;
  public
    /// <summary>Taste wie gedrückt; True, wenn sie verarbeitet wurde (auch für Tests).</summary>
    function HandleKey(AKey: Word; AShift: TShiftState): Boolean; virtual; abstract;
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
    cTitleHeight = 24;
    /// <summary>Höhe ohne eigene Angabe (logische Pixel).</summary>
    cDefaultBodyHeight = 120;
    /// <summary>Mindesthöhe der Bereiche, deren Höhe sich nach dem Inhalt richtet (logische Pixel).</summary>
    cMinBodyHeight = 40;
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
    /// <summary>AArrange neu ordnen lassen (nach neuer Breite); ändert sich dabei AContentHeight (anderer Umbruch),
    /// meldet es HeightChanged, damit der Frame „Atlas“ die Spalten neu ordnet. AContentHeight ist das Feld, das
    /// AArrange setzt.</summary>
    procedure Rearrange(const AArrange: TProc; var AContentHeight: Integer);
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
    /// <summary>Titelzeile; „Seite anpassen“ (#767) legt Griff und Werkzeuge hinein.</summary>
    property TitleBar: TPanel read FTitleBar;
    /// <summary>Der Frame „Atlas“ ordnet daraufhin die Spalten neu.</summary>
    property OnHeightChanged: TNotifyEvent read FOnHeightChanged write FOnHeightChanged;
  end;

  TAtlasWelcomeViewFactory = reference to function(AOwner: TComponent): TAtlasWelcomeSectionFrame;

  TAtlasWelcomeViews = class
  private class var
    FFactories: TDictionary<string, TAtlasWelcomeViewFactory>;
  public
    /// <summary>Gibt beim Entladen frei, was noch angemeldet ist.</summary>
    class destructor Destroy;
    class procedure Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory); static;
    /// <summary>Meldet AId ab; mit der letzten Fabrik wird auch das Verzeichnis freigegeben.</summary>
    class procedure Unregister(const AId: string); static;
    class function Exists(const AId: string): Boolean; static;
    /// <summary>Neuer Frame für AId mit SectionId; nil ohne Fabrik.</summary>
    class function CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame; static;
    /// <summary>Beim Entladen: alle Fabriken vergessen.</summary>
    class procedure Release; static;
  end;

implementation

uses
  Atlas.Vcl.Controls.Helpers;

const
  /// <summary>Oberkante des Titels in der Titelzeile (logische Pixel bei 96 dpi).</summary>
  cTitleTop = 4;

{$R *.dfm}

{ TAtlasWelcomeKeyControl }

procedure TAtlasWelcomeKeyControl.CNKeyDown(var Message: TWMKeyDown);
begin
  if not TAtlasControls.KeyHandled(Message, HandleKey) then
  begin
    inherited;
  end;
end;

procedure TAtlasWelcomeKeyControl.CNSysKeyDown(var Message: TWMKeyDown);
begin
  if not FSystemKeys or not TAtlasControls.KeyHandled(Message, HandleKey) then
  begin
    inherited;
  end;
end;

{ TAtlasWelcomeFrame }

constructor TAtlasWelcomeFrame.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  // Mehrere Frames unter einem Besitzer: kein fester Name aus der .dfm.
  Name := '';
  ParentBackground := True;
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

procedure TAtlasWelcomeFrame.UpdateContent;
begin
  Invalidate;
end;

function TAtlasWelcomeFrame.HasWindow: Boolean;
begin
  Result := TAtlasControls.WindowOrPending(Self, FPendingUpdate);
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
  FTitleBar.Height := FTitleBar.ScaleValue(cTitleHeight);
  FTitle := TLabel.Create(Self);
  FTitle.Parent := FTitleBar;
  FTitle.Left := FTitle.ScaleValue(2);
  FTitle.Top := FTitle.ScaleValue(cTitleTop);
  FTitle.Font.Style := [fsBold];
  FBody := TPanel.Create(Self);
  FBody.Parent := Self;
  FBody.Align := alClient;
  FBody.BevelOuter := bvNone;
  FBody.ParentBackground := True;
end;

function TAtlasWelcomeSectionFrame.GetTitle: string;
begin
  Result := FTitle.Caption;
end;

procedure TAtlasWelcomeSectionFrame.SetTitle(const AValue: string);
begin
  FTitle.Caption := AValue;
end;

function TAtlasWelcomeSectionFrame.GetShowTitle: Boolean;
begin
  Result := FTitleBar.Visible;
end;

procedure TAtlasWelcomeSectionFrame.SetShowTitle(AValue: Boolean);
begin
  FTitleBar.Visible := AValue;
end;

function TAtlasWelcomeSectionFrame.BodyHeight: Integer;
begin
  Result := cDefaultBodyHeight;
end;

procedure TAtlasWelcomeSectionFrame.HeightChanged;
begin
  if Assigned(FOnHeightChanged) then
  begin
    FOnHeightChanged(Self);
  end;
end;

procedure TAtlasWelcomeSectionFrame.Rearrange(const AArrange: TProc; var AContentHeight: Integer);
var
  mOldHeight: Integer;
begin
  mOldHeight := AContentHeight;
  AArrange();
  if mOldHeight <> AContentHeight then
  begin
    HeightChanged;
  end;
end;

function TAtlasWelcomeSectionFrame.PreferredHeight: Integer;
begin
  Result := BodyHeight;
  if ShowTitle then
  begin
    Inc(Result, FTitleBar.Height);
  end;
end;

{ TAtlasWelcomeViews }

class destructor TAtlasWelcomeViews.Destroy;
begin
  Release;
end;

class procedure TAtlasWelcomeViews.Register(const AId: string; const AFactory: TAtlasWelcomeViewFactory);
begin
  if FFactories = nil then
  begin
    FFactories := TDictionary<string, TAtlasWelcomeViewFactory>.Create;
  end;
  FFactories.AddOrSetValue(LowerCase(AId), AFactory);
end;

class procedure TAtlasWelcomeViews.Unregister(const AId: string);
begin
  if FFactories = nil then
  begin
    Exit;
  end;
  FFactories.Remove(LowerCase(AId));
  if FFactories.Count = 0 then
  begin
    FreeAndNil(FFactories);
  end;
end;

class function TAtlasWelcomeViews.Exists(const AId: string): Boolean;
begin
  Result := (FFactories <> nil) and FFactories.ContainsKey(LowerCase(AId));
end;

class function TAtlasWelcomeViews.CreateView(const AId: string; AOwner: TComponent): TAtlasWelcomeSectionFrame;
var
  mFactory: TAtlasWelcomeViewFactory;
begin
  Result := nil;
  if (FFactories = nil) or not FFactories.TryGetValue(LowerCase(AId), mFactory) then
  begin
    Exit;
  end;
  Result := mFactory(AOwner);
  if Result <> nil then
  begin
    Result.SectionId := AId;
  end;
end;

class procedure TAtlasWelcomeViews.Release;
begin
  FreeAndNil(FFactories);
end;

end.
