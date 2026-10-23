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
    VisibleMs = 6000;
    /// <summary>Abstand unter dem Element, logische Pixel.</summary>
    Gap = 4;
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
  Atlas.UI.Popup.Accessibility;

const
  Pad = 10;
  RowGap = 4;

{ TAtlasHideMenu }

constructor TAtlasHideMenu.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FMenu := TPopupMenu.Create(Self);
  FMenu.AutoHotkeys := maManual;
end;

class function TAtlasHideMenu.ElementName(AElement: TAtlasDrawnElement; APlural: Boolean): string;
const
  Singular: array[TAtlasDrawnElement] of TAtlasTextId = (TAtlasTextId.ElementCodeLensMetrics,
    TAtlasTextId.ElementCodeLensTests, TAtlasTextId.ElementCodeLensTestUnit, TAtlasTextId.ElementBlockEndLabels,
    TAtlasTextId.ElementInlayHints, TAtlasTextId.ElementProblems, TAtlasTextId.ElementNotes,
    TAtlasTextId.ElementBookmarks, TAtlasTextId.ElementPairColors, TAtlasTextId.ElementPairGuides,
    TAtlasTextId.ElementPairOwners, TAtlasTextId.ElementInactiveDim, TAtlasTextId.ElementCompletionPreview,
    TAtlasTextId.ElementUnusedUses, TAtlasTextId.ElementRecursion, TAtlasTextId.ElementInlineDiagnostics,
    TAtlasTextId.ElementInlayTypeHints, TAtlasTextId.ElementGitGutter, TAtlasTextId.ElementGitBlame,
    TAtlasTextId.ElementPatternPreview, TAtlasTextId.ElementGutterColumn, TAtlasTextId.ElementSelectionMatches,
    TAtlasTextId.ElementInlayDefineHints, TAtlasTextId.ElementInlayCharHints, TAtlasTextId.ElementQuickBookmarks,
    TAtlasTextId.ElementExitPoints, TAtlasTextId.ElementReassigned);
  Plural: array[TAtlasDrawnElement] of TAtlasTextId = (TAtlasTextId.ElementCodeLensMetricsPlural,
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
    TAtlasTextId.ElementExitPointsPlural, TAtlasTextId.ElementReassignedPlural);
begin
  if APlural then
    Result := TAtlasStrings.Text(Plural[AElement])
  else
    Result := TAtlasStrings.Text(Singular[AElement]);
end;

class function TAtlasHideMenu.ScopeCaption(AElement: TAtlasDrawnElement; AScope: TAtlasHideScope): string;
begin
  case AScope of
    TAtlasHideScope.Here:
      Result := TAtlasStrings.Text(TAtlasTextId.HideHere);
    TAtlasHideScope.InFile:
      Result := TAtlasStrings.Text(TAtlasTextId.HideInFile);
  else
    Result := TAtlasStrings.Fmt(TAtlasTextId.HideEverywhere, [ElementName(AElement, True)]);
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
  Item: TMenuItem;
begin
  Item := NewItem(AParent, ACaption);
  Item.Tag := Length(FChoices);
  Item.OnClick := ItemClick;
  FChoices := FChoices + [AChoice];
end;

procedure TAtlasHideMenu.AddTarget(AParent: TMenuItem; const ATarget: TAtlasHideTarget);
var
  Scope: TAtlasHideScope;
  Choice: TAtlasHideChoice;
begin
  for Scope := Low(TAtlasHideScope) to High(TAtlasHideScope) do
    if ATarget.Offers(Scope) then
    begin
      Choice := Default(TAtlasHideChoice);
      Choice.Target := ATarget;
      Choice.Scope := Scope;
      AddChoice(AParent, ScopeCaption(ATarget.Element, Scope), Choice);
    end;
  NewItem(AParent, '-');
  Choice := Default(TAtlasHideChoice);
  Choice.Target := ATarget;
  Choice.Scope := TAtlasHideScope.Everywhere;
  Choice.Settings := True;
  AddChoice(AParent, TAtlasStrings.Text(TAtlasTextId.HideSettings), Choice);
end;

procedure TAtlasHideMenu.Build(const ATargets: TArray<TAtlasHideTarget>);
var
  Targets: TArray<TAtlasHideTarget>;
  Target, Seen: TAtlasHideTarget;
  Known: Boolean;
  Sub: TMenuItem;
begin
  FMenu.Items.Clear;
  FChoices := nil;
  Targets := nil;
  for Target in ATargets do
  begin
    Known := False;
    for Seen in Targets do
      if Seen.Element = Target.Element then
        Known := True;
    if not Known then
      Targets := Targets + [Target];
  end;
  if Length(Targets) = 1 then
    AddTarget(FMenu.Items, Targets[0])
  else
    for Target in Targets do
    begin
      Sub := NewItem(FMenu.Items, ElementName(Target.Element, False));
      AddTarget(Sub, Target);
    end;
end;

procedure TAtlasHideMenu.Choose(AIndex: Integer);
var
  Choice: TAtlasHideChoice;
begin
  if (AIndex < 0) or (AIndex > High(FChoices)) then
    Exit;
  Choice := FChoices[AIndex];
  if Assigned(FOnChoose) then
    FOnChoose(Choice);
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
    FMenu.Popup(APoint.X, APoint.Y);
end;

{ TAtlasHideNoticeWindow }

constructor TAtlasHideNoticeWindow.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  GuardFeature := TAtlasFeature.Hide;
  SetAccessible(UiaToolTipControlType, TAtlasStrings.Text(TAtlasTextId.HideNotice));
  FTimer := TTimer.Create(Self);
  FTimer.Enabled := False;
  FTimer.Interval := VisibleMs;
  FTimer.OnTimer := TimerTick;
end;

class function TAtlasHideNoticeWindow.PlaceBelow(const APoint: TPoint; AWidth, AHeight, AGap: Integer;
  const AWorkArea: TRect): TRect;
var
  Left, Top: Integer;
begin
  Left := APoint.X;
  Top := APoint.Y + AGap;
  // Unten kein Platz: über die Stelle.
  if Top + AHeight > AWorkArea.Bottom then
    Top := APoint.Y - AGap - AHeight;
  if Left + AWidth > AWorkArea.Right then
    Left := AWorkArea.Right - AWidth;
  Left := Max(Left, AWorkArea.Left);
  Top := Max(Top, AWorkArea.Top);
  Result := Rect(Left, Top, Left + AWidth, Top + AHeight);
end;

function TAtlasHideNoticeWindow.Layout(ADraw: Boolean): TSize;
var
  X, Y, TextHeight, Width: Integer;
  Undo, Separator, Detail: string;
begin
  Canvas.Font := UIFont;
  TextHeight := Canvas.TextHeight('Wg');
  Undo := TAtlasStrings.Text(TAtlasTextId.HideUndo);
  Separator := '  ·  ';
  X := Scale(Pad);
  Y := Scale(Pad);
  if ADraw then
    Canvas.Brush.Style := bsClear;
  // Ohne Überschrift steht der Text in der ersten Zeile, in Textfarbe.
  Detail := FDetail;
  if FTitle <> '' then
  begin
    Canvas.Font.Style := [fsBold];
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Text);
      Canvas.TextOut(X, Y, FTitle);
    end;
    Inc(X, Canvas.TextWidth(FTitle));
    Canvas.Font.Style := [];
  end
  else
  begin
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Text);
      Canvas.TextOut(X, Y, Detail);
    end;
    Inc(X, Canvas.TextWidth(Detail));
    Detail := '';
  end;
  FUndoRect := TRect.Empty;
  if FCanUndo then
  begin
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(X, Y, Separator);
    end;
    Inc(X, Canvas.TextWidth(Separator));
    FUndoRect := Rect(X, Y, X + Canvas.TextWidth(Undo), Y + TextHeight);
    if ADraw then
    begin
      if FUndoHot then
        Canvas.Font.Style := [fsUnderline];
      Canvas.Font.Color := ToColor(Colors.Accent);
      Canvas.TextOut(X, Y, Undo);
      Canvas.Font.Style := [];
    end;
    Inc(X, Canvas.TextWidth(Undo));
  end;
  Width := X;
  if Detail <> '' then
  begin
    Y := Y + TextHeight + Scale(RowGap);
    if ADraw then
    begin
      Canvas.Font.Color := ToColor(Colors.Muted);
      Canvas.TextOut(Scale(Pad), Y, Detail);
    end;
    Width := Max(Width, Scale(Pad) + Canvas.TextWidth(Detail));
  end;
  if ADraw then
    Canvas.Brush.Style := bsSolid;
  Result.cx := Width + Scale(Pad);
  Result.cy := Y + TextHeight + Scale(Pad);
end;

procedure TAtlasHideNoticeWindow.ShowNotice(const ATitle, ADetail: string; ACanUndo: Boolean;
  const APoint: TPoint);
var
  Size: TSize;
begin
  FTitle := ATitle;
  FDetail := ADetail;
  FCanUndo := ACanUndo;
  FUndoHot := False;
  HandleNeeded;
  Size := Layout(False);
  ShowAt(PlaceBelow(APoint, Size.cx, Size.cy, Scale(Gap), WorkAreaAt(APoint)));
  Announce(Trim(ATitle + ' ' + ADetail));
  FTimer.Enabled := False;
  FTimer.Interval := VisibleMs;
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
    Exit;
  Dismiss;
  if Assigned(FOnUndo) then
    FOnUndo(Self);
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
      Exit;
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
    ClickUndo;
end;

procedure TAtlasHideNoticeWindow.MouseMove(Shift: TShiftState; X, Y: Integer);
var
  Hot: Boolean;
begin
  inherited;
  Hot := not FUndoRect.IsEmpty and PtInRect(FUndoRect, Point(X, Y));
  if Hot then
    Cursor := crHandPoint
  else
    Cursor := crDefault;
  if Hot <> FUndoHot then
  begin
    FUndoHot := Hot;
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
