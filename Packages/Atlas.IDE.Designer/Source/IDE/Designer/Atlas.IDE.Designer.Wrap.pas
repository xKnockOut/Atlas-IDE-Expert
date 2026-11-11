unit Atlas.IDE.Designer.Wrap;

// Befehle „Einpacken in“ und „Container auflösen“ (#733) im Menü „Anordnen“
// in der IDE. Rechteck, Koordinaten, TabOrder, Anchors des Containers und
// GridPanel-Zellen rechnet TAtlasContainerWrap; hier geht es um den Designer:
// - Einpacken: alle markierten Steuerelemente im selben Parent; Name (und bei
//   TGroupBox die Beschriftung) wird vorher abgefragt. Der Container entsteht
//   über IDesigner.CreateComponent an der Z-Stelle des obersten markierten,
//   die Kinder wandern mit umgerechneten Koordinaten hinein; TPageControl
//   bekommt eine Seite, TFlowPanel und TGridPanel die Kinder zeilenweise.
// - Auflösen: Verweise im Quelltext der Unit werden vorher gezeigt, Handler
//   des Containers in der Meldungsansicht genannt; die Kinder kommen an die
//   Z- und TabOrder-Stelle des Containers, der Container wird gelöscht.
// - Rückgängig: der letzte Schritt im selben Formular. Beim Auflösen bleibt
//   dafür eine Kopie der Eigenschaften des Containers (ohne Owner) stehen.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  ToolsAPI,
  DesignIntf;

type
  TAtlasWrapStep = (None, Wrapped, Unwrapped);

  /// <summary>Stand für „Einpacken rückgängig“.</summary>
  TAtlasWrapState = record
    Step: TAtlasWrapStep;
    FileName: string;
    ParentName: string;
    Container: string;
    Sheet: string;
    ContainerClass: TComponentClass;
    ContainerBounds: TRect;
    ContainerTab: Integer;
    Children: TArray<string>;
    /// <summary>Lage vor dem Schritt (Einpacken: im Parent, Auflösen: im Container).</summary>
    ChildBounds: TArray<TRect>;
    ChildTabs: TArray<Integer>;
    /// <summary>Reihenfolge (Z) der Steuerelemente im Parent vor dem Schritt.</summary>
    Stack: TArray<string>;
  end;

  TAtlasIdeWrap = class
  private
    FOnMessage: TProc<string>;
    FState: TAtlasWrapState;
    FTemplate: TComponent;
    FSheetTemplate: TComponent;
    procedure Say(const AText: string);
    /// <summary>Auswahl und Klasse prüfen; sonst Hinweis und False.</summary>
    function Ready(const AEditor: IOTAFormEditor; ARoot: TComponent; const AClassName: string;
      out AControls: TArray<TControl>; out AClass: TComponentClass): Boolean;
    procedure ClearState;
    procedure Remember(AStep: TAtlasWrapStep; const AFileName: string; AParent: TWinControl; ARoot: TComponent;
      const AChildren: TArray<TControl>);
    function CreateContainer(const ADesigner: IDesigner; AClass: TComponentClass; AParent: TWinControl;
      const AName, ACaption: string): TWinControl;
    procedure KeepTemplate(AContainer, AInner: TWinControl);
    procedure FinishUnwrap(ARoot: TComponent; AParent: TWinControl);
    procedure UndoWrap(const AEditor: IOTAFormEditor; ARoot: TComponent);
    procedure UndoUnwrap(const ADesigner: IDesigner; ARoot: TComponent);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Containerklassen fürs Menü: eingebaute und designer.wrapInContainer.classes.</summary>
    class function ClassNames: TArray<string>; static;
    /// <summary>Ist mindestens ein Steuerelement markiert?</summary>
    class function CanWrap: Boolean; static;
    /// <summary>Ist genau ein Container mit Kindern markiert?</summary>
    class function CanUnwrap: Boolean; static;
    procedure Wrap(const AClassName: string);
    procedure Unwrap;
    function CanUndo: Boolean;
    procedure Undo;
  end;

implementation

uses
  System.TypInfo,
  System.UITypes,
  System.Math,
  Vcl.Graphics,
  Vcl.ExtCtrls,
  Vcl.StdCtrls,
  Vcl.ComCtrls,
  Vcl.Dialogs,
  Atlas.Core.Designer.Anchors,
  Atlas.Core.Designer.Wrap,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.Anchors,
  Atlas.IDE.Designer.DuplicateRow,
  Atlas.IDE.Foundation.EditorBuffer,
  Atlas.IDE.Foundation.Settings;

const
  cBuiltIn: array[0..5] of string = ('TPanel', 'TGroupBox', 'TFlowPanel', 'TGridPanel', 'TScrollBox', 'TPageControl');
  cMaxShownReferences = 10;

{ Hilfen }

function ClassOf(const AName: string): TComponentClass;
const
  cClasses: array[0..5] of TComponentClass = (TPanel, TGroupBox, TFlowPanel, TGridPanel, TScrollBox, TPageControl);
var
  mIndex: Integer;
  mClass: TPersistentClass;
begin
  for mIndex := Low(cBuiltIn) to High(cBuiltIn) do
  begin
    if SameText(AName, cBuiltIn[mIndex]) then
    begin
      Exit(cClasses[mIndex]);
    end;
  end;
  Result := nil;
  mClass := GetClass(AName);
  if (mClass <> nil) and mClass.InheritsFrom(TWinControl) then
  begin
    Result := TComponentClass(mClass);
  end;
end;

function UniqueName(ARoot: TComponent; const AName: string): string;
var
  mNumber: Integer;
begin
  Result := AName;
  mNumber := 1;
  while ARoot.FindComponent(Result) <> nil do
  begin
    Inc(mNumber);
    Result := AName + IntToStr(mNumber);
  end;
end;

function ParentByName(ARoot: TComponent; const AName: string): TWinControl;
var
  mComponent: TComponent;
begin
  Result := nil;
  mComponent := ARoot;
  if not SameText(ARoot.Name, AName) then
  begin
    mComponent := ARoot.FindComponent(AName);
  end;
  if mComponent is TWinControl then
  begin
    Result := TWinControl(mComponent);
  end;
end;

/// <summary>Seite des PageControls, sonst der Container selbst.</summary>
function InnerOf(AContainer: TWinControl): TWinControl;
begin
  Result := AContainer;
  if (AContainer is TPageControl) and (TPageControl(AContainer).PageCount > 0) then
  begin
    Result := TPageControl(AContainer).Pages[0];
  end;
end;

/// <summary>Abstand des Clients von AInner zur Außenkante von AContainer.</summary>
function ClientOffset(AContainer, AInner: TWinControl): TPoint;
begin
  Result := TPoint.Zero;
  if (AContainer.Parent <> nil) and AInner.HandleAllocated and AContainer.Parent.HandleAllocated then
  begin
    Result := AInner.ClientOrigin - AContainer.Parent.ClientToScreen(AContainer.BoundsRect.TopLeft);
  end;
end;

function OwnedControls(AParent: TWinControl; ARoot: TComponent): TArray<TControl>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    if AParent.Controls[mIndex].Owner = ARoot then
    begin
      Result := Result + [AParent.Controls[mIndex]];
    end;
  end;
end;

function Contains(const ANames: TArray<string>; const AName: string): Boolean;
var
  mName: string;
begin
  for mName in ANames do
  begin
    if SameText(mName, AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function NamesOf(const AControls: TArray<TControl>): TArray<string>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    Result := Result + [mControl.Name];
  end;
end;

function TabOf(AControl: TComponent): Integer;
begin
  Result := -1;
  if AControl is TWinControl then
  begin
    Result := TWinControl(AControl).TabOrder;
  end;
end;

/// <summary>Z-Reihenfolge im Parent nach ANames: BringToFront in Folge.</summary>
procedure Restack(AParent: TWinControl; ARoot: TComponent; const ANames: TArray<string>);
var
  mName: string;
  mComponent: TComponent;
begin
  for mName in ANames do
  begin
    mComponent := ARoot.FindComponent(mName);
    if (mComponent is TControl) and (TControl(mComponent).Parent = AParent) then
    begin
      TControl(mComponent).BringToFront;
    end;
  end;
end;

/// <summary>TabOrder setzen, aufsteigend nach Wert; -1 bleibt.</summary>
procedure SetTabs(ARoot: TComponent; const ANames: TArray<string>; const ATabs: TArray<Integer>);
var
  mIndex: Integer;
  mComponent: TComponent;
begin
  for mIndex in TAtlasContainerWrap.ByTabOrder(ATabs) do
  begin
    mComponent := ARoot.FindComponent(ANames[mIndex]);
    if (ATabs[mIndex] >= 0) and (mComponent is TWinControl) then
    begin
      TWinControl(mComponent).TabOrder := ATabs[mIndex];
    end;
  end;
end;

/// <summary>Steuerelemente nach AParent mit den Lagen ABounds.</summary>
procedure MoveTo(ARoot: TComponent; AParent: TWinControl; const ANames: TArray<string>; const ABounds: TArray<TRect>);
var
  mIndex: Integer;
  mComponent: TComponent;
begin
  for mIndex := 0 to High(ANames) do
  begin
    mComponent := ARoot.FindComponent(ANames[mIndex]);
    if mComponent is TControl then
    begin
      TControl(mComponent).Parent := AParent;
      TControl(mComponent).BoundsRect := ABounds[mIndex];
    end;
  end;
end;

function DeleteComponent(const AEditor: IOTAFormEditor; const AName: string): Boolean;
var
  mComponent: IOTAComponent;
begin
  mComponent := AEditor.FindComponent(AName);
  Result := (mComponent <> nil) and mComponent.Delete;
end;

/// <summary>Quelltext der Unit zum Formular, auch ungespeichert.</summary>
function SourceOf(const AEditor: IOTAFormEditor): string;
var
  mModule: IOTAModule;
  mIndex: Integer;
  mBuffer: IOTAEditBuffer;
begin
  Result := '';
  mModule := AEditor.Module;
  if mModule = nil then
  begin
    Exit;
  end;
  for mIndex := 0 to mModule.ModuleFileCount - 1 do
  begin
    if Supports(mModule.ModuleFileEditors[mIndex], IOTAEditBuffer, mBuffer) then
    begin
      Exit(TAtlasEditorBuffer.Text(mBuffer));
    end;
  end;
end;

function HandlerNames(const ADesigner: IDesigner; AComponent: TComponent): TArray<string>;
var
  mList: PPropList;
  mCount, mIndex: Integer;
  mName: string;
begin
  Result := nil;
  mCount := GetPropList(AComponent, mList);
  try
    for mIndex := 0 to mCount - 1 do
    begin
      if mList[mIndex].PropType^.Kind = tkMethod then
      begin
        mName := ADesigner.GetMethodName(GetMethodProp(AComponent, mList[mIndex]));
        if mName <> '' then
        begin
          Result := Result + [mName];
        end;
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

/// <summary>Zeilen mit Verweisen als Text für die Rückfrage.</summary>
function ReferenceText(const ASource: string; const ALines: TArray<Integer>): string;
var
  mLines: TArray<string>;
  mIndex: Integer;
begin
  Result := '';
  mLines := ASource.Replace(#13#10, #10).Split([#10]);
  for mIndex := 0 to Min(High(ALines), cMaxShownReferences - 1) do
  begin
    if ALines[mIndex] <= Length(mLines) then
    begin
      Result := Result + sLineBreak + IntToStr(ALines[mIndex]) + ': ' + Trim(mLines[ALines[mIndex] - 1]);
    end;
  end;
end;

/// <summary>Spalten und Zeilen des GridPanels gleich verteilt.</summary>
procedure SetupGrid(AGrid: TGridPanel; const ACells: TAtlasGridCells);
var
  mIndex: Integer;
  mColumn: TColumnItem;
  mRow: TRowItem;
begin
  AGrid.ColumnCollection.BeginUpdate;
  AGrid.RowCollection.BeginUpdate;
  try
    AGrid.ColumnCollection.Clear;
    AGrid.RowCollection.Clear;
    for mIndex := 1 to Max(ACells.Columns, 1) do
    begin
      mColumn := AGrid.ColumnCollection.Add;
      mColumn.SizeStyle := ssPercent;
      mColumn.Value := 100 / Max(ACells.Columns, 1);
    end;
    for mIndex := 1 to Max(ACells.Rows, 1) do
    begin
      mRow := AGrid.RowCollection.Add;
      mRow.SizeStyle := ssPercent;
      mRow.Value := 100 / Max(ACells.Rows, 1);
    end;
  finally
    AGrid.RowCollection.EndUpdate;
    AGrid.ColumnCollection.EndUpdate;
  end;
end;

/// <summary>Markierte Steuerelemente in Z-Reihenfolge; False bei verschiedenen Parents.</summary>
function Targets(const AEditor: IOTAFormEditor; ARoot: TComponent; out AControls: TArray<TControl>): Boolean;
var
  mComponent: TComponent;
  mSelected: TArray<TComponent>;
  mSorted: TArray<TControl>;
  mControl: TControl;
begin
  AControls := nil;
  mSelected := TAtlasDesignerAccess.Selection(AEditor, ARoot);
  for mComponent in mSelected do
  begin
    if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) then
    begin
      Continue;
    end;
    if (Length(AControls) > 0) and (TControl(mComponent).Parent <> AControls[0].Parent) then
    begin
      Exit(False);
    end;
    AControls := AControls + [TControl(mComponent)];
  end;
  Result := True;
  if Length(AControls) > 0 then
  begin
    mSorted := nil;
    for mControl in OwnedControls(AControls[0].Parent, ARoot) do
    begin
      if Contains(NamesOf(AControls), mControl.Name) then
      begin
        mSorted := mSorted + [mControl];
      end;
    end;
    AControls := mSorted;
  end;
end;

/// <summary>Auflösbar: Container mit Parent und eigenen Kindern, PageControl mit einer Seite.</summary>
function IsContainer(AComponent: TComponent; ARoot: TComponent): Boolean;
begin
  Result := (AComponent is TWinControl) and (TWinControl(AComponent).Parent <> nil) and not (AComponent is TTabSheet);
  if Result and (AComponent is TPageControl) then
  begin
    Result := TPageControl(AComponent).PageCount = 1;
  end;
  Result := Result and (Length(OwnedControls(InnerOf(TWinControl(AComponent)), ARoot)) > 0);
end;

/// <summary>Markierter Container mit Kindern oder nil.</summary>
function SelectedContainer(const AEditor: IOTAFormEditor; ARoot: TComponent): TWinControl;
var
  mSelected: TArray<TComponent>;
begin
  Result := nil;
  mSelected := TAtlasDesignerAccess.Selection(AEditor, ARoot);
  if (Length(mSelected) = 1) and IsContainer(mSelected[0], ARoot) then
  begin
    Result := TWinControl(mSelected[0]);
  end;
end;

/// <summary>Name und bei Klassen mit Caption die Beschriftung abfragen.</summary>
function AskName(AClass: TComponentClass; ARoot: TComponent; out AName, ACaption: string): Boolean;
var
  mValues: TArray<string>;
  mPrompts: TArray<string>;
begin
  mPrompts := [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapNamePrompt)];
  mValues := [UniqueName(ARoot, TAtlasContainerWrap.PrefixFor(AClass.ClassName))];
  if AClass.InheritsFrom(TCustomGroupBox) then
  begin
    mPrompts := mPrompts + [TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapCaptionPrompt)];
    mValues := mValues + [''];
  end;
  Result := InputQuery(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapTitle, [AClass.ClassName]),
    mPrompts, mValues);
  AName := '';
  ACaption := '';
  if Result then
  begin
    AName := Trim(mValues[0]);
    if Length(mValues) > 1 then
    begin
      ACaption := mValues[1];
    end;
  end;
end;

function CaptionHeight(AContainer: TWinControl): Integer;
var
  mBitmap: TBitmap;
begin
  Result := 0;
  if AContainer is TCustomGroupBox then
  begin
    mBitmap := TBitmap.Create;
    try
      mBitmap.Canvas.Font.Assign(TGroupBox(AContainer).Font);
      Result := mBitmap.Canvas.TextHeight('Wg');
    finally
      mBitmap.Free;
    end;
  end;
end;

/// <summary>Container um ABounds legen: Innenrand, Beschriftung und Rahmen von AInner.</summary>
procedure PlaceContainer(AContainer, AInner: TWinControl; const ABounds: TArray<TRect>; APadding: Integer);
var
  mRect: TRect;
  mOffset: TPoint;
  mExtraX, mExtraY: Integer;
begin
  mRect := TAtlasContainerWrap.ContainerBounds(ABounds, APadding, CaptionHeight(AContainer));
  AContainer.BoundsRect := mRect;
  mOffset := ClientOffset(AContainer, AInner);
  mExtraX := AContainer.Width - AInner.ClientWidth - mOffset.X;
  mExtraY := AContainer.Height - AInner.ClientHeight - mOffset.Y;
  AContainer.BoundsRect := Rect(mRect.Left - mOffset.X, mRect.Top - mOffset.Y, mRect.Right + mExtraX,
    mRect.Bottom + mExtraY);
end;

{ TAtlasIdeWrap }

constructor TAtlasIdeWrap.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeWrap.Destroy;
begin
  ClearState;
  inherited Destroy;
end;

procedure TAtlasIdeWrap.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeWrap.ClearState;
begin
  FreeAndNil(FTemplate);
  FreeAndNil(FSheetTemplate);
  FState := Default(TAtlasWrapState);
end;

class function TAtlasIdeWrap.ClassNames: TArray<string>;
var
  mName: string;
  mSettings: TAtlasPluginSettings;
begin
  Result := nil;
  for mName in cBuiltIn do
  begin
    Result := Result + [mName];
  end;
  mSettings := TAtlasIdeSettings.Current;
  for mName in (mSettings.DesignerWrapInContainerClasses + ',' + mSettings.DesignerWrapInContainerDefaultClass).Split(
    [',', ';']) do
  begin
    if (Trim(mName) <> '') and not Contains(Result, Trim(mName)) then
    begin
      Result := Result + [Trim(mName)];
    end;
  end;
end;

class function TAtlasIdeWrap.CanWrap: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControls: TArray<TControl>;
begin
  Result := TAtlasDesignerAccess.Current(mEditor, mRoot) and Targets(mEditor, mRoot, mControls) and
    (Length(mControls) > 0);
end;

class function TAtlasIdeWrap.CanUnwrap: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := TAtlasDesignerAccess.Current(mEditor, mRoot) and (SelectedContainer(mEditor, mRoot) <> nil);
end;

procedure TAtlasIdeWrap.Remember(AStep: TAtlasWrapStep; const AFileName: string; AParent: TWinControl;
  ARoot: TComponent; const AChildren: TArray<TControl>);
var
  mControl: TControl;
begin
  ClearState;
  FState.Step := AStep;
  FState.FileName := AFileName;
  FState.ParentName := AParent.Name;
  FState.Stack := NamesOf(OwnedControls(AParent, ARoot));
  FState.Children := NamesOf(AChildren);
  for mControl in AChildren do
  begin
    FState.ChildBounds := FState.ChildBounds + [mControl.BoundsRect];
    FState.ChildTabs := FState.ChildTabs + [TabOf(mControl)];
  end;
end;

function TAtlasIdeWrap.CreateContainer(const ADesigner: IDesigner; AClass: TComponentClass; AParent: TWinControl;
  const AName, ACaption: string): TWinControl;
var
  mSheet: TTabSheet;
begin
  Result := TWinControl(ADesigner.CreateComponent(AClass, AParent, 0, 0, 0, 0));
  Result.Name := AName;
  if IsPublishedProp(Result, 'Caption') then
  begin
    SetStrProp(Result, 'Caption', ACaption);
  end;
  if Result is TPageControl then
  begin
    mSheet := TTabSheet(ADesigner.CreateComponent(TTabSheet, Result, 0, 0, 0, 0));
    mSheet.PageControl := TPageControl(Result);
    mSheet.Name := UniqueName(Result.Owner, TAtlasContainerWrap.PrefixFor(TTabSheet.ClassName) +
      Copy(AName, Length(TAtlasContainerWrap.PrefixFor(AClass.ClassName)) + 1, MaxInt));
    FState.Sheet := mSheet.Name;
  end;
end;

/// <summary>Kinder in den Container: Koordinaten, Reihenfolge (Flow/Grid zeilenweise), TabOrder, Anchors.</summary>
procedure FillContainer(ARoot: TComponent; AContainer, AInner: TWinControl; const AState: TAtlasWrapState);
var
  mOffset: TPoint;
  mOrder: TArray<Integer>;
  mCells: TAtlasGridCells;
  mIndex: Integer;
  mAnchors: TArray<TAtlasAnchorSet>;
  mControl: TControl;
begin
  mOffset := ClientOffset(AContainer, AInner);
  mOrder := nil;
  for mIndex := 0 to High(AState.Children) do
  begin
    mOrder := mOrder + [mIndex];
  end;
  if (AInner is TFlowPanel) or (AInner is TGridPanel) then
  begin
    mCells := TAtlasContainerWrap.GridCells(AState.ChildBounds);
    mOrder := mCells.Order;
    if AInner is TGridPanel then
    begin
      SetupGrid(TGridPanel(AInner), mCells);
    end;
  end;
  mAnchors := nil;
  for mIndex in mOrder do
  begin
    MoveTo(ARoot, AInner, [AState.Children[mIndex]], [TAtlasContainerWrap.IntoContainer(AState.ChildBounds[mIndex],
      AContainer.BoundsRect, mOffset)]);
  end;
  for mIndex := 0 to High(AState.Children) do
  begin
    mControl := TControl(ARoot.FindComponent(AState.Children[mIndex]));
    mAnchors := mAnchors + [TAtlasIdeAnchors.ToSet(mControl.Anchors)];
  end;
  SetTabs(ARoot, AState.Children, AState.ChildTabs);
  AContainer.Anchors := TAtlasIdeAnchors.ToAnchors(TAtlasContainerWrap.ContainerAnchors(mAnchors));
end;

/// <summary>Container an die TabOrder des ersten Kinds und die Z-Stelle des obersten.</summary>
procedure FinishWrap(ARoot: TComponent; AParent, AContainer: TWinControl; const AState: TAtlasWrapState);
var
  mName: string;
  mStack: TArray<string>;
  mTop, mIndex, mTab: Integer;
begin
  mTab := -1;
  mTop := -1;
  for mIndex := 0 to High(AState.Stack) do
  begin
    if Contains(AState.Children, AState.Stack[mIndex]) then
    begin
      mTop := mIndex;
    end;
  end;
  mStack := nil;
  for mIndex := 0 to High(AState.Stack) do
  begin
    mName := AState.Stack[mIndex];
    if mIndex = mTop then
    begin
      mStack := mStack + [AContainer.Name];
    end
    else if not Contains(AState.Children, mName) then
    begin
      mStack := mStack + [mName];
    end;
  end;
  Restack(AParent, ARoot, mStack);
  for mIndex in TAtlasContainerWrap.ByTabOrder(AState.ChildTabs) do
  begin
    if (mTab < 0) and (AState.ChildTabs[mIndex] >= 0) then
    begin
      mTab := AState.ChildTabs[mIndex];
    end;
  end;
  if mTab >= 0 then
  begin
    AContainer.TabOrder := mTab;
  end;
end;

/// <summary>Verweise auf den Container im Code zeigen; True, wenn keine oder trotzdem auflösen.</summary>
function ConfirmReferences(const AEditor: IOTAFormEditor; AContainer, AInner: TWinControl): Boolean;
var
  mSource: string;
  mLines: TArray<Integer>;
begin
  mSource := SourceOf(AEditor);
  mLines := TAtlasContainerWrap.References(mSource, AContainer.Name);
  if AInner <> AContainer then
  begin
    mLines := mLines + TAtlasContainerWrap.References(mSource, AInner.Name);
  end;
  Result := (Length(mLines) = 0) or (MessageDlg(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapReferences,
    [AContainer.Name, ReferenceText(mSource, mLines), sLineBreak + sLineBreak]), mtWarning, [mbYes, mbNo], 0) = mrYes);
end;

function TAtlasIdeWrap.Ready(const AEditor: IOTAFormEditor; ARoot: TComponent; const AClassName: string;
  out AControls: TArray<TControl>; out AClass: TComponentClass): Boolean;
begin
  AClass := ClassOf(AClassName);
  Result := False;
  if not Targets(AEditor, ARoot, AControls) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapParents));
  end
  else if Length(AControls) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapNeedSelection));
  end
  else if AClass = nil then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapUnknownClass, [AClassName]));
  end
  else
  begin
    Result := True;
  end;
end;

procedure TAtlasIdeWrap.Wrap(const AClassName: string);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mControls: TArray<TControl>;
  mClass: TComponentClass;
  mName, mCaption: string;
  mContainer: TWinControl;
begin
  if not TAtlasIdeSettings.Current.DesignerWrapInContainer or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  if not Ready(mEditor, mRoot, AClassName, mControls, mClass) or not AskName(mClass, mRoot, mName, mCaption) then
  begin
    Exit;
  end;
  if not IsValidIdent(mName) or (mRoot.FindComponent(mName) <> nil) then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapInvalidName, [mName]));
    Exit;
  end;
  Remember(TAtlasWrapStep.Wrapped, mEditor.FileName, mControls[0].Parent, mRoot, mControls);
  mContainer := CreateContainer(TAtlasDesignerAccess.DesignerOf(mEditor), mClass, mControls[0].Parent, mName,
    mCaption);
  FState.Container := mContainer.Name;
  PlaceContainer(mContainer, InnerOf(mContainer), FState.ChildBounds,
    TAtlasIdeSettings.Current.DesignerWrapInContainerPadding);
  FillContainer(mRoot, mContainer, InnerOf(mContainer), FState);
  FinishWrap(mRoot, mContainer.Parent, mContainer, FState);
  TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mContainer]);
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapDone, [Length(mControls), mContainer.Name]));
end;

procedure TAtlasIdeWrap.KeepTemplate(AContainer, AInner: TWinControl);
begin
  FTemplate := TComponentClass(AContainer.ClassType).Create(nil);
  TAtlasIdeDuplicateRow.CopyProperties(AContainer, FTemplate, True);
  if AInner <> AContainer then
  begin
    FSheetTemplate := TComponentClass(AInner.ClassType).Create(nil);
    TAtlasIdeDuplicateRow.CopyProperties(AInner, FSheetTemplate, True);
    FState.Sheet := AInner.Name;
  end;
end;

procedure TAtlasIdeWrap.Unwrap;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mContainer, mInner, mParent: TWinControl;
  mHandlers: TArray<string>;
  mIndex: Integer;
  mBounds: TArray<TRect>;
  mOffset: TPoint;
begin
  if not TAtlasIdeSettings.Current.DesignerWrapInContainer or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mContainer := SelectedContainer(mEditor, mRoot);
  if mContainer = nil then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapNoContainer));
    Exit;
  end;
  mInner := InnerOf(mContainer);
  if not ConfirmReferences(mEditor, mContainer, mInner) then
  begin
    Exit;
  end;
  mHandlers := HandlerNames(TAtlasDesignerAccess.DesignerOf(mEditor), mContainer);
  mParent := mContainer.Parent;
  Remember(TAtlasWrapStep.Unwrapped, mEditor.FileName, mParent, mRoot, OwnedControls(mInner, mRoot));
  FState.Container := mContainer.Name;
  FState.ContainerClass := TComponentClass(mContainer.ClassType);
  FState.ContainerBounds := mContainer.BoundsRect;
  FState.ContainerTab := mContainer.TabOrder;
  KeepTemplate(mContainer, mInner);
  mOffset := ClientOffset(mContainer, mInner);
  mBounds := nil;
  for mIndex := 0 to High(FState.Children) do
  begin
    mBounds := mBounds + [TAtlasContainerWrap.OutOfContainer(FState.ChildBounds[mIndex], FState.ContainerBounds,
      mOffset)];
  end;
  MoveTo(mRoot, mParent, FState.Children, mBounds);
  DeleteComponent(mEditor, FState.Container);
  FinishUnwrap(mRoot, mParent);
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapUnwrapped, [FState.Container,
    Length(FState.Children)]));
  if Length(mHandlers) > 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerWrapHandlers, [FState.Container,
      string.Join(', ', mHandlers)]));
  end;
end;

procedure TAtlasIdeWrap.FinishUnwrap(ARoot: TComponent; AParent: TWinControl);
var
  mNames: TArray<string>;
  mTabs: TArray<Integer>;
  mStack: TArray<string>;
  mIndex: Integer;
  mName: string;
begin
  mNames := nil;
  mTabs := nil;
  for mIndex := 0 to High(FState.Children) do
  begin
    if FState.ChildTabs[mIndex] >= 0 then
    begin
      mNames := mNames + [FState.Children[mIndex]];
      mTabs := mTabs + [FState.ChildTabs[mIndex]];
    end;
  end;
  SetTabs(ARoot, mNames, TAtlasContainerWrap.UnwrapTabOrders(FState.ContainerTab, mTabs));
  mStack := nil;
  for mName in FState.Stack do
  begin
    if SameText(mName, FState.Container) then
    begin
      mStack := mStack + FState.Children;
    end
    else
    begin
      mStack := mStack + [mName];
    end;
  end;
  Restack(AParent, ARoot, mStack);
end;

function TAtlasIdeWrap.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (FState.Step <> TAtlasWrapStep.None) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FState.FileName) and (ParentByName(mRoot, FState.ParentName) <> nil);
end;

procedure TAtlasIdeWrap.UndoWrap(const AEditor: IOTAFormEditor; ARoot: TComponent);
var
  mParent: TWinControl;
begin
  mParent := ParentByName(ARoot, FState.ParentName);
  if ARoot.FindComponent(FState.Container) = nil then
  begin
    Exit;
  end;
  MoveTo(ARoot, mParent, FState.Children, FState.ChildBounds);
  DeleteComponent(AEditor, FState.Container);
  SetTabs(ARoot, FState.Children, FState.ChildTabs);
  Restack(mParent, ARoot, FState.Stack);
end;

procedure TAtlasIdeWrap.UndoUnwrap(const ADesigner: IDesigner; ARoot: TComponent);
var
  mParent, mContainer, mInner: TWinControl;
begin
  mParent := ParentByName(ARoot, FState.ParentName);
  if (ARoot.FindComponent(FState.Container) <> nil) or (FTemplate = nil) then
  begin
    Exit;
  end;
  mContainer := TWinControl(ADesigner.CreateComponent(FState.ContainerClass, mParent, 0, 0, 0, 0));
  mContainer.Name := FState.Container;
  TAtlasIdeDuplicateRow.CopyProperties(FTemplate, mContainer, True);
  mContainer.BoundsRect := FState.ContainerBounds;
  mInner := mContainer;
  if (FSheetTemplate <> nil) and (mContainer is TPageControl) then
  begin
    mInner := TWinControl(ADesigner.CreateComponent(TComponentClass(FSheetTemplate.ClassType), mContainer, 0, 0, 0,
      0));
    TTabSheet(mInner).PageControl := TPageControl(mContainer);
    mInner.Name := FState.Sheet;
    TAtlasIdeDuplicateRow.CopyProperties(FSheetTemplate, mInner, True);
  end;
  MoveTo(ARoot, mInner, FState.Children, FState.ChildBounds);
  SetTabs(ARoot, FState.Children, FState.ChildTabs);
  mContainer.TabOrder := FState.ContainerTab;
  Restack(mParent, ARoot, FState.Stack);
end;

procedure TAtlasIdeWrap.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mDesigner := TAtlasDesignerAccess.DesignerOf(mEditor);
  if mDesigner = nil then
  begin
    Exit;
  end;
  if FState.Step = TAtlasWrapStep.Wrapped then
  begin
    UndoWrap(mEditor, mRoot);
  end
  else
  begin
    UndoUnwrap(mDesigner, mRoot);
  end;
  ClearState;
  mDesigner.Modified;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerWrapUndone));
end;

end.
