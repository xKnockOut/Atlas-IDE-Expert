unit Atlas.IDE.Designer.Measure;

// Knopf „Abstände messen“ der Designer-Leiste (#605) in der IDE. Ein eigener
// Takt (40 ms) beobachtet den Designer; gerechnet wird mit TAtlasMeasure:
// - Ziehen (designer.measureDistances): Solange die linke Maustaste über dem
//   Formular gedrückt ist und sich Lage oder Größe der Auswahl ändern,
//   stehen Maßlinien zu den Nachbarn im selben Parent bzw. zum Innenrand des
//   Parents (Padding) über dem Designer, bei Größenänderung zusätzlich
//   Breite × Höhe. Nach dem Loslassen bleiben sie kurz stehen: Zeichnet die
//   IDE erst am Ende um, sieht man die Werte so wenigstens danach.
// - Alt (designer.measureAltKey): Abstände von der Auswahl (bei
//   Mehrfachauswahl ihr umschließendes Rechteck) zur Komponente unter der
//   Maus, ohne etwas zu verändern.
// - Werte in Pixeln der DFM: Lagen werden mit PixelsPerInch des Formulars zu
//   seiner aktuellen DPI (CurrentPPI) zurückgerechnet (TAtlasDesignScale).
// - Der Knopf schaltet die Anzeige für die Sitzung aus und wieder an.
// Zeichnen: TAtlasMeasureOverlay. Nur im Hauptthread.

interface

uses
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.MeasureOverlay;

type
  TAtlasIdeDesignerMeasure = class
  public const
    cId = 'measure';
    cTickMs = 40;
    cHoldMs = 1500;
  private
    FTimer: TTimer;
    FOverlay: TAtlasMeasureOverlay;
    FActive: Boolean;
    FDragging: Boolean;
    FStart: TRect;
    FStartNames: string;
    FHoldUntil: UInt64;
    procedure Tick(Sender: TObject);
    procedure Update;
    procedure Hide;
    procedure Show(ARoot: TWinControl; const AMarks: TArray<TAtlasMeasureMark>);
    function DragMarks(ARoot: TWinControl; const AControls: TArray<TControl>; ALeftDown: Boolean;
      out AMarks: TArray<TAtlasMeasureMark>): Boolean;
    function AltMarks(ARoot: TWinControl; const AControls: TArray<TControl>): TArray<TAtlasMeasureMark>;
  public
    constructor Create;
    destructor Destroy; override;
    /// <summary>Knopf nach den Einstellungen; Id leer, wenn beide Anzeigen aus sind.</summary>
    function Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
    /// <summary>Klick auf den Knopf: Anzeige für die Sitzung an bzw. aus.</summary>
    procedure Toggle;
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Designer.Measure,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.UI.Designer.ViewStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Model,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

/// <summary>Steuerelemente der Auswahl mit demselben Parent wie das erste.</summary>
function SelectedControls(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TControl>;
var
  mComponent: TComponent;
  mParent: TWinControl;
begin
  Result := nil;
  mParent := nil;
  for mComponent in TAtlasDesignerAccess.Selection(AEditor, ARoot) do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) then
    begin
      Continue;
    end;
    if mParent = nil then
    begin
      mParent := TControl(mComponent).Parent;
    end;
    if TControl(mComponent).Parent = mParent then
    begin
      Result := Result + [TControl(mComponent)];
    end;
  end;
end;

function NamesOf(const AControls: TArray<TControl>): string;
var
  mControl: TControl;
begin
  Result := '';
  for mControl in AControls do
  begin
    Result := Result + mControl.Name + ',';
  end;
end;

/// <summary>Umschließendes Rechteck der Steuerelemente im Client von ARoot.</summary>
function UnionInRoot(const AControls: TArray<TControl>; ARoot: TWinControl): TRect;
var
  mIndex: Integer;
begin
  Result := TAtlasDesignerAccess.BoundsInRoot(AControls[0], ARoot);
  for mIndex := 1 to High(AControls) do
  begin
    Result.Union(TAtlasDesignerAccess.BoundsInRoot(AControls[mIndex], ARoot));
  end;
end;

/// <summary>Client von AParent im Client von ARoot.</summary>
function ClientInRoot(AParent, ARoot: TWinControl): TRect;
var
  mOrigin: TPoint;
begin
  if AParent = ARoot then
  begin
    Exit(Rect(0, 0, ARoot.ClientWidth, ARoot.ClientHeight));
  end;
  mOrigin := ARoot.ScreenToClient(AParent.ClientOrigin);
  Result := Rect(mOrigin.X, mOrigin.Y, mOrigin.X + AParent.ClientWidth, mOrigin.Y + AParent.ClientHeight);
end;

/// <summary>Geschwister der Auswahl im Client von ARoot, ohne die Auswahl selbst.</summary>
function SiblingsOf(const AControls: TArray<TControl>; ARoot: TWinControl;
  const AScale: TAtlasDesignScale): TArray<TAtlasMeasureItem>;
var
  mParent: TWinControl;
  mIndex, mSkip: Integer;
  mControl: TControl;
  mSelected: Boolean;
begin
  Result := nil;
  mParent := AControls[0].Parent;
  for mIndex := 0 to mParent.ControlCount - 1 do
  begin
    mControl := mParent.Controls[mIndex];
    mSelected := False;
    for mSkip := 0 to High(AControls) do
    begin
      mSelected := mSelected or (AControls[mSkip] = mControl);
    end;
    if mSelected or (mControl.Owner <> ARoot) or not mControl.Visible then
    begin
      Continue;
    end;
    Result := Result + [TAtlasMeasureItem.Create(mControl.Name,
      AScale.ToDesign(TAtlasDesignerAccess.BoundsInRoot(mControl, ARoot)))];
  end;
end;

/// <summary>Innenrand des Parents der Auswahl in Pixeln der DFM.</summary>
function InnerOf(AParent, ARoot: TWinControl; const AScale: TAtlasDesignScale): TRect;
begin
  // Padding ist wie die Lagen in Bildschirmpixeln skaliert: erst abziehen, dann umrechnen.
  Result := AScale.ToDesign(TAtlasMeasure.Inner(ClientInRoot(AParent, ARoot), AParent.Padding.Left,
    AParent.Padding.Top, AParent.Padding.Right, AParent.Padding.Bottom));
end;

function PlaceTexts: TArray<string>;
begin
  Result := ['', TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.MeasureAbove),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.MeasureBelow),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.MeasureLeftOf),
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.MeasureRightOf)];
end;

function MarksOf(const ALines: TArray<TAtlasMeasureLine>;
  const AScale: TAtlasDesignScale): TArray<TAtlasMeasureMark>;
var
  mLine: TAtlasMeasureLine;
  mTexts: TArray<string>;
begin
  Result := nil;
  mTexts := PlaceTexts;
  for mLine in ALines do
  begin
    if mLine.Distance <= 0 then
    begin
      Continue;
    end;
    Result := Result + [TAtlasMeasureMark.Line(AScale.ToScreen(mLine.FromPoint), AScale.ToScreen(mLine.ToPoint),
      TAtlasMeasure.Caption(mLine, mTexts), mLine.Same <> TAtlasMeasurePlace.None)];
  end;
end;

/// <summary>Marke „B × H“ unter dem Bezug, mit gleicher Breite bzw. Höhe eines Nachbarn.</summary>
function SizeMark(const ASubject: TRect; const ASiblings: TArray<TAtlasMeasureItem>;
  const AScale: TAtlasDesignScale): TAtlasMeasureMark;
var
  mSize: TAtlasMeasureSize;
  mText: string;
begin
  mSize := TAtlasMeasure.Size(ASubject, ASiblings);
  mText := Format('%d × %d', [mSize.Width, mSize.Height]);
  if mSize.SameWidth <> '' then
  begin
    mText := mText + ' · ' + TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.MeasureSameWidth,
      [mSize.SameWidth]);
  end;
  if mSize.SameHeight <> '' then
  begin
    mText := mText + ' · ' + TAtlasDesignerViewStrings.Fmt(TAtlasDesignerViewTextId.MeasureSameHeight,
      [mSize.SameHeight]);
  end;
  Result := TAtlasMeasureMark.Badge(AScale.ToScreen(Point((ASubject.Left + ASubject.Right) div 2,
    (ASubject.Top + ASubject.Bottom) div 2)), mText, (mSize.SameWidth <> '') or (mSize.SameHeight <> ''));
end;

/// <summary>Steuerelement des Formulars unter der Maus (das Formular selbst, wenn keins).</summary>
function ControlUnderMouse(ARoot: TWinControl): TControl;
var
  mPoint: TPoint;
begin
  GetCursorPos(mPoint);
  mPoint := ARoot.ScreenToClient(mPoint);
  if not PtInRect(Rect(0, 0, ARoot.ClientWidth, ARoot.ClientHeight), mPoint) then
  begin
    Exit(nil);
  end;
  Result := ARoot.ControlAtPos(mPoint, True, True, True);
  // Teile einer Komponente (das Label von TLabeledEdit) gehören nicht dem Formular: zu ihr hinauf.
  while (Result <> nil) and (Result <> ARoot) and (Result.Owner <> ARoot) do
  begin
    Result := Result.Parent;
  end;
  if Result = nil then
  begin
    Result := ARoot;
  end;
end;

/// <summary>Liegt die Maus über dem Formular (oder einem seiner Fenster)?</summary>
function MouseOverRoot(ARoot: TWinControl): Boolean;
var
  mPoint: TPoint;
  mWindow: HWND;
begin
  GetCursorPos(mPoint);
  mWindow := WindowFromPoint(mPoint);
  Result := (mWindow = ARoot.Handle) or IsChild(ARoot.Handle, mWindow);
end;

/// <summary>Client von ARoot auf dem Bildschirm, beschnitten auf das umgebende Fenster des Designers.</summary>
function VisibleArea(ARoot: TWinControl; out AScreen, AVisible: TRect): Boolean;
var
  mOrigin: TPoint;
  mHost: HWND;
begin
  mOrigin := ARoot.ClientToScreen(Point(0, 0));
  AScreen := Rect(mOrigin.X, mOrigin.Y, mOrigin.X + ARoot.ClientWidth, mOrigin.Y + ARoot.ClientHeight);
  AVisible := AScreen;
  mHost := GetParent(ARoot.Handle);
  if (mHost <> 0) and GetWindowRect(mHost, AVisible) then
  begin
    AVisible.Intersect(AScreen);
  end
  else
  begin
    AVisible := AScreen;
  end;
  Result := not AVisible.IsEmpty;
end;

{ TAtlasIdeDesignerMeasure }

constructor TAtlasIdeDesignerMeasure.Create;
begin
  inherited Create;
  FActive := True;
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cTickMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
end;

destructor TAtlasIdeDesignerMeasure.Destroy;
begin
  FTimer.Free;
  FOverlay.Free;
  inherited Destroy;
end;

function TAtlasIdeDesignerMeasure.Button(const ASettings: TAtlasPluginSettings): TAtlasDesignerButton;
begin
  if not ASettings.DesignerMeasureDistances and not ASettings.DesignerMeasureAltKey then
  begin
    Exit(Default(TAtlasDesignerButton));
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.MeasureDistances,
    TAtlasDesignerViewStrings.Text(TAtlasDesignerViewTextId.MeasureHint));
  Result.Pressed := FActive;
end;

procedure TAtlasIdeDesignerMeasure.Toggle;
begin
  FActive := not FActive;
  FDragging := False;
  Hide;
end;

procedure TAtlasIdeDesignerMeasure.ApplyTheme;
begin
  if FOverlay <> nil then
  begin
    FOverlay.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeDesignerMeasure.Tick(Sender: TObject);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      Update;
    end);
end;

procedure TAtlasIdeDesignerMeasure.Hide;
begin
  if FOverlay <> nil then
  begin
    FOverlay.HideMarks;
  end;
end;

procedure TAtlasIdeDesignerMeasure.Show(ARoot: TWinControl; const AMarks: TArray<TAtlasMeasureMark>);
var
  mScreen, mVisible: TRect;
  mMarks: TArray<TAtlasMeasureMark>;
  mIndex: Integer;
  mShift: TPoint;
begin
  if (Length(AMarks) = 0) or not VisibleArea(ARoot, mScreen, mVisible) then
  begin
    Hide;
    Exit;
  end;
  // Marken liegen im Client des Formulars; das Fenster deckt nur den sichtbaren Teil ab.
  mShift := Point(mScreen.Left - mVisible.Left, mScreen.Top - mVisible.Top);
  mMarks := Copy(AMarks);
  for mIndex := 0 to High(mMarks) do
  begin
    mMarks[mIndex].FromPoint.Offset(mShift);
    mMarks[mIndex].ToPoint.Offset(mShift);
  end;
  if FOverlay = nil then
  begin
    FOverlay := TAtlasMeasureOverlay.CreateOverlay(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  FOverlay.ShowMarks(mVisible, mMarks);
end;

function TAtlasIdeDesignerMeasure.DragMarks(ARoot: TWinControl; const AControls: TArray<TControl>;
  ALeftDown: Boolean; out AMarks: TArray<TAtlasMeasureMark>): Boolean;
var
  mScale: TAtlasDesignScale;
  mNow: TRect;
  mSiblings: TArray<TAtlasMeasureItem>;
  mSubject: TRect;
begin
  AMarks := nil;
  mNow := UnionInRoot(AControls, ARoot);
  // Neue Auswahl beim Drücken: Bezug neu.
  if not FDragging or (FStartNames <> NamesOf(AControls)) then
  begin
    FDragging := ALeftDown and MouseOverRoot(ARoot);
    FStart := mNow;
    FStartNames := NamesOf(AControls);
    Exit(False);
  end;
  if mNow = FStart then
  begin
    Exit(False);
  end;
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  mSubject := mScale.ToDesign(mNow);
  mSiblings := SiblingsOf(AControls, ARoot, mScale);
  AMarks := MarksOf(TAtlasMeasure.Lines(mSubject, mSiblings, InnerOf(AControls[0].Parent, ARoot, mScale)),
    mScale);
  if (mNow.Width <> FStart.Width) or (mNow.Height <> FStart.Height) then
  begin
    AMarks := AMarks + [SizeMark(mSubject, mSiblings, mScale)];
  end;
  Result := True;
end;

function TAtlasIdeDesignerMeasure.AltMarks(ARoot: TWinControl;
  const AControls: TArray<TControl>): TArray<TAtlasMeasureMark>;
var
  mScale: TAtlasDesignScale;
  mTarget: TControl;
  mTargetRect: TRect;
  mIndex: Integer;
begin
  Result := nil;
  mTarget := ControlUnderMouse(ARoot);
  if mTarget = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AControls) do
  begin
    if AControls[mIndex] = mTarget then
    begin
      Exit;
    end;
  end;
  mScale := TAtlasDesignScale.ForRoot(ARoot);
  if mTarget = ARoot then
  begin
    mTargetRect := Rect(0, 0, ARoot.ClientWidth, ARoot.ClientHeight);
  end
  else
  begin
    mTargetRect := TAtlasDesignerAccess.BoundsInRoot(mTarget, ARoot);
  end;
  Result := MarksOf(TAtlasMeasure.Between(mScale.ToDesign(UnionInRoot(AControls, ARoot)),
    mScale.ToDesign(mTargetRect), mTarget.Name), mScale);
end;

procedure TAtlasIdeDesignerMeasure.Update;
var
  mSettings: TAtlasPluginSettings;
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControls: TArray<TControl>;
  mLeft: Boolean;
  mMarks: TArray<TAtlasMeasureMark>;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not FActive or not mSettings.EditorDesignerBar or not Application.Active or
    not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) or
    not TWinControl(mRoot).HandleAllocated or not IsWindowVisible(TWinControl(mRoot).Handle) then
  begin
    FDragging := False;
    Hide;
    Exit;
  end;
  mControls := SelectedControls(mEditor, mRoot);
  mLeft := GetAsyncKeyState(VK_LBUTTON) < 0;
  if (Length(mControls) > 0) and mSettings.DesignerMeasureDistances and (mLeft or FDragging) then
  begin
    if DragMarks(TWinControl(mRoot), mControls, mLeft, mMarks) then
    begin
      Show(TWinControl(mRoot), mMarks);
      FHoldUntil := GetTickCount64 + cHoldMs;
    end;
    // Losgelassen: Die letzten Linien bleiben bis FHoldUntil stehen.
    FDragging := FDragging and mLeft;
    Exit;
  end;
  if (Length(mControls) > 0) and mSettings.DesignerMeasureAltKey and (GetAsyncKeyState(VK_MENU) < 0) then
  begin
    Show(TWinControl(mRoot), AltMarks(TWinControl(mRoot), mControls));
    FHoldUntil := 0;
    Exit;
  end;
  if GetTickCount64 >= FHoldUntil then
  begin
    Hide;
  end;
end;

end.
