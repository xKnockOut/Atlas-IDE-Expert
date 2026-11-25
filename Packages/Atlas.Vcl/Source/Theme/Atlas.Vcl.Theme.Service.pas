unit Atlas.Vcl.Theme.Service;

// Themendienst der Atlas-Fenster (#2061): Farben, Dialogschrift und
// Themenwechsel an einer Stelle, statt dass jedes Fenster sie selbst holt
// (39 Units setzten die Schrift von Hand, 36 Dialoge hatten gar kein Thema,
// der mitlaufende Kopf hörte nicht auf den Wechsel, #2058).
// Die Schicht UI kennt die Open Tools API nicht. Die IDE-Schicht von Base
// setzt deshalb mit Install die Quelle der Farben (TAtlasIdeStyle.Colors) und
// das Anwenden des IDE-Themas auf ein Fenster (ApplyIdeTheme) und meldet mit
// Changed jeden Themenwechsel. Ohne Install (Tests, Werkzeuge) gelten die
// hellen Atlas-Farben, Apply tut nichts.
// Wer dem Thema folgt, meldet sich mit Subscribe an und spätestens im
// Destroy mit Unsubscribe ab; nach dem Abmelden erreicht ihn nichts mehr.
// Systemfarben (clGrayText, clHighlight …) gelten im IDE-Thema nur über den
// Stil: SystemColor zum Zeichnen, UseFontColor für die Schrift eines
// Steuerelements.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  Vcl.Graphics,
  Vcl.Controls,
  Atlas.Plugin.Style.Palette,
  Atlas.Plugin.Style.Signal,
  Atlas.Plugin.Style.Listeners;

type
  TAtlasUiTheme = class
  public const
    /// <summary>Schrift der Atlas-Dialoge.</summary>
    cFontName = 'Segoe UI';
    cFontSize = 9;
  private
    class var FListeners: TAtlasThemeListeners;
    class var FColorSource: TFunc<TAtlasColors>;
    class var FApplier: TProc<TWinControl>;
    class var FOnFailure: TProc<string>;
    class function Listeners: TAtlasThemeListeners; static;
  public
    class destructor Destroy;
    /// <summary>Quelle der Farben und Anwenden des IDE-Themas setzen (IDE-Schicht von Base, beim Start).
    /// AOnFailure bekommt Fehler von Abonnenten für das Protokoll; nil = verwerfen.</summary>
    class procedure Install(const AColorSource: TFunc<TAtlasColors>; const AApplier: TProc<TWinControl>;
      const AOnFailure: TProc<string>); static;
    /// <summary>Quelle und Anwenden wieder lösen (beim Entladen von Base); Abonnenten bleiben angemeldet.</summary>
    class procedure Uninstall; static;
    /// <summary>Aktuelle Atlas-Farben passend zum IDE-Thema; ohne Install die hellen.</summary>
    class function Colors: TAtlasColors; static;
    /// <summary>Farben einer Fensterfläche im Stil von AControl (in der IDE deren Thema): Fläche und Schrift
    /// aus clWindow/clWindowText statt der festen Atlas-Palette, damit Listen und Zeichenflächen in
    /// andockbaren Fenstern wie die Fenster der IDE (Objektinspektor) aussehen; Akzent und Signale aus der
    /// Palette. AControl = nil: Stil der Anwendung.</summary>
    class function WindowColors(AControl: TControl): TAtlasColors; static;
    /// <summary>Textfarbe einer Meldung auf der Fensterfläche: Fehler, Warnung und Ok aus der Palette (für Text
    /// gedacht, nicht die Signalpunkte); Hinweis und ohne Aussage = Textfarbe des Stils (clWindowText).</summary>
    class function TextColor(AKind: TAtlasSignalKind): TColor; static;
    /// <summary>True, wenn TextColor(AKind) die Farbe des Stils ist (dann zeichnet der Stil die Schrift).</summary>
    class function UsesStyleText(AKind: TAtlasSignalKind): Boolean; static;
    /// <summary>Systemfarbe AColor (clGrayText, clHighlight …) im Stil von AControl als RGB, zum Zeichnen auf einer
    /// Zeichenfläche. Eine Systemfarbe direkt in Canvas.Font.Color bzw. Brush.Color nimmt die Farbe von Windows,
    /// im dunklen IDE-Thema also hell. AControl = nil: Stil der Anwendung.</summary>
    class function SystemColor(AControl: TControl; AColor: TColor): TColor; static;
    /// <summary>Farben einer selbst gefärbten Zeile einer Liste oder eines Baums AControl auf ACanvas: gewählt in den
    /// Farben der Auswahl, sonst Fläche und Schrift von AControl (AGray: clGrayText), alle über den Stil. ASelected
    /// kommt aus Item.Selected bzw. Node.Selected, nie aus cdsSelected: Das ist in der IDE bei jeder Zeile gesetzt,
    /// die Zeile bekäme dann die helle Auswahlschrift auf dem weißen Hintergrund von Windows.</summary>
    class procedure RowColors(ACanvas: TCanvas; AControl: TControl; ASelected, AGray: Boolean); static;
    /// <summary>Schrift von AControl in der Systemfarbe AColor des Stils zeigen und bei jedem Themenwechsel
    /// nachziehen, bis AControl freigegeben wird. Mit seFont übergeht der VCL-Stil Font.Color und zeichnet in
    /// seiner Textfarbe: Ein „Font.Color := clGrayText“ bliebe ohne Wirkung. Ein zweiter Aufruf ersetzt die Farbe;
    /// clDefault gibt die Schrift wieder an den Stil.</summary>
    class procedure UseFontColor(AControl: TControl; AColor: TColor); static;
    /// <summary>Dialogschrift auf AFont übertragen (Name und Größe, Stil und Farbe bleiben).</summary>
    class procedure AssignDialogFont(AFont: TFont); static;
    /// <summary>IDE-Thema auf AControl und seine Kinder anwenden; ohne Install nichts.</summary>
    class procedure Apply(AControl: TWinControl); static;
    /// <summary>AHandler bei jedem Themenwechsel rufen, bis AOwner sich abmeldet.</summary>
    class procedure Subscribe(AOwner: TObject; const AHandler: TProc); static;
    class procedure Unsubscribe(AOwner: TObject); static;
    /// <summary>True, wenn AOwner angemeldet ist.</summary>
    class function Subscribed(AOwner: TObject): Boolean; static;
    /// <summary>Das IDE-Thema hat gewechselt: alle Abonnenten rufen.</summary>
    class procedure Changed; static;
  end;

implementation

uses
  System.Classes,
  Vcl.Themes,
  Atlas.Plugin.Style.Color;

type
  TControlAccess = class(TControl);

  /// <summary>Hält die Schriftfarbe eines Steuerelements im Stil (UseFontColor); gehört dem Steuerelement und meldet
  /// sich mit ihm vom Themenwechsel ab.</summary>
  TAtlasFontColorKeeper = class(TComponent)
  private
    FColor: TColor;
    procedure Apply;
  public
    constructor Create(AOwner: TComponent); override;
    destructor Destroy; override;
    /// <summary>Hüter von AControl; nil, wenn es keinen hat.</summary>
    class function KeeperOf(AControl: TControl): TAtlasFontColorKeeper; static;
    procedure Follow(AColor: TColor);
  end;

{ TAtlasFontColorKeeper }

constructor TAtlasFontColorKeeper.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FColor := clWindowText;
  TAtlasUiTheme.Subscribe(Self,
    procedure
    begin
      Apply;
    end);
end;

destructor TAtlasFontColorKeeper.Destroy;
begin
  TAtlasUiTheme.Unsubscribe(Self);
  inherited;
end;

class function TAtlasFontColorKeeper.KeeperOf(AControl: TControl): TAtlasFontColorKeeper;
var
  mIndex: Integer;
begin
  for mIndex := 0 to AControl.ComponentCount - 1 do
  begin
    if AControl.Components[mIndex] is TAtlasFontColorKeeper then
    begin
      Exit(TAtlasFontColorKeeper(AControl.Components[mIndex]));
    end;
  end;
  Result := nil;
end;

procedure TAtlasFontColorKeeper.Follow(AColor: TColor);
begin
  FColor := AColor;
  Apply;
end;

procedure TAtlasFontColorKeeper.Apply;
var
  mControl: TControl;
begin
  mControl := TControl(Owner);
  mControl.StyleElements := mControl.StyleElements - [seFont];
  TControlAccess(mControl).Font.Color := TAtlasUiTheme.SystemColor(mControl, FColor);
end;

{ TAtlasUiTheme }

class destructor TAtlasUiTheme.Destroy;
begin
  FreeAndNil(FListeners);
  FColorSource := nil;
  FApplier := nil;
  FOnFailure := nil;
end;

class function TAtlasUiTheme.Listeners: TAtlasThemeListeners;
begin
  if FListeners = nil then
  begin
    FListeners := TAtlasThemeListeners.Create;
  end;
  Result := FListeners;
end;

class procedure TAtlasUiTheme.Install(const AColorSource: TFunc<TAtlasColors>;
  const AApplier: TProc<TWinControl>; const AOnFailure: TProc<string>);
begin
  FColorSource := AColorSource;
  FApplier := AApplier;
  FOnFailure := AOnFailure;
end;

class procedure TAtlasUiTheme.Uninstall;
begin
  FColorSource := nil;
  FApplier := nil;
  FOnFailure := nil;
end;

class function TAtlasUiTheme.Colors: TAtlasColors;
begin
  if Assigned(FColorSource) then
  begin
    Exit(FColorSource());
  end;
  Result := TAtlasColors.Light;
end;

class function TAtlasUiTheme.WindowColors(AControl: TControl): TAtlasColors;
var
  mStyle: TCustomStyleServices;
begin
  mStyle := StyleServices(AControl);
  Result := TAtlasColors.ForWindow(TAtlasColor(ColorToRGB(mStyle.GetSystemColor(clWindow))),
    TAtlasColor(ColorToRGB(mStyle.GetSystemColor(clWindowText))));
end;

class function TAtlasUiTheme.TextColor(AKind: TAtlasSignalKind): TColor;
var
  mColors: TAtlasColors;
begin
  if UsesStyleText(AKind) then
  begin
    Exit(clWindowText);
  end;
  mColors := Colors;
  case AKind of
    TAtlasSignalKind.Ok:
      Result := TColor(mColors.Add);
    TAtlasSignalKind.Warn:
      Result := TColor(mColors.Warn);
  else
    Result := TColor(mColors.Error);
  end;
end;

class function TAtlasUiTheme.UsesStyleText(AKind: TAtlasSignalKind): Boolean;
begin
  Result := (AKind = TAtlasSignalKind.Info) or (AKind = TAtlasSignalKind.Idle);
end;

class function TAtlasUiTheme.SystemColor(AControl: TControl; AColor: TColor): TColor;
begin
  Result := ColorToRGB(StyleServices(AControl).GetSystemColor(AColor));
end;

class procedure TAtlasUiTheme.RowColors(ACanvas: TCanvas; AControl: TControl; ASelected, AGray: Boolean);
begin
  if ASelected then
  begin
    ACanvas.Brush.Color := SystemColor(AControl, clHighlight);
    ACanvas.Font.Color := SystemColor(AControl, clHighlightText);
    Exit;
  end;
  ACanvas.Brush.Color := SystemColor(AControl, TControlAccess(AControl).Color);
  if AGray then
  begin
    ACanvas.Font.Color := SystemColor(AControl, clGrayText);
  end
  else
  begin
    ACanvas.Font.Color := SystemColor(AControl, TControlAccess(AControl).Font.Color);
  end;
end;

class procedure TAtlasUiTheme.UseFontColor(AControl: TControl; AColor: TColor);
var
  mKeeper: TAtlasFontColorKeeper;
begin
  if AControl = nil then
  begin
    Exit;
  end;
  mKeeper := TAtlasFontColorKeeper.KeeperOf(AControl);
  if AColor = clDefault then
  begin
    // Zurück an den Stil: Er zeichnet die Schrift wieder selbst, nichts folgt mehr dem Thema.
    mKeeper.Free;
    AControl.StyleElements := AControl.StyleElements + [seFont];
    TControlAccess(AControl).Font.Color := clWindowText;
    Exit;
  end;
  if mKeeper = nil then
  begin
    mKeeper := TAtlasFontColorKeeper.Create(AControl);
  end;
  mKeeper.Follow(AColor);
end;

class procedure TAtlasUiTheme.AssignDialogFont(AFont: TFont);
begin
  if AFont = nil then
  begin
    Exit;
  end;
  AFont.Name := cFontName;
  AFont.Size := cFontSize;
end;

class procedure TAtlasUiTheme.Apply(AControl: TWinControl);
begin
  if (AControl <> nil) and Assigned(FApplier) then
  begin
    FApplier(AControl);
  end;
end;

class procedure TAtlasUiTheme.Subscribe(AOwner: TObject; const AHandler: TProc);
begin
  Listeners.Add(AOwner, AHandler);
end;

class procedure TAtlasUiTheme.Unsubscribe(AOwner: TObject);
begin
  if FListeners <> nil then
  begin
    FListeners.Remove(AOwner);
  end;
end;

class function TAtlasUiTheme.Subscribed(AOwner: TObject): Boolean;
begin
  Result := (FListeners <> nil) and FListeners.Contains(AOwner);
end;

class procedure TAtlasUiTheme.Changed;
var
  mFailure: string;
begin
  if FListeners = nil then
  begin
    Exit;
  end;
  for mFailure in FListeners.Notify do
  begin
    if Assigned(FOnFailure) then
    begin
      FOnFailure(mFailure);
    end;
  end;
end;

end.
