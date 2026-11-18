unit Atlas.IDE.Designer.GapHandles;

// Abstandsgriffe im Designer (#734, designer.gapHandles) in der IDE: Bilden
// mindestens zwei markierte Steuerelemente im selben Elternelement eine Reihe
// oder Spalte (TAtlasGaps.Detect), zeigt ein durchsichtiges Fenster
// (TAtlasDesignerHandles) zwischen je zwei Nachbarn eine Pille mit dem
// Abstand; abweichende Abstände gedämpft.
// - Ziehen einer Pille setzt alle Abstände auf denselben Wert, die Controls
//   rücken sofort nach; Einrasten an designer.gapHandles.snapValues, mit Alt
//   ohne. Pfeiltasten bei gehaltener Pille ändern um 1 px.
// - Fester Punkt: designer.gapHandles.anchor, mit Umschalt die erste, mit
//   Strg die letzte Komponente.
// - Doppelklick auf eine Pille (oder „Abstände setzen …“ im Menü) fragt den
//   Wert ab.
// - Ragt danach ein Control aus dem Elternelement, ist es rot umrandet und
//   die Änderung gilt erst nach Rückfrage.
// - Jeder Zug bzw. jede Eingabe ist ein Schritt für „Abstände rückgängig“
//   (TAtlasIdeHandleTool).
// - Die Gruppe ist über Zug und Dialoge gemerkt (TAtlasDesignerKept): Nach
//   der Eingabe des Werts wird sie neu ermittelt und muss dieselbe sein, vor
//   jedem Schreiben und nach der Rückfrage muss sie noch leben; sonst bricht
//   der Schritt ab (Lost). Solange ein eigener Dialog offen ist, lässt Tick
//   die Gruppe in Ruhe.
// Knopf der Designer-Leiste: Klick auf das Symbol blendet die Griffe ein und
// aus, der Pfeil öffnet das Menü. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.Core.Designer.Gaps,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.UI.Designer.Handles,
  Atlas.IDE.Designer.HandleTool,
  Atlas.IDE.Designer.KeptForm,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeGapHandles = class;

  /// <summary>Pfeiltasten, solange eine Pille gehalten wird.</summary>
  TAtlasGapKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeGapHandles;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  TAtlasIdeGapHandles = class(TAtlasIdeHandleTool)
  public const
    cId = 'gapHandles';
  private
    FKeys: TAtlasGapKeys;
    FParent: TWinControl;
    FControls: TArray<TControl>;
    FKept: TAtlasDesignerKept;
    FAsking: Boolean;
    FStart: TArray<TRect>;
    FLayout: TAtlasGapLayout;
    FStartGap: Integer;
    FDelta: Integer;
    FKeyOffset: Integer;
    FShift: TShiftState;
    function FindGroup: Boolean;
    function AnchorFor(AShift: TShiftState): TAtlasGapAnchor;
    function GapNow: Integer;
    procedure ShowGroup(const ARects: TArray<TRect>; ABad: Boolean);
    function Pills(const ARects: TArray<TRect>; const AOrigin: TPoint): TArray<TAtlasHandle>;
    procedure Place(AGap: Integer; AAnchor: TAtlasGapAnchor);
    procedure FinishStep;
    procedure Ask(AIndex: Integer; AShift: TShiftState);
    function Regroup(const ABefore: TAtlasDesignerKept): Boolean;
    function AskValue(var AText: string): Boolean;
    function ConfirmOutside: Boolean;
  protected
    procedure Down(AIndex: Integer; AShift: TShiftState); override;
    procedure Drag(const ADelta: TPoint; AShift: TShiftState); override;
    procedure Up; override;
    procedure DoubleClick(AIndex: Integer; AShift: TShiftState); override;
    function Commands: TArray<string>; override;
    function CommandEnabled(AIndex: Integer): Boolean; override;
    procedure Command(AIndex: Integer); override;
    function ShowCaption: string; override;
    function UndoCaption: string; override;
    function UndoneText: string; override;
  public
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    /// <summary>Knopf der Designer-Leiste: gedrückt, solange die Griffe gezeigt werden.</summary>
    function Button: TAtlasDesignerButton;
    procedure Tick; override;
    procedure Hide; override;
    /// <summary>Pfeiltaste bei gehaltener Pille: Abstand um ADelta ändern.</summary>
    procedure Nudge(ADelta: Integer);
    property Layout: TAtlasGapLayout read FLayout;
  end;

implementation

uses
  Winapi.Windows,
  System.Math,
  System.UITypes,
  Vcl.Forms,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Diagnostics.Guard,
  Atlas.UI.Designer.ToolStrings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 40;
  cPillWidth = 28;
  cPillHeight = 16;

{ TAtlasGapKeys }

function TAtlasGapKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := FOwner.Dragging;
  if not Result then
  begin
    Exit;
  end;
  if FOwner.Layout.Axis = TAtlasGapAxis.Row then
  begin
    Result := (AKey = VK_LEFT) or (AKey = VK_RIGHT);
  end
  else
  begin
    Result := (AKey = VK_UP) or (AKey = VK_DOWN);
  end;
end;

procedure TAtlasGapKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeGapHandles;
  mDelta: Integer;
begin
  mOwner := FOwner;
  mDelta := 1;
  if (AKey = VK_LEFT) or (AKey = VK_UP) then
  begin
    mDelta := -1;
  end;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      mOwner.Nudge(mDelta);
    end);
end;

{ TAtlasIdeGapHandles }

constructor TAtlasIdeGapHandles.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(cId, AOnMessage);
  FKeys := TAtlasGapKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdeGapHandles.Destroy;
begin
  TAtlasKeyHook.Remove(FKeys);
  FKeys.Free;
  inherited Destroy;
end;

procedure TAtlasIdeGapHandles.Down(AIndex: Integer; AShift: TShiftState);
begin
  if not FindGroup or (AIndex < 0) or (AIndex >= Length(FLayout.Gaps)) then
  begin
    Overlay.CancelDrag;
    Exit;
  end;
  BeginStep;
  FStartGap := FLayout.Gaps[AIndex];
  FDelta := 0;
  FKeyOffset := 0;
  FShift := AShift;
  TAtlasKeyHook.Add(FKeys);
end;

procedure TAtlasIdeGapHandles.Drag(const ADelta: TPoint; AShift: TShiftState);
begin
  if not InStep then
  begin
    Exit;
  end;
  FDelta := ADelta.X;
  if FLayout.Axis = TAtlasGapAxis.Column then
  begin
    FDelta := ADelta.Y;
  end;
  FShift := AShift;
  if not FKept.Holds then
  begin
    Lost;
    Exit;
  end;
  Place(GapNow, AnchorFor(FShift));
end;

procedure TAtlasIdeGapHandles.Up;
begin
  TAtlasKeyHook.Remove(FKeys);
  FinishStep;
end;

procedure TAtlasIdeGapHandles.DoubleClick(AIndex: Integer; AShift: TShiftState);
begin
  Ask(AIndex, AShift);
end;

function TAtlasIdeGapHandles.Commands: TArray<string>;
begin
  Result := [TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapSetCmd)];
end;

function TAtlasIdeGapHandles.CommandEnabled(AIndex: Integer): Boolean;
begin
  Result := FindGroup;
end;

procedure TAtlasIdeGapHandles.Command(AIndex: Integer);
begin
  Ask(0, []);
end;

function TAtlasIdeGapHandles.ShowCaption: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapShow);
end;

function TAtlasIdeGapHandles.UndoCaption: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapUndo);
end;

function TAtlasIdeGapHandles.UndoneText: string;
begin
  Result := TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapUndone);
end;

procedure TAtlasIdeGapHandles.Tick;
begin
  if Dragging or FAsking then
  begin
    Exit;
  end;
  if not TAtlasIdeSettings.Current.DesignerGapHandles or not Active or not FindGroup then
  begin
    Hide;
    Exit;
  end;
  ShowGroup(FStart, False);
end;

procedure TAtlasIdeGapHandles.Hide;
begin
  TAtlasKeyHook.Remove(FKeys);
  inherited Hide;
end;

/// <summary>Markierte Steuerelemente im selben Elternelement als Reihe oder Spalte (Felder FParent, FControls,
/// FStart, FLayout, FKept).</summary>
function TAtlasIdeGapHandles.FindGroup: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  FParent := nil;
  FControls := nil;
  FStart := nil;
  FLayout := Default(TAtlasGapLayout);
  FKept := Default(TAtlasDesignerKept);
  if not Application.Active or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit(False);
  end;
  for mComponent in TAtlasDesignerAccess.Selection(mEditor, mRoot) do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) or
      ((FParent <> nil) and (TControl(mComponent).Parent <> FParent)) then
    begin
      Exit(False);
    end;
    FParent := TControl(mComponent).Parent;
    FControls := FControls + [TControl(mComponent)];
    FStart := FStart + [TControl(mComponent).BoundsRect];
  end;
  FLayout := TAtlasGaps.Detect(FStart);
  Result := FLayout.Axis <> TAtlasGapAxis.None;
  if Result then
  begin
    FKept := TAtlasDesignerKept.Take(mEditor, mRoot);
    FKept.Add(FParent);
    FKept.Add(FControls);
  end;
end;

function TAtlasIdeGapHandles.AnchorFor(AShift: TShiftState): TAtlasGapAnchor;
begin
  if ssShift in AShift then
  begin
    Result := TAtlasGapAnchor.First;
  end
  else if ssCtrl in AShift then
  begin
    Result := TAtlasGapAnchor.Last;
  end
  else
  begin
    Result := TAtlasGaps.AnchorOf(TAtlasIdeSettings.Current.DesignerGapHandlesAnchor);
  end;
end;

function TAtlasIdeGapHandles.GapNow: Integer;
begin
  Result := Max(FStartGap + FDelta + FKeyOffset, 0);
  if not (ssAlt in FShift) then
  begin
    Result := TAtlasGaps.Snap(Result, TAtlasGaps.ParseValues(TAtlasIdeSettings.Current.DesignerGapHandlesSnapValues),
      TAtlasGaps.cSnapRange);
  end;
end;

/// <summary>Griffe für die Lage ARects der Gruppe zeigen; ABad: herausragende rot umranden.</summary>
procedure TAtlasIdeGapHandles.ShowGroup(const ARects: TArray<TRect>; ABad: Boolean);
var
  mOrigin: TPoint;
  mVisible: TRect;
  mFrames: TArray<TAtlasHandleFrame>;
  mOutside: TArray<Boolean>;
  mIndex: Integer;
begin
  if not TAtlasDesignerAccess.ClientArea(FParent, 0, mOrigin, mVisible) then
  begin
    Hide;
    Exit;
  end;
  EnsureOverlay;
  mFrames := nil;
  if ABad then
  begin
    mOutside := TAtlasGaps.Outside(ARects, FParent.ClientRect);
    for mIndex := 0 to High(ARects) do
    begin
      if mOutside[mIndex] then
      begin
        mFrames := mFrames + [TAtlasHandleFrame.Create(Rect(ARects[mIndex].Left + mOrigin.X,
          ARects[mIndex].Top + mOrigin.Y, ARects[mIndex].Right + mOrigin.X, ARects[mIndex].Bottom + mOrigin.Y),
          TAtlasHandleFrameKind.Bad)];
      end;
    end;
  end;
  Overlay.SetContent(Pills(ARects, mOrigin), mFrames, '', Point(0, 0));
  Overlay.ShowAt(mVisible);
end;

/// <summary>Pillen zwischen je zwei Nachbarn; AOrigin rechnet vom Client des Parents in den des Fensters.</summary>
function TAtlasIdeGapHandles.Pills(const ARects: TArray<TRect>; const AOrigin: TPoint): TArray<TAtlasHandle>;
var
  mIndex: Integer;
  mFirst, mNext: TRect;
  mCenter: TPoint;
  mGaps: TArray<Integer>;
  mMuted: TArray<Boolean>;
  mCursor: TCursor;
begin
  Result := nil;
  SetLength(mGaps, Length(FLayout.Order) - 1);
  mCursor := crSizeNS;
  if FLayout.Axis = TAtlasGapAxis.Row then
  begin
    mCursor := crSizeWE;
  end;
  for mIndex := 0 to High(mGaps) do
  begin
    mFirst := ARects[FLayout.Order[mIndex]];
    mNext := ARects[FLayout.Order[mIndex + 1]];
    if FLayout.Axis = TAtlasGapAxis.Row then
    begin
      mGaps[mIndex] := mNext.Left - mFirst.Right;
      mCenter := Point((mFirst.Right + mNext.Left) div 2,
        (Max(mFirst.Top, mNext.Top) + Min(mFirst.Bottom, mNext.Bottom)) div 2);
    end
    else
    begin
      mGaps[mIndex] := mNext.Top - mFirst.Bottom;
      mCenter := Point((Max(mFirst.Left, mNext.Left) + Min(mFirst.Right, mNext.Right)) div 2,
        (mFirst.Bottom + mNext.Top) div 2);
    end;
    mCenter := Point(mCenter.X + AOrigin.X, mCenter.Y + AOrigin.Y);
    Result := Result + [TAtlasHandle.Create(Rect(mCenter.X - Overlay.S(cPillWidth) div 2,
      mCenter.Y - Overlay.S(cPillHeight) div 2, mCenter.X + Overlay.S(cPillWidth) div 2,
      mCenter.Y + Overlay.S(cPillHeight) div 2), TAtlasHandleKind.Pill, IntToStr(mGaps[mIndex]), mCursor, mIndex)];
  end;
  mMuted := TAtlasGaps.Deviating(mGaps);
  for mIndex := 0 to High(Result) do
  begin
    Result[mIndex].Muted := mMuted[mIndex];
  end;
end;

/// <summary>Alle Abstände auf AGap, ausgehend von der Lage zu Beginn des Schritts.</summary>
procedure TAtlasIdeGapHandles.Place(AGap: Integer; AAnchor: TAtlasGapAnchor);
var
  mNew: TArray<TRect>;
  mIndex: Integer;
begin
  mNew := TAtlasGaps.Respace(FStart, FLayout, AGap, AAnchor);
  Changed := False;
  for mIndex := 0 to High(FControls) do
  begin
    if FControls[mIndex].BoundsRect <> mNew[mIndex] then
    begin
      FControls[mIndex].BoundsRect := mNew[mIndex];
    end;
    Changed := Changed or (mNew[mIndex] <> FStart[mIndex]);
  end;
  ShowGroup(mNew, True);
end;

/// <summary>Ende eines Zugs: übernehmen (nach Rückfrage, wenn etwas herausragt) oder zurücksetzen.</summary>
procedure TAtlasIdeGapHandles.FinishStep;
var
  mOutside, mFlag, mRestore: Boolean;
begin
  if not InStep then
  begin
    Exit;
  end;
  if not FKept.Holds then
  begin
    Lost;
    Exit;
  end;
  mOutside := False;
  for mFlag in TAtlasGaps.Outside(TAtlasGaps.Respace(FStart, FLayout, GapNow, AnchorFor(FShift)),
    FParent.ClientRect) do
  begin
    mOutside := mOutside or mFlag;
  end;
  mRestore := Changed and mOutside and not ConfirmOutside;
  // Während der Rückfrage kann das Formular neu geladen worden sein.
  if not FKept.Holds then
  begin
    Lost;
    Exit;
  end;
  CommitStep(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.GapDone, [Length(FLayout.Gaps), GapNow]),
    mRestore);
  Tick;
end;

procedure TAtlasIdeGapHandles.Ask(AIndex: Integer; AShift: TShiftState);
var
  mText: string;
  mGap: Integer;
  mBefore: TAtlasDesignerKept;
begin
  if not FindGroup then
  begin
    Say(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapNeeds));
    Exit;
  end;
  mBefore := FKept;
  mText := IntToStr(FLayout.Gaps[EnsureRange(AIndex, 0, High(FLayout.Gaps))]);
  if not AskValue(mText) then
  begin
    Exit;
  end;
  // Während der Eingabe kann das Formular neu geladen oder die Auswahl geändert worden sein.
  if not Regroup(mBefore) then
  begin
    Say(TAtlasDesignerKept.LostText);
    Exit;
  end;
  if not TryStrToInt(mText.Trim, mGap) or (mGap < 0) or (mGap > TAtlasGaps.cMaxGap) then
  begin
    Say(TAtlasDesignerToolStrings.Fmt(TAtlasDesignerToolTextId.GapInvalid, [mText, TAtlasGaps.cMaxGap]));
    Exit;
  end;
  BeginStep;
  FStartGap := mGap;
  FDelta := 0;
  FKeyOffset := 0;
  // Eingabe gilt genau, ohne Einrasten.
  FShift := (AShift * [ssShift, ssCtrl]) + [ssAlt];
  EnsureOverlay;
  Place(mGap, AnchorFor(FShift));
  FinishStep;
end;

/// <summary>Nach einem Dialog: Gruppe neu ermitteln; False, wenn sie nicht mehr dieselbe ist wie ABefore.</summary>
function TAtlasIdeGapHandles.Regroup(const ABefore: TAtlasDesignerKept): Boolean;
begin
  Result := FindGroup and FKept.SameAs(ABefore);
end;

/// <summary>Wert abfragen; Tick lässt die Gruppe solange in Ruhe.</summary>
function TAtlasIdeGapHandles.AskValue(var AText: string): Boolean;
begin
  FAsking := True;
  try
    Result := InputQuery(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapSetTitle),
      TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapSetPrompt), AText);
  finally
    FAsking := False;
  end;
end;

/// <summary>Rückfrage, wenn etwas herausragt; True: trotzdem übernehmen.</summary>
function TAtlasIdeGapHandles.ConfirmOutside: Boolean;
begin
  FAsking := True;
  try
    Result := MessageDlg(TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapOutsideConfirm),
      mtConfirmation, [mbYes, mbNo], 0) = mrYes;
  finally
    FAsking := False;
  end;
end;

class function TAtlasIdeGapHandles.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerGapHandles;
end;

function TAtlasIdeGapHandles.Button: TAtlasDesignerButton;
begin
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.GapHandles,
    TAtlasDesignerToolStrings.Text(TAtlasDesignerToolTextId.GapHint));
  Result.Pressed := Active;
  Result.Menu := True;
end;

procedure TAtlasIdeGapHandles.Nudge(ADelta: Integer);
begin
  if not InStep or not Dragging then
  begin
    Exit;
  end;
  if not FKept.Holds then
  begin
    Lost;
    Exit;
  end;
  Inc(FKeyOffset, ADelta);
  // Pfeiltasten wirken pixelgenau, ohne Einrasten.
  FShift := FShift + [ssAlt];
  Place(GapNow, AnchorFor(FShift));
end;

end.
