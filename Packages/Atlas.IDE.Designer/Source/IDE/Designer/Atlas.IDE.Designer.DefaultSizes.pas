unit Atlas.IDE.Designer.DefaultSizes;

// Standardgrößen je Komponentenklasse (#747) in der IDE: Untermenü
// „Standardgröße“ im Menü „Anordnen“ und Anwenden beim Ablegen. Tabelle,
// Auflösung mit Nachfahren und Lage rechnet TAtlasDefaultSizes.
// - „Standardgröße setzen“: markierte Komponenten, ohne Auswahl alle des
//   Formulars, mit Eintrag in designer.defaultSizes.table; je Parent bleiben
//   Reihen an ihrer Kante und Abstände gleich. Align ändert nur die freie
//   Richtung, AutoSize wird übergangen. „text“ misst wie „Breite nach Text“
//   (TAtlasIdeFitText). „Standardgröße rückgängig“ setzt den Stand davor
//   zurück (TAtlasDesignerSnapshot).
// - „Tabelle aus Formular übernehmen“: häufigste Größe je Klasse des
//   Formulars; vorhandene Einträge anderer Klassen bleiben.
// - „Abweichungen anzeigen“ (designer.defaultSizes.markDeviations): rahmt
//   einige Sekunden alle Komponenten mit anderer Größe ein, mit Soll und Ist.
// - Beim Ablegen (designer.defaultSizes.applyOnInsert): IDesignNotification
//   meldet die neue Komponente; nach dem laufenden Ereignis bekommt sie die
//   Standardgröße, sofern sie noch die Größe hat, die ihre Klasse im
//   Konstruktor setzt (ein aufgezogener Rahmen bleibt).
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  System.Generics.Collections,
  Vcl.Controls,
  Vcl.ExtCtrls,
  DesignIntf,
  Atlas.UI.Designer.Outlines,
  Atlas.IDE.Designer.Snapshot;

type
{$SCOPEDENUMS ON}
  TAtlasSizesCommand = (Apply, Learn, Show, Undo);
{$SCOPEDENUMS OFF}

  TAtlasIdeDefaultSizes = class
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TAtlasIdeDefaultSizes;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;
  public const
    cShowMilliseconds = 8000;
  private class var
    FCurrent: TAtlasIdeDefaultSizes;
  private
    FOnMessage: TProc<string>;
    FSnapshot: TAtlasDesignerSnapshot;
    FOutlines: TAtlasDesignerOutlines;
    FTimer: TTimer;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    /// <summary>Größe, die eine Klasse im Konstruktor setzt.</summary>
    FClassSizes: TDictionary<TClass, TSize>;
    procedure Say(const AText: string);
    procedure TimerTick(Sender: TObject);
    procedure HideOutlines;
    procedure Inserted(AItem: TPersistent);
    procedure ApplyInserted(ARoot: TComponent; const AName: string);
    function ClassSize(AControl: TControl): TSize;
    procedure DoApply;
    procedure DoLearn;
    procedure DoShow;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure Execute(ACommand: TAtlasSizesCommand);
    function CanUndo: Boolean;
    procedure ApplyTheme;
  end;

implementation

uses
  ToolsAPI,
  Vcl.Forms,
  Atlas.Core.Designer.DefaultSizes,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Diagnostics.MainThread,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.FitText,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

type
  /// <summary>Zugang zu AutoSize (geschützt in TControl).</summary>
  TControlAccess = class(TControl);

function Table: TArray<TAtlasSizeEntry>;
begin
  Result := TAtlasDefaultSizes.Parse(TAtlasIdeSettings.Current.DesignerDefaultSizesTable);
end;

function Covered(AControl: TControl; const ATable: TArray<TAtlasSizeEntry>; out AEntry: TAtlasSizeEntry): Boolean;
begin
  Result := TAtlasDefaultSizes.Resolve(ATable, TAtlasDesignerAccess.ClassChain(AControl), AEntry);
end;

/// <summary>Sollgröße von AControl nach AEntry (-1 = bleibt); Align lässt nur die freie Richtung.</summary>
function TargetOf(AControl: TControl; const AEntry: TAtlasSizeEntry; ARoot: TComponent): TSize;
var
  mText: Integer;
begin
  mText := -1;
  if AEntry.Width.Kind = TAtlasSizeKind.Text then
  begin
    mText := TAtlasIdeFitText.CommonWidth([AControl], ARoot);
  end;
  Result := TSize.Create(TAtlasDefaultSizes.Target(AEntry.Width, mText),
    TAtlasDefaultSizes.Target(AEntry.Height, -1));
  if AControl.Align in [alTop, alBottom, alClient] then
  begin
    Result.cx := -1;
  end;
  if AControl.Align in [alLeft, alRight, alClient] then
  begin
    Result.cy := -1;
  end;
end;

function ItemOf(AControl: TControl; const ATarget: TSize): TAtlasSizeItem;
begin
  Result := TAtlasSizeItem.Create(AControl.BoundsRect, ATarget.cx, ATarget.cy,
    (akRight in AControl.Anchors) and not (akLeft in AControl.Anchors),
    (akBottom in AControl.Anchors) and not (akTop in AControl.Anchors));
end;

/// <summary>Markierte Steuerelemente, ohne Auswahl alle des Formulars.</summary>
function Targets(const AEditor: IOTAFormEditor; ARoot: TComponent): TArray<TControl>;
var
  mSelected: TArray<TComponent>;
  mIndex: Integer;
begin
  Result := nil;
  mSelected := TAtlasDesignerAccess.Selection(AEditor, ARoot);
  if Length(mSelected) = 0 then
  begin
    for mIndex := 0 to ARoot.ComponentCount - 1 do
    begin
      mSelected := mSelected + [ARoot.Components[mIndex]];
    end;
  end;
  for mIndex := 0 to High(mSelected) do
  begin
    if (mSelected[mIndex] is TControl) and (TControl(mSelected[mIndex]).Parent <> nil) then
    begin
      Result := Result + [TControl(mSelected[mIndex])];
    end;
  end;
end;

/// <summary>Steuerelemente von AControls mit dem Parent AParent.</summary>
function ChildrenOf(const AControls: TArray<TControl>; AParent: TWinControl): TArray<TControl>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    if mControl.Parent = AParent then
    begin
      Result := Result + [mControl];
    end;
  end;
end;

/// <summary>Standardgröße für AControls (Geschwister) setzen; Anzahl geänderter.</summary>
function ApplyGroup(const AControls: TArray<TControl>; const ATable: TArray<TAtlasSizeEntry>;
  ARoot: TComponent): Integer;
var
  mItems: TArray<TAtlasSizeItem>;
  mRects: TArray<TRect>;
  mEntry: TAtlasSizeEntry;
  mIndex: Integer;
begin
  mItems := nil;
  for mIndex := 0 to High(AControls) do
  begin
    Covered(AControls[mIndex], ATable, mEntry);
    mItems := mItems + [ItemOf(AControls[mIndex], TargetOf(AControls[mIndex], mEntry, ARoot))];
  end;
  mRects := TAtlasDefaultSizes.Layout(mItems, AControls[0].Parent.ClientWidth);
  Result := 0;
  for mIndex := 0 to High(AControls) do
  begin
    if AControls[mIndex].BoundsRect <> mRects[mIndex] then
    begin
      AControls[mIndex].BoundsRect := mRects[mIndex];
      Inc(Result);
    end;
  end;
end;

{ TAtlasIdeDefaultSizes.TNotification }

procedure TAtlasIdeDefaultSizes.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
end;

procedure TAtlasIdeDefaultSizes.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Inserted(AItem);
  end;
end;

procedure TAtlasIdeDefaultSizes.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
end;

procedure TAtlasIdeDefaultSizes.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
end;

procedure TAtlasIdeDefaultSizes.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
end;

procedure TAtlasIdeDefaultSizes.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
begin
end;

{ TAtlasIdeDefaultSizes }

constructor TAtlasIdeDefaultSizes.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
  FSnapshot := TAtlasDesignerSnapshot.Create;
  FClassSizes := TDictionary<TClass, TSize>.Create;
  FTimer := TTimer.Create(nil);
  FTimer.Enabled := False;
  FTimer.Interval := cShowMilliseconds;
  FTimer.OnTimer := TimerTick;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FCurrent := Self;
end;

destructor TAtlasIdeDefaultSizes.Destroy;
begin
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  if FNotification <> nil then
  begin
    FNotification.FOwner := nil;
    UnregisterDesignNotification(FNotificationRef);
    FNotificationRef := nil;
  end;
  FTimer.Free;
  FOutlines.Free;
  FClassSizes.Free;
  FSnapshot.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDefaultSizes.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeDefaultSizes.TimerTick(Sender: TObject);
begin
  HideOutlines;
end;

procedure TAtlasIdeDefaultSizes.HideOutlines;
begin
  FTimer.Enabled := False;
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

procedure TAtlasIdeDefaultSizes.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

function TAtlasIdeDefaultSizes.CanUndo: Boolean;
begin
  Result := FSnapshot.CanRestore;
end;

function TAtlasIdeDefaultSizes.ClassSize(AControl: TControl): TSize;
var
  mFresh: TControl;
begin
  if FClassSizes.TryGetValue(AControl.ClassType, Result) then
  begin
    Exit;
  end;
  mFresh := TControlClass(AControl.ClassType).Create(nil);
  try
    Result := TSize.Create(mFresh.Width, mFresh.Height);
  finally
    mFresh.Free;
  end;
  FClassSizes.Add(AControl.ClassType, Result);
end;

procedure TAtlasIdeDefaultSizes.Inserted(AItem: TPersistent);
var
  mSettings: TAtlasPluginSettings;
  mOwner: TAtlasIdeDefaultSizes;
  mRoot: TComponent;
  mName: string;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not mSettings.DesignerDefaultSizes or not mSettings.DesignerDefaultSizesApplyOnInsert or
    not (AItem is TControl) or (TControl(AItem).Owner = nil) then
  begin
    Exit;
  end;
  // Erst nach dem laufenden Ereignis: Dann hat der Designer Lage und Größe gesetzt.
  mOwner := Self;
  mRoot := TControl(AItem).Owner;
  mName := TControl(AItem).Name;
  TAtlasMainThread.ForceQueue(TAtlasFeature.DesignerBar,
    procedure
    begin
      if FCurrent = mOwner then
      begin
        TAtlasGuard.Run(TAtlasFeature.DesignerBar,
          procedure
          begin
            mOwner.ApplyInserted(mRoot, mName);
          end);
      end;
    end);
end;

procedure TAtlasIdeDefaultSizes.ApplyInserted(ARoot: TComponent; const AName: string);
var
  mEditor: IOTAFormEditor;
  mCurrent, mComponent: TComponent;
  mControl: TControl;
  mEntry: TAtlasSizeEntry;
  mSize: TSize;
begin
  // ARoot nur vergleichen: Das Formular kann inzwischen geschlossen sein.
  if (AName = '') or not TAtlasDesignerAccess.Current(mEditor, mCurrent) or (mCurrent <> ARoot) then
  begin
    Exit;
  end;
  mComponent := mCurrent.FindComponent(AName);
  if not (mComponent is TControl) or (TControl(mComponent).Parent = nil) or
    not Covered(TControl(mComponent), Table, mEntry) then
  begin
    Exit;
  end;
  mControl := TControl(mComponent);
  // Eingebettete Frames laden im Konstruktor ihre DFM: keine Probe-Instanz.
  if (csInline in mControl.ComponentState) or (mControl is TCustomFrame) then
  begin
    Exit;
  end;
  mSize := ClassSize(mControl);
  if TControlAccess(mControl).AutoSize or (mControl.Width <> mSize.cx) or (mControl.Height <> mSize.cy) then
  begin
    Exit;
  end;
  if (ApplyGroup([mControl], Table, mCurrent) > 0) and (TAtlasDesignerAccess.DesignerOf(mEditor) <> nil) then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesInserted, [mControl.Name, mControl.Width,
      mControl.Height]));
  end;
end;

procedure TAtlasIdeDefaultSizes.DoApply;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mTable: TArray<TAtlasSizeEntry>;
  mControls, mCovered, mParents: TArray<TControl>;
  mControl: TControl;
  mEntry: TAtlasSizeEntry;
  mSkipped: TArray<string>;
  mCount: Integer;
begin
  mTable := Table;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Exit;
  end;
  if Length(mTable) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesNoTable));
    Exit;
  end;
  mControls := Targets(mEditor, mRoot);
  mCovered := nil;
  mSkipped := nil;
  mParents := nil;
  for mControl in mControls do
  begin
    if not Covered(mControl, mTable, mEntry) then
    begin
      Continue;
    end;
    if TControlAccess(mControl).AutoSize then
    begin
      mSkipped := mSkipped + [mControl.Name];
      Continue;
    end;
    mCovered := mCovered + [mControl];
  end;
  if Length(mCovered) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesNone));
    Exit;
  end;
  FSnapshot.Take(mEditor.FileName, mRoot);
  mCount := 0;
  for mControl in mCovered do
  begin
    if Length(ChildrenOf(mParents, mControl.Parent)) = 0 then
    begin
      mParents := mParents + [mControl];
      Inc(mCount, ApplyGroup(ChildrenOf(mCovered, mControl.Parent), mTable, mRoot));
    end;
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesDone, [mCount]));
  if Length(mSkipped) > 0 then
  begin
    Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesSkipped, [string.Join(', ', mSkipped)]));
  end;
end;

/// <summary>AOld mit den Einträgen von ANew; Klassen aus ANew ersetzen die alten.</summary>
function Merged(const AOld, ANew: TArray<TAtlasSizeEntry>): TArray<TAtlasSizeEntry>;
var
  mOld, mNew: TAtlasSizeEntry;
  mReplaced: Boolean;
begin
  Result := nil;
  for mOld in AOld do
  begin
    mReplaced := False;
    for mNew in ANew do
    begin
      mReplaced := mReplaced or SameText(mOld.ClassName, mNew.ClassName);
    end;
    if not mReplaced then
    begin
      Result := Result + [mOld];
    end;
  end;
  Result := Result + ANew;
end;

procedure TAtlasIdeDefaultSizes.DoLearn;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSamples: TArray<TAtlasSizeSample>;
  mLearned: TArray<TAtlasSizeEntry>;
  mSettings: TAtlasPluginSettings;
  mIndex: Integer;
  mControl: TControl;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSamples := nil;
  for mIndex := 0 to mRoot.ComponentCount - 1 do
  begin
    if not (mRoot.Components[mIndex] is TControl) then
    begin
      Continue;
    end;
    mControl := TControl(mRoot.Components[mIndex]);
    if (mControl.Align = alNone) and not TControlAccess(mControl).AutoSize then
    begin
      mSamples := mSamples + [TAtlasSizeSample.Create(mControl.ClassName, mControl.Width, mControl.Height)];
    end;
  end;
  mLearned := TAtlasDefaultSizes.Learn(mSamples);
  if Length(mLearned) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesNone));
    Exit;
  end;
  mSettings := TAtlasIdeSettings.Stored;
  mSettings.DesignerDefaultSizesTable := TAtlasDefaultSizes.ToText(Merged(TAtlasDefaultSizes.Parse(
    mSettings.DesignerDefaultSizesTable), mLearned));
  TAtlasIdeSettings.Update(mSettings);
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesLearned, [TAtlasDefaultSizes.ToText(mLearned)]));
end;

function SizeText(ATarget, AActual: Integer): string;
begin
  Result := IntToStr(AActual);
  if ATarget > 0 then
  begin
    Result := IntToStr(ATarget);
  end;
end;

/// <summary>Rahmen um jedes Steuerelement von ARoot, dessen Größe von der Standardgröße abweicht.</summary>
function Deviations(ARoot: TWinControl; const ATable: TArray<TAtlasSizeEntry>): TArray<TAtlasOutline>;
var
  mIndex: Integer;
  mControl: TControl;
  mEntry: TAtlasSizeEntry;
  mTarget: TSize;
begin
  Result := nil;
  for mIndex := 0 to ARoot.ComponentCount - 1 do
  begin
    if not (ARoot.Components[mIndex] is TControl) then
    begin
      Continue;
    end;
    mControl := TControl(ARoot.Components[mIndex]);
    if (mControl.Parent = nil) or TControlAccess(mControl).AutoSize or not Covered(mControl, ATable, mEntry) then
    begin
      Continue;
    end;
    mTarget := TargetOf(mControl, mEntry, ARoot);
    if ((mTarget.cx > 0) and (mTarget.cx <> mControl.Width)) or ((mTarget.cy > 0) and (mTarget.cy <> mControl.Height))
      then
    begin
      Result := Result + [TAtlasOutline.Create(TAtlasDesignerAccess.BoundsInRoot(mControl, ARoot),
        mControl.Name + ': ' + TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesTarget,
        [SizeText(mTarget.cx, mControl.Width), SizeText(mTarget.cy, mControl.Height)]), True)];
    end;
  end;
end;

procedure TAtlasIdeDefaultSizes.DoShow;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mOutlines: TArray<TAtlasOutline>;
  mArea: TRect;
begin
  HideOutlines;
  if not TAtlasIdeSettings.Current.DesignerDefaultSizesMarkDeviations or
    not TAtlasDesignerAccess.Current(mEditor, mRoot) or not (mRoot is TWinControl) then
  begin
    Exit;
  end;
  mOutlines := Deviations(TWinControl(mRoot), Table);
  if Length(mOutlines) = 0 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesNoDeviations));
    Exit;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerSizesDeviations, [Length(mOutlines)]));
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea := TWinControl(mRoot).ClientRect;
  mArea.Offset(TWinControl(mRoot).ClientOrigin);
  FOutlines.ShowOutlines(mArea, mOutlines);
  FTimer.Enabled := True;
end;

procedure TAtlasIdeDefaultSizes.Execute(ACommand: TAtlasSizesCommand);
begin
  if not TAtlasIdeSettings.Current.DesignerDefaultSizes then
  begin
    Exit;
  end;
  case ACommand of
    TAtlasSizesCommand.Apply:
      DoApply;
    TAtlasSizesCommand.Learn:
      DoLearn;
    TAtlasSizesCommand.Show:
      DoShow;
    TAtlasSizesCommand.Undo:
      if FSnapshot.Restore then
      begin
        Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerSizesUndone));
      end;
  end;
end;

end.
