unit Atlas.IDE.Designer.DuplicateRow;

// Befehl „In Reihe duplizieren …“ (#736) im Menü „Anordnen“ in der IDE: die
// markierten Steuerelemente (Geschwister der ersten Auswahl) werden mehrmals
// nach unten oder rechts kopiert. Lage, Namen, Captions, TabOrder und
// Verweise rechnet TAtlasDuplicateRow; hier entstehen die Kopien über
// IDesigner.CreateComponent (der Designer legt die Felder an).
// - Eigenschaften: alle gespeicherten veröffentlichten außer Name, Lage und
//   TabOrder; Ereignis-Handler nur mit „Ereignis-Handler teilen“. Kinder von
//   Containern werden mitkopiert.
// - Verweise auf ein anderes Steuerelement der Auswahl (FocusControl) zeigen
//   in der Kopie auf dessen Kopie.
// - Vorschau: Umrisse der Kopien über dem Elternelement, live beim Ändern im
//   Dialog (TAtlasDesignerOutlines).
// - Rückgängig: „Duplizieren rückgängig“ entfernt alle Kopien des letzten
//   Laufs und schiebt verschobene Steuerelemente zurück.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Types,
  Vcl.Controls,
  Atlas.UI.Designer.Outlines;

type
  TAtlasIdeDuplicateRow = class
  private
    FOnMessage: TProc<string>;
    FOutlines: TAtlasDesignerOutlines;
    /// <summary>Letzter Lauf: Datei, angelegte Kopien und verschobene Steuerelemente mit alter Lage.</summary>
    FLastFile: string;
    FCreated: TArray<string>;
    FMoved: TArray<string>;
    FMovedFrom: TArray<TRect>;
    procedure Say(const AText: string);
    procedure ShowOutlines(AParent: TWinControl; const AOutlines: TArray<TAtlasOutline>);
    procedure HideOutlines;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    /// <summary>Steuerelemente unter ASelected (Geschwister des ersten).</summary>
    class function Candidates(const ASelected: TArray<TComponent>): TArray<TControl>; static;
    /// <summary>Gibt es einen Lauf im aktiven Designer, der sich zurücknehmen lässt?</summary>
    function CanUndo: Boolean;
    /// <summary>Dialog zeigen und die Kopien anlegen.</summary>
    procedure Execute;
    /// <summary>Kopien des letzten Laufs entfernen.</summary>
    procedure Undo;
    procedure ApplyTheme;
  end;

implementation

uses
  Winapi.Windows,
  System.TypInfo,
  Vcl.Forms,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.DuplicateRow,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.DuplicateDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.EditorStyle,
  Atlas.IDE.Foundation.Settings;

const
  cDefaultPpi = 96;

type
  /// <summary>Eine Kopie: Originale und ihre Kopien in gleicher Reihenfolge (samt Kindern).</summary>
  TCopyGroup = record
    Originals: TArray<TComponent>;
    Copies: TArray<TComponent>;
  end;

  /// <summary>Ein Lauf: Formular, Designer, Auswahl und die Rechnung aus den Optionen.</summary>
  TDuplicateRun = record
    Root: TComponent;
    Designer: IDesigner;
    Controls: TArray<TControl>;
    Others: TArray<TControl>;
    Options: TAtlasDuplicateOptions;
    function Entries: TArray<string>;
    function Count: Integer;
    function Request: TAtlasDuplicateRequest;
    function Taken: TArray<string>;
    function ControlNames: TArray<string>;
  end;

{ TDuplicateRun }

function TDuplicateRun.Entries: TArray<string>;
begin
  Result := TAtlasDuplicateRow.ParseList(Options.List);
end;

function TDuplicateRun.Count: Integer;
begin
  Result := TAtlasDuplicateRow.CopyCount(Entries, Options.Count);
end;

function RectsOf(const AControls: TArray<TControl>): TArray<TRect>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    Result := Result + [mControl.BoundsRect];
  end;
end;

function TDuplicateRun.Request: TAtlasDuplicateRequest;
begin
  Result.Group := TAtlasDuplicateRow.UnionOf(RectsOf(Controls));
  Result.Client := Controls[0].Parent.ClientRect;
  Result.Others := RectsOf(Others);
  Result.Direction := Options.Direction;
  Result.Gap := Options.Gap;
  Result.Count := Count;
  Result.Push := Options.Push;
end;

function TDuplicateRun.Taken: TArray<string>;
var
  mIndex: Integer;
begin
  Result := [Root.Name];
  for mIndex := 0 to Root.ComponentCount - 1 do
  begin
    Result := Result + [Root.Components[mIndex].Name];
  end;
end;

function TDuplicateRun.ControlNames: TArray<string>;
var
  mControl: TControl;
begin
  Result := nil;
  for mControl in Controls do
  begin
    Result := Result + [mControl.Name];
  end;
end;

function Contains(const AControls: TArray<TControl>; AControl: TControl): Boolean;
var
  mControl: TControl;
begin
  for mControl in AControls do
  begin
    if mControl = AControl then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

function SiblingsOf(const AControls: TArray<TControl>; ARoot: TComponent): TArray<TControl>;
var
  mParent: TWinControl;
  mIndex: Integer;
begin
  Result := nil;
  mParent := AControls[0].Parent;
  for mIndex := 0 to mParent.ControlCount - 1 do
  begin
    if (mParent.Controls[mIndex].Owner = ARoot) and not Contains(AControls, mParent.Controls[mIndex]) then
    begin
      Result := Result + [mParent.Controls[mIndex]];
    end;
  end;
end;

{ Eigenschaften kopieren }

function Skipped(const AName: string): Boolean;
begin
  Result := SameText(AName, 'Name') or SameText(AName, 'Left') or SameText(AName, 'Top') or
    SameText(AName, 'TabOrder');
end;

procedure CopyProp(ASource, ATarget: TComponent; AProp: PPropInfo; AShare: Boolean);
begin
  case AProp.PropType^.Kind of
    tkMethod:
      if AShare then
      begin
        SetMethodProp(ATarget, AProp, GetMethodProp(ASource, AProp));
      end;
    tkClass:
      // Die Setter von Font, Items usw. übernehmen per Assign; Verweise richtet FixReferences.
      SetObjectProp(ATarget, AProp, GetObjectProp(ASource, AProp));
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      SetOrdProp(ATarget, AProp, GetOrdProp(ASource, AProp));
    tkFloat:
      SetFloatProp(ATarget, AProp, GetFloatProp(ASource, AProp));
    tkInt64:
      SetInt64Prop(ATarget, AProp, GetInt64Prop(ASource, AProp));
    tkString, tkLString, tkWString, tkUString:
      SetStrProp(ATarget, AProp, GetStrProp(ASource, AProp));
    tkVariant:
      SetVariantProp(ATarget, AProp, GetVariantProp(ASource, AProp));
  end;
end;

procedure CopyProps(ASource, ATarget: TComponent; AShare: Boolean);
var
  mList: PPropList;
  mCount, mIndex: Integer;
  mProp: PPropInfo;
begin
  mCount := GetPropList(ASource, mList);
  try
    for mIndex := 0 to mCount - 1 do
    begin
      mProp := mList[mIndex];
      if (mProp.SetProc <> nil) and not Skipped(string(mProp.Name)) and IsStoredProp(ASource, mProp) then
      begin
        CopyProp(ASource, ATarget, mProp, AShare);
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

/// <summary>Verweise der Kopien auf Originale der Gruppe zeigen auf deren Kopien (FocusControl).</summary>
procedure FixReferences(const AGroup: TCopyGroup; ARoot: TComponent);
var
  mOriginals, mCopies: TArray<string>;
  mComponent: TComponent;
  mList: PPropList;
  mCount, mIndex: Integer;
  mTarget: TObject;
begin
  mOriginals := nil;
  mCopies := nil;
  for mIndex := 0 to High(AGroup.Originals) do
  begin
    mOriginals := mOriginals + [AGroup.Originals[mIndex].Name];
    mCopies := mCopies + [AGroup.Copies[mIndex].Name];
  end;
  for mComponent in AGroup.Copies do
  begin
    mCount := GetPropList(mComponent, mList);
    try
      for mIndex := 0 to mCount - 1 do
      begin
        if (mList[mIndex].PropType^.Kind <> tkClass) or (mList[mIndex].SetProc = nil) then
        begin
          Continue;
        end;
        mTarget := GetObjectProp(mComponent, mList[mIndex]);
        if (mTarget is TComponent) and (TComponent(mTarget).Owner = ARoot) then
        begin
          SetObjectProp(mComponent, mList[mIndex], ARoot.FindComponent(TAtlasDuplicateRow.MapReference(
            TComponent(mTarget).Name, mOriginals, mCopies)));
        end;
      end;
    finally
      FreeMem(mList);
    end;
  end;
end;

procedure SetText(AComponent: TComponent; const AProp, AValue: string);
begin
  if IsPublishedProp(AComponent, AProp) and (PropType(AComponent, AProp) in [tkString, tkLString, tkWString,
    tkUString]) then
  begin
    SetStrProp(AComponent, AProp, AValue);
  end;
end;

{ Anlegen }

/// <summary>Kopie von AControl in AParent an ABounds mit Namen AName; Kinder folgen rekursiv.</summary>
function CopyControl(var ARun: TDuplicateRun; var AGroup: TCopyGroup; AControl: TControl; AParent: TComponent;
  const ABounds: TRect; const AName: string): TControl;
var
  mIndex: Integer;
  mChild: TControl;
  mTaken: TArray<string>;
begin
  Result := TControl(ARun.Designer.CreateComponent(TComponentClass(AControl.ClassType), AParent, ABounds.Left,
    ABounds.Top, ABounds.Width, ABounds.Height));
  // Erst der Name, dann die Eigenschaften: SetName setzt sonst eine Caption gleich dem alten Namen mit um.
  Result.Name := AName;
  CopyProps(AControl, Result, ARun.Options.ShareEvents);
  Result.BoundsRect := ABounds;
  AGroup.Originals := AGroup.Originals + [AControl];
  AGroup.Copies := AGroup.Copies + [Result];
  if not (AControl is TWinControl) then
  begin
    Exit;
  end;
  for mIndex := 0 to TWinControl(AControl).ControlCount - 1 do
  begin
    mChild := TWinControl(AControl).Controls[mIndex];
    if mChild.Owner <> ARun.Root then
    begin
      Continue;
    end;
    mTaken := ARun.Taken;
    CopyControl(ARun, AGroup, mChild, Result, mChild.BoundsRect, TAtlasDuplicateRow.UniqueName(mChild.Name, mTaken));
  end;
end;

/// <summary>Captions und DataField der Kopie aus dem Listeneintrag.</summary>
procedure ApplyEntry(const ARun: TDuplicateRun; AOriginal, ACopy: TControl; const AEntry: string);
var
  mCaption: string;
begin
  if AEntry = '' then
  begin
    Exit;
  end;
  if TAtlasDesignerAccess.PropText(AOriginal, 'Caption', mCaption) then
  begin
    SetText(ACopy, 'Caption', TAtlasDuplicateRow.CaptionFor(mCaption, AEntry));
  end;
  if ARun.Options.DataFields then
  begin
    SetText(ACopy, 'DataField', TAtlasDuplicateRow.Identifier(AEntry));
  end;
end;


/// <summary>Fokussierbare Originale nach TabOrder.</summary>
function TabControls(const AControls: TArray<TControl>): TArray<TWinControl>;
var
  mControl: TControl;
  mIndex, mPos: Integer;
  mValue: TWinControl;
begin
  Result := nil;
  for mControl in AControls do
  begin
    if mControl is TWinControl then
    begin
      Result := Result + [TWinControl(mControl)];
    end;
  end;
  for mIndex := 1 to High(Result) do
  begin
    mValue := Result[mIndex];
    mPos := mIndex - 1;
    while (mPos >= 0) and (Result[mPos].TabOrder > mValue.TabOrder) do
    begin
      Result[mPos + 1] := Result[mPos];
      Dec(mPos);
    end;
    Result[mPos + 1] := mValue;
  end;
end;

function IndexIn(const AComponents: TArray<TComponent>; AComponent: TComponent): Integer;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(AComponents) do
  begin
    if AComponents[mIndex] = AComponent then
    begin
      Exit(mIndex);
    end;
  end;
  Result := -1;
end;

/// <summary>TabOrder: die Kopien hinter dem Original, je Kopie in der Folge des Originals.</summary>
procedure ApplyTabOrder(const ARun: TDuplicateRun; const AGroups: TArray<TCopyGroup>);
var
  mTabs: TArray<TWinControl>;
  mOrders: TArray<TArray<Integer>>;
  mCopy, mIndex, mPos: Integer;
begin
  mTabs := TabControls(ARun.Controls);
  if Length(mTabs) = 0 then
  begin
    Exit;
  end;
  mOrders := TAtlasDuplicateRow.TabOrders(mTabs[High(mTabs)].TabOrder, Length(mTabs), Length(AGroups));
  // Aufsteigend setzen: jede Zuweisung schiebt die folgenden eins weiter.
  for mCopy := 0 to High(AGroups) do
  begin
    for mIndex := 0 to High(mTabs) do
    begin
      mPos := IndexIn(AGroups[mCopy].Originals, mTabs[mIndex]);
      if mPos >= 0 then
      begin
        TWinControl(AGroups[mCopy].Copies[mPos]).TabOrder := mOrders[mCopy][mIndex];
      end;
    end;
  end;
end;

/// <summary>Verschiebung der Kopie ACopy gegenüber der Auswahl.</summary>
function ShiftOf(const ARun: TDuplicateRun; const ALayout: TAtlasDuplicateLayout; ACopy: Integer): TPoint;
var
  mGroup: TRect;
begin
  mGroup := ARun.Request.Group;
  Result := Point(ALayout.Copies[ACopy].Left - mGroup.Left, ALayout.Copies[ACopy].Top - mGroup.Top);
end;

function EntryOf(const AEntries: TArray<string>; AIndex: Integer): string;
begin
  Result := '';
  if AIndex < Length(AEntries) then
  begin
    Result := AEntries[AIndex];
  end;
end;

/// <summary>Alle Kopien anlegen; je Kopie eine Gruppe.</summary>
function CreateCopies(var ARun: TDuplicateRun; const ALayout: TAtlasDuplicateLayout): TArray<TCopyGroup>;
var
  mNames: TArray<TArray<string>>;
  mEntries: TArray<string>;
  mCopy, mIndex: Integer;
  mBounds: TRect;
  mGroup: TCopyGroup;
  mControl: TControl;
begin
  mEntries := ARun.Entries;
  mNames := TAtlasDuplicateRow.Names(ARun.ControlNames, mEntries, ARun.Count, ARun.Taken);
  Result := nil;
  for mCopy := 0 to ARun.Count - 1 do
  begin
    mGroup.Originals := nil;
    mGroup.Copies := nil;
    for mIndex := 0 to High(ARun.Controls) do
    begin
      mBounds := ARun.Controls[mIndex].BoundsRect;
      mBounds.Offset(ShiftOf(ARun, ALayout, mCopy));
      mControl := CopyControl(ARun, mGroup, ARun.Controls[mIndex], ARun.Controls[mIndex].Parent, mBounds,
        TAtlasDuplicateRow.UniqueName(mNames[mCopy][mIndex], ARun.Taken));
      ApplyEntry(ARun, ARun.Controls[mIndex], mControl, EntryOf(mEntries, mCopy));
    end;
    FixReferences(mGroup, ARun.Root);
    Result := Result + [mGroup];
  end;
end;

function NamesOf(const AComponents: TArray<TComponent>): TArray<string>;
var
  mComponent: TComponent;
begin
  Result := nil;
  for mComponent in AComponents do
  begin
    Result := Result + [mComponent.Name];
  end;
end;

/// <summary>Kopien direkt im Elternelement AParent (ohne Kinder von Containern).</summary>
function TopCopies(const AGroups: TArray<TCopyGroup>; AParent: TWinControl): TArray<TComponent>;
var
  mGroup: TCopyGroup;
  mComponent: TComponent;
begin
  Result := nil;
  for mGroup in AGroups do
  begin
    for mComponent in mGroup.Copies do
    begin
      if TControl(mComponent).Parent = AParent then
      begin
        Result := Result + [mComponent];
      end;
    end;
  end;
end;

/// <summary>Text der Vorschau: „lblFax, edtFax; lblMobil, edtMobil“.</summary>
function PreviewText(const ANames: TArray<TArray<string>>): string;
var
  mCopy: TArray<string>;
begin
  Result := '';
  for mCopy in ANames do
  begin
    if Result <> '' then
    begin
      Result := Result + '; ';
    end;
    Result := Result + string.Join(', ', mCopy);
  end;
end;

{ TAtlasIdeDuplicateRow }

constructor TAtlasIdeDuplicateRow.Create(const AOnMessage: TProc<string>);
begin
  inherited Create;
  FOnMessage := AOnMessage;
end;

destructor TAtlasIdeDuplicateRow.Destroy;
begin
  FOutlines.Free;
  inherited Destroy;
end;

procedure TAtlasIdeDuplicateRow.Say(const AText: string);
begin
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

procedure TAtlasIdeDuplicateRow.ApplyTheme;
begin
  if FOutlines <> nil then
  begin
    FOutlines.ApplyColors(TAtlasIdeStyle.Colors);
  end;
end;

class function TAtlasIdeDuplicateRow.Candidates(const ASelected: TArray<TComponent>): TArray<TControl>;
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

procedure TAtlasIdeDuplicateRow.ShowOutlines(AParent: TWinControl; const AOutlines: TArray<TAtlasOutline>);
var
  mArea: TRect;
  mOutline: TAtlasOutline;
  mShifted: TArray<TAtlasOutline>;
begin
  // Fläche: Client des Elternelements und alles, was herausragt.
  mArea := AParent.ClientRect;
  for mOutline in AOutlines do
  begin
    mArea.Union(mOutline.Bounds);
  end;
  mShifted := nil;
  for mOutline in AOutlines do
  begin
    mShifted := mShifted + [TAtlasOutline.Create(Rect(mOutline.Bounds.Left - mArea.Left,
      mOutline.Bounds.Top - mArea.Top, mOutline.Bounds.Right - mArea.Left, mOutline.Bounds.Bottom - mArea.Top),
      mOutline.Name, mOutline.Bad)];
  end;
  if FOutlines = nil then
  begin
    FOutlines := TAtlasDesignerOutlines.CreateOutlines(nil, Application.MainFormHandle, TAtlasIdeStyle.Colors);
  end;
  mArea.Offset(AParent.ClientOrigin);
  FOutlines.ShowOutlines(mArea, mShifted);
end;

procedure TAtlasIdeDuplicateRow.HideOutlines;
begin
  if FOutlines <> nil then
  begin
    FOutlines.HideOutlines;
  end;
end;

/// <summary>Vorschau zu AOptions: Umrisse im Designer, Zeile „Kopien: …“ und Hinweis im Dialog.</summary>
procedure Preview(AOwner: TAtlasIdeDuplicateRow; ARun: TDuplicateRun; const AOptions: TAtlasDuplicateOptions;
  ADialog: TAtlasDuplicateDialog);
var
  mLayout: TAtlasDuplicateLayout;
  mNames: TArray<TArray<string>>;
  mOutlines: TArray<TAtlasOutline>;
  mCopy, mIndex: Integer;
  mBounds: TRect;
begin
  ARun.Options := AOptions;
  mLayout := TAtlasDuplicateRow.Layout(ARun.Request);
  mNames := TAtlasDuplicateRow.Names(ARun.ControlNames, ARun.Entries, ARun.Count, ARun.Taken);
  mOutlines := nil;
  for mCopy := 0 to ARun.Count - 1 do
  begin
    for mIndex := 0 to High(ARun.Controls) do
    begin
      mBounds := ARun.Controls[mIndex].BoundsRect;
      mBounds.Offset(ShiftOf(ARun, mLayout, mCopy));
      mOutlines := mOutlines + [TAtlasOutline.Create(mBounds, mNames[mCopy][mIndex], mLayout.Bad[mCopy])];
    end;
  end;
  AOwner.ShowOutlines(ARun.Controls[0].Parent, mOutlines);
  ADialog.SetPreview(PreviewText(mNames), mLayout.AnyBad);
  ADialog.PushCheck.Enabled := mLayout.AnyBad or AOptions.Push;
end;

/// <summary>Dialog mit Vorschau; True nach „Anlegen“.</summary>
function Ask(AOwner: TAtlasIdeDuplicateRow; const ARun: TDuplicateRun; var AOptions: TAtlasDuplicateOptions): Boolean;
var
  mRun: TDuplicateRun;
begin
  mRun := ARun;
  try
    Result := TAtlasDuplicateDialog.Execute(AOptions,
      procedure(AChanged: TAtlasDuplicateOptions; ADialog: TAtlasDuplicateDialog)
      begin
        Preview(AOwner, mRun, AChanged, ADialog);
      end);
  finally
    AOwner.HideOutlines;
  end;
end;

/// <summary>Vorgaben: nach unten, Abstand zum Nachbarn bzw. designer.duplicateRow.defaultGap, eine Kopie.</summary>
function DefaultOptions(const ARun: TDuplicateRun; const ASettings: TAtlasPluginSettings): TAtlasDuplicateOptions;
var
  mPpi: Integer;
begin
  Result.Direction := TAtlasDuplicateDirection.Down;
  Result.Gap := TAtlasDuplicateRow.DetectGap(ARun.Request.Group, RectsOf(ARun.Others), Result.Direction);
  if Result.Gap < 0 then
  begin
    mPpi := cDefaultPpi;
    if (ARun.Root is TCustomForm) and (TCustomForm(ARun.Root).PixelsPerInch > 0) then
    begin
      mPpi := TCustomForm(ARun.Root).PixelsPerInch;
    end;
    Result.Gap := MulDiv(ASettings.DesignerDuplicateRowDefaultGap, mPpi, cDefaultPpi);
  end;
  Result.Count := 1;
  Result.List := '';
  Result.ShareEvents := ASettings.DesignerDuplicateRowShareEvents;
  Result.DataFields := False;
  Result.Push := False;
end;

/// <summary>Nachfolgende verschieben; alte Lage für „Duplizieren rückgängig“ in AOwner.</summary>
procedure Push(AOwner: TAtlasIdeDuplicateRow; const ARun: TDuplicateRun; const ALayout: TAtlasDuplicateLayout);
var
  mIndex: Integer;
begin
  AOwner.FMoved := nil;
  AOwner.FMovedFrom := nil;
  for mIndex := 0 to High(ARun.Others) do
  begin
    if ALayout.Others[mIndex] <> ARun.Others[mIndex].BoundsRect then
    begin
      AOwner.FMoved := AOwner.FMoved + [ARun.Others[mIndex].Name];
      AOwner.FMovedFrom := AOwner.FMovedFrom + [ARun.Others[mIndex].BoundsRect];
      ARun.Others[mIndex].BoundsRect := ALayout.Others[mIndex];
    end;
  end;
end;

procedure TAtlasIdeDuplicateRow.Execute;
var
  mEditor: IOTAFormEditor;
  mRun: TDuplicateRun;
  mOptions: TAtlasDuplicateOptions;
  mLayout: TAtlasDuplicateLayout;
  mGroups: TArray<TCopyGroup>;
  mGroup: TCopyGroup;
begin
  if not TAtlasIdeSettings.Current.DesignerDuplicateRow or not TAtlasDesignerAccess.Current(mEditor, mRun.Root) then
  begin
    Exit;
  end;
  mRun.Designer := TAtlasDesignerAccess.DesignerOf(mEditor);
  mRun.Controls := Candidates(TAtlasDesignerAccess.Selection(mEditor, mRun.Root));
  if (mRun.Designer = nil) or (Length(mRun.Controls) = 0) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerDuplicateNoSelection));
    Exit;
  end;
  mRun.Others := SiblingsOf(mRun.Controls, mRun.Root);
  mOptions := DefaultOptions(mRun, TAtlasIdeSettings.Current);
  if not Ask(Self, mRun, mOptions) then
  begin
    Exit;
  end;
  mRun.Options := mOptions;
  mLayout := TAtlasDuplicateRow.Layout(mRun.Request);
  Push(Self, mRun, mLayout);
  mGroups := CreateCopies(mRun, mLayout);
  ApplyTabOrder(mRun, mGroups);
  FLastFile := mEditor.FileName;
  FCreated := nil;
  for mGroup in mGroups do
  begin
    FCreated := FCreated + NamesOf(mGroup.Copies);
  end;
  TAtlasDesignerAccess.Select(mRun.Designer, mRun.Root, TopCopies(mGroups, mRun.Controls[0].Parent));
  mRun.Designer.Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerDuplicateDone, [Length(mGroups),
    string.Join(', ', FCreated)]));
end;

function TAtlasIdeDuplicateRow.CanUndo: Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (Length(FCreated) > 0) and TAtlasDesignerAccess.Current(mEditor, mRoot) and
    SameText(mEditor.FileName, FLastFile) and (mRoot.FindComponent(FCreated[0]) <> nil);
end;

procedure TAtlasIdeDuplicateRow.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mComponent: IOTAComponent;
  mControl: TComponent;
  mIndex, mCount: Integer;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  // Rückwärts: Kinder vor ihren Containern.
  mCount := 0;
  for mIndex := High(FCreated) downto 0 do
  begin
    mComponent := mEditor.FindComponent(FCreated[mIndex]);
    if (mComponent <> nil) and mComponent.Delete then
    begin
      Inc(mCount);
    end;
  end;
  for mIndex := 0 to High(FMoved) do
  begin
    mControl := mRoot.FindComponent(FMoved[mIndex]);
    if mControl is TControl then
    begin
      TControl(mControl).BoundsRect := FMovedFrom[mIndex];
    end;
  end;
  FCreated := nil;
  FMoved := nil;
  FMovedFrom := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerDuplicateUndone, [mCount]));
end;

end.
