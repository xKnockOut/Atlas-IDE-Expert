unit Atlas.Common.Lsp.LeakSetup;

// Befehl atlas.server.leakSetup [uri, {manager, fileReport}?] (#1880): Stand
// der Leckprüfung des Projekts hinter uri (.dproj, Hauptquelltext oder eine
// Datei des Projekts) für den Dialog „Leckprüfung einrichten …“ des Plugins.
// Mit dem zweiten Argument liefert er dazu den Plan: ein WorkspaceEdit für den
// Hauptquelltext, die Symbole für die Konfiguration Debug und ob die DLL zu
// kopieren ist. Die Symbole setzt das Plugin über die Projektoptionen der IDE,
// nicht als Text in der .dproj. Logik in Atlas.Common.Leaks.Setup, Projekt
// und Dateien kommen von außen (Shell).
//
// Antwort:
//   { project, mainSource, mainUri, platform, isPackage, isTestProject,
//     leakMonitor, hasUses, hasMainBlock,
//     fastmm4: {file, version, optionsFile} | null, fastmm5: … | null,
//     uses: {manager, first, debugOnly}, report: {line, debugOnly},
//     debugDefine, fileReport,
//     dll: {name, file, source, target},
//     plan?: {manager, fileReport, edit, defines, copyDll, empty} }
// manager: "none" (RTL, Einfach), "fastmm4", "fastmm5".

interface

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Leaks.Setup;

type
  /// <summary>Eingabe für das Projekt hinter AUri; False, wenn es kein geladenes Projekt dazu gibt (AReason).
  /// </summary>
  TLeakSetupContextProvider = reference to function(const AUri: string; out AInput: TLeakSetupInput;
    out AReason: string): Boolean;

  TLspLeakSetup = class
  public const
    cCommand = 'atlas.server.leakSetup';
    cManagerNames: array[TLeakManager] of string = ('none', 'fastmm4', 'fastmm5');
  private
    FContextFor: TLeakSetupContextProvider;
    FFiles: ILeakSetupFiles;
  public
    constructor Create(const AContextFor: TLeakSetupContextProvider; const AFiles: ILeakSetupFiles);
    /// <summary>Speichermanager zum Namen aus cManagerNames; False bei unbekanntem Namen.</summary>
    class function ManagerOf(const AName: string; out AManager: TLeakManager): Boolean; static;
    /// <summary>Stand als JSON (ohne plan). Der Aufrufer übernimmt das Objekt.</summary>
    class function StateToJson(const AInput: TLeakSetupInput; const AState: TLeakSetupState): TJSONObject; static;
    /// <summary>Plan als JSON. Der Aufrufer übernimmt das Objekt.</summary>
    class function PlanToJson(const AInput: TLeakSetupInput; AManager: TLeakManager; AFileReport: Boolean;
      const APlan: TLeakSetupPlan): TJSONObject; static;
    /// <summary>atlas.server.leakSetup [uri, {manager, fileReport}?]; EJsonRpcError ohne Projekt.</summary>
    function Execute(const AArguments: TJSONArray): TJSONValue;
  end;

implementation

uses
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Unit in beiden Sprachen (#1458).</summary>
  TLspLeakSetupText = (NeedsUri, UnknownManager);

const
  cTexts: array[TLspLeakSetupText] of TAtlasText = (
    (De: '%s braucht die URI des Projekts'; En: '%s needs the URI of the project'),
    (De: 'Unbekannter Speichermanager „%s“'; En: 'Unknown memory manager “%s”'));

{$SCOPEDENUMS OFF}

constructor TLspLeakSetup.Create(const AContextFor: TLeakSetupContextProvider; const AFiles: ILeakSetupFiles);
begin
  inherited Create;
  FContextFor := AContextFor;
  FFiles := AFiles;
end;

class function TLspLeakSetup.ManagerOf(const AName: string; out AManager: TLeakManager): Boolean;
var
  mManager: TLeakManager;
begin
  for mManager := Low(TLeakManager) to High(TLeakManager) do
  begin
    if SameText(AName, cManagerNames[mManager]) then
    begin
      AManager := mManager;
      Exit(True);
    end;
  end;
  AManager := TLeakManager.None;
  Result := False;
end;

function SourceToJson(const ASource: TLeakManagerSource): TJSONValue;
var
  mObject: TJSONObject;
begin
  if not ASource.Found then
  begin
    Result := TJSONNull.Create;
    Exit;
  end;
  mObject := TJSONObject.Create;
  mObject.AddPair('file', ASource.FileName);
  mObject.AddPair('version', ASource.Version);
  mObject.AddPair('optionsFile', ASource.OptionsFile);
  Result := mObject;
end;

function UsesToJson(const AState: TLeakSetupState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('manager', TLspLeakSetup.cManagerNames[AState.UsesManager]);
  Result.AddPair('first', TJSONBool.Create(AState.UsesFirst));
  Result.AddPair('debugOnly', TJSONBool.Create(AState.UsesDebugOnly));
end;

function ReportToJson(const AState: TLeakSetupState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(AState.ReportLine));
  Result.AddPair('debugOnly', TJSONBool.Create(AState.ReportDebugOnly));
end;

function DllToJson(const AState: TLeakSetupState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('name', AState.DllName);
  Result.AddPair('file', AState.DllFile);
  Result.AddPair('source', AState.DllSource);
  Result.AddPair('target', AState.DllTarget);
end;

class function TLspLeakSetup.StateToJson(const AInput: TLeakSetupInput; const AState: TLeakSetupState): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('project', AInput.ProjectFile);
  Result.AddPair('mainSource', AInput.MainSource);
  Result.AddPair('mainUri', TDocumentUris.FromPath(AInput.MainSource));
  Result.AddPair('platform', AInput.Platform);
  Result.AddPair('isPackage', TJSONBool.Create(AState.IsPackage));
  Result.AddPair('isTestProject', TJSONBool.Create(AState.IsTestProject));
  Result.AddPair('leakMonitor', AState.LeakMonitor);
  Result.AddPair('hasUses', TJSONBool.Create(AState.HasUses));
  Result.AddPair('hasMainBlock', TJSONBool.Create(AState.HasMainBlock));
  Result.AddPair('fastmm4', SourceToJson(AState.Sources[TLeakManager.FastMM4]));
  Result.AddPair('fastmm5', SourceToJson(AState.Sources[TLeakManager.FastMM5]));
  Result.AddPair('uses', UsesToJson(AState));
  Result.AddPair('report', ReportToJson(AState));
  Result.AddPair('debugDefine', TJSONBool.Create(AState.DebugDefine));
  Result.AddPair('fileReport', TJSONBool.Create(AState.FileReport));
  Result.AddPair('dll', DllToJson(AState));
end;

function PositionToJson(ALine, ACharacter: Integer): TJSONObject;
begin
  Result := TJSONObject.Create;
  Result.AddPair('line', TJSONNumber.Create(ALine));
  Result.AddPair('character', TJSONNumber.Create(ACharacter));
end;

function TextEditToJson(const AEdit: TLeakSetupEdit): TJSONObject;
var
  mRange: TJSONObject;
begin
  mRange := TJSONObject.Create;
  mRange.AddPair('start', PositionToJson(AEdit.Line, AEdit.Character));
  mRange.AddPair('end', PositionToJson(AEdit.Line, AEdit.Character));
  Result := TJSONObject.Create;
  Result.AddPair('range', mRange);
  Result.AddPair('newText', AEdit.Text);
end;

/// <summary>WorkspaceEdit mit den Einfügungen in den Hauptquelltext (changes).</summary>
function EditToJson(const AMainSource: string; const AEdits: TArray<TLeakSetupEdit>): TJSONObject;
var
  mEdits: TJSONArray;
  mEdit: TLeakSetupEdit;
  mChanges: TJSONObject;
begin
  mEdits := TJSONArray.Create;
  for mEdit in AEdits do
  begin
    mEdits.AddElement(TextEditToJson(mEdit));
  end;
  mChanges := TJSONObject.Create;
  mChanges.AddPair(TDocumentUris.FromPath(AMainSource), mEdits);
  Result := TJSONObject.Create;
  Result.AddPair('changes', mChanges);
end;

class function TLspLeakSetup.PlanToJson(const AInput: TLeakSetupInput; AManager: TLeakManager;
  AFileReport: Boolean; const APlan: TLeakSetupPlan): TJSONObject;
var
  mDefines: TJSONArray;
  mDefine: string;
begin
  mDefines := TJSONArray.Create;
  for mDefine in APlan.Defines do
  begin
    mDefines.Add(mDefine);
  end;
  Result := TJSONObject.Create;
  Result.AddPair('manager', cManagerNames[AManager]);
  Result.AddPair('fileReport', TJSONBool.Create(AFileReport));
  Result.AddPair('edit', EditToJson(AInput.MainSource, APlan.Edits));
  Result.AddPair('defines', mDefines);
  Result.AddPair('copyDll', TJSONBool.Create(APlan.CopyDll));
  Result.AddPair('empty', TJSONBool.Create(APlan.IsEmpty));
end;

/// <summary>Wunsch aus dem zweiten Argument; False ohne.</summary>
function PlanWish(const AArguments: TJSONArray; out AManager: TLeakManager; out AFileReport: Boolean): Boolean;
var
  mWish: TJSONObject;
  mName: string;
begin
  AManager := TLeakManager.None;
  AFileReport := False;
  Result := (AArguments.Count > 1) and (AArguments.Items[1] is TJSONObject);
  if not Result then
  begin
    Exit;
  end;
  mWish := TJSONObject(AArguments.Items[1]);
  mName := 'none';
  if mWish.GetValue('manager') is TJSONString then
  begin
    mName := mWish.GetValue('manager').Value;
  end;
  if not TLspLeakSetup.ManagerOf(mName, AManager) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspLeakSetupText.UnknownManager].Fmt([mName]));
  end;
  AFileReport := (mWish.GetValue('fileReport') is TJSONBool) and TJSONBool(mWish.GetValue('fileReport')).AsBoolean;
end;

function TLspLeakSetup.Execute(const AArguments: TJSONArray): TJSONValue;
var
  mInput: TLeakSetupInput;
  mState: TLeakSetupState;
  mReason: string;
  mManager: TLeakManager;
  mFileReport: Boolean;
  mResult: TJSONObject;
begin
  if (AArguments = nil) or (AArguments.Count = 0) or not (AArguments.Items[0] is TJSONString) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams,
      cTexts[TLspLeakSetupText.NeedsUri].Fmt([TLspLeakSetup.cCommand]));
  end;
  if not FContextFor(AArguments.Items[0].Value, mInput, mReason) then
  begin
    raise EJsonRpcError.Create(TJsonRpcErrorCode.cInvalidParams, mReason);
  end;
  mState := TLeakSetup.Analyze(mInput, FFiles);
  mResult := StateToJson(mInput, mState);
  try
    if PlanWish(AArguments, mManager, mFileReport) then
    begin
      mResult.AddPair('plan', PlanToJson(mInput, mManager, mFileReport,
        TLeakSetup.Plan(mState, mInput.MainText, mManager, mFileReport)));
    end;
  except
    mResult.Free;
    raise;
  end;
  Result := mResult;
end;

end.
