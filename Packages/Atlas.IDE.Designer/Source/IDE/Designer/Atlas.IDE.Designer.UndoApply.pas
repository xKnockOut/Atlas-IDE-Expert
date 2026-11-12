unit Atlas.IDE.Designer.UndoApply;

// Rückgängig im Designer (#1887): einen Plan von TAtlasFormUndo im offenen
// Designer ausführen. Die ToolsAPI lädt keinen Formulartext in einen offenen
// Designer; Atlas ändert darum Stück für Stück:
// - Löschen über IOTAComponent.Delete (der Designer nimmt das Feld aus der
//   Klasse), Umbenennen über Name (der Designer zieht das Feld nach).
// - Anlegen über IDesigner.CreateComponent mit der registrierten Klasse
//   (FindClass), danach Name und Werte wie beim Ändern.
// - Werte über TReader aus dem kleinen Formulartext des Plans, wie beim
//   Laden eines Formulars: so auch Kollektionen, Listen, Binärdaten und
//   Verweise auf andere Komponenten. Entfernte Werte gehen per RTTI auf die
//   Vorgabe (Kollektionen und Listen werden geleert).
// - Ereignisse über IDesigner.CreateMethod, nur wenn die Methode im Code
//   steht; sonst bleibt das Ereignis leer und Atlas meldet es (kein neuer
//   Handler im Code).
// Nach Löschen, Umbenennen und Anlegen vergleicht Atlas den Stand noch
// einmal mit dem Ziel und setzt nur noch Werte. Was nicht ging, steht in
// Failures bzw. MissingMethods. Nur im Hauptthread.

interface

uses
  System.Classes,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Designer.Undo;

type
  /// <summary>Ereignis, dessen Handler im Code fehlt.</summary>
  TAtlasUndoMissingMethod = record
    Component: string;
    Path: string;
    Handler: string;
  end;

  TAtlasDesignerUndoApply = class
  private
    FEditor: IOTAFormEditor;
    FDesigner: IDesigner;
    FRoot: TComponent;
    FFailures: TArray<string>;
    FMissing: TArray<TAtlasUndoMissingMethod>;
    /// <summary>Meldungen von TReader für die gerade gelesene Komponente.</summary>
    FReadErrors: TArray<string>;
    procedure Fail(const AKey, AReason: string);
    function Find(const AKey: string): TComponent;
    procedure DeleteComponent(const AKey: string);
    procedure Rename(const ARename: TAtlasUndoRename);
    procedure CreateComponent(const ACreate: TAtlasUndoComponent);
    procedure Apply(AComponent: TComponent; const AChange: TAtlasUndoComponent);
    procedure ReadValues(AComponent: TComponent; const AKey, AText: string);
    procedure ResetValue(AComponent: TComponent; const AKey, APath: string);
    procedure AssignEvent(AComponent: TComponent; const AKey: string; const AEvent: TAtlasUndoEvent);
    procedure ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
  public
    constructor Create(const AEditor: IOTAFormEditor; const ADesigner: IDesigner; ARoot: TComponent);
    /// <summary>Führt APlan aus und gleicht danach die Werte mit ATarget ab.</summary>
    procedure Run(const APlan: TAtlasUndoPlan; const ATarget: string);
    /// <summary>Nicht hergestellt: „Schlüssel (Grund)“.</summary>
    property Failures: TArray<string> read FFailures;
    property MissingMethods: TArray<TAtlasUndoMissingMethod> read FMissing;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Designer.Access;

type
  /// <summary>Zugriff auf das geschützte Loaded (E2362).</summary>
  TComponentAccess = class(TComponent);

const
  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  cNoDefaultValue = Integer($80000000);
  /// <summary>Puffer des TReader für die Werte einer Komponente.</summary>
  cReaderBuffer = 4096;

{ TAtlasDesignerUndoApply }

constructor TAtlasDesignerUndoApply.Create(const AEditor: IOTAFormEditor; const ADesigner: IDesigner;
  ARoot: TComponent);
begin
  inherited Create;
  FEditor := AEditor;
  FDesigner := ADesigner;
  FRoot := ARoot;
end;

procedure TAtlasDesignerUndoApply.Fail(const AKey, AReason: string);
var
  mName: string;
begin
  mName := AKey;
  if mName = '' then
  begin
    mName := FRoot.Name;
  end;
  FFailures := FFailures + [mName + ' (' + AReason + ')'];
end;

function TAtlasDesignerUndoApply.Find(const AKey: string): TComponent;
var
  mPart: string;
begin
  Result := FRoot;
  if AKey = '' then
  begin
    Exit;
  end;
  // In eingebetteten Frames: „Frame1.Button1“, Button1 gehört dem Frame.
  for mPart in AKey.Split(['.']) do
  begin
    Result := Result.FindComponent(mPart);
    if Result = nil then
    begin
      Exit;
    end;
  end;
end;

procedure TAtlasDesignerUndoApply.DeleteComponent(const AKey: string);
var
  mComponent: IOTAComponent;
begin
  mComponent := FEditor.FindComponent(AKey);
  if (mComponent = nil) or not mComponent.Delete then
  begin
    Fail(AKey, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonDelete));
  end;
end;

procedure TAtlasDesignerUndoApply.Rename(const ARename: TAtlasUndoRename);
var
  mComponent: TComponent;
begin
  mComponent := Find(ARename.OldKey);
  if mComponent = nil then
  begin
    Fail(ARename.OldKey, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonMissing));
    Exit;
  end;
  try
    mComponent.Name := ARename.NewName;
  except
    on mError: Exception do
      Fail(ARename.OldKey, mError.Message);
  end;
end;

procedure TAtlasDesignerUndoApply.CreateComponent(const ACreate: TAtlasUndoComponent);
var
  mClass: TPersistentClass;
  mParent, mComponent: TComponent;
begin
  mClass := GetClass(ACreate.TypeName);
  mParent := Find(ACreate.ParentKey);
  if (mClass = nil) or not mClass.InheritsFrom(TComponent) or (mParent = nil) then
  begin
    Fail(ACreate.Key, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoReasonClass, [ACreate.TypeName]));
    Exit;
  end;
  try
    mComponent := FDesigner.CreateComponent(TComponentClass(mClass), mParent, 0, 0, 0, 0);
    if (mComponent <> nil) and not SameText(mComponent.Name, ACreate.Name) then
    begin
      mComponent.Name := ACreate.Name;
    end;
  except
    on mError: Exception do
    begin
      Fail(ACreate.Key, mError.Message);
      Exit;
    end;
  end;
  if mComponent = nil then
  begin
    Fail(ACreate.Key, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoReasonClass, [ACreate.TypeName]));
    Exit;
  end;
  Apply(mComponent, ACreate);
end;

procedure TAtlasDesignerUndoApply.ReaderError(Reader: TReader; const Message: string; var Handled: Boolean);
begin
  // Unbekannte Eigenschaft oder falscher Wert: diesen Wert auslassen, die übrigen lesen.
  FReadErrors := FReadErrors + [Message];
  Handled := True;
end;

procedure TAtlasDesignerUndoApply.ReadValues(AComponent: TComponent; const AKey, AText: string);
var
  mText: TStringStream;
  mBinary: TMemoryStream;
  mReader: TReader;
  mError: string;
begin
  FReadErrors := nil;
  mText := TStringStream.Create(AText, TEncoding.UTF8);
  mBinary := TMemoryStream.Create;
  try
    try
      ObjectTextToBinary(mText, mBinary);
      mBinary.Position := 0;
      mReader := TReader.Create(mBinary, cReaderBuffer);
      try
        mReader.Root := FRoot;
        mReader.Owner := AComponent.Owner;
        mReader.Parent := AComponent.GetParentComponent;
        mReader.OnError := ReaderError;
        mReader.BeginReferences;
        try
          mReader.ReadSignature;
          mReader.ReadComponent(AComponent);
          mReader.FixupReferences;
        finally
          mReader.EndReferences;
        end;
      finally
        mReader.Free;
      end;
    except
      // Auch Fehler beim Setzen eines Werts (EConvertError, EComponentError …): diese Komponente melden.
      on mFailure: Exception do
        FReadErrors := FReadErrors + [mFailure.Message];
    end;
  finally
    mBinary.Free;
    mText.Free;
  end;
  // Ohne Loaded bliebe die Komponente im Zustand csLoading.
  if csLoading in AComponent.ComponentState then
  begin
    TComponentAccess(AComponent).Loaded;
  end;
  for mError in FReadErrors do
  begin
    Fail(AKey, mError);
  end;
end;

/// <summary>Löst APath (auch Font.Style, Lines.Strings) bis zum letzten Teil auf: AInstance trägt ALeaf.</summary>
function Resolve(AComponent: TComponent; const APath: string; out AInstance: TObject; out ALeaf: string): Boolean;
var
  mParts: TArray<string>;
  mIndex: Integer;
  mProp: PPropInfo;
begin
  mParts := APath.Split(['.']);
  AInstance := AComponent;
  ALeaf := mParts[High(mParts)];
  for mIndex := 0 to High(mParts) - 1 do
  begin
    mProp := GetPropInfo(AInstance, mParts[mIndex]);
    if (mProp = nil) or (mProp^.PropType^.Kind <> tkClass) then
    begin
      Exit(False);
    end;
    AInstance := GetObjectProp(AInstance, mProp);
    if AInstance = nil then
    begin
      Exit(False);
    end;
  end;
  Result := True;
end;

/// <summary>Objekt-Eigenschaft leeren; False, wenn das nicht geht.</summary>
function ClearObject(AInstance: TObject; AProp: PPropInfo): Boolean;
var
  mValue: TObject;
begin
  mValue := GetObjectProp(AInstance, AProp);
  Result := True;
  if mValue is TCollection then
  begin
    TCollection(mValue).Clear;
  end
  else if mValue is TStrings then
  begin
    TStrings(mValue).Clear;
  end
  else if (mValue = nil) or (mValue is TComponent) then
  begin
    // Verweis auf eine andere Komponente (FocusControl, PopupMenu).
    SetObjectProp(AInstance, AProp, nil);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>AProp von AInstance auf die Vorgabe; False, wenn das für diese Art nicht geht.</summary>
function ResetProp(AInstance: TObject; AProp: PPropInfo): Boolean;
var
  mNothing: TMethod;
begin
  Result := True;
  case AProp^.PropType^.Kind of
    tkInteger, tkChar, tkWChar, tkEnumeration, tkSet:
      if AProp^.Default <> cNoDefaultValue then
      begin
        SetOrdProp(AInstance, AProp, AProp^.Default);
      end
      else
      begin
        SetOrdProp(AInstance, AProp, 0);
      end;
    tkFloat:
      SetFloatProp(AInstance, AProp, 0);
    tkInt64:
      SetInt64Prop(AInstance, AProp, 0);
    tkString, tkLString, tkWString, tkUString:
      SetStrProp(AInstance, AProp, '');
    tkMethod:
      begin
        mNothing.Code := nil;
        mNothing.Data := nil;
        SetMethodProp(AInstance, AProp, mNothing);
      end;
    tkClass:
      Result := ClearObject(AInstance, AProp);
  else
    Result := False;
  end;
end;

procedure TAtlasDesignerUndoApply.ResetValue(AComponent: TComponent; const AKey, APath: string);
var
  mInstance: TObject;
  mLeaf: string;
  mProp: PPropInfo;
begin
  // Hilfswerte der VCL (ExplicitLeft, DesignSize, TextHeight) stellt sie selbst wieder her.
  if APath.StartsWith('Explicit', True) or SameText(APath, 'DesignSize') or SameText(APath, 'TextHeight') then
  begin
    Exit;
  end;
  if not Resolve(AComponent, APath, mInstance, mLeaf) then
  begin
    Fail(AKey, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoReasonValue, [APath]));
    Exit;
  end;
  // Lines.Strings, Items.Strings: Liste ohne Einträge.
  if SameText(mLeaf, 'Strings') and (mInstance is TStrings) then
  begin
    TStrings(mInstance).Clear;
    Exit;
  end;
  mProp := GetPropInfo(mInstance, mLeaf);
  if (mProp = nil) or ((mProp^.SetProc = nil) and (mProp^.PropType^.Kind <> tkClass)) or
    not ResetProp(mInstance, mProp) then
  begin
    Fail(AKey, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoReasonValue, [APath]));
  end;
end;

procedure TAtlasDesignerUndoApply.AssignEvent(AComponent: TComponent; const AKey: string;
  const AEvent: TAtlasUndoEvent);
var
  mProp: PPropInfo;
  mMethod: TMethod;
  mMissing: TAtlasUndoMissingMethod;
begin
  mProp := GetPropInfo(AComponent, AEvent.Path);
  if (mProp = nil) or (mProp^.PropType^.Kind <> tkMethod) then
  begin
    Fail(AKey, TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UndoReasonValue, [AEvent.Path]));
    Exit;
  end;
  mMethod.Code := nil;
  mMethod.Data := nil;
  if AEvent.Handler <> '' then
  begin
    // CreateMethod legte eine fehlende Methode neu an: Der Code bleibt aber unangetastet.
    if not FDesigner.MethodExists(AEvent.Handler) then
    begin
      mMissing.Component := AComponent.Name;
      mMissing.Path := AEvent.Path;
      mMissing.Handler := AEvent.Handler;
      FMissing := FMissing + [mMissing];
      Exit;
    end;
    mMethod := FDesigner.CreateMethod(AEvent.Handler, GetTypeData(mProp^.PropType^));
  end;
  SetMethodProp(AComponent, mProp, mMethod);
end;

procedure TAtlasDesignerUndoApply.Apply(AComponent: TComponent; const AChange: TAtlasUndoComponent);
var
  mPath: string;
  mEvent: TAtlasUndoEvent;
begin
  for mPath in AChange.Resets do
  begin
    ResetValue(AComponent, AChange.Key, mPath);
  end;
  if AChange.Text <> '' then
  begin
    ReadValues(AComponent, AChange.Key, AChange.Text);
  end;
  for mEvent in AChange.Events do
  begin
    AssignEvent(AComponent, AChange.Key, mEvent);
  end;
end;

procedure TAtlasDesignerUndoApply.Run(const APlan: TAtlasUndoPlan; const ATarget: string);
var
  mKey: string;
  mRename: TAtlasUndoRename;
  mCreate, mChange: TAtlasUndoComponent;
  mPlan: TAtlasUndoPlan;
  mComponent: TComponent;
begin
  for mKey in APlan.Deletes do
  begin
    DeleteComponent(mKey);
  end;
  for mRename in APlan.Renames do
  begin
    Rename(mRename);
  end;
  for mCreate in APlan.Creates do
  begin
    CreateComponent(mCreate);
  end;
  for mKey in APlan.Skipped do
  begin
    Fail(mKey, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonInherited));
  end;
  mPlan := APlan;
  if APlan.Structural then
  begin
    // Neu angelegte Komponenten tragen Vorgaben des Designers (Caption = Name): noch einmal abgleichen.
    mPlan := TAtlasFormUndo.Plan(TAtlasDesignerAccess.FormText(FRoot, FDesigner), ATarget);
  end;
  for mChange in mPlan.Changes do
  begin
    mComponent := Find(mChange.Key);
    if mComponent = nil then
    begin
      Fail(mChange.Key, TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UndoReasonMissing));
    end
    else
    begin
      Apply(mComponent, mChange);
    end;
  end;
end;

end.
