unit Atlas.IDE.Designer.InlineCaption;

// Beschriftung direkt im Designer bearbeiten (#748) in der IDE:
// - F2 (designer.inlineCaption.key) auf der markierten Komponente oder ein
//   langsamer Doppelklick (designer.inlineCaption.slowDoubleClick: ein Klick
//   auf die schon markierte Komponente, ohne Ziehen, nach dem kein
//   Doppelklick folgt) öffnet das Eingabefeld (TAtlasCaptionEditor) über
//   ihrem Text. Der normale Doppelklick bleibt bei der IDE.
// - Die Eigenschaft wählt TAtlasInlineCaption.PropertyFor mit
//   designer.inlineCaption.properties; bei DB-Grids der Titel der Spalte
//   unter dem Mauszeiger. Ohne passende Eigenschaft bleibt F2 bei der IDE.
// - Tab übernimmt und öffnet die nächste Komponente in Tab-Reihenfolge
//   (TAtlasInlineCaption.Order), Umschalt+Tab die vorige; Strg+H tauscht
//   Text und TextHint.
// - Nach dem Übernehmen: mit designer.inlineCaption.autoWidth die Breite
//   nach #730, doppelte Tastenkürzel im selben Container kurz rot umrandet.
//   Jede Übernahme ist ein Schritt für „Beschriftung rückgängig“.
// Nur im Hauptthread.

interface

uses
  Winapi.Windows,
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Vcl.ExtCtrls,
  Vcl.AppEvnts,
  Atlas.UI.Designer.CaptionEditor,
  Atlas.UI.Designer.Outlines,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeInlineCaption = class;

  /// <summary>F2 (einstellbar), solange der Designer den Fokus hat und eine Komponente mit Text markiert ist.</summary>
  TAtlasCaptionKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdeInlineCaption;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Eine Übernahme: alter Text und, wenn die Breite mitwuchs, die alte Lage.</summary>
  TAtlasCaptionChange = record
    FormFile: string;
    Component: string;
    Path: string;
    OldText: string;
    OldBounds: TRect;
    Resized: Boolean;
  end;

  /// <summary>Die Komponente in Bearbeitung bzw. die zuletzt geklickte.</summary>
  TAtlasCaptionSpot = record
    Component: string;
    Path: string;
    Point: TPoint;
    Armed: Boolean;
  end;

  TAtlasIdeInlineCaption = class
  private class var
    FCurrent: TAtlasIdeInlineCaption;
  private
    FOnMessage: TProc<string>;
    FKeys: TAtlasCaptionKeys;
    FEvents: TApplicationEvents;
    FEditor: TAtlasCaptionEditor;
    FOutlines: TAtlasDesignerOutlines;
    FClickTimer: TTimer;
    FHideTimer: TTimer;
    FClick: TAtlasCaptionSpot;
    FEdit: TAtlasCaptionSpot;
    FUndo: TArray<TAtlasCaptionChange>;
    procedure Say(const AText: string);
    function Target(out AComponent: TComponent; out APath: string): Boolean;
    procedure OpenFor(AComponent: TComponent; const APath: string; const APoint: TPoint);
    procedure Queue(AEnd: TAtlasCaptionEnd; const AText: string);
    procedure Done(AEnd: TAtlasCaptionEnd; const AText: string);
    procedure Apply(const AText: string);
    procedure FitWidth(AControl: TControl; ARoot: TComponent; var AChange: TAtlasCaptionChange);
    procedure ShowDuplicates(AControl: TControl; ARoot: TComponent);
    procedure Move(ABack: Boolean);
    procedure AppMessage(var AMsg: TMsg; var AHandled: Boolean);
    procedure MouseDown;
    procedure MouseUp;
    procedure ClickTick(Sender: TObject);
    procedure HideTick(Sender: TObject);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Beschriftung der markierten Komponente bearbeiten (F2, Menü).</summary>
    procedure Edit;
    /// <summary>Hat die markierte Komponente eine Beschriftung?</summary>
    function CanEdit: Boolean;
    function CanUndo: Boolean;
    /// <summary>Letzte Übernahme zurücknehmen.</summary>
    procedure Undo;
    /// <summary>Taste an- oder abmelden (Einstellungen, Designer gezeigt).</summary>
    procedure UpdateKeys(AWanted: Boolean);
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Messages,
  System.Math,
  System.TypInfo,
  System.StrUtils,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Forms,
  Vcl.Menus,
  ToolsAPI,
  Atlas.Core.Designer.InlineCaption,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Designer.FormTextProps,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 50;
  cIndicatorWidth = 11;
  cDuplicateMs = 1500;
  cBandExtra = 6;
  cGroupIndent = 8;
  /// <summary>Punkt außerhalb jedes Grids: erste Spalte.</summary>
  cNoPoint: TPoint = (X: -30000; Y: -30000);

type
  /// <summary>Zugriff auf das geschützte TControl.Font (Delphi: E2362, FPC nimmt es an).</summary>
  TControlAccess = class(TControl);

function IsTextProp(AObject: TObject; const AName: string): Boolean;
begin
  Result := IsPublishedProp(AObject, AName) and (PropType(AObject, AName) in [tkString, tkLString, tkWString,
    tkUString]);
end;

function FlagOf(AObject: TObject; const AName: string): Boolean;
begin
  Result := IsPublishedProp(AObject, AName) and (PropType(AObject, AName) = tkEnumeration) and
    (GetOrdProp(AObject, AName) <> 0);
end;

function ObjectOf(AObject: TObject; const AName: string): TObject;
begin
  Result := nil;
  if IsPublishedProp(AObject, AName) and (PropType(AObject, AName) = tkClass) then
  begin
    Result := GetObjectProp(AObject, AName);
  end;
end;

/// <summary>Titel der Spalte unter AScreen (Client des Grids); AIndex 0, wenn keine getroffen ist, -1 ohne
/// Spalten.</summary>
function GridTitle(AGrid: TControl; const AScreen: TPoint; out AIndex: Integer): TRect;
var
  mColumns: TObject;
  mWidths: TArray<Integer>;
  mItem: TCollectionItem;
  mOptions: string;
  mStart, mLine, mLeft: Integer;
begin
  AIndex := -1;
  Result := TRect.Empty;
  mColumns := ObjectOf(AGrid, 'Columns');
  if not (mColumns is TCollection) or (TCollection(mColumns).Count = 0) then
  begin
    Exit;
  end;
  mWidths := nil;
  for mItem in TCollection(mColumns) do
  begin
    mWidths := mWidths + [GetOrdProp(mItem, 'Width')];
  end;
  mOptions := '';
  if IsPublishedProp(AGrid, 'Options') then
  begin
    mOptions := GetSetProp(AGrid, 'Options');
  end;
  mStart := Ord(ContainsText(mOptions, 'dgIndicator')) * MulDiv(cIndicatorWidth, AGrid.CurrentPPI, 96);
  mLine := Ord(ContainsText(mOptions, 'dgColLines'));
  AIndex := Max(0, TAtlasInlineCaption.ColumnAt(AGrid.ScreenToClient(AScreen).X, mWidths, mStart, mLine));
  mLeft := mStart;
  for mStart := 0 to AIndex - 1 do
  begin
    mLeft := mLeft + mWidths[mStart] + mLine;
  end;
  Result := Rect(mLeft, 0, mLeft + mWidths[AIndex],
    Abs(TControlAccess(AGrid).Font.Height) + MulDiv(cBandExtra, AGrid.CurrentPPI, 96));
end;

function PathAt(AComponent: TComponent; const AScreen: TPoint): string;
var
  mIndex: Integer;
begin
  Result := '';
  if not (AComponent is TControl) then
  begin
    Exit;
  end;
  Result := TAtlasInlineCaption.PropertyFor(TAtlasDesignerAccess.ClassChain(AComponent),
    IsTextProp(AComponent, 'Caption'), TAtlasIdeSettings.Current.DesignerInlineCaptionProperties);
  if Pos('*', Result) > 0 then
  begin
    GridTitle(TControl(AComponent), AScreen, mIndex);
    Result := '';
    if mIndex >= 0 then
    begin
      Result := TAtlasInlineCaption.ColumnPath(mIndex);
    end;
  end;
end;

/// <summary>Steuerelement, das den Text zeigt: EditLabel bei TLabeledEdit, sonst die Komponente.</summary>
function HolderOf(AControl: TControl; const APath: string): TControl;
begin
  Result := AControl;
  if StartsText('EditLabel.', APath) and (ObjectOf(AControl, 'EditLabel') is TControl) then
  begin
    Result := TControl(ObjectOf(AControl, 'EditLabel'));
  end;
end;

function ScreenRect(AControl: TControl): TRect;
begin
  Result := TRect.Empty;
  if AControl.Parent <> nil then
  begin
    Result := AControl.BoundsRect;
    Result.SetLocation(AControl.Parent.ClientToScreen(Result.TopLeft));
  end;
end;

/// <summary>Lage des Eingabefelds auf dem Bildschirm: über dem Text, nicht über der ganzen Komponente.</summary>
function EditorRect(AHolder: TControl; const APath: string; const APoint: TPoint): TRect;
var
  mBand, mIndex: Integer;
begin
  Result := ScreenRect(AHolder);
  mBand := Abs(TControlAccess(AHolder).Font.Height) + MulDiv(cBandExtra, AHolder.CurrentPPI, 96);
  if Pos('Columns[', APath) = 1 then
  begin
    Result := GridTitle(AHolder, APoint, mIndex);
    Result.SetLocation(AHolder.ClientToScreen(Result.TopLeft));
  end
  else if AHolder is TCustomGroupBox then
  begin
    Result := Rect(Result.Left + cGroupIndent, Result.Top, Result.Right - cGroupIndent, Result.Top + mBand);
  end
  else if AHolder is TTabSheet then
  begin
    Result := Rect(Result.Left, Result.Top - mBand, Result.Right, Result.Top);
  end
  else if not (AHolder is TCustomLabel) and not (AHolder is TCustomEdit) and (Result.Height > mBand) then
  begin
    Result.Top := Result.Top + (Result.Height - mBand) div 2;
    Result.Height := mBand;
  end;
end;

function AlignmentOf(AHolder: TControl): TAlignment;
begin
  Result := taLeftJustify;
  if AHolder is TButton then
  begin
    Result := taCenter;
  end
  else if IsPublishedProp(AHolder, 'Alignment') and (PropType(AHolder, 'Alignment') = tkEnumeration) then
  begin
    Result := TAlignment(Min(GetOrdProp(AHolder, 'Alignment'), Ord(High(TAlignment))));
  end;
end;

function FontOf(AHolder: TControl; const APath: string): TFont;
var
  mObject: TObject;
begin
  Result := TControlAccess(AHolder).Font;
  if Pos('Columns[', APath) = 1 then
  begin
    mObject := ObjectOf(AHolder, 'TitleFont');
    if mObject is TFont then
    begin
      Result := TFont(mObject);
    end;
  end;
end;

function TabPathOf(AControl: TControl; ARoot: TComponent): TArray<Integer>;
var
  mControl: TControl;
begin
  Result := nil;
  if not (AControl is TWinControl) then
  begin
    Exit;
  end;
  mControl := AControl;
  while (mControl <> nil) and (mControl <> ARoot) do
  begin
    if mControl is TWinControl then
    begin
      Insert(TWinControl(mControl).TabOrder, Result, 0);
    end;
    mControl := mControl.Parent;
  end;
end;

function Stops(ARoot: TComponent): TArray<TAtlasCaptionStop>;
var
  mIndex: Integer;
  mControl: TControl;
  mFocus: TObject;
  mFocusName: string;
  mBounds: TRect;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not (ARoot.Components[mIndex] is TControl) or (PathAt(ARoot.Components[mIndex], cNoPoint) = '') then
    begin
      Continue;
    end;
    mControl := TControl(ARoot.Components[mIndex]);
    mFocus := ObjectOf(mControl, 'FocusControl');
    mFocusName := '';
    if mFocus is TComponent then
    begin
      mFocusName := TComponent(mFocus).Name;
    end;
    mBounds := TRect.Empty;
    if ARoot is TWinControl then
    begin
      mBounds := TAtlasDesignerAccess.BoundsInRoot(mControl, TWinControl(ARoot));
    end;
    Result := Result + [TAtlasCaptionStop.Create(mControl.Name, TAtlasDesignerAccess.ParentNameOf(mControl, ARoot),
      TabPathOf(mControl, ARoot), mFocusName, mBounds.Top, mBounds.Left)];
  end;
end;

function Selected(out AEditor: IOTAFormEditor; out ARoot: TComponent; out AComponent: TComponent): Boolean;
var
  mSelection: TArray<TComponent>;
begin
  AComponent := nil;
  Result := TAtlasDesignerAccess.Current(AEditor, ARoot);
  if Result then
  begin
    mSelection := TAtlasDesignerAccess.Selection(AEditor, ARoot);
    Result := Length(mSelection) = 1;
    if Result then
    begin
      AComponent := mSelection[0];
    end;
  end;
end;

{ TAtlasCaptionKeys }

function TAtlasCaptionKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerInlineCaption and (mSettings.DesignerInlineCaptionKey <> 0) and
    (ShortCut(AKey, AShift) = TShortCut(mSettings.DesignerInlineCaptionKey)) and TAtlasDesignerAccess.Focused and
    FOwner.CanEdit;
end;

procedure TAtlasCaptionKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdeInlineCaption;
begin
  mOwner := FOwner;
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      mOwner.Edit;
    end);
end;

{ TAtlasIdeInlineCaption }

constructor TAtlasIdeInlineCaption.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FKeys := TAtlasCaptionKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
  FClickTimer := TTimer.Create(nil);
  FClickTimer.Enabled := False;
  FClickTimer.OnTimer := ClickTick;
  FHideTimer := TTimer.Create(nil);
  FHideTimer.Enabled := False;
  FHideTimer.Interval := cDuplicateMs;
  FHideTimer.OnTimer := HideTick;
  FEvents := TApplicationEvents.Create(nil);
  FEvents.OnMessage := AppMessage;
  FCurrent := Self;
end;

destructor TAtlasIdeInlineCaption.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  if FEvents <> nil then
  begin
    FEvents.OnMessage := nil;
  end;
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  FEvents.Free;
  FHideTimer.Free;
  FClickTimer.Free;
  FOutlines.Free;
  FEditor.Free;
  FKeys.Free;
  inherited Destroy;
end;

procedure TAtlasIdeInlineCaption.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

function TAtlasIdeInlineCaption.Target(out AComponent: TComponent; out APath: string): Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  APath := '';
  Result := TAtlasIdeSettings.Current.DesignerInlineCaption and Selected(mEditor, mRoot, AComponent);
  if Result then
  begin
    APath := PathAt(AComponent, Mouse.CursorPos);
    Result := APath <> '';
  end;
end;

function TAtlasIdeInlineCaption.CanEdit: Boolean;
var
  mComponent: TComponent;
  mPath: string;
begin
  Result := Target(mComponent, mPath);
end;

procedure TAtlasIdeInlineCaption.Edit;
var
  mComponent: TComponent;
  mPath: string;
begin
  if Target(mComponent, mPath) then
  begin
    OpenFor(mComponent, mPath, Mouse.CursorPos);
  end
  else
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerCaptionNone));
  end;
end;

procedure TAtlasIdeInlineCaption.OpenFor(AComponent: TComponent; const APath: string; const APoint: TPoint);
var
  mText: string;
  mHolder: TControl;
  mSelf: TAtlasIdeInlineCaption;
begin
  if not (AComponent is TControl) or not TAtlasFormTextProps.Read(AComponent, APath, mText) then
  begin
    Exit;
  end;
  FEdit.Component := AComponent.Name;
  FEdit.Path := APath;
  FEdit.Point := APoint;
  mHolder := HolderOf(TControl(AComponent), APath);
  if FEditor = nil then
  begin
    FEditor := TAtlasCaptionEditor.CreateEditor(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mSelf := Self;
  FEditor.Open(EditorRect(mHolder, APath, APoint), FontOf(mHolder, APath), AlignmentOf(mHolder), mText,
    TAtlasInlineCaption.CanBreak(FlagOf(mHolder, 'WordWrap'), mText),
    procedure(AEnd: TAtlasCaptionEnd; const AText: string)
    begin
      mSelf.Queue(AEnd, AText);
    end);
end;

procedure TAtlasIdeInlineCaption.Queue(AEnd: TAtlasCaptionEnd; const AText: string);
var
  mSelf: TAtlasIdeInlineCaption;
  mText: string;
begin
  // Erst nach dem Tastendruck im Eingabefeld: dann darf es sich neu öffnen.
  mSelf := Self;
  mText := AText;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mSelf then
      begin
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mSelf.Done(AEnd, mText);
          end);
      end;
    end);
end;

procedure TAtlasIdeInlineCaption.Done(AEnd: TAtlasCaptionEnd; const AText: string);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mComponent: TComponent;
begin
  if AEnd = TAtlasCaptionEnd.Cancel then
  begin
    Exit;
  end;
  Apply(AText);
  if AEnd in [TAtlasCaptionEnd.CommitNext, TAtlasCaptionEnd.CommitBack] then
  begin
    Move(AEnd = TAtlasCaptionEnd.CommitBack);
  end
  else if (AEnd = TAtlasCaptionEnd.Toggle) and TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    mComponent := mRoot.FindComponent(FEdit.Component);
    if mComponent <> nil then
    begin
      OpenFor(mComponent, TAtlasInlineCaption.Toggled(FEdit.Path), FEdit.Point);
    end;
  end;
end;

procedure TAtlasIdeInlineCaption.Apply(const AText: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mChange: TAtlasCaptionChange;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mComponent := mRoot.FindComponent(FEdit.Component);
  if (mComponent = nil) or not TAtlasFormTextProps.Read(mComponent, FEdit.Path, mChange.OldText) or
    (mChange.OldText = AText) or not TAtlasFormTextProps.Write(mComponent, FEdit.Path, AText) then
  begin
    Exit;
  end;
  mChange.FormFile := mEditor.FileName;
  mChange.Component := FEdit.Component;
  mChange.Path := FEdit.Path;
  mChange.Resized := False;
  FitWidth(TControl(mComponent), mRoot, mChange);
  FUndo := FUndo + [mChange];
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  ShowDuplicates(TControl(mComponent), mRoot);
end;

procedure TAtlasIdeInlineCaption.FitWidth(AControl: TControl; ARoot: TComponent; var AChange: TAtlasCaptionChange);
var
  mWidth: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerInlineCaptionAutoWidth or FlagOf(AControl, 'AutoSize') or
    (Pos('Columns[', AChange.Path) = 1) then
  begin
    Exit;
  end;
  mWidth := TAtlasIdeFitText.CommonWidth([AControl], ARoot);
  if mWidth <= AControl.Width then
  begin
    Exit;
  end;
  AChange.Resized := True;
  AChange.OldBounds := AControl.BoundsRect;
  if (akRight in AControl.Anchors) and not (akLeft in AControl.Anchors) then
  begin
    AControl.SetBounds(AControl.Left - (mWidth - AControl.Width), AControl.Top, mWidth, AControl.Height);
  end
  else
  begin
    AControl.Width := mWidth;
  end;
end;

procedure TAtlasIdeInlineCaption.ShowDuplicates(AControl: TControl; ARoot: TComponent);
var
  mTexts: TArray<string>;
  mControls: TArray<TControl>;
  mIndex, mSelf: Integer;
  mText: string;
  mOutlines: TArray<TAtlasOutline>;
  mArea: TRect;
begin
  if AControl.Parent = nil then
  begin
    Exit;
  end;
  mSelf := -1;
  for mIndex := 0 to AControl.Parent.ControlCount - 1 do
  begin
    if (AControl.Parent.Controls[mIndex].Owner = ARoot) and TAtlasFormTextProps.Read(AControl.Parent.Controls[mIndex],
      PathAt(AControl.Parent.Controls[mIndex], cNoPoint), mText) then
    begin
      if AControl.Parent.Controls[mIndex] = AControl then
      begin
        mSelf := Length(mControls);
      end;
      mControls := mControls + [AControl.Parent.Controls[mIndex]];
      mTexts := mTexts + [mText];
    end;
  end;
  mOutlines := nil;
  mArea := AControl.Parent.ClientRect;
  for mIndex in TAtlasInlineCaption.Duplicates(mTexts, mSelf) + [mSelf] do
  begin
    mOutlines := mOutlines + [TAtlasOutline.Create(mControls[mIndex].BoundsRect, mControls[mIndex].Name, True)];
    mArea.Union(mControls[mIndex].BoundsRect);
  end;
  if Length(mOutlines) < 2 then
  begin
    Exit;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerCaptionDuplicate, [AControl.Name]));
  for mIndex := 0 to High(mOutlines) do
  begin
    mOutlines[mIndex].Bounds.Offset(-mArea.Left, -mArea.Top);
  end;
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea.SetLocation(AControl.Parent.ClientToScreen(mArea.TopLeft));
  FOutlines.ShowOutlines(mArea, mOutlines);
  FHideTimer.Enabled := False;
  FHideTimer.Enabled := True;
end;

procedure TAtlasIdeInlineCaption.Move(ABack: Boolean);
var
  mEditor: IOTAFormEditor;
  mRoot, mNext: TComponent;
  mName: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mName := TAtlasInlineCaption.Next(TAtlasInlineCaption.Order(Stops(mRoot)), FEdit.Component, ABack);
  mNext := nil;
  if mName <> '' then
  begin
    mNext := mRoot.FindComponent(mName);
  end;
  if mNext = nil then
  begin
    Exit;
  end;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mNext]);
  end;
  OpenFor(mNext, PathAt(mNext, cNoPoint), cNoPoint);
end;

procedure TAtlasIdeInlineCaption.AppMessage(var AMsg: TMsg; var AHandled: Boolean);
begin
  if not TAtlasIdeSettings.Current.DesignerInlineCaption or
    not TAtlasIdeSettings.Current.DesignerInlineCaptionSlowDoubleClick then
  begin
    Exit;
  end;
  case AMsg.message of
    WM_LBUTTONDOWN:
      TAtlasGuard.Run(TAtlasFeature.DesignerBar, MouseDown);
    WM_LBUTTONUP:
      MouseUp;
    WM_LBUTTONDBLCLK, WM_RBUTTONDOWN:
      begin
        FClickTimer.Enabled := False;
        FClick.Armed := False;
      end;
  end;
end;

procedure TAtlasIdeInlineCaption.MouseDown;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent, mHit: TComponent;
begin
  FClickTimer.Enabled := False;
  FClick.Armed := False;
  if ((FEditor <> nil) and FEditor.Visible) or not Selected(mEditor, mRoot, mComponent) then
  begin
    Exit;
  end;
  // Nur ein Klick auf die schon markierte Komponente (vor dem Klick, die IDE wählt erst danach).
  mHit := FindDragTarget(Mouse.CursorPos, True);
  if (mHit <> nil) and (mHit.Owner <> mRoot) and (mHit.Owner <> nil) and (mHit.Owner.Owner = mRoot) then
  begin
    mHit := mHit.Owner;
  end;
  if (mHit = mComponent) and (PathAt(mComponent, Mouse.CursorPos) <> '') then
  begin
    FClick.Component := mComponent.Name;
    FClick.Point := Mouse.CursorPos;
    FClick.Armed := True;
  end;
end;

procedure TAtlasIdeInlineCaption.MouseUp;
var
  mPoint: TPoint;
begin
  mPoint := Mouse.CursorPos;
  if FClick.Armed and (Abs(mPoint.X - FClick.Point.X) <= GetSystemMetrics(SM_CXDRAG)) and
    (Abs(mPoint.Y - FClick.Point.Y) <= GetSystemMetrics(SM_CYDRAG)) then
  begin
    // Folgt kein Doppelklick, war es der langsame zweite Klick.
    FClickTimer.Interval := GetDoubleClickTime;
    FClickTimer.Enabled := True;
  end;
  FClick.Armed := False;
end;

procedure TAtlasIdeInlineCaption.ClickTick(Sender: TObject);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  FClickTimer.Enabled := False;
  if Selected(mEditor, mRoot, mComponent) and SameText(mComponent.Name, FClick.Component) then
  begin
    TAtlasGuard.Run(TAtlasFeature.DesignerBar,
      procedure
      begin
        OpenFor(mComponent, PathAt(mComponent, FClick.Point), FClick.Point);
      end);
  end;
end;

procedure TAtlasIdeInlineCaption.HideTick(Sender: TObject);
begin
  FHideTimer.Enabled := False;
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

function TAtlasIdeInlineCaption.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FUndo) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(FUndo[High(FUndo)].FormFile, mEditor.FileName);
end;

procedure TAtlasIdeInlineCaption.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mChange: TAtlasCaptionChange;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mChange := FUndo[High(FUndo)];
  SetLength(FUndo, Length(FUndo) - 1);
  mComponent := mRoot.FindComponent(mChange.Component);
  if (mComponent = nil) or not TAtlasFormTextProps.Write(mComponent, mChange.Path, mChange.OldText) then
  begin
    Exit;
  end;
  if mChange.Resized and (mComponent is TControl) then
  begin
    TControl(mComponent).BoundsRect := mChange.OldBounds;
  end;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerCaptionUndone, [mChange.Component + '.' + mChange.Path]));
end;

procedure TAtlasIdeInlineCaption.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and TAtlasIdeSettings.Current.DesignerInlineCaption then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

procedure TAtlasIdeInlineCaption.ApplyTheme;
begin
  if FEditor <> nil then
  begin
    FEditor.ApplyColors(TAtlasIdeStyle.Colors);
  end;
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

end.
