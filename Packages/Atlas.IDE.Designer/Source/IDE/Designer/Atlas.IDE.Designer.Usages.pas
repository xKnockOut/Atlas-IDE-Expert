unit Atlas.IDE.Designer.Usages;

// „Verwendungen im Code“ aus dem Designer (#750, designer.usages):
// - Knopf der Designer-Leiste, Befehl im Atlas-Menü und Taste
//   designer.usages.key (Vorgabe Umschalt+Alt+F7), solange der Designer den
//   Fokus hat. Für jede markierte Komponente fragt Atlas die Referenzsuche an
//   ihrer Felddeklaration in der Formular-Klasse (offene Puffer vorher
//   abgeglichen), behält die Fundorte im Bereich designer.usages.scope und
//   ordnet jeden ein (TAtlasDesignerUsages). Ergebnisfenster: je Komponente,
//   Unit und Methode eine Gruppe, je Fundort Zeile, Art und Vorschau; die
//   Handler aus der DFM in der Gruppe „Ereignisse (DFM)“. Doppelklick
//   springt zur Stelle.
// - Zähler im Atlas-Statusfeld (designer.usages.statusCount) für genau eine
//   markierte Komponente: nach einem Auswahlwechsel entprellt im Hintergrund
//   über die laufende Sitzung (ohne Abgleich der Puffer und ohne den Server
//   zu starten); bis zur Antwort „…“. Klick öffnet die Liste.
// Nur im Hauptthread.

interface

uses
  System.SysUtils,
  System.Classes,
  ToolsAPI,
  Atlas.Core.Modules.Contract,
  Atlas.Core.Settings.Plugin,
  Atlas.UI.Designer.Bar,
  Atlas.IDE.Foundation.KeyHook;

type
  TAtlasIdeDesignerUsages = class
  public const
    cId = 'usages';
    cOwner = 'designerUsages';
  private class var
    FOnMessage: TProc<string>;
    FScopeOf: TFunc<IAtlasModuleScope>;
    FKeys: TAtlasKeyClient;
    /// <summary>Zuletzt gesehene Auswahl („Unit|Komponente“) und seit wann.</summary>
    FWatched: string;
    FSince: UInt64;
    /// <summary>Auswahl, für die der Zähler gefragt ist bzw. steht.</summary>
    FAsked: string;
    /// <summary>Zählt jede Frage des Zählers; eine Antwort mit anderer Nummer ist überholt.</summary>
    FGeneration: Integer;
    FShown: Boolean;
    class procedure Say(const AText: string); static;
    class procedure ShowCount(const AName: string; const AJson: string; AEvents, AGeneration: Integer); static;
    class procedure ClearStatus; static;
    class procedure UpdateKeys(const ASettings: TAtlasPluginSettings); static;
    /// <summary>Zähler für AComponent im Hintergrund erfragen; bis zur Antwort „…“.</summary>
    class procedure AskCount(const AEditor: IOTAFormEditor; ARoot, AComponent: TComponent); static;
  public
    /// <summary>AScopeOf: Scope des Moduls für Anfragen im Hintergrund; AOnMessage: Zeile in der
    /// Meldungsansicht.</summary>
    class procedure Install(const AScopeOf: TFunc<IAtlasModuleScope>; const AOnMessage: TProc<string>); static;
    class procedure Uninstall; static;
    class function Available(const ASettings: TAtlasPluginSettings): Boolean; static;
    class function Button: TAtlasDesignerButton; static;
    /// <summary>Verwendungen der markierten Komponenten ins Ergebnisfenster.</summary>
    class procedure Run; static;
    /// <summary>Takt der Designer-Leiste: Taste anmelden, Zähler nachführen.</summary>
    class procedure Tick; static;
    /// <summary>Leiste weg: Taste ab, Zähler weg.</summary>
    class procedure Hide; static;
  end;

implementation

uses
  System.Types,
  System.JSON,
  System.Generics.Collections,
  Vcl.Menus,
  DesignIntf,
  Atlas.Text.Lines,
  Atlas.Core.Diagnostics.Guard,
  Atlas.Core.EditorToolbar.Icons,
  Atlas.Core.Lsp.Client,
  Atlas.Core.Lsp.Session,
  Atlas.Core.Lsp.Session.Json,
  Atlas.Core.Designer.CodeLink,
  Atlas.Core.Designer.Usages,
  Atlas.UI.Results.Items,
  Atlas.UI.Designer.Strings,
  Atlas.IDE.Foundation.Host,
  Atlas.IDE.Foundation.Settings,
  Atlas.IDE.Foundation.ResultsWindow,
  Atlas.IDE.Editor.Rename,
  Atlas.IDE.Editor.WorkspaceEdit,
  Atlas.IDE.Designer.Access,
  Atlas.IDE.Designer.SearchItems;

const
  cKeyPriority = 44;
  /// <summary>So lange muss die Auswahl stehen, bevor der Zähler fragt.</summary>
  cDebounceMs = 400;
  cCountTimeoutMs = 10000;
  cStatusField = 'designer.usages';
  // Trenner in „OnClick = btnOkClick“ (Ereignisliste des Designers).
  cEventAssign = ' = ';

type
  TUsagesKeys = class(TAtlasKeyClient)
  protected
    function WantsKey(AKey: Word; AShift: TShiftState): Boolean; override;
    procedure HandleKey(AKey: Word; AShift: TShiftState); override;
  end;

  /// <summary>Komponente mit Fundort ihrer Felddeklaration.</summary>
  TTarget = record
    Component: TComponent;
    UnitFile: string;
    Line: Integer;
    Character: Integer;
  end;

function TUsagesKeys.WantsKey(AKey: Word; AShift: TShiftState): Boolean;
var
  mSettings: TAtlasPluginSettings;
begin
  mSettings := TAtlasIdeSettings.Current;
  Result := mSettings.DesignerUsages and (mSettings.DesignerUsagesKey <> 0) and
    (ShortCut(AKey, AShift) = TShortCut(mSettings.DesignerUsagesKey)) and TAtlasDesignerAccess.Focused;
end;

procedure TUsagesKeys.HandleKey(AKey: Word; AShift: TShiftState);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, TAtlasIdeDesignerUsages.Run);
end;

function ScopeOf(const ASettings: TAtlasPluginSettings): TAtlasUsageScope;
begin
  if SameText(ASettings.DesignerUsagesScope, TAtlasPluginSettings.cDesignerUsagesUnit) then
  begin
    Result := TAtlasUsageScope.UnitOnly;
  end
  else if SameText(ASettings.DesignerUsagesScope, TAtlasPluginSettings.cDesignerUsagesGroup) then
  begin
    Result := TAtlasUsageScope.ProjectGroup;
  end
  else
  begin
    Result := TAtlasUsageScope.Project;
  end;
end;

function KindText(AKind: TAtlasUsageKind): string;
begin
  case AKind of
    TAtlasUsageKind.Writes: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesKindWrites);
    TAtlasUsageKind.Passes: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesKindPasses);
    TAtlasUsageKind.Event: Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesKindEvent);
  else
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesKindReads);
  end;
end;

type
  /// <summary>Zeilen von Dateien, je Datei einmal gelesen (Editorpuffer oder Platte).</summary>
  TLineCache = class
  private
    FFiles: TDictionary<string, TArray<string>>;
  public
    constructor Create;
    destructor Destroy; override;
    function Lines(const AFileName: string): TArray<string>;
  end;

constructor TLineCache.Create;
begin
  inherited Create;
  FFiles := TDictionary<string, TArray<string>>.Create;
end;

destructor TLineCache.Destroy;
begin
  FFiles.Free;
  inherited Destroy;
end;

function TLineCache.Lines(const AFileName: string): TArray<string>;
var
  mKey: string;
begin
  mKey := LowerCase(AFileName);
  if not FFiles.TryGetValue(mKey, Result) then
  begin
    Result := TTextLines.SplitLines(TAtlasIdeWorkspaceEdit.CurrentText(AFileName));
    FFiles.Add(mKey, Result);
  end;
end;

function LineOf(const ALines: TArray<string>; ALine: Integer): string;
begin
  Result := '';
  if (ALine >= 0) and (ALine <= High(ALines)) then
  begin
    Result := ALines[ALine];
  end;
end;

/// <summary>Felddeklaration von AComponent in der Unit des Formulars; False ohne Feld.</summary>
function TargetOf(const AEditor: IOTAFormEditor; ARoot, AComponent: TComponent; ACache: TLineCache;
  out ATarget: TTarget): Boolean;
begin
  ATarget := Default(TTarget);
  ATarget.Component := AComponent;
  if AEditor.Module <> nil then
  begin
    ATarget.UnitFile := AEditor.Module.FileName;
  end;
  ATarget.Line := TAtlasDesignerUsages.FieldLine(ACache.Lines(ATarget.UnitFile), ARoot.ClassName,
    AComponent.Name, ATarget.Character);
  Result := (ATarget.UnitFile <> '') and (ATarget.Line >= 0);
end;

function UsagesOf(const ATarget: TTarget; const ALocations: TArray<TLspLocation>; ACache: TLineCache;
  AScope: TAtlasUsageScope; const AProjectFiles: TArray<string>): TArray<TAtlasUsage>;
var
  mLocation: TLspLocation;
  mUsage: TAtlasUsage;
  mLines: TArray<string>;
begin
  Result := nil;
  for mLocation in ALocations do
  begin
    if not TAtlasDesignerUsages.InScope(AScope, mLocation.FileName, ATarget.UnitFile, AProjectFiles) then
    begin
      Continue;
    end;
    mLines := ACache.Lines(mLocation.FileName);
    mUsage := Default(TAtlasUsage);
    mUsage.Component := ATarget.Component.Name;
    mUsage.FileName := mLocation.FileName;
    mUsage.Line := mLocation.Line;
    mUsage.Character := mLocation.Character;
    mUsage.Kind := TAtlasDesignerUsages.KindAt(LineOf(mLines, mLocation.Line), mLocation.Character);
    mUsage.Method := TAtlasDesignerLink.MethodAt(mLines, mLocation.Line);
    mUsage.Preview := Trim(LineOf(mLines, mLocation.Line));
    Result := Result + [mUsage];
  end;
end;

function Item(const AId, ACaption, AFileName: string; ALine: Integer): TAtlasResultsItem;
begin
  Result := Default(TAtlasResultsItem);
  Result.Id := AId;
  Result.Caption := ACaption;
  Result.FileName := AFileName;
  Result.Line := ALine;
end;

/// <summary>Gruppen je Komponente, Unit und Methode.</summary>
procedure AddUsageGroups(var AList: TAtlasResultsItemList; const AUsages: TArray<TAtlasUsage>);
var
  mGroup: TAtlasResultsItemGroup;
  mUsage: TAtlasUsage;
  mCaption, mMethod: string;
begin
  mGroup := Default(TAtlasResultsItemGroup);
  for mUsage in TAtlasDesignerUsages.Sorted(AUsages) do
  begin
    mMethod := mUsage.Method;
    if mMethod = '' then
    begin
      mMethod := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesOutside);
    end;
    mCaption := mUsage.Component + ' · ' + ExtractFileName(mUsage.FileName) + ' · ' + mMethod;
    if mCaption <> mGroup.Caption then
    begin
      if mGroup.Items <> nil then
      begin
        AList.Groups := AList.Groups + [mGroup];
      end;
      mGroup := Default(TAtlasResultsItemGroup);
      mGroup.Caption := mCaption;
      mGroup.FileName := mUsage.FileName;
    end;
    mGroup.Items := mGroup.Items + [Item(mUsage.FileName + ':' + IntToStr(mUsage.Line),
      IntToStr(mUsage.Line + 1) + ': [' + KindText(mUsage.Kind) + '] ' + mUsage.Preview, mUsage.FileName,
      mUsage.Line)];
  end;
  if mGroup.Items <> nil then
  begin
    AList.Groups := AList.Groups + [mGroup];
  end;
end;

/// <summary>Gruppe „Ereignisse (DFM)“: je Handler ein Eintrag mit Sprung zur Implementierung.</summary>
function EventGroup(const ATargets: TArray<TTarget>; ARoot: TComponent; const ADesigner: IDesigner;
  ACache: TLineCache): TAtlasResultsItemGroup;
var
  mTarget: TTarget;
  mEvent, mMethod: string;
  mPos, mLine: Integer;
begin
  Result := Default(TAtlasResultsItemGroup);
  Result.Caption := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesEventsGroup);
  for mTarget in ATargets do
  begin
    for mEvent in TAtlasDesignerSearchItems.Events(mTarget.Component, ADesigner) do
    begin
      mPos := Pos(cEventAssign, mEvent);
      mMethod := Copy(mEvent, mPos + Length(cEventAssign), MaxInt);
      // Ohne Implementierung (Handler gelöscht) an den Anfang der Unit.
      mLine := TAtlasDesignerUsages.HandlerLine(ACache.Lines(mTarget.UnitFile), ARoot.ClassName, mMethod);
      if mLine < 0 then
      begin
        mLine := 0;
      end;
      Result.Items := Result.Items + [Item('dfm:' + mTarget.Component.Name + '.' + mEvent,
        mTarget.Component.Name + '.' + mEvent, mTarget.UnitFile, mLine)];
    end;
  end;
end;

{ TAtlasIdeDesignerUsages }

class procedure TAtlasIdeDesignerUsages.Install(const AScopeOf: TFunc<IAtlasModuleScope>;
  const AOnMessage: TProc<string>);
begin
  FScopeOf := AScopeOf;
  FOnMessage := AOnMessage;
  FKeys := TUsagesKeys.Create(cKeyPriority);
end;

class procedure TAtlasIdeDesignerUsages.Uninstall;
begin
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
    FreeAndNil(FKeys);
  end;
  ClearStatus;
  TAtlasIdeResultsWindow.ReleaseItems(cOwner);
  FScopeOf := nil;
  FOnMessage := nil;
end;

class procedure TAtlasIdeDesignerUsages.Say(const AText: string);
begin
  TAtlasGuard.Log('Verwendungen im Code: ' + AText);
  if Assigned(FOnMessage) then
  begin
    FOnMessage(AText);
  end;
end;

class function TAtlasIdeDesignerUsages.Available(const ASettings: TAtlasPluginSettings): Boolean;
begin
  Result := ASettings.DesignerUsages;
end;

class function TAtlasIdeDesignerUsages.Button: TAtlasDesignerButton;
var
  mHint: string;
  mKey: Integer;
begin
  mHint := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesHint);
  mKey := TAtlasIdeSettings.Current.DesignerUsagesKey;
  if mKey <> 0 then
  begin
    mHint := mHint + ' (' + ShortCutToText(TShortCut(mKey)) + ')';
  end;
  Result := TAtlasDesignerButton.Create(cId, TAtlasToolbarIcon.Usages, mHint);
end;

/// <summary>Felddeklarationen der Auswahl; ANames listet die Komponenten mit Feld. Ohne Feld eine Meldung.</summary>
function TargetsOf(const AEditor: IOTAFormEditor; ARoot: TComponent; ACache: TLineCache;
  out ANames: string): TArray<TTarget>;
var
  mComponent: TComponent;
  mTarget: TTarget;
  mNames: TArray<string>;
begin
  Result := nil;
  mNames := nil;
  for mComponent in TAtlasDesignerAccess.Selection(AEditor, ARoot) do
  begin
    if not TargetOf(AEditor, ARoot, mComponent, ACache, mTarget) then
    begin
      TAtlasIdeDesignerUsages.Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UsagesNoField, [mComponent.Name]));
      Continue;
    end;
    Result := Result + [mTarget];
    mNames := mNames + [mComponent.Name];
  end;
  ANames := string.Join(', ', mNames);
end;

/// <summary>Referenzsuche für alle Ziele, gefiltert und eingeordnet; False (mit Meldung) bei Fehler.</summary>
function QueryUsages(ASession: TLspSession; const ATargets: TArray<TTarget>; ACache: TLineCache;
  out AUsages: TArray<TAtlasUsage>): Boolean;
var
  mTarget: TTarget;
  mScope: TAtlasUsageScope;
  mProjectFiles: TArray<string>;
begin
  AUsages := nil;
  mScope := ScopeOf(TAtlasIdeSettings.Current);
  mProjectFiles := TAtlasDesignerAccess.ProjectUnits(False, False);
  TAtlasIdeRename.SyncOpenBuffers(ASession);
  try
    for mTarget in ATargets do
    begin
      AUsages := AUsages + UsagesOf(mTarget, ASession.References(mTarget.UnitFile, mTarget.Line,
        mTarget.Character), ACache, mScope, mProjectFiles);
    end;
    Result := True;
  except
    on E: ELspClientError do
    begin
      TAtlasIdeDesignerUsages.Say(TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UsagesFailed, [E.Message]));
      Result := False;
    end;
  end;
end;

/// <summary>Liste fürs Ergebnisfenster: Zugriffe, danach die Handler aus der DFM.</summary>
function UsageList(const ANames: string; const AUsages: TArray<TAtlasUsage>;
  const AEvents: TAtlasResultsItemGroup): TAtlasResultsItemList;
begin
  Result := Default(TAtlasResultsItemList);
  Result.Owner := TAtlasIdeDesignerUsages.cOwner;
  Result.Title := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UsagesTitle, [ANames, Length(AUsages)]);
  AddUsageGroups(Result, AUsages);
  if AEvents.Items <> nil then
  begin
    Result.Groups := Result.Groups + [AEvents];
  end;
end;

class procedure TAtlasIdeDesignerUsages.Run;
var
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSession: TLspSession;
  mCache: TLineCache;
  mTargets: TArray<TTarget>;
  mUsages: TArray<TAtlasUsage>;
  mNames: string;
begin
  if not TAtlasDesignerAccess.Current(mEditor, mRoot) or
    (Length(TAtlasDesignerAccess.Selection(mEditor, mRoot)) = 0) then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesNoSelection));
    Exit;
  end;
  mSession := TAtlasIdeHost.ActiveSession;
  if mSession = nil then
  begin
    Say(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesNoServer));
    Exit;
  end;
  mCache := TLineCache.Create;
  try
    mTargets := TargetsOf(mEditor, mRoot, mCache, mNames);
    if (mTargets <> nil) and QueryUsages(mSession, mTargets, mCache, mUsages) then
    begin
      TAtlasIdeResultsWindow.ShowItems(UsageList(mNames, mUsages,
        EventGroup(mTargets, mRoot, TAtlasDesignerAccess.DesignerOf(mEditor), mCache)));
    end;
  finally
    mCache.Free;
  end;
end;

/// <summary>„1 Verwendung, 2 Ereignisse“ bzw. „keine Verwendung, keine Ereignisse“.</summary>
function CountText(AUsages, AEvents: Integer): string;
begin
  if (AUsages = 0) and (AEvents = 0) then
  begin
    Exit(TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesNone));
  end;
  if AUsages = 1 then
  begin
    Result := TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesOne);
  end
  else
  begin
    Result := TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UsagesMany, [AUsages]);
  end;
  if AEvents = 1 then
  begin
    Result := Result + ', ' + TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesEventOne);
  end
  else if AEvents > 1 then
  begin
    Result := Result + ', ' + TAtlasDesignerStrings.Fmt(TAtlasDesignerTextId.UsagesEventMany, [AEvents]);
  end;
end;

procedure StatusClicked(APoint: TPoint);
begin
  TAtlasGuard.Run(TAtlasFeature.DesignerBar, TAtlasIdeDesignerUsages.Run);
end;

class procedure TAtlasIdeDesignerUsages.ClearStatus;
begin
  if FShown then
  begin
    TAtlasIdeHost.SetStatusField(cStatusField, '', '', nil);
    FShown := False;
  end;
  FWatched := '';
  FAsked := '';
  Inc(FGeneration);
end;

class procedure TAtlasIdeDesignerUsages.ShowCount(const AName: string; const AJson: string;
  AEvents, AGeneration: Integer);
var
  mValue: TJSONValue;
  mLocations: TArray<TLspLocation>;
  mLocation: TLspLocation;
  mUnit: string;
  mCount: Integer;
  mScope: TAtlasUsageScope;
  mProjectFiles: TArray<string>;
begin
  if AGeneration <> FGeneration then
  begin
    Exit;
  end;
  if AJson = '' then
  begin
    // Keine Antwort (Zeitgrenze, Fehler): lieber nichts als ein falscher Zähler.
    TAtlasIdeHost.SetStatusField(cStatusField, '', '', nil);
    FShown := False;
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AJson);
  try
    mLocations := TLspSessionJson.LocationsOf(mValue);
  finally
    mValue.Free;
  end;
  mUnit := Copy(FAsked, 1, Pos('|', FAsked) - 1);
  mScope := ScopeOf(TAtlasIdeSettings.Current);
  mProjectFiles := TAtlasDesignerAccess.ProjectUnits(False, False);
  mCount := 0;
  for mLocation in mLocations do
  begin
    if TAtlasDesignerUsages.InScope(mScope, mLocation.FileName, mUnit, mProjectFiles) then
    begin
      Inc(mCount);
    end;
  end;
  TAtlasIdeHost.SetStatusField(cStatusField, AName + ' · ' + CountText(mCount, AEvents),
    TAtlasDesignerStrings.Text(TAtlasDesignerTextId.UsagesStatusHint), StatusClicked);
  FShown := True;
end;

/// <summary>Parameter für textDocument/references an der Felddeklaration.</summary>
function ReferenceParams(const ATarget: TTarget): string;
var
  mParams, mDocument, mPosition, mContext: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mDocument := TJSONObject.Create;
    mDocument.AddPair('uri', TLspSessionJson.PathToUri(ATarget.UnitFile));
    mParams.AddPair('textDocument', mDocument);
    mPosition := TJSONObject.Create;
    mPosition.AddPair('line', TJSONNumber.Create(ATarget.Line));
    mPosition.AddPair('character', TJSONNumber.Create(ATarget.Character));
    mParams.AddPair('position', mPosition);
    mContext := TJSONObject.Create;
    mContext.AddPair('includeDeclaration', TJSONBool.Create(False));
    mParams.AddPair('context', mContext);
    Result := mParams.ToJSON([]);
  finally
    mParams.Free;
  end;
end;

class procedure TAtlasIdeDesignerUsages.UpdateKeys(const ASettings: TAtlasPluginSettings);
begin
  if FKeys = nil then
  begin
    Exit;
  end;
  if ASettings.DesignerUsages and (ASettings.DesignerUsagesKey <> 0) then
  begin
    TAtlasKeyHook.Add(FKeys);
  end
  else
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
end;

class procedure TAtlasIdeDesignerUsages.AskCount(const AEditor: IOTAFormEditor; ARoot, AComponent: TComponent);
var
  mCache: TLineCache;
  mTarget: TTarget;
  mFound: Boolean;
  mName: string;
  mEvents, mGeneration: Integer;
begin
  Inc(FGeneration);
  mGeneration := FGeneration;
  mName := AComponent.Name;
  mEvents := Length(TAtlasDesignerSearchItems.Events(AComponent, TAtlasDesignerAccess.DesignerOf(AEditor)));
  mCache := TLineCache.Create;
  try
    mFound := TargetOf(AEditor, ARoot, AComponent, mCache, mTarget);
  finally
    mCache.Free;
  end;
  FShown := True;
  if not mFound then
  begin
    TAtlasIdeHost.SetStatusField(cStatusField, mName + ' · ' + CountText(0, mEvents), '', nil);
    Exit;
  end;
  TAtlasIdeHost.SetStatusField(cStatusField, mName + ' · …', '', nil);
  if not Assigned(FScopeOf) or not TAtlasIdeHost.RunRequestAsync(FScopeOf(), TAtlasFeature.DesignerBar,
    TAtlasServerRequest.Create('textDocument/references', ReferenceParams(mTarget), cCountTimeoutMs,
    function: Boolean
    begin
      Result := FGeneration <> mGeneration;
    end),
    procedure(AJson: string)
    begin
      ShowCount(mName, AJson, mEvents, mGeneration);
    end) then
  begin
    // Ohne laufenden Server kein Zähler; der Befehl startet ihn. Bis zum nächsten Auswahlwechsel nicht erneut.
    TAtlasIdeHost.SetStatusField(cStatusField, '', '', nil);
    FShown := False;
  end;
end;

class procedure TAtlasIdeDesignerUsages.Tick;
var
  mSettings: TAtlasPluginSettings;
  mEditor: IOTAFormEditor;
  mRoot: TComponent;
  mSelected: TArray<TComponent>;
  mKey: string;
begin
  mSettings := TAtlasIdeSettings.Current;
  UpdateKeys(mSettings);
  mSelected := nil;
  if mSettings.DesignerUsages and mSettings.DesignerUsagesStatusCount and
    TAtlasDesignerAccess.Current(mEditor, mRoot) and (mEditor.Module <> nil) then
  begin
    mSelected := TAtlasDesignerAccess.Selection(mEditor, mRoot);
  end;
  if Length(mSelected) <> 1 then
  begin
    ClearStatus;
    Exit;
  end;
  mKey := mEditor.Module.FileName + '|' + mSelected[0].Name;
  if mKey <> FWatched then
  begin
    FWatched := mKey;
    FSince := TThread.GetTickCount64;
  end
  else if (FAsked <> mKey) and (TThread.GetTickCount64 - FSince >= cDebounceMs) then
  begin
    FAsked := mKey;
    AskCount(mEditor, mRoot, mSelected[0]);
  end;
end;

class procedure TAtlasIdeDesignerUsages.Hide;
begin
  if FKeys <> nil then
  begin
    TAtlasKeyHook.Remove(FKeys);
  end;
  ClearStatus;
end;

end.
