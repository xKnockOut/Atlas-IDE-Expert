unit Atlas.IDE.Designer.PropertyPainter;

// Format-Pinsel (#726) in der IDE: Untermenü „Eigenschaften übertragen“ im
// Menü „Anordnen“ und Strg+Umschalt+C/V, solange der Designer den Fokus hat.
// - Aufnehmen: genau eine markierte Komponente ist die Quelle. Der Dialog
//   (TAtlasPaintDialog) zeigt ihre gesetzten Eigenschaften (gespeichert und
//   nicht auf dem Standardwert) nach Gruppen; verschachtelte (Font, Margins)
//   als Knoten mit Kindern. Die Häkchen merkt Atlas je Quellklasse in
//   property-painter.json neben der globalen Einstellungsdatei.
// - Übertragen: auf alle markierten Komponenten außer der Quelle, im selben
//   Formular. Übertragen wird über RTTI, was das Ziel unter demselben Pfad
//   mit demselben Typ veröffentlicht; Ereignisse bekommen denselben Handler.
//   Was fehlt, steht in der Meldungsansicht („lblName: BevelKind
//   übersprungen“). Verweise auf Komponenten und TStrings werden übertragen,
//   andere Objekte nur über ihre Eigenschaften.
// - „Übertragen rückgängig“ setzt alle Werte des letzten Strichs zurück.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.TypInfo,
  Atlas.Core.Designer.PropertyPainter,
  Atlas.IDE.Foundation.KeyHook,
  Atlas.IDE.Designer.Tool;

type
{$SCOPEDENUMS ON}
  TAtlasPaintCommand = (PickUp, Apply, Undo);
{$SCOPEDENUMS OFF}

  TAtlasIdePropertyPainter = class;

  /// <summary>Strg+Umschalt+C (aufnehmen) und Strg+Umschalt+V (übertragen) im Designer.</summary>
  TAtlasPaintKeys = class(TAtlasKeyClient)
  private
    FOwner: TAtlasIdePropertyPainter;
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Ein Wert vor dem Übertragen, für „Übertragen rückgängig“.</summary>
  TAtlasPaintOld = record
    Component: string;
    Path: string;
    Kind: TTypeKind;
    Ordinal: Int64;
    Float: Extended;
    Text: string;
    Method: TMethod;
    Reference: TObject;
  end;

  TAtlasIdePropertyPainter = class(TAtlasIdeDesignerTool)
  private
    FKeys: TAtlasPaintKeys;
    FSourceFile: string;
    FSourceName: string;
    FSourceProperties: TArray<TAtlasPaintProperty>;
    FChosen: TArray<string>;
    FUndoFile: string;
    FUndo: TArray<TAtlasPaintOld>;
    procedure PickUp;
    procedure Apply;
    procedure Undo;
  public
    /// <summary>AOnMessage: Zeile in der Meldungsansicht.</summary>
    constructor Create(const AOnMessage: TProc<string>);
    destructor Destroy; override;
    procedure UpdateKeys(AWanted: Boolean);
    procedure Execute(ACommand: TAtlasPaintCommand);
    /// <summary>Gibt es aufgenommene Eigenschaften für das aktive Formular?</summary>
    function CanApply: Boolean;
    function CanUndo: Boolean;
  end;

implementation

uses
  System.IOUtils,
  ToolsAPI,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Strings,
  Atlas.UI.Designer.PaintDialog,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Foundation.Settings;

const
  cKeyPriority = 50;
  cMaxDepth = 2;
  cMemoryFile = 'property-painter.json';
  cNoDefault = Integer($80000000);

{ RTTI }

function HasProperties(AObject: TObject): Boolean;
var
  mList: PPropList;
  mCount: Integer;
begin
  mCount := GetPropList(AObject, mList);
  FreeMem(mList);
  Result := mCount > 0;
end;

/// <summary>Gesetzt: gespeichert und nicht auf dem Standardwert.</summary>
function IsSet(AInstance: TObject; AProp: PPropInfo): Boolean;
begin
  Result := IsStoredProp(AInstance, AProp);
  if not Result then
  begin
    Exit;
  end;
  case AProp.PropType^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      Result := (AProp.Default = cNoDefault) or (GetOrdProp(AInstance, AProp) <> AProp.Default);
    tkString, tkLString, tkWString, tkUString:
      Result := GetStrProp(AInstance, AProp) <> '';
    tkMethod:
      Result := GetMethodProp(AInstance, AProp).Code <> nil;
    tkClass:
      Result := GetObjectProp(AInstance, AProp) <> nil;
  end;
end;

/// <summary>Als Ganzes übertragbares Objekt: Verweis auf eine Komponente oder TStrings.</summary>
function WholeObject(AProp: PPropInfo): Boolean;
var
  mClass: TClass;
begin
  mClass := GetTypeData(AProp.PropType^).ClassType;
  Result := mClass.InheritsFrom(TComponent) or mClass.InheritsFrom(TStrings);
end;

procedure Collect(AInstance: TObject; const APrefix: string; AOnlySet: Boolean; ADepth: Integer;
  var AList: TArray<TAtlasPaintProperty>);
var
  mList: PPropList;
  mCount, mIndex: Integer;
  mProp: PPropInfo;
  mName: string;
  mChild: TObject;
begin
  mCount := GetPropList(AInstance, mList);
  try
    for mIndex := 0 to mCount - 1 do
    begin
      mProp := mList[mIndex];
      mName := string(mProp.Name);
      if (mProp.GetProc = nil) or SameText(mName, 'Name') or (AOnlySet and not IsSet(AInstance, mProp)) then
      begin
        Continue;
      end;
      if (mProp.PropType^.Kind = tkClass) and not WholeObject(mProp) then
      begin
        mChild := GetObjectProp(AInstance, mProp);
        if (mChild is TPersistent) and (ADepth < cMaxDepth) and HasProperties(mChild) then
        begin
          Collect(mChild, APrefix + mName + '.', AOnlySet, ADepth + 1, AList);
        end;
        Continue;
      end;
      if mProp.SetProc <> nil then
      begin
        AList := AList + [TAtlasPaintProperty.Create(APrefix + mName, string(mProp.PropType^.Name),
          mProp.PropType^.Kind = tkMethod)];
      end;
    end;
  finally
    FreeMem(mList);
  end;
end;

function PropertiesOf(AComponent: TComponent; AOnlySet: Boolean): TArray<TAtlasPaintProperty>;
begin
  Result := nil;
  Collect(AComponent, '', AOnlySet, 0, Result);
end;

/// <summary>Objekt und Eigenschaft hinter APath (Font.Style: Font und Style); False ohne.</summary>
function Resolve(AInstance: TObject; const APath: string; out AObject: TObject; out AProp: PPropInfo): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mProp: PPropInfo;
begin
  AObject := AInstance;
  AProp := nil;
  mParts := APath.Split(['.']);
  for mIndex := 0 to High(mParts) - 1 do
  begin
    mProp := GetPropInfo(AObject, mParts[mIndex]);
    if (mProp = nil) or (mProp.PropType^.Kind <> tkClass) then
    begin
      Exit(False);
    end;
    AObject := GetObjectProp(AObject, mProp);
    if AObject = nil then
    begin
      Exit(False);
    end;
  end;
  AProp := GetPropInfo(AObject, mParts[High(mParts)]);
  Result := (AProp <> nil) and (AProp.SetProc <> nil);
end;

function ReadValue(AObject: TObject; AProp: PPropInfo): TAtlasPaintOld;
begin
  Result := Default(TAtlasPaintOld);
  Result.Kind := AProp.PropType^.Kind;
  case Result.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      Result.Ordinal := GetOrdProp(AObject, AProp);
    tkInt64:
      Result.Ordinal := GetInt64Prop(AObject, AProp);
    tkFloat:
      Result.Float := GetFloatProp(AObject, AProp);
    tkString, tkLString, tkWString, tkUString:
      Result.Text := GetStrProp(AObject, AProp);
    tkMethod:
      Result.Method := GetMethodProp(AObject, AProp);
    tkClass:
      begin
        Result.Reference := GetObjectProp(AObject, AProp);
        if Result.Reference is TStrings then
        begin
          // Den Inhalt merken: Das Objekt selbst gehört dem Ziel und bleibt.
          Result.Text := TStrings(Result.Reference).Text;
          Result.Reference := nil;
        end;
      end;
  end;
end;

procedure WriteValue(AObject: TObject; AProp: PPropInfo; const AValue: TAtlasPaintOld);
var
  mTarget: TObject;
begin
  case AValue.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      SetOrdProp(AObject, AProp, AValue.Ordinal);
    tkInt64:
      SetInt64Prop(AObject, AProp, AValue.Ordinal);
    tkFloat:
      SetFloatProp(AObject, AProp, AValue.Float);
    tkString, tkLString, tkWString, tkUString:
      SetStrProp(AObject, AProp, AValue.Text);
    tkMethod:
      SetMethodProp(AObject, AProp, AValue.Method);
    tkClass:
      begin
        mTarget := GetObjectProp(AObject, AProp);
        if mTarget is TStrings then
        begin
          TStrings(mTarget).Text := AValue.Text;
        end
        else
        begin
          SetObjectProp(AObject, AProp, AValue.Reference);
        end;
      end;
  end;
end;

function MemoryPath: string;
begin
  Result := '';
  if TAtlasIdeSettings.GlobalFile <> '' then
  begin
    Result := TPath.Combine(ExtractFilePath(TAtlasIdeSettings.GlobalFile), cMemoryFile);
  end;
end;

function LoadMemory: TAtlasPaintMemory;
begin
  Result := TAtlasPaintMemory.Create;
  if (MemoryPath = '') or not FileExists(MemoryPath) then
  begin
    Exit;
  end;
  try
    Result.LoadJson(TFile.ReadAllText(MemoryPath, TEncoding.UTF8));
  except
    on EInOutError do
      Result.LoadJson('');
    on EFileStreamError do
      Result.LoadJson('');
  end;
end;

procedure SaveMemory(AMemory: TAtlasPaintMemory);
begin
  if MemoryPath = '' then
  begin
    Exit;
  end;
  try
    TFile.WriteAllText(MemoryPath, AMemory.ToJson, TEncoding.UTF8);
  except
    // Merken ist eine Bequemlichkeit: Ohne Schreibrecht bleibt die Vorauswahl der Gruppen.
    on EInOutError do
      Exit;
    on EFileStreamError do
      Exit;
  end;
end;

{ TAtlasPaintKeys }

function TAtlasPaintKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
begin
  Result := TAtlasIdeSettings.Current.DesignerPropertyPainter and (AShift = [ssCtrl, ssShift]) and
    ((AKey = Ord('C')) or (AKey = Ord('V'))) and TAtlasDesignerAccess.Focused;
end;

procedure TAtlasPaintKeys.HandleKey(AKey: Word; AShift: TShiftState);
var
  mOwner: TAtlasIdePropertyPainter;
  mPick: Boolean;
begin
  mOwner := FOwner;
  mPick := AKey = Ord('C');
  TAtlasGuard.Run(TAtlasFeature.DesignerBar,
    procedure
    begin
      if mPick then
      begin
        mOwner.Execute(TAtlasPaintCommand.PickUp);
      end
      else
      begin
        mOwner.Execute(TAtlasPaintCommand.Apply);
      end;
    end);
end;

{ TAtlasIdePropertyPainter }

constructor TAtlasIdePropertyPainter.Create(const AOnMessage: TProc<string>);
begin
  inherited Create(AOnMessage);
  FKeys := TAtlasPaintKeys.Create(cKeyPriority);
  FKeys.FOwner := Self;
end;

destructor TAtlasIdePropertyPainter.Destroy;
begin
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
    FKeys.Free;
  end;
  inherited Destroy;
end;

procedure TAtlasIdePropertyPainter.UpdateKeys(AWanted: Boolean);
begin
  if AWanted and TAtlasIdeSettings.Current.DesignerPropertyPainter then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

function SameForm(const AFile: string): Boolean;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  Result := (AFile <> '') and TAtlasDesignerAccess.Current(mEditor, mRoot) and SameText(mEditor.FileName, AFile);
end;

function TAtlasIdePropertyPainter.CanApply: Boolean;
begin
  Result := (Length(FChosen) > 0) and SameForm(FSourceFile);
end;

function TAtlasIdePropertyPainter.CanUndo: Boolean;
begin
  Result := (Length(FUndo) > 0) and SameForm(FUndoFile);
end;

procedure TAtlasIdePropertyPainter.PickUp;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mSettings: TAtlasPluginSettings;
  mMemory: TAtlasPaintMemory;
  mRows: TArray<TAtlasPaintRow>;
  mChecked: TArray<Boolean>;
  mRemembered: TArray<string>;
  mHas: Boolean;
begin
  mSettings := TAtlasIdeSettings.Current;
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  if Length(mSelected) <> 1 then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintNeedOne));
    Exit;
  end;
  FSourceProperties := PropertiesOf(mSelected[0], True);
  mRows := TAtlasPropertyPainter.Rows(FSourceProperties);
  mMemory := LoadMemory;
  try
    mHas := mSettings.DesignerPropertyPainterRememberPerClass and mMemory.TryGet(mSelected[0].ClassName, mRemembered);
    mChecked := TAtlasPropertyPainter.Preselect(mRows,
      TAtlasPropertyPainter.ParseGroups(mSettings.DesignerPropertyPainterDefaultGroups), mRemembered, mHas);
    if not TAtlasPaintDialog.Execute(mSelected[0].Name, mRows, mChecked) then
    begin
      Exit;
    end;
    FChosen := TAtlasPropertyPainter.Chosen(mRows, mChecked);
    FSourceFile := mEditor.FileName;
    FSourceName := mSelected[0].Name;
    if mSettings.DesignerPropertyPainterRememberPerClass then
    begin
      mMemory.Put(mSelected[0].ClassName, FChosen);
      SaveMemory(mMemory);
    end;
  finally
    mMemory.Free;
  end;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPaintPicked, [FSourceName, Length(FChosen)]));
end;

/// <summary>APaths von ASource auf ATarget übertragen; die alten Werte an AUndo anhängen.</summary>
procedure Transfer(ASource, ATarget: TComponent; const APaths: TArray<string>; var AUndo: TArray<TAtlasPaintOld>);
var
  mPath: string;
  mFrom, mTo: TObject;
  mFromProp, mToProp: PPropInfo;
  mOld: TAtlasPaintOld;
begin
  for mPath in APaths do
  begin
    if not Resolve(ASource, mPath, mFrom, mFromProp) or not Resolve(ATarget, mPath, mTo, mToProp) then
    begin
      Continue;
    end;
    mOld := ReadValue(mTo, mToProp);
    mOld.Component := ATarget.Name;
    mOld.Path := mPath;
    AUndo := AUndo + [mOld];
    WriteValue(mTo, mToProp, ReadValue(mFrom, mFromProp));
  end;
end;

procedure TAtlasIdePropertyPainter.Apply;
var
  mEditor: IOTAFormEditor;
  mRoot, mSource, mTarget: TComponent;
  mApply, mSkipped: TArray<string>;
  mCount: Integer;
begin
  if not CanApply or not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (TAtlasDesignerAccess.DesignerOf(mEditor) = nil) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintNothing));
    Exit;
  end;
  mSource := mRoot.FindComponent(FSourceName);
  if mSource = nil then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintNothing));
    Exit;
  end;
  FUndo := nil;
  FUndoFile := mEditor.FileName;
  mCount := 0;
  for mTarget in TAtlasDesignerAccess.Selection(mEditor, mRoot) do
  begin
    if mTarget = mSource then
    begin
      Continue;
    end;
    mApply := TAtlasPropertyPainter.Match(FSourceProperties, FChosen, PropertiesOf(mTarget, False), mSkipped);
    Transfer(mSource, mTarget, mApply, FUndo);
    Inc(mCount);
    if Length(mSkipped) > 0 then
    begin
      Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPaintSkipped, [mTarget.Name,
        string.Join(', ', mSkipped)]));
    end;
  end;
  TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.DesignerPaintDone, [mCount]));
end;

procedure TAtlasIdePropertyPainter.Undo;
var
  mEditor: IOTAFormEditor;
  mRoot, mComponent: TComponent;
  mIndex: Integer;
  mObject: TObject;
  mProp: PPropInfo;
begin
  if not CanUndo or not TAtlasDesignerAccess.Current(mEditor, mRoot) then
  begin
    Exit;
  end;
  // Rückwärts: Bei mehrfach gesetzten Pfaden gilt am Ende der älteste Wert.
  for mIndex := High(FUndo) downto 0 do
  begin
    mComponent := mRoot.FindComponent(FUndo[mIndex].Component);
    if (mComponent <> nil) and Resolve(mComponent, FUndo[mIndex].Path, mObject, mProp) then
    begin
      WriteValue(mObject, mProp, FUndo[mIndex]);
    end;
  end;
  FUndo := nil;
  if TAtlasDesignerAccess.DesignerOf(mEditor) <> nil then
  begin
    TAtlasDesignerAccess.DesignerOf(mEditor).Modified;
  end;
  Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.DesignerPaintUndone));
end;

procedure TAtlasIdePropertyPainter.Execute(ACommand: TAtlasPaintCommand);
begin
  if not TAtlasIdeSettings.Current.DesignerPropertyPainter then
  begin
    Exit;
  end;
  case ACommand of
    TAtlasPaintCommand.PickUp:
      PickUp;
    TAtlasPaintCommand.Apply:
      Apply;
    TAtlasPaintCommand.Undo:
      Undo;
  end;
end;

end.
