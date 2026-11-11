unit Atlas.IDE.Designer.Magnifier;

// Lupe für den Designer (#743, designer.magnifier) in der IDE:
// - Eigener Knopf in der Designer-Leiste: Symbol öffnet und schließt die
//   Lupe (TAtlasMagnifierWindow), Pfeil = Menü (auch Kontextmenü der Lupe)
//   mit Einfrieren, Stufe, Raster, Kanten und Kopieren.
// - Taste designer.magnifier.key (Vorgabe Strg+Alt+L), solange ein Designer
//   gezeigt wird: öffnet die Lupe, bei offener Lupe friert sie den Ausschnitt
//   ein bzw. lässt ihn wieder der Maus folgen. Eingefroren verschieben die
//   Pfeiltasten im Designer den Ausschnitt um ein Pixel.
// - Ein eigener Takt (30 ms) holt den Ausschnitt nur, wenn sich die Maus
//   bewegt hat oder seit dem letzten Mal 300 ms vergangen sind (Designer
//   geändert). Über der Lupe selbst bleibt das letzte Bild stehen.
// - Kopfzeile: Koordinaten in DFM-Pixeln des Formulars (Bildschirmpixel über
//   CurrentPPI und PixelsPerInch des Formulars, TAtlasMagnifier.ToDesign) und
//   relativ zum Elternelement der Komponente darunter. Fußzeile: Farbe als
//   Hex, Systemfarben und VCL-Name, Name der Komponente.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.Menus,
  Atlas.Core.Designer.Magnifier,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.Magnifier,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeMagnifier = class;

  /// <summary>Taste der Lupe und, eingefroren, die Pfeiltasten.</summary>
  TAtlasMagnifierKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeMagnifier;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  TAtlasIdeMagnifier = class
  public const
    cId = 'magnifier';
  private
    FOnMessage: TProc<string>;
    FWindow: TAtlasMagnifierWindow;
    FMenu: TPopupMenu;
    FTimer: TTimer;
    FKeys: TAtlasMagnifierKeys;
    FSystemColors: TArray<TAtlasNamedColor>;
    FZoom: Integer;
    FGrid: Boolean;
    FEdges: Boolean;
    FFrozen: Boolean;
    FCenter: TPoint;
    FLastCapture: UInt64;
    FCoordinates: string;
    FColorText: string;
    procedure Say(const AText: string);
    procedure EnsureWindow;
    function Open: Boolean;
    /// <summary>Ausschnitt holen, wenn sich die Maus bewegt hat, AForce gilt oder cRefresh vergangen ist.</summary>
    procedure UpdateView(AForce: Boolean);
    procedure TimerTick(Sender: TObject);
    procedure Describe;
    function CoordinatesOf(ARoot: TWinControl; out AControl: TControl): string;
    function ColorTextOf(ARgb: Cardinal): string;
    function EdgeLines: TArray<TAtlasMagnifierLine>;
    procedure AddEdges(var ALines: TArray<TAtlasMagnifierLine>; AControl: TControl; ASelected: Boolean);
    procedure BuildMenu;
    procedure AddMenuItem(const ACaption: string; ATag: Integer; AChecked: Boolean);
    procedure MenuPopup(Sender: TObject);
    procedure MenuClick(Sender: TObject);
    procedure CopyText(const AText: string);
    procedure SetZoom(AZoom: Integer);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Knopf der Designer-Leiste: gedrückt, solange die Lupe offen ist.</summary>
    function Button: TAtlasDesignerButton;
    /// <summary>Klick auf das Symbol: Lupe öffnen oder schließen.</summary>
    procedure Toggle;
    /// <summary>Taste: öffnen, sonst einfrieren bzw. wieder folgen.</summary>
    procedure KeyPressed;
    /// <summary>Eingefroren: Ausschnitt um ADX, ADY Pixel verschieben.</summary>
    procedure Nudge(ADX, ADY: Integer);
    procedure Popup(const APoint: TPoint);
    /// <summary>Takt der Leiste: Tasten an- und abmelden.</summary>
    procedure Tick;
    procedure Hide;
    procedure ApplyTheme;
    function Shown: Boolean;
    property Frozen: Boolean read FFrozen;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.UITypes,
  Vcl.Graphics,
  Vcl.Forms,
  Vcl.Clipbrd,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ToolStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 42;
  cInterval = 30;
  /// <summary>Spätestens so oft neu holen, auch ohne Mausbewegung (Designer geändert).</summary>
  cRefresh = 300;
  cMenuShow = 0;
  cMenuFreeze = 1;
  cMenuZoom = 10;
  cMenuGrid = 20;
  cMenuEdges = 21;
  cMenuCopyColor = 30;
  cMenuCopyPos = 31;

type
  /// <summary>Sammelt die Systemfarben (Bezeichner und Wert) für GetColorValues.</summary>
  TAtlasColorCollector = class
  public
    Colors: TArray<TAtlasNamedColor>;
    procedure Add(const AName: string);
  end;

procedure TAtlasColorCollector.Add(const AName: string);
var
  mColor: Integer;
  mRgb: TColor;
begin
  if not IdentToColor(AName, mColor) or (mColor >= 0) then
  begin
    Exit;
  end;
  mRgb := ColorToRGB(mColor);
  Colors := Colors + [TAtlasNamedColor.Create(AName, (Cardinal(GetRValue(mRgb)) shl 16) or
    (Cardinal(GetGValue(mRgb)) shl 8) or GetBValue(mRgb))];
end;

{ TAtlasMagnifierKeys }

function TAtlasMagnifierKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := False;
  if (FOwner = nil) or not mSettings.DesignerMagnifier or not TAtlasDesignerAccess.Shown then
  begin
    Exit;
  end;
  if (mSettings.DesignerMagnifierKey <> 0) and
    (ShortCut(AKey, AShift) = TShortCut(mSettings.DesignerMagnifierKey)) then
  begin
    Exit(True);
  end;
  Result := FOwner.Shown and FOwner.Frozen and (AShift = []) and TAtlasDesignerAccess.Focused and
    ((AKey = VK_LEFT) or (AKey = VK_RIGHT) or (AKey = VK_UP) or (AKey = VK_DOWN));
end;

procedure TAtlasMagnifierKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeMagnifier;
  mKey: Word;
begin
  mOwner := FOwner;
  mKey := AKey;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mKey = VK_LEFT then
      begin
        mOwner.Nudge(-1, 0);
      end
      else if mKey = VK_RIGHT then
      begin
        mOwner.Nudge(1, 0);
      end
      else if mKey = VK_UP then
      begin
        mOwner.Nudge(0, -1);
      end
      else if mKey = VK_DOWN then
      begin
        mOwner.Nudge(0, 1);
      end
      else
      begin
        mOwner.KeyPressed;
      end;
    end);
end;

{ TAtlasIdeMagnifier }

constructor TAtlasIdeMagnifier.Create(const AOnMessage: TProc<string>);
var
  mCollector: TAtlasColorCollector;
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FMenu := TPopupMenu.Create(nil);
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cInterval;
  FTimer.OnTimer := TimerTick;
  FKeys := TAtlasMagnifierKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
  mCollector := TAtlasColorCollector.Create;
  try
    GetColorValues(mCollector.Add);
    FSystemColors := mCollector.Colors;
  finally
    mCollector.Free;
  end;
end;

destructor TAtlasIdeMagnifier.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  FTimer.Free;
  FWindow.Free;
  FMenu.Free;
  inherited Destroy;
end;

class function TAtlasIdeMagnifier.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerMagnifier;
end;

function TAtlasIdeMagnifier.Button: TAtlasDesignerButton;
begin
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.Magnifier,
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagHint));
  Result.Pressed := Shown;
  Result.Menu := True;
end;

procedure TAtlasIdeMagnifier.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeMagnifier.Shown: Boolean;
begin
  Result := (FWindow <> nil) and FWindow.Shown;
end;

procedure TAtlasIdeMagnifier.EnsureWindow;
var
  mOwner: TAtlasIdeMagnifier;
begin
  if FWindow <> nil then
  begin
    Exit;
  end;
  mOwner := Self;
  FWindow := TAtlasMagnifierWindow.CreateMagnifier(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  FWindow.Caption := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagTitle);
  FWindow.PopupMenu := FMenu;
  FMenu.OnPopup := MenuPopup;
  FWindow.OnCopy :=
    procedure
    begin
      mOwner.CopyText(mOwner.FColorText);
    end;
  FWindow.OnWheel :=
    procedure(ADelta: Integer)
    begin
      mOwner.SetZoom(TAtlasMagnifier.NextZoom(mOwner.FZoom, ADelta));
    end;
  FWindow.OnClosed :=
    procedure
    begin
      mOwner.FTimer.Enabled := False;
    end;
end;

function TAtlasIdeMagnifier.Open: Boolean;
var
  mSettings: TAtlasPluginSettings;
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mOrigin: TPoint;
  mArea: TRect;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerMagnifier and TAtlasDesignerAccess.Current(mEditor, mRoot) and (mRoot is TWinControl);
  if not Result then
  begin
    Exit;
  end;
  EnsureWindow;
  FZoom := TAtlasMagnifier.NormalizeZoom(mSettings.DesignerMagnifierZoom);
  FGrid := mSettings.DesignerMagnifierGrid;
  FEdges := mSettings.DesignerMagnifierEdges;
  FFrozen := False;
  mArea := TRect.Empty;
  TAtlasDesignerAccess.ClientArea(TWinControl(mRoot), 0, mOrigin, mArea);
  FWindow.ShowNear(mArea);
  FTimer.Enabled := True;
  UpdateView(True);
end;

procedure TAtlasIdeMagnifier.Toggle;
begin
  if Shown then
  begin
    Hide;
  end
  else
  begin
    Open;
  end;
end;

procedure TAtlasIdeMagnifier.KeyPressed;
begin
  if not Shown then
  begin
    Open;
    Exit;
  end;
  FFrozen := not FFrozen;
  UpdateView(True);
end;

procedure TAtlasIdeMagnifier.Nudge(ADX, ADY: Integer);
begin
  if Shown and FFrozen then
  begin
    FCenter := Point(FCenter.X + ADX, FCenter.Y + ADY);
    UpdateView(True);
  end;
end;

procedure TAtlasIdeMagnifier.SetZoom(AZoom: Integer);
begin
  FZoom := TAtlasMagnifier.NormalizeZoom(AZoom);
  UpdateView(True);
end;

procedure TAtlasIdeMagnifier.Tick;
begin
  if TAtlasIdeSettings.Current.DesignerMagnifier and TAtlasDesignerAccess.Shown then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
    Hide;
  end;
end;

procedure TAtlasIdeMagnifier.Hide;
begin
  FTimer.Enabled := False;
  FFrozen := False;
  if FWindow <> nil then
  begin
    FWindow.HideWindow;
  end;
end;

procedure TAtlasIdeMagnifier.ApplyTheme;
begin
  if FWindow <> nil then
  begin
    FWindow.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeMagnifier.TimerTick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      UpdateView(False);
    end);
end;

procedure TAtlasIdeMagnifier.UpdateView(AForce: Boolean);
var
  mCursor: TPoint;
  mMoved: Boolean;
begin
  if not Shown then
  begin
    FTimer.Enabled := False;
    Exit;
  end;
  mMoved := False;
  if not FFrozen and GetCursorPos(mCursor) and not FWindow.Contains(mCursor) then
  begin
    mMoved := mCursor <> FCenter;
    FCenter := mCursor;
  end;
  if not AForce and not mMoved and (GetTickCount64 - FLastCapture < cRefresh) then
  begin
    Exit;
  end;
  FLastCapture := GetTickCount64;
  FWindow.Capture(TAtlasMagnifier.SourceRect(FCenter, FWindow.ViewSize, FZoom), FZoom, FGrid);
  if FEdges then
  begin
    FWindow.SetLines(EdgeLines);
  end
  else
  begin
    FWindow.SetLines(nil);
  end;
  Describe;
end;

procedure TAtlasIdeMagnifier.Describe;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControl: TControl;
  mRgb: Cardinal;
  mHeader, mFooter: string;
begin
  mControl := nil;
  FCoordinates := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagOutside);
  mHeader := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagZoom, [FZoom]) + '   ' + FCoordinates;
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (mRoot is TWinControl) then
  begin
    mHeader := CoordinatesOf(TWinControl(mRoot), mControl);
  end;
  if FFrozen then
  begin
    mHeader := mHeader + TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagFrozen);
  end;
  FColorText := '';
  if FWindow.ColorAt(FCenter, mRgb) then
  begin
    FColorText := TAtlasMagnifier.HexOf(mRgb);
  end;
  mFooter := ColorTextOf(mRgb);
  if mControl <> nil then
  begin
    mFooter := mFooter + '   ·   ' + mControl.Name;
  end;
  FWindow.SetTexts(mHeader, mFooter);
end;

function TAtlasIdeMagnifier.CoordinatesOf(ARoot: TWinControl; out AControl: TControl): string;
var
  mCurrent, mDesign: Integer;
  mOffset, mParent: TPoint;
begin
  AControl := nil;
  mCurrent := ARoot.CurrentPPI;
  mDesign := Screen.PixelsPerInch;
  if ARoot is TCustomForm then
  begin
    mDesign := TCustomForm(ARoot).PixelsPerInch;
  end;
  mOffset := ARoot.ScreenToClient(FCenter);
  FCoordinates := Format('%d, %d', [TAtlasMagnifier.ToDesign(mOffset.X, mCurrent, mDesign),
    TAtlasMagnifier.ToDesign(mOffset.Y, mCurrent, mDesign)]);
  Result := TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagHeader,
    [FZoom, TAtlasMagnifier.ToDesign(mOffset.X, mCurrent, mDesign), TAtlasMagnifier.ToDesign(mOffset.Y, mCurrent,
    mDesign)]);
  if not ARoot.ClientRect.Contains(mOffset) then
  begin
    Exit;
  end;
  AControl := ARoot.ControlAtPos(mOffset, True, True, True);
  if (AControl = nil) or (AControl.Parent = nil) or (AControl.Parent = ARoot) then
  begin
    Exit;
  end;
  mParent := AControl.Parent.ScreenToClient(FCenter);
  Result := Result + TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagHeaderParent,
    [TAtlasMagnifier.ToDesign(mParent.X, mCurrent, mDesign), TAtlasMagnifier.ToDesign(mParent.Y, mCurrent, mDesign),
    AControl.Parent.Name]);
end;

function TAtlasIdeMagnifier.ColorTextOf(ARgb: Cardinal): string;
var
  mName, mStandard: string;
begin
  if FColorText = '' then
  begin
    Exit('');
  end;
  Result := FColorText;
  for mName in TAtlasMagnifier.NamesOf(ARgb, FSystemColors) do
  begin
    Result := Result + '   ' + TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagSystem, [mName]);
  end;
  mStandard := TAtlasMagnifier.StandardName(ARgb);
  if mStandard <> '' then
  begin
    Result := Result + '   ' + mStandard;
  end;
end;

procedure TAtlasIdeMagnifier.AddEdges(var ALines: TArray<TAtlasMagnifierLine>; AControl: TControl;
  ASelected: Boolean);
var
  mSource: TRect;
  mTopLeft: TPoint;
  mRect: TRect;
begin
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  mSource := FWindow.Source;
  mTopLeft := AControl.Parent.ClientToScreen(AControl.BoundsRect.TopLeft);
  mRect := Rect(mTopLeft.X, mTopLeft.Y, mTopLeft.X + AControl.Width, mTopLeft.Y + AControl.Height);
  // Nur Kanten, die den Ausschnitt schneiden; rechte und untere Kante liegen hinter dem letzten Pixel.
  if (mRect.Bottom < mSource.Top) or (mRect.Top > mSource.Bottom) or (mRect.Right < mSource.Left) or
    (mRect.Left > mSource.Right) then
  begin
    Exit;
  end;
  ALines := ALines + [TAtlasMagnifierLine.Create(True, TAtlasMagnifier.ToView(mRect.Left, mSource.Left, FZoom),
    ASelected), TAtlasMagnifierLine.Create(True, TAtlasMagnifier.ToView(mRect.Right, mSource.Left, FZoom), ASelected),
    TAtlasMagnifierLine.Create(False, TAtlasMagnifier.ToView(mRect.Top, mSource.Top, FZoom), ASelected),
    TAtlasMagnifierLine.Create(False, TAtlasMagnifier.ToView(mRect.Bottom, mSource.Top, FZoom), ASelected)];
end;

function TAtlasIdeMagnifier.EdgeLines: TArray<TAtlasMagnifierLine>;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mControl: TControl;
  mIndex: Integer;
  mSelected: TArray<TComponent>;
  mDone: TList;
begin
  Result := nil;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  mDone := TList.Create;
  try
    for mComponent in mSelected do
    begin
      if (mComponent is TControl) and (TControl(mComponent).Parent <> nil) then
      begin
        mDone.Add(mComponent);
        AddEdges(Result, TControl(mComponent), True);
      end;
    end;
    // Nachbarn: übrige Kinder der Elternelemente der Auswahl.
    for mComponent in mSelected do
    begin
      if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) then
      begin
        Continue;
      end;
      for mIndex := 0 to TControl(mComponent).Parent.ControlCount - 1 do
      begin
        mControl := TControl(mComponent).Parent.Controls[mIndex];
        if mDone.IndexOf(mControl) < 0 then
        begin
          mDone.Add(mControl);
          AddEdges(Result, mControl, False);
        end;
      end;
    end;
  finally
    mDone.Free;
  end;
end;

procedure TAtlasIdeMagnifier.CopyText(const AText: string);
begin
  if AText = '' then
  begin
    Exit;
  end;
  Clipboard.AsText := AText;
  Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagCopied, [AText]));
end;

procedure TAtlasIdeMagnifier.AddMenuItem(const ACaption: string; ATag: Integer; AChecked: Boolean);
var
  mItem: TMenuItem;
begin
  mItem := TMenuItem.Create(FMenu);
  mItem.Caption := ACaption;
  mItem.Tag := ATag;
  mItem.Checked := AChecked;
  mItem.OnClick := MenuClick;
  FMenu.Items.Add(mItem);
end;

procedure TAtlasIdeMagnifier.MenuPopup(Sender: TObject);
begin
  BuildMenu;
end;

procedure TAtlasIdeMagnifier.BuildMenu;
var
  mZoom: Integer;
begin
  FMenu.Items.Clear;
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagShow), cMenuShow, Shown);
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagFreeze), cMenuFreeze, FFrozen);
  FMenu.Items.Add(NewLine);
  mZoom := TAtlasMagnifier.cMinZoom;
  while mZoom <= TAtlasMagnifier.cMaxZoom do
  begin
    AddMenuItem(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.MagZoom, [mZoom]), cMenuZoom + mZoom,
      mZoom = FZoom);
    mZoom := mZoom * 2;
  end;
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagGrid), cMenuGrid, FGrid);
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagEdges), cMenuEdges, FEdges);
  FMenu.Items.Add(NewLine);
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagCopyColor), cMenuCopyColor, False);
  AddMenuItem(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.MagCopyPos), cMenuCopyPos, False);
end;

procedure TAtlasIdeMagnifier.Popup(const APoint: TPoint);
begin
  // OnPopup baut das Menü.
  FMenu.Popup(APoint.X, APoint.Y);
end;

procedure TAtlasIdeMagnifier.MenuClick(Sender: TObject);
var
  mTag: NativeInt;
  mOwner: TAtlasIdeMagnifier;
begin
  mTag := TMenuItem(Sender).Tag;
  mOwner := Self;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      case mTag of
        cMenuShow:
          mOwner.Toggle;
        cMenuFreeze:
          mOwner.KeyPressed;
        cMenuGrid:
          begin
            mOwner.FGrid := not mOwner.FGrid;
            mOwner.UpdateView(True);
          end;
        cMenuEdges:
          begin
            mOwner.FEdges := not mOwner.FEdges;
            mOwner.UpdateView(True);
          end;
        cMenuCopyColor:
          mOwner.CopyText(mOwner.FColorText);
        cMenuCopyPos:
          mOwner.CopyText(mOwner.FCoordinates);
      else
        mOwner.SetZoom(Integer(mTag) - cMenuZoom);
      end;
    end);
end;

end.
