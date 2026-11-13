unit Atlas.IDE.Designer.FormGrid;

// Befehl „Als Formularraster anordnen …“ (#731) im Menü „Anordnen“ in der
// IDE: die markierten Steuerelemente im Parent des ersten markierten.
// Paare, Zeilen und Raster rechnet TAtlasFormGrid; Partner kommen aus
// FocusControl, Grundlinien aus der Schrift (TAtlasIdeNearAlign.Baseline).
// Die neue Lage erscheint als Umriss; Enter (OK) übernimmt, Esc verwirft.
// Mit designer.arrangeForm.setTabOrder bekommen die Felder ihre bisherigen
// TabOrder-Werte in der neuen Reihenfolge. „Raster rückgängig“ stellt Lage
// (TAtlasDesignerSnapshot) und TabOrder wieder her. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Atlas.IDE.Designer.Snapshot,
  Atlas.IDE.Designer.Tool;

type
  TAtlasIdeFormGrid = class(TAtlasIdeDesignerTool)
  private
    FSnapshot: TAtlasDesignerSnapshot;
    FTabNames: TArray<string>;
    FTabOrders: TArray<Integer>;
    procedure HideOutlines;
    procedure SetTabOrders(ARoot: TComponent; const AControls: TArray<TControl>; const AOrder: TArray<Integer>);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure Execute;
    function CanUndo: Boolean;
    procedure Undo;
    /// <summary>Mindestens zwei markierte Steuerelemente?</summary>
    class function CanArrange: Boolean; static;
  end;

implementation

uses
  System.Types,
  System.TypInfo,
  System.UITypes,
  Vcl.Graphics,
  Vcl.StdCtrls,
  Vcl.Dialogs,
  ToolsAPI,
  Atlas.Core.Designer.FormGrid,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.NearAlign,
  Atlas.IDE.Foundation.Settings,
  Atlas.UI.Designer.Outlines;

function IsLabel(AControl: TControl): Boolean;
begin
  Result := (AControl is TCustomLabel) or (AControl is TCustomStaticText);
end;

function PartnerName(AControl: TControl): string;
var
  mField: TObject;
begin
  Result := '';
  if IsPublishedProp(AControl, 'FocusControl') and (PropType(AControl, 'FocusControl') = tkClass) then
  begin
    mField := GetObjectProp(AControl, 'FocusControl');
    if mField is TComponent then
    begin
      Result := TComponent(mField).Name;
    end;
  end;
end;

function ItemsOf(const AControls: TArray<TControl>; ACanvas: TCanvas): TArray<TAtlasGridItem>;
var
  mControl: TControl;
  mBaseline: Integer;
begin
  Result := nil;
  for mControl in AControls do
  begin
    mBaseline := TAtlasIdeNearAlign.Baseline(mControl, ACanvas);
    if mBaseline >= 0 then
    begin
      mBaseline := mBaseline - mControl.Top;
    end;
    Result := Result + [TAtlasGridItem.Create(mControl.Name, mControl.BoundsRect, IsLabel(mControl),
      PartnerName(mControl), mBaseline)];
  end;
end;

function OptionsOf(const ASettings: TAtlasPluginSettings): TAtlasGridOptions;
begin
  Result.RowGap := ASettings.DesignerArrangeFormRowGap;
  Result.LabelGap := ASettings.DesignerArrangeFormLabelGap;
  Result.LabelAlign := TAtlasGridLabelAlign.Left;
  if SameText(ASettings.DesignerArrangeFormLabelAlign, TAtlasPluginSettings.cGridLabelRight) then
  begin
    Result.LabelAlign := TAtlasGridLabelAlign.Right;
  end
  else if SameText(ASettings.DesignerArrangeFormLabelAlign, TAtlasPluginSettings.cGridLabelAbove) then
  begin
    Result.LabelAlign := TAtlasGridLabelAlign.Above;
  end;
  Result.EqualWidth := ASettings.DesignerArrangeFormEqualFieldWidth;
  Result.TwoPerRow := ASettings.DesignerArrangeFormTwoPerRow;
end;

function OutlinesOf(const AControls: TArray<TControl>; const AResult: TAtlasGridResult;
  ARoot: TWinControl): TArray<TAtlasOutline>;
var
  mIndex: Integer;
  mBounds: TRect;
begin
  Result := nil;
  for mIndex := 0 to High(AControls) do
  begin
    // Neue Lage im Parent in die Lage im Formular umrechnen.
    mBounds := AResult.Bounds[mIndex];
    mBounds.Offset(TAtlasDesignerAccess.BoundsInRoot(AControls[mIndex], ARoot).TopLeft -
      AControls[mIndex].BoundsRect.TopLeft);
    Result := Result + [TAtlasOutline.Create(mBounds, AControls[mIndex].Name, False)];
  end;
end;

{ TAtlasIdeFormGrid }

constructor TAtlasIdeFormGrid.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(AOnMessage);
  FSnapshot := TAtlasDesignerSnapshot.Create;
end;

destructor TAtlasIdeFormGrid.Destroy;
begin
  FSnapshot.Free;
  inherited Destroy;
end;

procedure TAtlasIdeFormGrid.HideOutlines;
begin
  if HasOutlines then
  begin
    Outlines.HideOutlines;
  end;
end;

class function TAtlasIdeFormGrid.CanArrange: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := TAtlasDesignerAccess.Current(mEditor, mRoot) and
    (Length(TAtlasDesignerAccess.SelectedSiblings(mEditor, mRoot)) >= 2);
end;

procedure TAtlasIdeFormGrid.SetTabOrders(ARoot: TComponent; const AControls: TArray<TControl>;
  const AOrder: TArray<Integer>);
var
  mOrders: TArray<Integer>;
  mIndex, mOuter, mSwap: Integer;
begin
  FTabNames := nil;
  FTabOrders := nil;
  mOrders := nil;
  for mIndex in AOrder do
  begin
    if AControls[mIndex] is TWinControl then
    begin
      FTabNames := FTabNames + [AControls[mIndex].Name];
      FTabOrders := FTabOrders + [TWinControl(AControls[mIndex]).TabOrder];
      mOrders := mOrders + [TWinControl(AControls[mIndex]).TabOrder];
    end;
  end;
  // Die bisherigen Werte aufsteigend in der neuen Reihenfolge vergeben.
  for mOuter := 1 to High(mOrders) do
  begin
    mIndex := mOuter;
    while (mIndex > 0) and (mOrders[mIndex] < mOrders[mIndex - 1]) do
    begin
      mSwap := mOrders[mIndex];
      mOrders[mIndex] := mOrders[mIndex - 1];
      mOrders[mIndex - 1] := mSwap;
      Dec(mIndex);
    end;
  end;
  for mIndex := 0 to High(FTabNames) do
  begin
    TWinControl(ARoot.FindComponent(FTabNames[mIndex])).TabOrder := mOrders[mIndex];
  end;
end;

procedure TAtlasIdeFormGrid.Execute;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControls: TArray<TControl>;
  mSettings: TAtlasPluginSettings;
  mResult: TAtlasGridResult;
  mBitmap: TBitmap;
  mIndex: Integer;
  mAccepted: Boolean;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.DesignerArrangeForm or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    not (mRoot is TWinControl) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mControls := TAtlasDesignerAccess.SelectedSiblings(mEditor, mRoot);
  if Length(mControls) < 2 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGridNeedTwo));
    Exit;
  end;
  mBitmap := TBitmap.Create;
  try
    mResult := TAtlasFormGrid.Arrange(ItemsOf(mControls, mBitmap.Canvas), OptionsOf(mSettings));
  finally
    mBitmap.Free;
  end;
  ShowOutlinesIn(TWinControl(mRoot), OutlinesOf(mControls, mResult, TWinControl(mRoot)));
  try
    mAccepted := MessageDlg(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerGridConfirm, [Length(mControls)]),
      mtConfirmation, [mbOK, mbCancel], 0) = mrOk;
  finally
    HideOutlines;
  end;
  if not mAccepted then
  begin
    Exit;
  end;
  FSnapshot.Take(mEditor.FileName, mRoot);
  for mIndex := 0 to High(mControls) do
  begin
    mControls[mIndex].BoundsRect := mResult.Bounds[mIndex];
  end;
  FTabNames := nil;
  FTabOrders := nil;
  if mSettings.DesignerArrangeFormSetTabOrder then
  begin
    SetTabOrders(mRoot, mControls, mResult.TabOrder);
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerGridDone, [Length(mControls)]));
end;

function TAtlasIdeFormGrid.CanUndo: Boolean;
begin
  Result := FSnapshot.CanRestore;
end;

procedure TAtlasIdeFormGrid.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mIndex: Integer;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  // TabOrder rückwärts: Jeder Wert schiebt die anderen, also in umgekehrter Reihenfolge zurück.
  for mIndex := High(FTabNames) downto 0 do
  begin
    mComponent := mRoot.FindComponent(FTabNames[mIndex]);
    if mComponent is TWinControl then
    begin
      TWinControl(mComponent).TabOrder := FTabOrders[mIndex];
    end;
  end;
  FTabNames := nil;
  FTabOrders := nil;
  FSnapshot.Restore;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerGridUndone));
end;

end.
