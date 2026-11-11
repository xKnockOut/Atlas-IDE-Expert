unit Atlas.IDE.Designer.InsertSpace;

// Befehle „Platz einfügen …“ und „Platz entfernen …“ (#740) im Menü
// „Anordnen“ in der IDE. Die Linie liegt an der Ober- (Zeilen) bzw. linken
// Kante (Spalten) der Auswahl im Elternelement der ersten Auswahl; die neue
// Lage rechnet TAtlasInsertSpace Ebene für Ebene:
// - Wächst bzw. schrumpft der Parent, geht es eine Ebene höher weiter: Linie
//   an seiner alten Unterkante, Betrag = sein Wachstum, bis zum Formular
//   (ClientHeight bzw. ClientWidth). Füllt der Parent seinen Parent entlang
//   der Achse (alClient, quer ausgerichtet), wächst gleich dieser.
// - Erst wachsen die Parents, dann bekommen alle Steuerelemente ohne Align
//   ihre Lage ausdrücklich: Anker hätten sie beim Wachsen sonst mitgezogen.
// - Rückgängig: „Platz rückgängig“ setzt Lage und Größe aller
//   Steuerelemente und des Formulars auf den Stand vor dem Befehl
//   (TAtlasDesignerSnapshot).
// Der Betrag rastet am Raster des Designers ein (Umgebungsoptionen
// GridSizeX/GridSizeY, sonst cDefaultGrid). Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.IDE.Designer.Snapshot;

type
  TAtlasIdeInsertSpace = class
  private
    FOnMessage: TProc<string>;
    /// <summary>Stand vor dem letzten Befehl.</summary>
    FSnapshot: TAtlasDesignerSnapshot;
    procedure Say(const AText: string);
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Steuerelemente unter ASelected (Geschwister des ersten).</summary>
    class function Candidates(const ASelected: TArray<TComponent>): TArray<TControl>; static;
    /// <summary>Dialog zeigen und Platz einfügen bzw. (ARemove) entfernen.</summary>
    procedure Execute(ARemove: Boolean);
    function CanUndo: Boolean;
    procedure Undo;
  end;

implementation

uses
  System.Math,
  System.TypInfo,
  System.Variants,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.InsertSpace,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.SpaceDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cDefaultGrid = 8;

type
  /// <summary>Ein Lauf: Formular, Achse, Wachsen erlaubt und gesammelte Hinweise.</summary>
  TSpaceRun = record
    Root: TComponent;
    Axis: TAtlasSpaceAxis;
    Grow: Boolean;
    Untouched: TArray<string>;
  end;

function AlignOf(AControl: TControl; AAxis: TAtlasSpaceAxis): TAtlasSpaceAlign;
begin
  Result := TAtlasSpaceAlign.None;
  case AControl.Align of
    alClient:
      Result := TAtlasSpaceAlign.Fill;
    alTop, alBottom:
      if AAxis = TAtlasSpaceAxis.Rows then
      begin
        Result := TAtlasSpaceAlign.Near;
        if AControl.Align = alBottom then
        begin
          Result := TAtlasSpaceAlign.Far;
        end;
      end
      else
      begin
        Result := TAtlasSpaceAlign.Across;
      end;
    alLeft, alRight:
      if AAxis = TAtlasSpaceAxis.Columns then
      begin
        Result := TAtlasSpaceAlign.Near;
        if AControl.Align = alRight then
        begin
          Result := TAtlasSpaceAlign.Far;
        end;
      end
      else
      begin
        Result := TAtlasSpaceAlign.Across;
      end;
  end;
end;

function StretchOf(AControl: TControl; AAxis: TAtlasSpaceAxis): Boolean;
begin
  if AAxis = TAtlasSpaceAxis.Rows then
  begin
    Result := [akTop, akBottom] <= AControl.Anchors;
  end
  else
  begin
    Result := [akLeft, akRight] <= AControl.Anchors;
  end;
end;

function HiOf(const ARect: TRect; AAxis: TAtlasSpaceAxis): Integer;
begin
  Result := ARect.Bottom;
  if AAxis = TAtlasSpaceAxis.Columns then
  begin
    Result := ARect.Right;
  end;
end;

/// <summary>Kinder von AParent, die zum Formular gehören, ohne AExclude.</summary>
function ChildrenOf(AParent: TWinControl; ARoot: TComponent; AExclude: TControl): TArray<TControl>;
var
  mIndex: Integer;
begin
  Result := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    if (AParent.Controls[mIndex] <> AExclude) and (AParent.Controls[mIndex].Owner = ARoot) then
    begin
      Result := Result + [AParent.Controls[mIndex]];
    end;
  end;
end;

procedure ApplyLevel(var ARun: TSpaceRun; AParent: TWinControl; ALine, AAmount: Integer; AExclude: TControl);
  forward;

/// <summary>AContainer entlang der Achse um AGrow vergrößern; geht nach oben weiter.</summary>
procedure GrowContainer(var ARun: TSpaceRun; AContainer: TWinControl; AGrow: Integer);
var
  mOldHi: Integer;
begin
  if AContainer = ARun.Root then
  begin
    if (AContainer is TCustomForm) and (ARun.Axis = TAtlasSpaceAxis.Rows) then
    begin
      TCustomForm(AContainer).ClientHeight := TCustomForm(AContainer).ClientHeight + AGrow;
    end
    else if AContainer is TCustomForm then
    begin
      TCustomForm(AContainer).ClientWidth := TCustomForm(AContainer).ClientWidth + AGrow;
    end
    else if ARun.Axis = TAtlasSpaceAxis.Rows then
    begin
      AContainer.Height := AContainer.Height + AGrow;
    end
    else
    begin
      AContainer.Width := AContainer.Width + AGrow;
    end;
    Exit;
  end;
  if AContainer.Parent = nil then
  begin
    Exit;
  end;
  if AlignOf(AContainer, ARun.Axis) in [TAtlasSpaceAlign.Fill, TAtlasSpaceAlign.Across] then
  begin
    // Füllt seinen Parent entlang der Achse: der Parent wächst.
    GrowContainer(ARun, AContainer.Parent, AGrow);
    Exit;
  end;
  mOldHi := HiOf(AContainer.BoundsRect, ARun.Axis);
  if ARun.Axis = TAtlasSpaceAxis.Rows then
  begin
    AContainer.Height := AContainer.Height + AGrow;
  end
  else
  begin
    AContainer.Width := AContainer.Width + AGrow;
  end;
  ApplyLevel(ARun, AContainer.Parent, mOldHi, AGrow, AContainer);
end;

procedure ApplyLevel(var ARun: TSpaceRun; AParent: TWinControl; ALine, AAmount: Integer; AExclude: TControl);
var
  mControls: TArray<TControl>;
  mItems: TArray<TAtlasSpaceItem>;
  mResult: TAtlasSpaceResult;
  mIndex: Integer;
begin
  mControls := ChildrenOf(AParent, ARun.Root, AExclude);
  mItems := nil;
  for mIndex := 0 to High(mControls) do
  begin
    mItems := mItems + [TAtlasSpaceItem.Create(mControls[mIndex].BoundsRect, AlignOf(mControls[mIndex], ARun.Axis),
      StretchOf(mControls[mIndex], ARun.Axis))];
  end;
  mResult := TAtlasInsertSpace.Apply(mItems, ARun.Axis, ALine, AAmount, AParent.ClientRect, ARun.Grow);
  if mResult.Grow <> 0 then
  begin
    GrowContainer(ARun, AParent, mResult.Grow);
  end;
  for mIndex := 0 to High(mControls) do
  begin
    if mItems[mIndex].Align = TAtlasSpaceAlign.None then
    begin
      mControls[mIndex].BoundsRect := mResult.Bounds[mIndex];
    end;
  end;
  for mIndex in mResult.Untouched do
  begin
    ARun.Untouched := ARun.Untouched + [mControls[mIndex].Name];
  end;
end;

/// <summary>Raster des Designers aus den Umgebungsoptionen; cDefaultGrid, wenn die IDE keins nennt.</summary>
function GridOf(AAxis: TAtlasSpaceAxis): Integer;
var
  mServices: IOTAServices;
  mOptions: IOTAEnvironmentOptions;
  mName: string;
  mOption: TOTAOptionName;
begin
  Result := cDefaultGrid;
  if not Supports(BorlandIDEServices, IOTAServices, mServices) then
  begin
    Exit;
  end;
  mOptions := mServices.GetEnvironmentOptions;
  if mOptions = nil then
  begin
    Exit;
  end;
  mName := 'GridSizeY';
  if AAxis = TAtlasSpaceAxis.Columns then
  begin
    mName := 'GridSizeX';
  end;
  for mOption in mOptions.GetOptionNames do
  begin
    if SameText(mOption.Name, mName) and (mOption.Kind in [tkInteger, tkInt64]) then
    begin
      Result := StrToIntDef(VarToStr(mOptions.Values[mName]), cDefaultGrid);
      Exit;
    end;
  end;
end;

/// <summary>Kante der Auswahl entlang der Achse.</summary>
function LineOf(const AControls: TArray<TControl>; AAxis: TAtlasSpaceAxis): Integer;
var
  mControl: TControl;
begin
  Result := MaxInt;
  for mControl in AControls do
  begin
    if AAxis = TAtlasSpaceAxis.Rows then
    begin
      Result := Min(Result, mControl.Top);
    end
    else
    begin
      Result := Min(Result, mControl.Left);
    end;
  end;
end;

{ TAtlasIdeInsertSpace }

constructor TAtlasIdeInsertSpace.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FSnapshot := TAtlasDesignerSnapshot.Create;
end;

destructor TAtlasIdeInsertSpace.Destroy;
begin
  FSnapshot.Free;
  inherited Destroy;
end;

procedure TAtlasIdeInsertSpace.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

class function TAtlasIdeInsertSpace.Candidates(const ASelected: TArray<TComponent>): TArray<TControl>;
var
  mComponent: TComponent;
  mParent: TWinControl;
begin
  Result := nil;
  mParent := nil;
  for mComponent in ASelected do
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

procedure TAtlasIdeInsertSpace.Execute(ARemove: Boolean);
var
  mEditor: IOTAFormEditor;
  mRun: TSpaceRun;
  mControls: TArray<TControl>;
  mOptions: TAtlasSpaceOptions;
  mAmount: Integer;
begin
  if not TAtlasIdeSettings.Current.DesignerInsertSpace or not TAtlasDesignerAccess.Current(mEditor, mRun.Root) then
  begin
    Exit;
  end;
  mControls := Candidates(TAtlasDesignerAccess.Selection(mEditor, mRun.Root));
  if (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) or (Length(mControls) = 0) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceNoSelection));
    Exit;
  end;
  mOptions.Axis := TAtlasSpaceAxis.Rows;
  mOptions.Amount := cDefaultGrid * 3;
  mOptions.Snap := True;
  if not TAtlasSpaceDialog.Execute(ARemove, mOptions) or (mOptions.Amount = 0) then
  begin
    Exit;
  end;
  mAmount := mOptions.Amount;
  if mOptions.Snap then
  begin
    mAmount := Max(TAtlasInsertSpace.Snap(mAmount, GridOf(mOptions.Axis)), 1);
  end;
  if ARemove then
  begin
    mAmount := -mAmount;
  end;
  mRun.Axis := mOptions.Axis;
  mRun.Grow := TAtlasIdeSettings.Current.DesignerInsertSpaceGrowParent;
  mRun.Untouched := nil;
  FSnapshot.Take(mEditor.FileName, mRun.Root);
  ApplyLevel(mRun, mControls[0].Parent, LineOf(mControls, mRun.Axis), mAmount, nil);
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSpaceDone, [mAmount, mControls[0].Parent.Name]));
  if Length(mRun.Untouched) > 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSpaceUntouched, [string.Join(', ', mRun.Untouched)]));
  end;
end;

function TAtlasIdeInsertSpace.CanUndo: Boolean;
begin
  Result := FSnapshot.CanRestore;
end;

procedure TAtlasIdeInsertSpace.Undo;
begin
  if FSnapshot.Restore then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSpaceUndone));
  end;
end;

end.
