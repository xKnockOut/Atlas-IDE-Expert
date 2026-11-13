unit Atlas.UI.Editor.Hide;

// „Ausblenden“ direkt am Element (#628), Fensterteil (nur VCL):
// - TAtlasHideMenu baut das Menü zum Element: „Nur hier ausblenden“, „In
//   dieser Datei ausblenden“, „<Elemente> überall ausblenden“, Trennlinie,
//   „Einstellungen dazu …“. Ein Bereich steht nur da, wenn das Element ihn
//   anbietet (TAtlasHideTarget.Offers). Liegen an der Stelle mehrere Elemente
//   (etwa Befund und Inlay-Hint), bekommt jedes ein Untermenü mit seinem Namen.
//   Ob ein Bereich wirklich geht (Projektordner, .atlas an), prüft erst die
//   Ausführung und meldet den Grund; so bleibt kein Eintrag ohne Erklärung grau.
// - TAtlasHideNoticeWindow ist der kurze Hinweis danach: „Ausgeblendet ·
//   Rückgängig“ und darunter, was geschehen ist. Er nimmt dem Editor nie den
//   Fokus, steht unter dem Element und verschwindet nach VisibleMs von selbst,
//   solange die Maus nicht darüber steht.
// Die Namen der Elemente (Einzahl und Mehrzahl) stehen hier, damit Menü,
// Hinweis und Befehlspalette dieselben verwenden.

interface

uses
  Winapi.Windows,
  Winapi.Messages,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Graphics,
  Vcl.Controls,
  Vcl.Menus,
  Vcl.ExtCtrls,
  Atlas.Core.Editor.Elements,
  Atlas.Core.Editor.Hide,
  Atlas.UI.Popup.Window;

type
  /// <summary>Gewählter Eintrag: Bereich für ein Element oder „Einstellungen dazu …“.</summary>
  TAtlasHideChoice = record
    Target: TAtlasHideTarget;
    Scope: TAtlasHideScope;
    /// <summary>„Einstellungen dazu …“ statt eines Bereichs.</summary>
    Settings: Boolean;
  end;

  TAtlasHideMenu = class(TComponent)
  private
    FMenu: TPopupMenu;
    FChoices: TArray<TAtlasHideChoice>;
    FOnChoose: TProc<TAtlasHideChoice>;
    procedure ItemClick(Sender: TObject);
    function NewItem(AOwner: TMenuItem; const ACaption: string): TMenuItem;
    procedure AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TAtlasHideChoice);
    procedure AddTarget(AParent: TMenuItem; const ATarget: TAtlasHideTarget);
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Menü für ATargets neu aufbauen; gleiche Elemente nur einmal (das erste zählt).</summary>
    procedure Build(const ATargets: TArray<TAtlasHideTarget>);
    /// <summary>Wie ein Klick auf den Eintrag mit der Nummer AIndex (Reihenfolge von Choices).</summary>
    procedure Choose(AIndex: Integer);
    /// <summary>Zeigt das Menü an der Bildschirmstelle.</summary>
    procedure Popup(const APoint: TPoint);
    /// <summary>Name des Elements, Einzahl oder Mehrzahl, wie im Menü.</summary>
    class function ElementName(AElement: TAtlasDrawnElement; APlural: Boolean): string; static;
    /// <summary>Beschriftung des Eintrags für AScope (Überall mit dem Namen in der Mehrzahl).</summary>
    class function ScopeCaption(AElement: TAtlasDrawnElement; AScope: TAtlasHideScope): string; static;
    property Menu: TPopupMenu read FMenu;
    /// <summary>Alle wählbaren Einträge in der Reihenfolge des Menüs.</summary>
    property Choices: TArray<TAtlasHideChoice> read FChoices;
    property OnChoose: TProc<TAtlasHideChoice> read FOnChoose write FOnChoose;
  end;

  TAtlasHideNoticeWindow = class(TAtlasPopupWindow)
  public const
    cVisibleMs = 6000;
    /// <summary>Abstand unter dem Element, logische Pixel.</summary>
    cGap = 4;
  private
    FTitle: string;
    FDetail: string;
    FUndoRect: TRect;
    FUndoHot: Boolean;
    FCanUndo: Boolean;
    FTimer: TTimer;
    FOnUndo: TNotifyEvent;
    procedure TimerTick(Sender: TObject);
    function Layout(ADraw: Boolean): TSize;
    /// <summary>„  ·  Rückgängig“ ab AX in der Zeile AY (nur mit FCanUndo); merkt FUndoRect.</summary>
    procedure LayoutUndo(ADraw: Boolean; var AX: Integer; AY, ATextHeight: Integer);
    procedure CMMouseLeave(var Message: TMessage); message CM_MOUSELEAVE;
  protected
    procedure Paint; override;
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer); override;
    procedure MouseMove(Shift: TShiftState; X, Y: Integer); override;
  public
    constructor Create(AOwner: TComponent); override;
    /// <summary>Zeigt den Hinweis unter APoint (Bildschirm): ATitle fett (leer: nur ADetail), dahinter
    /// „Rückgängig“, sofern ACanUndo, darunter ADetail.</summary>
    procedure ShowNotice(const ATitle, ADetail: string; ACanUndo: Boolean; const APoint: TPoint);
    procedure Dismiss;
    /// <summary>Wie ein Klick auf „Rückgängig“.</summary>
    procedure ClickUndo;
    function UndoRect: TRect;
    /// <summary>Lage für AWidth × AHeight unter APoint, ganz in AWorkArea.</summary>
    class function PlaceBelow(const APoint: TPoint; AWidth, AHeight, AGap: Integer;
      const AWorkArea: TRect): TRect; static;
    property Title: string read FTitle;
    property Detail: string read FDetail;
    property CanUndo: Boolean read FCanUndo;
    property Timer: TTimer read FTimer;
    property OnUndo: TNotifyEvent read FOnUndo write FOnUndo;
  end;

implementation

uses
  System.Math,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Strings,
  Atlas.UI.Editor.Strings,
  Atlas.UI.Popup.Accessibility;

const
  cPad = 10;
  cRowGap = 4;

{ TAtlasHideMenu }

constructor TAtlasHideMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenu := TPopupMenu.Create(Self);
  FMenu.AutoHotkeys := maManual;
end;

class function TAtlasHideMenu.ElementName(AElement: TAtlasDrawnElement; APlural: Boolean): string;
const
  cSingular: array[TAtlasDrawnElement] of TAtlasTextId = (TAtlasTextId.ElementCodeLensMetrics,
    TAtlasTextId.ElementCodeLensTests, TAtlasTextId.ElementCodeLensTestUnit, TAtlasTextId.ElementBlockEndLabels,
    TAtlasTextId.ElementInlayHints, TAtlasTextId.ElementProblems, TAtlasTextId.ElementNotes,
    TAtlasTextId.ElementBookmarks, TAtlasTextId.ElementPairColors, TAtlasTextId.ElementPairGuides,
    TAtlasTextId.ElementPairOwners, TAtlasTextId.ElementInactiveDim, TAtlasTextId.ElementCompletionPreview,
    TAtlasTextId.ElementUnusedUses, TAtlasTextId.ElementRecursion, TAtlasTextId.ElementInlineDiagnostics,
    TAtlasTextId.ElementInlayTypeHints, TAtlasTextId.ElementGitGutter, TAtlasTextId.ElementGitBlame,
    TAtlasTextId.ElementPatternPreview, TAtlasTextId.ElementGutterColumn, TAtlasTextId.ElementSelectionMatches,
    TAtlasTextId.ElementInlayDefineHints, TAtlasTextId.ElementInlayCharHints, TAtlasTextId.ElementQuickBookmarks,
    TAtlasTextId.ElementInlayMethodHints,
    TAtlasTextId.ElementExitPoints, TAtlasTextId.ElementReassigned, TAtlasTextId.ElementLearnedSuggestions,
    TAtlasTextId.ElementTestCoverage);
  cPlural: array[TAtlasDrawnElement] of TAtlasTextId = (TAtlasTextId.ElementCodeLensMetricsPlural,
    TAtlasTextId.ElementCodeLensTestsPlural, TAtlasTextId.ElementCodeLensTestUnitPlural,
    TAtlasTextId.ElementBlockEndLabelsPlural, TAtlasTextId.ElementInlayHintsPlural,
    TAtlasTextId.ElementProblemsPlural, TAtlasTextId.ElementNotesPlural, TAtlasTextId.ElementBookmarksPlural,
    TAtlasTextId.ElementPairColorsPlural, TAtlasTextId.ElementPairGuidesPlural,
    TAtlasTextId.ElementPairOwnersPlural, TAtlasTextId.ElementInactiveDimPlural,
    TAtlasTextId.ElementCompletionPreviewPlural, TAtlasTextId.ElementUnusedUsesPlural,
    TAtlasTextId.ElementRecursionPlural, TAtlasTextId.ElementInlineDiagnosticsPlural,
    TAtlasTextId.ElementInlayTypeHintsPlural, TAtlasTextId.ElementGitGutterPlural, TAtlasTextId.ElementGitBlamePlural,
    TAtlasTextId.ElementPatternPreviewPlural, TAtlasTextId.ElementGutterColumnPlural,
    TAtlasTextId.ElementSelectionMatchesPlural, TAtlasTextId.ElementInlayDefineHintsPlural,
    TAtlasTextId.ElementInlayCharHintsPlural, TAtlasTextId.ElementQuickBookmarksPlural,
    TAtlasTextId.ElementInlayMethodHintsPlural,
    TAtlasTextId.ElementExitPointsPlural, TAtlasTextId.ElementReassignedPlural,
    TAtlasTextId.ElementLearnedSuggestionsPlural, TAtlasTextId.ElementTestCoveragePlural);
begin
  if APlural then
  begin
    Result := TAtlasStrings.Text(cPlural[AElement]);
  end
  else
  begin
    Result := TAtlasStrings.Text(cSingular[AElement]);
  end;
end;

class function TAtlasHideMenu.ScopeCaption(AElement: TAtlasDrawnElement; AScope: TAtlasHideScope): string;
begin
  case AScope of
    TAtlasHideScope.Here:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.HideHere);
    TAtlasHideScope.InFile:
      Result := TAtlasEditorStrings.Text(TAtlasEditorTextId.HideInFile);
  else
    Result := TAtlasEditorStrings.Fmt(TAtlasEditorTextId.HideEverywhere, [ElementName(AElement, True)]);
  end;
end;

function TAtlasHideMenu.NewItem(AOwner: TMenuItem; const ACaption: string): TMenuItem;
begin
  Result := TMenuItem.Create(FMenu);
  // Kein & als Zugriffstaste aus Namen wie „Testunit-Lens“.
  Result.Caption := StringReplace(ACaption, '&', '&&', [rfReplaceAll]);
  AOwner.Add(Result);
end;

procedure TAtlasHideMenu.AddChoice(AParent: TMenuItem; const ACaption: string; const AChoice: TAtlasHideChoice);
var
  mItem: TMenuItem;
begin
  mItem := NewItem(AParent, ACaption);
  mItem.Tag := Length(FChoices);
  mItem.OnClick := ItemClick;
  FChoices := FChoices + [AChoice];
end;

procedure TAtlasHideMenu.AddTarget(AParent: TMenuItem; const ATarget: TAtlasHideTarget);
var
  mScope: TAtlasHideScope;
  mChoice: TAtlasHideChoice;
begin
  for mScope := Low(TAtlasHideScope) to High(TAtlasHideScope) do
  begin
    if ATarget.Offers(mScope) then
    begin
      mChoice := Default(TAtlasHideChoice);
      mChoice.Target := ATarget;
      mChoice.Scope := mScope;
      AddChoice(AParent, ScopeCaption(ATarget.Element, mScope), mChoice);
    end;
  end;
  NewItem(AParent, '-');
  mChoice := Default(TAtlasHideChoice);
  mChoice.Target := ATarget;
  mChoice.Scope := TAtlasHideScope.Everywhere;
  mChoice.Settings := True;
  AddChoice(AParent, TAtlasEditorStrings.Text(TAtlasEditorTextId.HideSettings), mChoice);
end;

procedure TAtlasHideMenu.Build(const ATargets: TArray<TAtlasHideTarget>);
var
  mTargets: TArray<TAtlasHideTarget>;
  mTarget, mSeen: TAtlasHideTarget;
  mKnown: Boolean;
  mSub: TMenuItem;
begin
  FMenu.Items.Clear;
  FChoices := nil;
  mTargets := nil;
  for mTarget in ATargets do
  begin
    mKnown := False;
    for mSeen in mTargets do
    begin
      if mSeen.Element = mTarget.Element then
      begin
        mKnown := True;
      end;
    end;
    if not mKnown then
    begin
      mTargets := mTargets + [mTarget];
    end;
  end;
  if Length(mTargets) = 1 then
  begin
    AddTarget(FMenu.Items, mTargets[0]);
  end
  else
  begin
    for mTarget in mTargets do
    begin
      mSub := NewItem(FMenu.Items, ElementName(mTarget.Element, False));
      AddTarget(mSub, mTarget);
    end;
  end;
end;

procedure TAtlasHideMenu.Choose(AIndex: Integer);
var
  mChoice: TAtlasHideChoice;
begin
  if (AIndex < 0) or (AIndex > High(FChoices)) then
  begin
    Exit;
  end;
  mChoice := FChoices[AIndex];
  if Assigned(FOnChoose) then
  begin
    FOnChoose(mChoice);
  end;
end;

procedure TAtlasHideMenu.ItemClick(Sender: TObject);
begin
  try
    Choose(TMenuItem(Sender).Tag);
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

procedure TAtlasHideMenu.Popup(const APoint: TPoint);
begin
  if FMenu.Items.Count > 0 then
  begin
    FMenu.Popup(APoint.X, APoint.Y);
  end;
end;

{ TAtlasHideNoticeWindow }

constructor TAtlasHideNoticeWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Hide;
  SetAccessible(cUiaToolTipControlType, TAtlasEditorStrings.Text(TAtlasEditorTextId.HideNotice));
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := cVisibleMs;
  FTimer.OnTimer := TimerTick;
end;

class function TAtlasHideNoticeWindow.PlaceBelow(const APoint: TPoint; AWidth, AHeight, AGap: Integer;
  const AWorkArea: TRect): TRect;
var
  mLeft, mTop: Integer;
begin
  mLeft := APoint.X;
  mTop := APoint.Y + AGap;
  // Unten kein Platz: über die Stelle.
  if mTop + AHeight > AWorkArea.Bottom then
  begin
    mTop := APoint.Y - AGap - AHeight;
  end;
  if mLeft + AWidth > AWorkArea.Right then
  begin
    mLeft := AWorkArea.Right - AWidth;
  end;
  mLeft := Max(mLeft, AWorkArea.Left);
  mTop := Max(mTop, AWorkArea.Top);
  Result := Rect(mLeft, mTop, mLeft + AWidth, mTop + AHeight);
end;

/// <summary>Schreibt AText bei AX, AY in AColor (nur wenn ADraw) und rückt AX um seine Breite weiter.</summary>
procedure PutText(ACanvas: TCanvas; ADraw: Boolean; var AX: Integer; AY: Integer; const AText: string;
  AColor: TColor);
begin
  if ADraw then
  begin
    ACanvas.Font.Color := AColor;
    ACanvas.TextOut(AX, AY, AText);
  end;
  Inc(AX, ACanvas.TextWidth(AText));
end;

function TAtlasHideNoticeWindow.Layout(ADraw: Boolean): TSize;
var
  mX, mY, mTextHeight, mWidth: Integer;
  mDetail: string;
begin
  Canvas.Font := UIFont;
  mTextHeight := Canvas.TextHeight('Wg');
  mX := Scale(cPad);
  mY := Scale(cPad);
  if ADraw then
  begin
    Canvas.Brush.Style := bsClear;
  end;
  // Ohne Überschrift steht der Text in der ersten Zeile, in Textfarbe.
  mDetail := FDetail;
  if FTitle <> '' then
  begin
    Canvas.Font.Style := [fsBold];
    PutText(Canvas, ADraw, mX, mY, FTitle, ToColor(Colors.Text));
    Canvas.Font.Style := [];
  end
  else
  begin
    PutText(Canvas, ADraw, mX, mY, mDetail, ToColor(Colors.Text));
    mDetail := '';
  end;
  LayoutUndo(ADraw, mX, mY, mTextHeight);
  mWidth := mX;
  if mDetail <> '' then
  begin
    mY := mY + mTextHeight + Scale(cRowGap);
    mX := Scale(cPad);
    PutText(Canvas, ADraw, mX, mY, mDetail, ToColor(Colors.Muted));
    mWidth := Max(mWidth, mX);
  end;
  if ADraw then
  begin
    Canvas.Brush.Style := bsSolid;
  end;
  Result.cx := mWidth + Scale(cPad);
  Result.cy := mY + mTextHeight + Scale(cPad);
end;

procedure TAtlasHideNoticeWindow.LayoutUndo(ADraw: Boolean; var AX: Integer; AY, ATextHeight: Integer);
var
  mUndo: string;
begin
  FUndoRect := TRect.Empty;
  if not FCanUndo then
  begin
    Exit;
  end;
  mUndo := TAtlasEditorStrings.Text(TAtlasEditorTextId.HideUndo);
  PutText(Canvas, ADraw, AX, AY, '  ·  ', ToColor(Colors.Muted));
  FUndoRect := Rect(AX, AY, AX + Canvas.TextWidth(mUndo), AY + ATextHeight);
  if ADraw and FUndoHot then
  begin
    Canvas.Font.Style := [fsUnderline];
  end;
  PutText(Canvas, ADraw, AX, AY, mUndo, ToColor(Colors.Accent));
  Canvas.Font.Style := [];
end;

procedure TAtlasHideNoticeWindow.ShowNotice(const ATitle, ADetail: string; ACanUndo: Boolean;
  const APoint: TPoint);
var
  mSize: TSize;
begin
  FTitle := ATitle;
  FDetail := ADetail;
  FCanUndo := ACanUndo;
  FUndoHot := False;
  HandleNeeded;
  mSize := Layout(False);
  ShowAt(PlaceBelow(APoint, mSize.cx, mSize.cy, Scale(cGap), WorkAreaAt(APoint)));
  Announce(Trim(ATitle + ' ' + ADetail));
  FTimer.Enabled := False;
  FTimer.Interval := cVisibleMs;
  FTimer.Enabled := True;
end;

procedure TAtlasHideNoticeWindow.Dismiss;
begin
  FTimer.Enabled := False;
  FUndoHot := False;
  HidePopup;
end;

procedure TAtlasHideNoticeWindow.ClickUndo;
begin
  if not FCanUndo then
  begin
    Exit;
  end;
  Dismiss;
  if Assigned(FOnUndo) then
  begin
    FOnUndo(Self);
  end;
end;

function TAtlasHideNoticeWindow.UndoRect: TRect;
begin
  Result := FUndoRect;
end;

procedure TAtlasHideNoticeWindow.TimerTick(Sender: TObject);
begin
  try
    // Wer auf den Hinweis zeigt, will vielleicht zurücknehmen: noch einmal so lange.
    if IsShown and PtInRect(BoundsRect, Mouse.CursorPos) then
    begin
      Exit;
    end;
    Dismiss;
  except
    on E: Exception do
      TAtlasGuard.Report(TAtlasFeature.Hide, E);
  end;
end;

procedure TAtlasHideNoticeWindow.Paint;
begin
  Canvas.Brush.Style := bsSolid;
  Canvas.Brush.Color := ToColor(Colors.Surface);
  Canvas.FillRect(ClientRect);
  Layout(True);
  PaintBorder;
end;

procedure TAtlasHideNoticeWindow.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  inherited;
  if (Button = mbLeft) and not FUndoRect.IsEmpty and PtInRect(FUndoRect, Point(X, Y)) then
  begin
    ClickUndo;
  end;
end;

procedure TAtlasHideNoticeWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  mHot: Boolean;
begin
  inherited;
  mHot := not FUndoRect.IsEmpty and PtInRect(FUndoRect, Point(X, Y));
  if mHot then
  begin
    Cursor := crHandPoint;
  end
  else
  begin
    Cursor := crDefault;
  end;
  if mHot <> FUndoHot then
  begin
    FUndoHot := mHot;
    Invalidate;
  end;
end;

procedure TAtlasHideNoticeWindow.CMMouseLeave(var Message: TMessage);
begin
  inherited;
  if FUndoHot then
  begin
    FUndoHot := False;
    Invalidate;
  end;
end;

end.
