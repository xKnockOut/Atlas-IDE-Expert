unit Atlas.IDE.Designer.Anchors;

// Befehl „Anchors vorschlagen …“ (#727) im Menü „Anordnen“ in der IDE: für
// die markierten Steuerelemente, ohne Auswahl für alle des Formulars. Je
// Parent rechnet TAtlasAnchorSuggest mit allen Geschwistern (für Reihen und
// Labels mit FocusControl); der Dialog (TAtlasAnchorDialog) zeigt die
// Vorschläge, solange er offen ist, auch als Umrisse mit „L T R B“ im
// Designer. „Übernehmen“ setzt die angehakten, „Anchors rückgängig“ stellt
// die alten Werte her.
// Füllend sind Steuerelemente, deren Klasse oder eine Vorfahrklasse in
// designer.suggestAnchors.fillClasses steht. Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  Vcl.Controls,
  Atlas.UI.Designer.Outlines;

type
  TAtlasIdeAnchors = class
  private
    FOnMessage: TProc<string>;
    FOutlines: TAtlasDesignerOutlines;
    FUndoFile: string;
    FUndoNames: TArray<string>;
    FUndoAnchors: TArray<TAnchors>;
    procedure Say(const AText: string);
    procedure ShowOutlines(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
    procedure HideOutlines;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure Execute;
    function CanUndo: Boolean;
    procedure Undo;
    procedure ApplyTheme;
  end;

implementation

uses
  System.Types,
  System.TypInfo,
  Vcl.Forms,
  ToolsAPI,
  Atlas.Core.Designer.Anchors,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.AnchorDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

type
  /// <summary>Eine Komponente mit Vorschlag.</summary>
  TAnchorPlan = record
    Control: TControl;
    Suggestion: TAtlasAnchorSuggestion;
  end;

function ToSet(AAnchors: TAnchors): TAtlasAnchorSet;
begin
  Result := [];
  if akLeft in AAnchors then
  begin
    Include(Result, TAtlasAnchorSide.Left);
  end;
  if akTop in AAnchors then
  begin
    Include(Result, TAtlasAnchorSide.Top);
  end;
  if akRight in AAnchors then
  begin
    Include(Result, TAtlasAnchorSide.Right);
  end;
  if akBottom in AAnchors then
  begin
    Include(Result, TAtlasAnchorSide.Bottom);
  end;
end;

function ToAnchors(ASet: TAtlasAnchorSet): TAnchors;
begin
  Result := [];
  if TAtlasAnchorSide.Left in ASet then
  begin
    Include(Result, akLeft);
  end;
  if TAtlasAnchorSide.Top in ASet then
  begin
    Include(Result, akTop);
  end;
  if TAtlasAnchorSide.Right in ASet then
  begin
    Include(Result, akRight);
  end;
  if TAtlasAnchorSide.Bottom in ASet then
  begin
    Include(Result, akBottom);
  end;
end;

function IsFill(AControl: TControl; const AClasses: TArray<string>): Boolean;
var
  mChain: TArray<string>;
  mName, mClass: string;
begin
  mChain := TAtlasDesignerAccess.ClassChain(AControl);
  for mName in mChain do
  begin
    for mClass in AClasses do
    begin
      if SameText(Trim(mClass), mName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Name des Felds bei einem Label mit FocusControl; leer ohne.</summary>
function FocusOf(AControl: TControl): string;
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

/// <summary>Vorschläge für alle Kinder von AParent, die ARoot gehören.</summary>
function PlanParent(AParent: TWinControl; ARoot: TComponent; const ASettings: TAtlasPluginSettings): TArray<TAnchorPlan>;
var
  mControls: TArray<TControl>;
  mItems: TArray<TAtlasAnchorItem>;
  mSuggestions: TArray<TAtlasAnchorSuggestion>;
  mIndex: Integer;
  mControl: TControl;
  mPlan: TAnchorPlan;
begin
  mControls := nil;
  mItems := nil;
  for mIndex := 0 to AParent.ControlCount - 1 do
  begin
    mControl := AParent.Controls[mIndex];
    if mControl.Owner <> ARoot then
    begin
      Continue;
    end;
    mControls := mControls + [mControl];
    mItems := mItems + [TAtlasAnchorItem.Create(mControl.Name, mControl.BoundsRect, mControl.Align <> alNone,
      IsFill(mControl, ASettings.DesignerSuggestAnchorsFillClasses.Split([',', ';'])), ToSet(mControl.Anchors),
      FocusOf(mControl))];
  end;
  mSuggestions := TAtlasAnchorSuggest.Suggest(mItems, TSize.Create(AParent.ClientWidth, AParent.ClientHeight),
    ASettings.DesignerSuggestAnchorsEdgeDistance, ASettings.DesignerSuggestAnchorsKeepExisting);
  Result := nil;
  for mIndex := 0 to High(mControls) do
  begin
    mPlan.Control := mControls[mIndex];
    mPlan.Suggestion := mSuggestions[mIndex];
    Result := Result + [mPlan];
  end;
end;

function Selected(AControl: TControl; const ASelected: TArray<TComponent>): Boolean;
var
  mComponent: TComponent;
begin
  Result := Length(ASelected) = 0;
  for mComponent in ASelected do
  begin
    Result := Result or (mComponent = AControl);
  end;
end;

/// <summary>Vorschläge für die Auswahl, ohne Auswahl für alle Steuerelemente des Formulars.</summary>
function PlanForm(ARoot: TWinControl; const ASelected: TArray<TComponent>): TArray<TAnchorPlan>;
var
  mSettings: TAtlasPluginSettings;
  mParents: TArray<TWinControl>;
  mParent: TWinControl;
  mPlan: TAnchorPlan;
  mIndex: Integer;
begin
  mSettings := TAtlasIdeSettings.Current;
  mParents := [ARoot];
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if ARoot.Components[mIndex] is TWinControl then
    begin
      mParents := mParents + [TWinControl(ARoot.Components[mIndex])];
    end;
  end;
  Result := nil;
  for mParent in mParents do
  begin
    for mPlan in PlanParent(mParent, ARoot, mSettings) do
    begin
      if Selected(mPlan.Control, ASelected) then
      begin
        Result := Result + [mPlan];
      end;
    end;
  end;
end;

function ReasonText(AReason: TAtlasAnchorReason): string;
const
  cIds: array [TAtlasAnchorReason] of TAtlasDesignerTextId = (TAtlasDesignerTextId.AnchorsReasonAligned,
    TAtlasDesignerTextId.AnchorsReasonExisting, TAtlasDesignerTextId.AnchorsReasonFill,
    TAtlasDesignerTextId.AnchorsReasonWideBottom, TAtlasDesignerTextId.AnchorsReasonWide,
    TAtlasDesignerTextId.AnchorsReasonBottomRight, TAtlasDesignerTextId.AnchorsReasonRight,
    TAtlasDesignerTextId.AnchorsReasonBottom, TAtlasDesignerTextId.AnchorsReasonRow,
    TAtlasDesignerTextId.AnchorsReasonField, TAtlasDesignerTextId.AnchorsReasonDefault);
begin
  Result := TAtlasDesignerStrings.Text(cIds[AReason]);
end;

function RowsOf(const APlans: TArray<TAnchorPlan>): TArray<TAtlasAnchorRow>;
var
  mPlan: TAnchorPlan;
  mRow: TAtlasAnchorRow;
begin
  Result := nil;
  for mPlan in APlans do
  begin
    mRow.Name := mPlan.Control.Name;
    mRow.Anchors := TAtlasAnchorSuggest.Text(mPlan.Suggestion.Anchors);
    mRow.Reason := ReasonText(mPlan.Suggestion.Reason);
    mRow.Offered := mPlan.Suggestion.Changed;
    Result := Result + [mRow];
  end;
end;

function OutlinesOf(const APlans: TArray<TAnchorPlan>; ARoot: TWinControl): TArray<TAtlasOutline>;
var
  mPlan: TAnchorPlan;
begin
  Result := nil;
  for mPlan in APlans do
  begin
    if mPlan.Suggestion.Changed then
    begin
      Result := Result + [TAtlasOutline.Create(TAtlasDesignerAccess.BoundsInRoot(mPlan.Control, ARoot),
        mPlan.Control.Name + ': ' + TAtlasAnchorSuggest.Text(mPlan.Suggestion.Anchors), False)];
    end;
  end;
end;

procedure SelectByName(const AName: string);
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
begin
  if TAtlasDesignerAccess.Current(mEditor, mRoot) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
  begin
    mComponent := mRoot.FindComponent(AName);
    if mComponent <> nil then
    begin
      TAtlasDesignerAccess.Select(TAtlasDesignerAccess.DesignerOf(mEditor), mRoot, [mComponent]);
    end;
  end;
end;

{ TAtlasIdeAnchors }

constructor TAtlasIdeAnchors.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeAnchors.Destroy;
begin
  FOutlines.Free;
  inherited Destroy;
end;

procedure TAtlasIdeAnchors.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeAnchors.ShowOutlines(ARoot: TWinControl; const AOutlines: TArray<TAtlasOutline>);
var
  mArea: TRect;
begin
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea := ARoot.ClientRect;
  mArea.Offset(ARoot.ClientOrigin);
  FOutlines.ShowOutlines(mArea, AOutlines);
end;

procedure TAtlasIdeAnchors.HideOutlines;
begin
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

procedure TAtlasIdeAnchors.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

procedure TAtlasIdeAnchors.Execute;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mPlans: TArray<TAnchorPlan>;
  mChecked: TArray<Boolean>;
  mIndex: Integer;
  mAccepted: Boolean;
begin
  if not TAtlasIdeSettings.Current.DesignerSuggestAnchors or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    not (mRoot is TWinControl) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  mPlans := PlanForm(TWinControl(mRoot), TAtlasDesignerAccess.Selection(mEditor, mRoot));
  if Length(mPlans) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsNone));
    Exit;
  end;
  ShowOutlines(TWinControl(mRoot), OutlinesOf(mPlans, TWinControl(mRoot)));
  try
    mAccepted := TAtlasAnchorDialog.Execute(RowsOf(mPlans), SelectByName, mChecked);
  finally
    HideOutlines;
  end;
  if not mAccepted then
  begin
    Exit;
  end;
  FUndoFile := mEditor.FileName;
  FUndoNames := nil;
  FUndoAnchors := nil;
  for mIndex := 0 to High(mPlans) do
  begin
    if (mIndex <= High(mChecked)) and mChecked[mIndex] then
    begin
      FUndoNames := FUndoNames + [mPlans[mIndex].Control.Name];
      FUndoAnchors := FUndoAnchors + [mPlans[mIndex].Control.Anchors];
      mPlans[mIndex].Control.Anchors := ToAnchors(mPlans[mIndex].Suggestion.Anchors);
    end;
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerAnchorsDone, [Length(FUndoNames)]));
end;

function TAtlasIdeAnchors.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FUndoNames) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FUndoFile);
end;

procedure TAtlasIdeAnchors.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mIndex: Integer;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  for mIndex := 0 to High(FUndoNames) do
  begin
    mComponent := mRoot.FindComponent(FUndoNames[mIndex]);
    if mComponent is TControl then
    begin
      TControl(mComponent).Anchors := FUndoAnchors[mIndex];
    end;
  end;
  FUndoNames := nil;
  FUndoAnchors := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerAnchorsUndone));
end;

end.
