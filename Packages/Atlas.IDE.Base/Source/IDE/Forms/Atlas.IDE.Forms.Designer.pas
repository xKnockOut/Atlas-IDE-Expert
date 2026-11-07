unit Atlas.IDE.Forms.Designer;

// Formularinhalt aus dem Designer an den Server (#402). Bei offenem Formular
// liegt der aktuelle Stand im Designer, nicht in der .dfm auf der Platte.
// - Senden: Jedes offene Formular geht als eigenes Dokument (uri der .dfm,
//   didOpen/didChange) an den Server; der liest offene Dokumente vor der
//   Platte. Der Text entsteht wie beim Speichern (TAtlasFormText), die Namen
//   der Ereignis-Handler liefert der Designer (IDesigner.GetMethodName).
// - Änderungen im Designer (Komponente eingefügt, gelöscht, umbenannt,
//   Ereignis zugewiesen) meldet IDesignNotification; 500 ms danach geht der
//   neue Text an den Server, nur für die geänderten Formulare (vorher wurde
//   jedes offene Formular neu in Text gewandelt, im Diagnose-Fenster bis
//   266 ms je Änderung). Ein geschlossenes Formular meldet Atlas mit
//   didClose ab, danach gilt wieder die Datei. Nach einem Serverneustart
//   gehen alle Formulare neu an den Server.
// - Änderungen des Servers an einem offenen Formular (Umbenennen eines
//   Handlers, #397) schreibt Atlas nicht auf die Platte, sonst überschreibt
//   der Designer sie beim Speichern: TAtlasFormChanges vergleicht den
//   gesendeten mit dem geänderten Text, die Ereignis-Zuordnungen und einzeilige
//   Eigenschaften (Eigenschaftsregeln, #309) setzt Atlas im Designer über RTTI.
//   Andere Änderungen an offenen Formularen lehnt Atlas ab.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  System.Generics.Collections,
  Vcl.ExtCtrls,
  ToolsAPI,
  DesignIntf,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.WorkspaceEdits,
  Atlas.Core.Forms.Changes;

type
  TAtlasIdeForms = class
  private type
    TNotification = class(TInterfacedObject, IDesignNotification)
    private
      FOwner: TAtlasIdeForms;
    public
      procedure ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
      procedure ItemsModified(const ADesigner: IDesigner);
      procedure SelectionChanged(const ADesigner: IDesigner; const ASelection: IDesignerSelections);
      procedure DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
      procedure DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
    end;
  private class var
    FCurrent: TAtlasIdeForms;
  private
    FSessionOf: TFunc<TLspSession>;
    FLog: TProc<string>;
    FNotification: TNotification;
    FNotificationRef: IDesignNotification;
    FTimer: TTimer;
    FDirty: Boolean;
    /// <summary>Alle Formulare senden (Start, neue Sitzung, Änderung ohne Designer); sonst nur FDirtyRoots.
    /// </summary>
    FAll: Boolean;
    /// <summary>Wurzeln der Formulare, die sich seit dem letzten Senden geändert haben; nur verglichen, nie
    /// benutzt (die Komponente kann inzwischen frei sein).</summary>
    FDirtyRoots: TList<TComponent>;
    FLastSession: TLspSession;
    /// <summary>Zuletzt gesendeter Text je Formulardatei (Schlüssel in Großbuchstaben).</summary>
    FTexts: TDictionary<string, string>;
    /// <summary>Wurzelkomponente → Formulardatei, für DesignerClosed.</summary>
    FRoots: TDictionary<TComponent, string>;
    procedure Tick(Sender: TObject);
    /// <summary>Formular von ADesigner geändert; nil: welches, ist unbekannt (alle senden).</summary>
    procedure Changed(const ADesigner: IDesigner);
    procedure Closed(ARoot: TComponent);
    procedure SyncAll(ASession: TLspSession);
    /// <summary>Nur die geänderten Formulare (FDirtyRoots) senden.</summary>
    procedure SyncDirty(ASession: TLspSession);
    procedure SyncEditor(ASession: TLspSession; const AEditor: IOTAFormEditor; ARoot: TComponent);
    procedure Log(const AText: string);
  public
    /// <summary>ASessionOf: laufende Sitzung, ohne den Server zu starten; ALog: Diagnoseprotokoll.</summary>
    constructor Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
    destructor Destroy; override;
    /// <summary>Alle offenen Formulare sofort an ASession schicken, z. B. vor dem Umbenennen.</summary>
    class procedure SyncNow(ASession: TLspSession); static;
    /// <summary>Zuletzt an den Server geschickter Text eines offenen Formulars.</summary>
    class function SentText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Aktueller Stand eines offenen Formulars im Designer als Text, wie er an den Server ginge
    /// (#721); False, wenn es nicht offen ist.</summary>
    class function CurrentText(const AFileName: string; out AText: string): Boolean; static;
    /// <summary>Ist AFileName (.dfm/.fmx) gerade im Designer offen?</summary>
    class function IsOpen(const AFileName: string): Boolean; static;
    /// <summary>Lassen sich AEdits im offenen Formular ausführen? '' mit AChanges und AProperties, sonst der
    /// Grund.</summary>
    class function Check(const AFileName: string; const AEdits: TArray<TLspTextEdit>;
      out AChanges: TArray<TAtlasFormEventChange>; out AProperties: TArray<TAtlasFormPropertyChange>): string;
      static;
    /// <summary>Setzt Ereignis-Zuordnungen und Eigenschaften (#309) im Designer; '' bei Erfolg, sonst der
    /// Grund (nichts geändert).</summary>
    class function Apply(const AFileName: string; const AChanges: TArray<TAtlasFormEventChange>;
      const AProperties: TArray<TAtlasFormPropertyChange>): string; static;
  end;

implementation

uses
  System.TypInfo,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.Forms.Text,
  Atlas.IDE.Foundation.EditorSnapshot,
  Atlas.Core.Localization.Language;

{$SCOPEDENUMS ON}

type
  /// <summary>Benutzertexte dieser Unit (#1458).</summary>
  TDesignerText = (IsNotAnObjectProperty, IsNotSet, CannotBeSet, HasNoDefaultValue, NotAStringValue, IsNotANumber,
    TypeIsNotSetIn, ComponentNotFound, IsNotAnEvent, MethodIsMissingInThe, OpenInTheDesignerBut,
    OpenInTheDesignerThere, FormIsNoLongerOpen);
{$SCOPEDENUMS OFF}

const
  cTexts: array[TAtlasLanguage, TDesignerText] of string = (
    ('%s ist keine Objekt-Eigenschaft',
     '%s ist nicht gesetzt',
     '%s lässt sich nicht setzen',
     '%s hat keinen Vorgabewert',
     '%s: kein String-Wert',
     '%s: %s ist keine Zahl',
     '%s: Typ wird im Designer nicht gesetzt',
     'Komponente %s nicht gefunden',
     '%s.%s ist kein Ereignis',
     'Methode %s fehlt in der Unit',
     'im Designer offen, aber noch nicht an den Server gemeldet',
     'im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen und einzeilige Eigenschaften (%s)',
     'Formular ist nicht mehr offen'),
    ('%s is not an object property',
     '%s is not set',
     '%s cannot be set',
     '%s has no default value',
     '%s: not a string value',
     '%s: %s is not a number',
     '%s: type is not set in the designer',
     'component %s not found',
     '%s.%s is not an event',
     'method %s is missing in the unit',
     'open in the designer, but not yet reported to the server',
     'open in the designer; there Atlas only changes event assignments and single-line properties (%s)',
     'form is no longer open'));

/// <summary>Text AId in der Sprache der Oberfläche.</summary>
function UiText(AId: TDesignerText): string;
begin
  Result := cTexts[TAtlasTextLanguage.Current, AId];
end;

const
  cSyncDelayMs = 500;

function Key(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

function FormEditors: TArray<IOTAFormEditor>;
var
  mServices: IOTAModuleServices;
  mIndex, mFileIndex: Integer;
  mModule: IOTAModule;
  mEditor: IOTAFormEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, mServices) then
  begin
    Exit;
  end;
  for mIndex := 0 to mServices.ModuleCount - 1 do
  begin
    mModule := mServices.Modules[mIndex];
    for mFileIndex := 0 to mModule.ModuleFileCount - 1 do
    begin
      if Supports(mModule.ModuleFileEditors[mFileIndex], IOTAFormEditor, mEditor) then
      begin
        Result := Result + [mEditor];
      end;
    end;
  end;
end;

function EditorOf(const AFileName: string): IOTAFormEditor;
var
  mEditor: IOTAFormEditor;
begin
  Result := nil;
  for mEditor in FormEditors do
  begin
    if SameText(mEditor.FileName, AFileName) then
    begin
      Exit(mEditor);
    end;
  end;
end;

function RootOf(const AEditor: IOTAFormEditor): TComponent;
var
  mComponent: INTAComponent;
begin
  Result := nil;
  if (AEditor <> nil) and Supports(AEditor.GetRootComponent, INTAComponent, mComponent) then
  begin
    Result := mComponent.GetComponent;
  end;
end;

function DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  mNative: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, mNative) then
  begin
    Result := mNative.FormDesigner;
  end;
end;

function TextOf(const AEditor: IOTAFormEditor): string;
var
  mRoot: TComponent;
  mDesigner: IDesigner;
begin
  Result := '';
  mRoot := RootOf(AEditor);
  mDesigner := DesignerOf(AEditor);
  if (mRoot = nil) or (mDesigner = nil) then
  begin
    Exit;
  end;
  Result := TAtlasFormText.Write(mRoot,
    function(AMethod: TMethod): string
    begin
      Result := mDesigner.GetMethodName(AMethod);
    end);
end;

const
  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  cNoDefaultValue = Integer($80000000);

/// <summary>Löst APath (auch Font.Name) an AComponent auf; '' oder der Grund.</summary>
function ResolveProperty(AComponent: TObject; const APath: string; out AInstance: TObject;
  out AProp: PPropInfo): string;
var
  mParts: TArray<string>;
  mIndex: Integer;
begin
  AInstance := AComponent;
  AProp := nil;
  mParts := APath.Split(['.']);
  if Length(mParts) = 0 then
  begin
    Exit('ohne Eigenschaft');
  end;
  for mIndex := 0 to High(mParts) - 1 do
  begin
    AProp := GetPropInfo(AInstance, mParts[mIndex]);
    if (AProp = nil) or (AProp^.PropType^.Kind <> tkClass) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotAnObjectProperty), [mParts[mIndex]]));
    end;
    AInstance := GetObjectProp(AInstance, AProp);
    if AInstance = nil then
    begin
      Exit(Format(UiText(TDesignerText.IsNotSet), [mParts[mIndex]]));
    end;
  end;
  AProp := GetPropInfo(AInstance, mParts[High(mParts)]);
  if (AProp = nil) or (AProp^.SetProc = nil) then
  begin
    Exit(Format(UiText(TDesignerText.CannotBeSet), [APath]));
  end;
  Result := '';
end;

/// <summary>Zeile entfernt (Rückgängig, #721): zurück zum Vorgabewert der Deklaration.</summary>
function ResetValue(AInstance: TObject; AProp: PPropInfo; const APath: string; ACheckOnly: Boolean): string;
var
  mKind: TTypeKind;
begin
  Result := '';
  mKind := AProp^.PropType^.Kind;
  if (mKind in [tkInteger, tkChar, tkWChar, tkEnumeration, tkSet]) and (AProp^.Default <> cNoDefaultValue) then
  begin
    if not ACheckOnly then
    begin
      SetOrdProp(AInstance, AProp, AProp^.Default);
    end;
  end
  else if mKind in [tkString, tkLString, tkWString, tkUString] then
  begin
    if not ACheckOnly then
    begin
      SetStrProp(AInstance, AProp, '');
    end;
  end
  else
  begin
    Result := Format(UiText(TDesignerText.HasNoDefaultValue), [APath]);
  end;
end;

function AssignString(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mText: string;
begin
  Result := '';
  if not TAtlasFormChanges.StringValue(AChange.Value, mText) then
  begin
    Result := Format(UiText(TDesignerText.NotAStringValue), [AChange.PropertyPath]);
  end
  else if not ACheckOnly then
  begin
    SetStrProp(AInstance, AProp, mText);
  end;
end;

/// <summary>Ganzzahl oder Bezeichner wie clRed oder crHandPoint.</summary>
function AssignInteger(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
  mIdentToInt: TIdentToInt;
begin
  Result := '';
  if not TryStrToInt(AChange.Value, mNumber) then
  begin
    mIdentToInt := FindIdentToInt(AProp^.PropType^);
    if not Assigned(mIdentToInt) or not mIdentToInt(AChange.Value, mNumber) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]));
    end;
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignInt64(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Int64;
begin
  Result := '';
  if not TryStrToInt64(AChange.Value, mNumber) then
  begin
    Result := Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetInt64Prop(AInstance, AProp, mNumber);
  end;
end;

function AssignEnumeration(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  mNumber := GetEnumValue(AProp^.PropType^, AChange.Value);
  if mNumber < 0 then
  begin
    Result := Format('%s: unbekannter Wert %s', [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignSet(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mNumber: Integer;
begin
  Result := '';
  try
    mNumber := StringToSet(AProp, AChange.Value);
  except
    on EPropertyConvertError do
      Exit(Format('%s: unbekanntes Element in %s', [AChange.PropertyPath, AChange.Value]));
  end;
  if not ACheckOnly then
  begin
    SetOrdProp(AInstance, AProp, mNumber);
  end;
end;

function AssignFloat(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  mFloat: Double;
begin
  Result := '';
  if not TryStrToFloat(AChange.Value, mFloat, TFormatSettings.Invariant) then
  begin
    Result := Format(UiText(TDesignerText.IsNotANumber), [AChange.PropertyPath, AChange.Value]);
  end
  else if not ACheckOnly then
  begin
    SetFloatProp(AInstance, AProp, mFloat);
  end;
end;

/// <summary>DFM-Wert aus AChange in die Eigenschaft; mit ACheckOnly nur prüfen. '' oder der Grund.</summary>
function AssignValue(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
begin
  if AChange.Removed then
  begin
    Exit(ResetValue(AInstance, AProp, AChange.PropertyPath, ACheckOnly));
  end;
  case AProp^.PropType^.Kind of
    tkString, tkLString, tkWString, tkUString:
      Result := AssignString(AInstance, AProp, AChange, ACheckOnly);
    tkInteger:
      Result := AssignInteger(AInstance, AProp, AChange, ACheckOnly);
    tkInt64:
      Result := AssignInt64(AInstance, AProp, AChange, ACheckOnly);
    tkEnumeration:
      Result := AssignEnumeration(AInstance, AProp, AChange, ACheckOnly);
    tkSet:
      Result := AssignSet(AInstance, AProp, AChange, ACheckOnly);
    tkFloat:
      Result := AssignFloat(AInstance, AProp, AChange, ACheckOnly);
  else
    Result := Format(UiText(TDesignerText.TypeIsNotSetIn), [AChange.PropertyPath]);
  end;
end;

/// <summary>Komponente AName unter ARoot; '' ist die Wurzel selbst.</summary>
function ComponentOf(ARoot: TComponent; const AName: string): TComponent;
begin
  Result := ARoot;
  if AName <> '' then
  begin
    Result := ARoot.FindComponent(AName);
  end;
end;

/// <summary>Ziele der Ereignis-Zuordnungen; '' oder der Grund.</summary>
function CheckEvents(ARoot: TComponent; const ADesigner: IDesigner; const AChanges: TArray<TAtlasFormEventChange>;
  out ATargets: TArray<TComponent>; out AProperties: TArray<PPropInfo>): string;
var
  mChange: TAtlasFormEventChange;
  mComponent: TComponent;
  mPropInfo: PPropInfo;
begin
  ATargets := nil;
  AProperties := nil;
  for mChange in AChanges do
  begin
    mComponent := ComponentOf(ARoot, mChange.Component);
    if mComponent = nil then
    begin
      Exit(Format(UiText(TDesignerText.ComponentNotFound), [mChange.Component]));
    end;
    mPropInfo := GetPropInfo(mComponent, mChange.EventName);
    if (mPropInfo = nil) or (mPropInfo^.PropType^.Kind <> tkMethod) then
    begin
      Exit(Format(UiText(TDesignerText.IsNotAnEvent), [mComponent.Name, mChange.EventName]));
    end;
    // Die Unit ist schon geändert; der Handler muss dort unter dem neuen Namen stehen.
    if not ADesigner.MethodExists(mChange.NewHandler) then
    begin
      Exit(Format(UiText(TDesignerText.MethodIsMissingInThe), [mChange.NewHandler]));
    end;
    ATargets := ATargets + [mComponent];
    AProperties := AProperties + [mPropInfo];
  end;
  Result := '';
end;

/// <summary>Ziele der Eigenschaften, Werte geprüft; '' oder der Grund.</summary>
function CheckProperties(ARoot: TComponent; const AProperties: TArray<TAtlasFormPropertyChange>;
  out ATargets: TArray<TObject>; out AProps: TArray<PPropInfo>): string;
var
  mProp: TAtlasFormPropertyChange;
  mComponent: TComponent;
  mInstance: TObject;
  mPropInfo: PPropInfo;
  mReason: string;
begin
  ATargets := nil;
  AProps := nil;
  for mProp in AProperties do
  begin
    mComponent := ComponentOf(ARoot, mProp.Component);
    if mComponent = nil then
    begin
      Exit(Format(UiText(TDesignerText.ComponentNotFound), [mProp.Component]));
    end;
    mReason := ResolveProperty(mComponent, mProp.PropertyPath, mInstance, mPropInfo);
    if mReason = '' then
    begin
      mReason := AssignValue(mInstance, mPropInfo, mProp, True);
    end;
    if mReason <> '' then
    begin
      Exit(Format('%s: %s', [mComponent.Name, mReason]));
    end;
    ATargets := ATargets + [mInstance];
    AProps := AProps + [mPropInfo];
  end;
  Result := '';
end;

{ TAtlasIdeForms.TNotification }

procedure TAtlasIdeForms.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TAtlasIdeForms.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TAtlasIdeForms.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TAtlasIdeForms.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
end;

procedure TAtlasIdeForms.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
  begin
    FOwner.Changed(ADesigner);
  end;
end;

procedure TAtlasIdeForms.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
var
  mOwner: TAtlasIdeForms;
  mRoot: TComponent;
begin
  mOwner := FOwner;
  if (mOwner = nil) or (ADesigner = nil) then
  begin
    Exit;
  end;
  mRoot := ADesigner.Root;
  TAtlasGuard.Run(TAtlasFeature.Forms,
    procedure
    begin
      mOwner.Closed(mRoot);
    end);
end;

{ TAtlasIdeForms }

constructor TAtlasIdeForms.Create(const ASessionOf: TFunc<TLspSession>; const ALog: TProc<string>);
begin
  inherited Create;
  FSessionOf := ASessionOf;
  FLog := ALog;
  FTexts := TDictionary<string, string>.Create;
  FRoots := TDictionary<TComponent, string>.Create;
  FDirtyRoots := TList<TComponent>.Create;
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := cSyncDelayMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FDirty := True;
  FAll := True;
  FCurrent := Self;
end;

destructor TAtlasIdeForms.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if FCurrent = Self then
  begin
    FCurrent := nil;
  end;
  FTimer.Free;
  FNotification.FOwner := nil;
  UnregisterDesignNotification(FNotificationRef);
  FNotificationRef := nil;
  FDirtyRoots.Free;
  FRoots.Free;
  FTexts.Free;
  inherited;
end;

procedure TAtlasIdeForms.Log(const AText: string);
begin
  if Assigned(FLog) then
  begin
    FLog(AText);
  end;
end;

procedure TAtlasIdeForms.Changed(const ADesigner: IDesigner);
var
  mRoot: TComponent;
begin
  mRoot := nil;
  if ADesigner <> nil then
  begin
    mRoot := ADesigner.Root;
  end;
  if mRoot = nil then
  begin
    FAll := True;
  end
  else if not FDirtyRoots.Contains(mRoot) then
  begin
    FDirtyRoots.Add(mRoot);
  end;
  // Der Designer schreibt Felder und Methoden ohne Editorereignis in die Unit (P-04).
  TAtlasEditorSnapshots.Invalidate;
  // Erst nach einer Pause senden: Beim Ziehen kommt eine Meldung je Mausbewegung.
  FDirty := True;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeForms.Tick(Sender: TObject);
var
  mSession: TLspSession;
begin
  TAtlasGuard.Run(TAtlasFeature.Forms,
    procedure
    begin
      mSession := nil;
      if Assigned(FSessionOf) then
      begin
        mSession := FSessionOf();
      end;
      if mSession = nil then
      begin
        FLastSession := nil;
        Exit;
      end;
      // Neue Sitzung (Serverstart, Neustart): alles neu schicken.
      if mSession <> FLastSession then
      begin
        FLastSession := mSession;
        FTexts.Clear;
        FDirty := True;
        FAll := True;
      end;
      if not FDirty then
      begin
        Exit;
      end;
      FDirty := False;
      if FAll then
      begin
        SyncAll(mSession);
      end
      else
      begin
        SyncDirty(mSession);
      end;
    end);
end;

procedure TAtlasIdeForms.SyncAll(ASession: TLspSession);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  FAll := False;
  FDirtyRoots.Clear;
  for mEditor in FormEditors do
  begin
    mRoot := RootOf(mEditor);
    if mRoot <> nil then
    begin
      SyncEditor(ASession, mEditor, mRoot);
    end;
  end;
end;

procedure TAtlasIdeForms.SyncDirty(ASession: TLspSession);
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
begin
  if FDirtyRoots.Count = 0 then
  begin
    Exit;
  end;
  for mEditor in FormEditors do
  begin
    mRoot := RootOf(mEditor);
    if (mRoot <> nil) and FDirtyRoots.Contains(mRoot) then
    begin
      SyncEditor(ASession, mEditor, mRoot);
    end;
  end;
  FDirtyRoots.Clear;
end;

procedure TAtlasIdeForms.SyncEditor(ASession: TLspSession; const AEditor: IOTAFormEditor; ARoot: TComponent);
var
  mText, mPrevious: string;
begin
  try
    FRoots.AddOrSetValue(ARoot, AEditor.FileName);
    mText := TextOf(AEditor);
    if (mText = '') or (FTexts.TryGetValue(Key(AEditor.FileName), mPrevious) and (mPrevious = mText)) then
    begin
      Exit;
    end;
    ASession.Sync(AEditor.FileName, mText);
    FTexts.AddOrSetValue(Key(AEditor.FileName), mText);
  except
    on E: Exception do
      Log(Format('Formular %s nicht gesendet: %s', [ExtractFileName(AEditor.FileName), E.Message]));
  end;
end;

procedure TAtlasIdeForms.Closed(ARoot: TComponent);
var
  mFileName: string;
  mSession: TLspSession;
begin
  if not FRoots.TryGetValue(ARoot, mFileName) then
  begin
    Exit;
  end;
  FRoots.Remove(ARoot);
  FTexts.Remove(Key(mFileName));
  mSession := nil;
  if Assigned(FSessionOf) then
  begin
    mSession := FSessionOf();
  end;
  if mSession <> nil then
    try
      mSession.Close(mFileName);
    except
      on E: Exception do
        Log(Format('Formular %s nicht abgemeldet: %s', [ExtractFileName(mFileName), E.Message]));
    end;
end;

class procedure TAtlasIdeForms.SyncNow(ASession: TLspSession);
begin
  if (FCurrent = nil) or (ASession = nil) then
  begin
    Exit;
  end;
  if ASession <> FCurrent.FLastSession then
  begin
    FCurrent.FLastSession := ASession;
    FCurrent.FTexts.Clear;
  end;
  FCurrent.FDirty := False;
  FCurrent.SyncAll(ASession);
end;

class function TAtlasIdeForms.SentText(const AFileName: string; out AText: string): Boolean;
begin
  AText := '';
  Result := (FCurrent <> nil) and FCurrent.FTexts.TryGetValue(Key(AFileName), AText);
end;

class function TAtlasIdeForms.CurrentText(const AFileName: string; out AText: string): Boolean;
begin
  AText := TextOf(EditorOf(AFileName));
  Result := AText <> '';
end;

class function TAtlasIdeForms.IsOpen(const AFileName: string): Boolean;
begin
  Result := RootOf(EditorOf(AFileName)) <> nil;
end;

class function TAtlasIdeForms.Check(const AFileName: string; const AEdits: TArray<TLspTextEdit>;
  out AChanges: TArray<TAtlasFormEventChange>; out AProperties: TArray<TAtlasFormPropertyChange>): string;
var
  mSent, mEdited, mReason: string;
begin
  AChanges := nil;
  AProperties := nil;
  // Die Positionen des Servers beziehen sich auf den Text, den Atlas zuletzt geschickt hat.
  if (FCurrent = nil) or not FCurrent.FTexts.TryGetValue(Key(AFileName), mSent) then
  begin
    Exit(UiText(TDesignerText.OpenInTheDesignerBut));
  end;
  try
    mEdited := TLspEdits.Apply(mSent, AEdits);
  except
    on E: ELspEditError do
      Exit(E.Message);
  end;
  if not TAtlasFormChanges.Diff(mSent, mEdited, AChanges, AProperties, mReason) then
  begin
    Exit(Format(UiText(TDesignerText.OpenInTheDesignerThere),
      [mReason]));
  end;
  Result := '';
end;

class function TAtlasIdeForms.Apply(const AFileName: string; const AChanges: TArray<TAtlasFormEventChange>;
  const AProperties: TArray<TAtlasFormPropertyChange>): string;
var
  mEditor: IOTAFormEditor;
  mDesigner: IDesigner;
  mRoot: TComponent;
  mTargets: TArray<TComponent>;
  mProperties, mValueProps: TArray<PPropInfo>;
  mValueTargets: TArray<TObject>;
  mIndex: Integer;
begin
  mEditor := EditorOf(AFileName);
  mRoot := RootOf(mEditor);
  mDesigner := DesignerOf(mEditor);
  if (mRoot = nil) or (mDesigner = nil) then
  begin
    Exit(UiText(TDesignerText.FormIsNoLongerOpen));
  end;
  // Erst alles prüfen, dann setzen: Entweder alle Zuordnungen oder keine.
  Result := CheckEvents(mRoot, mDesigner, AChanges, mTargets, mProperties);
  if Result = '' then
  begin
    Result := CheckProperties(mRoot, AProperties, mValueTargets, mValueProps);
  end;
  if Result <> '' then
  begin
    Exit;
  end;
  for mIndex := 0 to High(AChanges) do
  begin
    SetMethodProp(mTargets[mIndex], mProperties[mIndex], mDesigner.CreateMethod(AChanges[mIndex].NewHandler,
      GetTypeData(mProperties[mIndex]^.PropType^)));
  end;
  for mIndex := 0 to High(AProperties) do
  begin
    AssignValue(mValueTargets[mIndex], mValueProps[mIndex], AProperties[mIndex], False);
  end;
  if (Length(AChanges) > 0) or (Length(AProperties) > 0) then
  begin
    mDesigner.Modified;
    if FCurrent <> nil then
    begin
      FCurrent.Changed(mDesigner);
    end;
  end;
end;

initialization
  TAtlasTextLanguage.AddTable('Atlas.IDE.Forms.Designer', cTexts[TAtlasLanguage.German], cTexts[TAtlasLanguage.English]);

end.
