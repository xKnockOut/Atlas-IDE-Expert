unit Atlas.IDE.Forms.Designer;

// Formularinhalt aus dem Designer an den Server (#402). Bei offenem Formular
// liegt der aktuelle Stand im Designer, nicht in der .dfm auf der Platte.
// - Senden: Jedes offene Formular geht als eigenes Dokument (uri der .dfm,
//   didOpen/didChange) an den Server; der liest offene Dokumente vor der
//   Platte. Der Text entsteht wie beim Speichern (TAtlasFormText), die Namen
//   der Ereignis-Handler liefert der Designer (IDesigner.GetMethodName).
// - Änderungen im Designer (Komponente eingefügt, gelöscht, umbenannt,
//   Ereignis zugewiesen) meldet IDesignNotification; 500 ms danach geht der
//   neue Text an den Server. Ein geschlossenes Formular meldet Atlas mit
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
    FLastSession: TLspSession;
    /// <summary>Zuletzt gesendeter Text je Formulardatei (Schlüssel in Großbuchstaben).</summary>
    FTexts: TDictionary<string, string>;
    /// <summary>Wurzelkomponente → Formulardatei, für DesignerClosed.</summary>
    FRoots: TDictionary<TComponent, string>;
    procedure Tick(Sender: TObject);
    procedure Changed;
    procedure Closed(ARoot: TComponent);
    procedure SyncAll(ASession: TLspSession);
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
  Atlas.IDE.Foundation.EditorSnapshot;

const
  SyncDelayMs = 500;

function Key(const AFileName: string): string;
begin
  Result := AnsiUpperCase(AFileName);
end;

function FormEditors: TArray<IOTAFormEditor>;
var
  Services: IOTAModuleServices;
  Index, FileIndex: Integer;
  Module: IOTAModule;
  Editor: IOTAFormEditor;
begin
  Result := nil;
  if not Supports(BorlandIDEServices, IOTAModuleServices, Services) then
    Exit;
  for Index := 0 to Services.ModuleCount - 1 do
  begin
    Module := Services.Modules[Index];
    for FileIndex := 0 to Module.ModuleFileCount - 1 do
      if Supports(Module.ModuleFileEditors[FileIndex], IOTAFormEditor, Editor) then
        Result := Result + [Editor];
  end;
end;

function EditorOf(const AFileName: string): IOTAFormEditor;
var
  Editor: IOTAFormEditor;
begin
  Result := nil;
  for Editor in FormEditors do
    if SameText(Editor.FileName, AFileName) then
      Exit(Editor);
end;

function RootOf(const AEditor: IOTAFormEditor): TComponent;
var
  Component: INTAComponent;
begin
  Result := nil;
  if (AEditor <> nil) and Supports(AEditor.GetRootComponent, INTAComponent, Component) then
    Result := Component.GetComponent;
end;

function DesignerOf(const AEditor: IOTAFormEditor): IDesigner;
var
  Native: INTAFormEditor;
begin
  Result := nil;
  if Supports(AEditor, INTAFormEditor, Native) then
    Result := Native.FormDesigner;
end;

function TextOf(const AEditor: IOTAFormEditor): string;
var
  Root: TComponent;
  Designer: IDesigner;
begin
  Result := '';
  Root := RootOf(AEditor);
  Designer := DesignerOf(AEditor);
  if (Root = nil) or (Designer = nil) then
    Exit;
  Result := TAtlasFormText.Write(Root,
    function(AMethod: TMethod): string
    begin
      Result := Designer.GetMethodName(AMethod);
    end);
end;

const
  /// <summary>PropInfo.Default ohne default-Angabe (wie in System.Classes).</summary>
  NoDefaultValue = Integer($80000000);

/// <summary>Löst APath (auch Font.Name) an AComponent auf; '' oder der Grund.</summary>
function ResolveProperty(AComponent: TObject; const APath: string; out AInstance: TObject;
  out AProp: PPropInfo): string;
var
  Parts: TArray<string>;
  Index: Integer;
begin
  AInstance := AComponent;
  AProp := nil;
  Parts := APath.Split(['.']);
  if Length(Parts) = 0 then
    Exit('ohne Eigenschaft');
  for Index := 0 to High(Parts) - 1 do
  begin
    AProp := GetPropInfo(AInstance, Parts[Index]);
    if (AProp = nil) or (AProp^.PropType^.Kind <> tkClass) then
      Exit(Format('%s ist keine Objekt-Eigenschaft', [Parts[Index]]));
    AInstance := GetObjectProp(AInstance, AProp);
    if AInstance = nil then
      Exit(Format('%s ist nicht gesetzt', [Parts[Index]]));
  end;
  AProp := GetPropInfo(AInstance, Parts[High(Parts)]);
  if (AProp = nil) or (AProp^.SetProc = nil) then
    Exit(Format('%s lässt sich nicht setzen', [APath]));
  Result := '';
end;

/// <summary>DFM-Wert aus AChange in die Eigenschaft; mit ACheckOnly nur prüfen. '' oder der Grund.</summary>
function AssignValue(AInstance: TObject; AProp: PPropInfo; const AChange: TAtlasFormPropertyChange;
  ACheckOnly: Boolean): string;
var
  Text: string;
  Number: Integer;
  Number64: Int64;
  Float: Double;
  IdentToInt: TIdentToInt;
  Kind: TTypeKind;
begin
  Result := '';
  Kind := AProp^.PropType^.Kind;
  if AChange.Removed then
  begin
    // Zeile entfernt (Rückgängig, #721): zurück zum Vorgabewert der Deklaration.
    if Kind in [tkInteger, tkChar, tkWChar, tkEnumeration, tkSet] then
    begin
      if AProp^.Default = NoDefaultValue then
        Exit(Format('%s hat keinen Vorgabewert', [AChange.PropertyPath]));
      if not ACheckOnly then
        SetOrdProp(AInstance, AProp, AProp^.Default);
    end
    else if Kind in [tkString, tkLString, tkWString, tkUString] then
    begin
      if not ACheckOnly then
        SetStrProp(AInstance, AProp, '');
    end
    else
      Result := Format('%s hat keinen Vorgabewert', [AChange.PropertyPath]);
    Exit;
  end;
  case Kind of
    tkString, tkLString, tkWString, tkUString:
      begin
        if not TAtlasFormChanges.StringValue(AChange.Value, Text) then
          Exit(Format('%s: kein String-Wert', [AChange.PropertyPath]));
        if not ACheckOnly then
          SetStrProp(AInstance, AProp, Text);
      end;
    tkInteger:
      begin
        if not TryStrToInt(AChange.Value, Number) then
        begin
          // Bezeichner wie clRed oder crHandPoint.
          IdentToInt := FindIdentToInt(AProp^.PropType^);
          if not Assigned(IdentToInt) or not IdentToInt(AChange.Value, Number) then
            Exit(Format('%s: %s ist keine Zahl', [AChange.PropertyPath, AChange.Value]));
        end;
        if not ACheckOnly then
          SetOrdProp(AInstance, AProp, Number);
      end;
    tkInt64:
      begin
        if not TryStrToInt64(AChange.Value, Number64) then
          Exit(Format('%s: %s ist keine Zahl', [AChange.PropertyPath, AChange.Value]));
        if not ACheckOnly then
          SetInt64Prop(AInstance, AProp, Number64);
      end;
    tkEnumeration:
      begin
        Number := GetEnumValue(AProp^.PropType^, AChange.Value);
        if Number < 0 then
          Exit(Format('%s: unbekannter Wert %s', [AChange.PropertyPath, AChange.Value]));
        if not ACheckOnly then
          SetOrdProp(AInstance, AProp, Number);
      end;
    tkSet:
      begin
        try
          Number := StringToSet(AProp, AChange.Value);
        except
          on EPropertyConvertError do
            Exit(Format('%s: unbekanntes Element in %s', [AChange.PropertyPath, AChange.Value]));
        end;
        if not ACheckOnly then
          SetOrdProp(AInstance, AProp, Number);
      end;
    tkFloat:
      begin
        if not TryStrToFloat(AChange.Value, Float, TFormatSettings.Invariant) then
          Exit(Format('%s: %s ist keine Zahl', [AChange.PropertyPath, AChange.Value]));
        if not ACheckOnly then
          SetFloatProp(AInstance, AProp, Float);
      end;
  else
    Result := Format('%s: Typ wird im Designer nicht gesetzt', [AChange.PropertyPath]);
  end;
end;

{ TAtlasIdeForms.TNotification }

procedure TAtlasIdeForms.TNotification.ItemDeleted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
    FOwner.Changed;
end;

procedure TAtlasIdeForms.TNotification.ItemInserted(const ADesigner: IDesigner; AItem: TPersistent);
begin
  if FOwner <> nil then
    FOwner.Changed;
end;

procedure TAtlasIdeForms.TNotification.ItemsModified(const ADesigner: IDesigner);
begin
  if FOwner <> nil then
    FOwner.Changed;
end;

procedure TAtlasIdeForms.TNotification.SelectionChanged(const ADesigner: IDesigner;
  const ASelection: IDesignerSelections);
begin
end;

procedure TAtlasIdeForms.TNotification.DesignerOpened(const ADesigner: IDesigner; AResurrecting: Boolean);
begin
  if FOwner <> nil then
    FOwner.Changed;
end;

procedure TAtlasIdeForms.TNotification.DesignerClosed(const ADesigner: IDesigner; AGoingDormant: Boolean);
var
  Owner: TAtlasIdeForms;
  Root: TComponent;
begin
  Owner := FOwner;
  if (Owner = nil) or (ADesigner = nil) then
    Exit;
  Root := ADesigner.Root;
  TAtlasGuard.Run(TAtlasFeature.Forms,
    procedure
    begin
      Owner.Closed(Root);
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
  FNotification := TNotification.Create;
  FNotification.FOwner := Self;
  FNotificationRef := FNotification;
  RegisterDesignNotification(FNotificationRef);
  FTimer := TTimer.Create(nil);
  FTimer.Interval := SyncDelayMs;
  FTimer.OnTimer := Tick;
  FTimer.Enabled := True;
  FDirty := True;
  FCurrent := Self;
end;

destructor TAtlasIdeForms.Destroy;
begin
  // Erst abmelden, dann freigeben (#493).
  if FCurrent = Self then
    FCurrent := nil;
  FTimer.Free;
  FNotification.FOwner := nil;
  UnregisterDesignNotification(FNotificationRef);
  FNotificationRef := nil;
  FRoots.Free;
  FTexts.Free;
  inherited;
end;

procedure TAtlasIdeForms.Log(const AText: string);
begin
  if Assigned(FLog) then
    FLog(AText);
end;

procedure TAtlasIdeForms.Changed;
begin
  // Der Designer schreibt Felder und Methoden ohne Editorereignis in die Unit (P-04).
  TAtlasEditorSnapshots.Invalidate;
  // Erst nach einer Pause senden: Beim Ziehen kommt eine Meldung je Mausbewegung.
  FDirty := True;
  FTimer.Enabled := False;
  FTimer.Enabled := True;
end;

procedure TAtlasIdeForms.Tick(Sender: TObject);
var
  Session: TLspSession;
begin
  TAtlasGuard.Run(TAtlasFeature.Forms,
    procedure
    begin
      Session := nil;
      if Assigned(FSessionOf) then
        Session := FSessionOf();
      if Session = nil then
      begin
        FLastSession := nil;
        Exit;
      end;
      // Neue Sitzung (Serverstart, Neustart): alles neu schicken.
      if Session <> FLastSession then
      begin
        FLastSession := Session;
        FTexts.Clear;
        FDirty := True;
      end;
      if not FDirty then
        Exit;
      FDirty := False;
      SyncAll(Session);
    end);
end;

procedure TAtlasIdeForms.SyncAll(ASession: TLspSession);
var
  Editor: IOTAFormEditor;
  Root: TComponent;
  Text, Previous: string;
begin
  for Editor in FormEditors do
    try
      Root := RootOf(Editor);
      if Root = nil then
        Continue;
      FRoots.AddOrSetValue(Root, Editor.FileName);
      Text := TextOf(Editor);
      if (Text = '') or (FTexts.TryGetValue(Key(Editor.FileName), Previous) and (Previous = Text)) then
        Continue;
      ASession.Sync(Editor.FileName, Text);
      FTexts.AddOrSetValue(Key(Editor.FileName), Text);
    except
      on E: Exception do
        Log(Format('Formular %s nicht gesendet: %s', [ExtractFileName(Editor.FileName), E.Message]));
    end;
end;

procedure TAtlasIdeForms.Closed(ARoot: TComponent);
var
  FileName: string;
  Session: TLspSession;
begin
  if not FRoots.TryGetValue(ARoot, FileName) then
    Exit;
  FRoots.Remove(ARoot);
  FTexts.Remove(Key(FileName));
  Session := nil;
  if Assigned(FSessionOf) then
    Session := FSessionOf();
  if Session <> nil then
    try
      Session.Close(FileName);
    except
      on E: Exception do
        Log(Format('Formular %s nicht abgemeldet: %s', [ExtractFileName(FileName), E.Message]));
    end;
end;

class procedure TAtlasIdeForms.SyncNow(ASession: TLspSession);
begin
  if (FCurrent = nil) or (ASession = nil) then
    Exit;
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
  Sent, Edited, Reason: string;
begin
  AChanges := nil;
  AProperties := nil;
  // Die Positionen des Servers beziehen sich auf den Text, den Atlas zuletzt geschickt hat.
  if (FCurrent = nil) or not FCurrent.FTexts.TryGetValue(Key(AFileName), Sent) then
    Exit('im Designer offen, aber noch nicht an den Server gemeldet');
  try
    Edited := TLspEdits.Apply(Sent, AEdits);
  except
    on E: ELspEditError do
      Exit(E.Message);
  end;
  if not TAtlasFormChanges.Diff(Sent, Edited, AChanges, AProperties, Reason) then
    Exit(Format('im Designer offen; dort ändert Atlas nur Ereignis-Zuordnungen und einzeilige Eigenschaften (%s)',
      [Reason]));
  Result := '';
end;

class function TAtlasIdeForms.Apply(const AFileName: string; const AChanges: TArray<TAtlasFormEventChange>;
  const AProperties: TArray<TAtlasFormPropertyChange>): string;
var
  Editor: IOTAFormEditor;
  Designer: IDesigner;
  Root, Component: TComponent;
  Targets: TArray<TComponent>;
  Properties, ValueProps: TArray<PPropInfo>;
  ValueTargets: TArray<TObject>;
  PropInfo: PPropInfo;
  Instance: TObject;
  Change: TAtlasFormEventChange;
  Prop: TAtlasFormPropertyChange;
  Index: Integer;
  Reason: string;
begin
  Editor := EditorOf(AFileName);
  Root := RootOf(Editor);
  Designer := DesignerOf(Editor);
  if (Root = nil) or (Designer = nil) then
    Exit('Formular ist nicht mehr offen');
  // Erst alles prüfen, dann setzen: Entweder alle Zuordnungen oder keine.
  Targets := nil;
  Properties := nil;
  for Change in AChanges do
  begin
    if Change.Component = '' then
      Component := Root
    else
      Component := Root.FindComponent(Change.Component);
    if Component = nil then
      Exit(Format('Komponente %s nicht gefunden', [Change.Component]));
    PropInfo := GetPropInfo(Component, Change.EventName);
    if (PropInfo = nil) or (PropInfo^.PropType^.Kind <> tkMethod) then
      Exit(Format('%s.%s ist kein Ereignis', [Component.Name, Change.EventName]));
    // Die Unit ist schon geändert; der Handler muss dort unter dem neuen Namen stehen.
    if not Designer.MethodExists(Change.NewHandler) then
      Exit(Format('Methode %s fehlt in der Unit', [Change.NewHandler]));
    Targets := Targets + [Component];
    Properties := Properties + [PropInfo];
  end;
  ValueTargets := nil;
  ValueProps := nil;
  for Prop in AProperties do
  begin
    if Prop.Component = '' then
      Component := Root
    else
      Component := Root.FindComponent(Prop.Component);
    if Component = nil then
      Exit(Format('Komponente %s nicht gefunden', [Prop.Component]));
    Reason := ResolveProperty(Component, Prop.PropertyPath, Instance, PropInfo);
    if Reason = '' then
      Reason := AssignValue(Instance, PropInfo, Prop, True);
    if Reason <> '' then
      Exit(Format('%s: %s', [Component.Name, Reason]));
    ValueTargets := ValueTargets + [Instance];
    ValueProps := ValueProps + [PropInfo];
  end;
  for Index := 0 to High(AChanges) do
    SetMethodProp(Targets[Index], Properties[Index], Designer.CreateMethod(AChanges[Index].NewHandler,
      GetTypeData(Properties[Index]^.PropType^)));
  for Index := 0 to High(AProperties) do
    AssignValue(ValueTargets[Index], ValueProps[Index], AProperties[Index], False);
  if (Length(AChanges) > 0) or (Length(AProperties) > 0) then
  begin
    Designer.Modified;
    if FCurrent <> nil then
      FCurrent.Changed;
  end;
  Result := '';
end;

end.
