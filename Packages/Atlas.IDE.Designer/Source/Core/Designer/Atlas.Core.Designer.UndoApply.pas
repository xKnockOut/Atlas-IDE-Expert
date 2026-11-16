unit Atlas.Core.Designer.UndoApply;

// Rückgängig im Designer (#1887): einen Plan von TAtlasFormUndo im offenen
// Designer ausführen, über den Vertrag IAtlasDesignSurface (ohne VCL und
// Open Tools API). Die ToolsAPI lädt keinen Formulartext in einen offenen
// Designer; Atlas ändert darum Stück für Stück:
// - Löschen über IAtlasDesignSurface.DeleteComponent (der Designer nimmt das
//   Feld aus der Klasse), Umbenennen über Name (der Designer zieht das Feld
//   nach).
// - Anlegen über IAtlasDesignSurface.CreateComponent mit der registrierten
//   Klasse (GetClass), danach Name und Werte wie beim Ändern.
// - Werte über TReader aus dem kleinen Formulartext des Plans, wie beim
//   Laden eines Formulars: so auch Kollektionen, Listen, Binärdaten und
//   Verweise auf andere Komponenten. Entfernte Werte gehen per RTTI auf die
//   Vorgabe (Kollektionen und Listen werden geleert).
// - Ereignisse über IAtlasDesignSurface.CreateMethod, nur wenn die Methode im Code
//   steht; sonst bleibt das Ereignis leer und Atlas meldet es (kein neuer
//   Handler im Code).
// Nach Löschen, Umbenennen und Anlegen vergleicht Atlas den Stand noch
// einmal mit dem Ziel und setzt nur noch Werte. Was nicht ging, steht in
// Failures bzw. MissingMethods; die Gründe kommen als TAtlasUndoReasons von
// außen (Sprache der Oberfläche). Nur im Hauptthread.

interface

uses
  System.Classes,
  Atlas.Core.Designer.Undo,
  Atlas.Core.Designer.Surface;

type
  /// <summary>Ereignis, dessen Handler im Code fehlt.</summary>
  TAtlasUndoMissingMethod = record
    Component: string;
    Path: string;
    Handler: string;
  end;

  /// <summary>Gründe in Failures in der Sprache der Oberfläche.</summary>
  TAtlasUndoReasons = record
    /// <summary>Komponente ließ sich nicht löschen.</summary>
    Delete: string;
    /// <summary>Komponente fehlt.</summary>
    Missing: string;
    /// <summary>Klassenname: Klasse unbekannt oder nicht anlegbar.</summary>
    ClassUnknown: string;
    /// <summary>Pfad: Wert nicht herstellbar.</summary>
    Value: string;
    /// <summary>Geerbt oder in einem eingebetteten Frame.</summary>
    Skipped: string;
  end;

  TAtlasDesignerUndoApply = class
  private type
    /// <summary>Text der Meldungen von TReader (FPC: AnsiString).</summary>
    TReaderText = {$IFDEF FPC}AnsiString{$ELSE}string{$ENDIF};
  private
    FSurface: IAtlasDesignSurface;
    FRoot: TComponent;
    FReasons: TAtlasUndoReasons;
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
    procedure ReaderError(Reader: TReader; const Message: TReaderText; var Handled: Boolean);
  public
    constructor Create(const ASurface: IAtlasDesignSurface; const AReasons: TAtlasUndoReasons);
    /// <summary>Führt APlan aus und gleicht danach die Werte mit ATarget ab.</summary>
    procedure Run(const APlan: TAtlasUndoPlan; const ATarget: string);
    /// <summary>Nicht hergestellt: „Schlüssel (Grund)“.</summary>
    property Failures: TArray<string> read FFailures;
    property MissingMethods: TArray<TAtlasUndoMissingMethod> read FMissing;
  end;

implementation

uses
  System.SysUtils,
  System.TypInfo;

type
  /// <summary>Zugriff auf das geschützte Loaded (E2362).</summary>
  TComponentAccess = class(TComponent);

const
  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  cNoDefaultValue = Integer($80000000);
  /// <summary>Puffer des TReader für die Werte einer Komponente.</summary>
  cReaderBuffer = 4096;

{ TAtlasDesignerUndoApply }

constructor TAtlasDesignerUndoApply.Create(const ASurface: IAtlasDesignSurface; const AReasons: TAtlasUndoReasons);
begin
  inherited Create;
  FSurface := ASurface;
  FRoot := ASurface.Root;
  FReasons := AReasons;
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
begin
  Result := TAtlasDesignSurfaces.Find(FRoot, AKey);
end;

procedure TAtlasDesignerUndoApply.DeleteComponent(const AKey: string);
begin
  if not FSurface.DeleteComponent(AKey) then
  begin
    Fail(AKey, FReasons.Delete);
  end;
end;

procedure TAtlasDesignerUndoApply.Rename(const ARename: TAtlasUndoRename);
var
  mComponent: TComponent;
begin
  mComponent := Find(ARename.OldKey);
  if mComponent = nil then
  begin
    Fail(ARename.OldKey, FReasons.Missing);
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
    Fail(ACreate.Key, Format(FReasons.ClassUnknown, [ACreate.TypeName]));
    Exit;
  end;
  try
    mComponent := FSurface.CreateComponent(TComponentClass(mClass), mParent);
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
    Fail(ACreate.Key, Format(FReasons.ClassUnknown, [ACreate.TypeName]));
    Exit;
  end;
  Apply(mComponent, ACreate);
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
    Fail(AKey, Format(FReasons.Value, [APath]));
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
    Fail(AKey, Format(FReasons.Value, [APath]));
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
    Fail(AKey, Format(FReasons.Value, [AEvent.Path]));
    Exit;
  end;
  mMethod.Code := nil;
  mMethod.Data := nil;
  if AEvent.Handler <> '' then
  begin
    // CreateMethod legte eine fehlende Methode neu an: Der Code bleibt aber unangetastet.
    if not FSurface.MethodExists(AEvent.Handler) then
    begin
      mMissing.Component := AComponent.Name;
      mMissing.Path := AEvent.Path;
      mMissing.Handler := AEvent.Handler;
      FMissing := FMissing + [mMissing];
      Exit;
    end;
    // Delphi führt den Typ über einen Zeiger mehr als FPC.
    mMethod := FSurface.CreateMethod(AEvent.Handler, GetTypeData(mProp^.PropType{$IFNDEF FPC}^{$ENDIF}));
  end;
  SetMethodProp(AComponent, mProp, mMethod);
end;

procedure TAtlasDesignerUndoApply.ReaderError(Reader: TReader; const Message: TReaderText; var Handled: Boolean);
begin
  // Unbekannte Eigenschaft oder falscher Wert: diesen Wert auslassen, die übrigen lesen.
  FReadErrors := FReadErrors + [Message];
  Handled := True;
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
    Fail(mKey, FReasons.Skipped);
  end;
  mPlan := APlan;
  if APlan.Structural then
  begin
    // Neu angelegte Komponenten tragen Vorgaben des Designers (Caption = Name): noch einmal abgleichen.
    mPlan := TAtlasFormUndo.Plan(TAtlasDesignSurfaces.FormText(FSurface), ATarget);
  end;
  for mChange in mPlan.Changes do
  begin
    mComponent := Find(mChange.Key);
    if mComponent = nil then
    begin
      Fail(mChange.Key, FReasons.Missing);
    end
    else
    begin
      Apply(mComponent, mChange);
    end;
  end;
end;

end.
