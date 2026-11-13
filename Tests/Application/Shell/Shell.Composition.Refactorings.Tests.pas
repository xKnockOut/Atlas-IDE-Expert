unit Shell.Composition.Refactorings.Tests;

// Refactorings des Servers über die Fassade: Anmeldung der Befehle, abgeschaltete Refactorings, fehlende Argumente,
// nicht geöffnete Dateien, Folgearbeit nach dem Umbenennen einer Unit und der Schrittfilter auf einem offenen
// Dokument.

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Lsp.Commands,
  Shell.Composition.Refactorings.Services,
  Shell.Composition.Refactorings;

type
  [TestFixture]
  TShellRefactoringsTests = class
  private
    FSettings: TRefactoringSettings;
    FDocuments: IDocumentStore;
    FCommands: TLspCommands;
    FRefactorings: TShellRefactorings;
    FServices: TShellRefactoringServices;
    function SettingsFor(const AUri: string): TRefactoringSettings;
    function Run(const ACommand, AArguments: string): string;
    function ErrorOf(const ACommand, AArguments: string; out ACode: Integer): string;
    /// <summary>Befehle, die APart anmeldet, als JSON; gibt APart frei.</summary>
    function CommandsOf(APart: TShellRefactoringPart): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>Die Fassade meldet die Befehle aller Teile an, auch die des Debuggers.</summary>
    [Test]
    procedure RegistersCommandsOfAllParts;
    /// <summary>Jeder Teil meldet nur seine eigenen Befehle an.</summary>
    [Test]
    procedure EachPartRegistersItsCommands;
    /// <summary>Ohne eingeschaltetes Refactoring bietet keine Datei eine Code-Aktion an.</summary>
    [Test]
    procedure DisabledRefactoringsOfferNoActions;
    /// <summary>Ein abgeschaltetes Refactoring nennt seine Einstellung.</summary>
    [Test]
    procedure DisabledCommandNamesSetting;
    [Test]
    procedure MissingArgumentsAreInvalidParams;
    [Test]
    procedure ClosedDocumentIsRefused;
    /// <summary>Ohne refactoring.unitRenameFollowUp antwortet der Befehl mit enabled = false.</summary>
    [Test]
    procedure UnitRenameFollowUpOff;
    [Test]
    procedure StepFilterFindsRoutineOfOpenDocument;
    [Test]
    procedure MethodBreakpointsFindRoutineOfOpenDocument;
    [Test]
    procedure MethodBreakpointsReportInvalidPattern;
    /// <summary>refactoring.raiseVisibility schaltet die Code-Aktion auf der Deklaration (#2108).</summary>
    [Test]
    procedure RaiseVisibilityOnDeclaration;
    /// <summary>Der Befehl für die Vervollständigung braucht eine lesbare Datei, nicht ein offenes Dokument.
    /// </summary>
    [Test]
    procedure MemberActionsNeedReadableFile;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Lsp.Contract,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.Projects.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Logging.Providers.Logger,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Documents.Providers.DocumentStore,
  Atlas.Common.Lsp.ChangeSignature,
  Atlas.Common.Lsp.SafeDelete,
  Atlas.Common.Lsp.TypeAlias,
  Atlas.Common.Lsp.DisableWarning,
  Atlas.Common.Lsp.StepFilter,
  Atlas.Common.Lsp.MethodBreakpoints,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Lsp.UnitRename,
  Atlas.Common.Lsp.RaiseVisibility,
  Shell.Composition.Refactorings.Structure,
  Shell.Composition.Refactorings.Visibility,
  Shell.Composition.Refactorings.Conversions,
  Shell.Composition.Refactorings.Types,
  Shell.Composition.Refactorings.Fixes,
  Shell.Composition.Refactorings.Editing,
  Shell.Composition.Stepping,
  Shell.Composition.MethodBreakpoints;

const
  cUri = 'file:///tmp/Kunden.pas';
  cSource = 'unit Kunden;'#10'interface'#10'implementation'#10'procedure Laden;'#10'begin'#10'end;'#10'end.'#10;

function NoNames: TArray<string>;
begin
  Result := nil;
end;

function NamesFunc(): TShellNamesFunc;
begin
  Result :=
    function: TArray<string>
    begin
      Result := NoNames;
    end;
end;

function NoText(): TShellUriTextFunc;
begin
  Result :=
    function(const AUri: string): string
    begin
      Result := '';
    end;
end;

procedure TShellRefactoringsTests.Setup;
var
  mServices: TShellRefactoringServices;
begin
  FSettings := Default(TRefactoringSettings);
  FDocuments := TDocumentStore.Create;
  mServices := Default(TShellRefactoringServices);
  mServices.Logger := TLogger.Create;
  mServices.Documents := FDocuments;
  mServices.Index := TSymbolIndex.Create;
  mServices.EnsureUnit :=
    function(const AUnitName: string): Boolean
    begin
      Result := False;
    end;
  mServices.Namespaces := NamesFunc();
  mServices.ProjectFiles := NamesFunc();
  mServices.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      AText := '';
      Result := False;
    end;
  mServices.SettingsFor := SettingsFor;
  mServices.FormatStyleFor :=
    function(const AUri: string): TFormatStyle
    begin
      Result := Default(TFormatStyle);
    end;
  mServices.LanguageLevelFor := NoText();
  mServices.DelphiVersionFor := NoText();
  mServices.UsesContextFor :=
    function(const AUri: string; out AContext: TUsesContext): Boolean
    begin
      AContext := Default(TUsesContext);
      Result := False;
    end;
  mServices.MessagesFor :=
    function(const AFileName: string): TArray<TCompilerMessage>
    begin
      Result := nil;
    end;
  mServices.ProjectFor :=
    function(const AFileName: string; out AProject: TProjectInfo): Boolean
    begin
      AProject := Default(TProjectInfo);
      Result := False;
    end;
  mServices.NewNamesFor :=
    function(const AUri: string): TPascalNamePrefixes
    begin
      Result := Default(TPascalNamePrefixes);
    end;
  FServices := mServices;
  FRefactorings := TShellRefactorings.Create(mServices);
  FCommands := TLspCommands.Create;
  FRefactorings.Register(FCommands);
end;

procedure TShellRefactoringsTests.TearDown;
begin
  FreeAndNil(FCommands);
  FreeAndNil(FRefactorings);
  FDocuments := nil;
  FServices := Default(TShellRefactoringServices);
  FSettings := Default(TRefactoringSettings);
end;

function TShellRefactoringsTests.SettingsFor(const AUri: string): TRefactoringSettings;
begin
  Result := FSettings;
end;

function TShellRefactoringsTests.Run(const ACommand, AArguments: string): string;
var
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments) as TJSONArray;
  try
    mAnswer := FCommands.Execute(ACommand, mArguments);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mArguments.Free;
  end;
end;

function TShellRefactoringsTests.ErrorOf(const ACommand, AArguments: string; out ACode: Integer): string;
begin
  ACode := 0;
  Result := '';
  try
    Run(ACommand, AArguments);
  except
    on E: EJsonRpcError do
    begin
      ACode := E.Code;
      Result := E.Message;
    end;
  end;
end;

function TShellRefactoringsTests.CommandsOf(APart: TShellRefactoringPart): string;
var
  mCommands: TLspCommands;
  mCapability: TJSONObject;
begin
  mCommands := TLspCommands.Create;
  try
    APart.Register(mCommands);
    mCapability := mCommands.Capability;
    try
      Result := mCapability.ToJSON;
    finally
      mCapability.Free;
    end;
  finally
    mCommands.Free;
    APart.Free;
  end;
end;

procedure TShellRefactoringsTests.EachPartRegistersItsCommands;
var
  mText: string;
begin
  mText := CommandsOf(TShellStructureRefactorings.Create(FServices));
  Assert.IsTrue(Pos(TLspChangeSignature.cApplyCommand, mText) > 0, 'Aufbau');
  Assert.IsFalse(Pos(TLspStepFilter.cCommand, mText) > 0, 'Aufbau ohne Debugger');
  mText := CommandsOf(TShellConversionRefactorings.Create(FServices));
  Assert.IsFalse(Pos(TLspSafeDelete.cApplyCommand, mText) > 0, 'Umwandlungen ohne Sicher löschen');
  Assert.IsTrue(Pos(TLspTypeAlias.cApplyCommand, CommandsOf(TShellTypeRefactorings.Create(FServices))) > 0, 'Typen');
  Assert.IsTrue(Pos(TLspDisableWarning.cApplyCommand, CommandsOf(TShellFixRefactorings.Create(FServices))) > 0,
    'Korrekturen');
  Assert.IsTrue(Pos(TLspUnitRename.cCommand, CommandsOf(TShellEditingRefactorings.Create(FServices))) > 0,
    'Bearbeiten');
  Assert.IsTrue(Pos(TLspStepFilter.cCountsCommand, CommandsOf(TShellStepping.Create(FServices))) > 0, 'Debugger');
  Assert.IsTrue(Pos(TLspMethodBreakpoints.cCommand, CommandsOf(TShellMethodBreakpoints.Create(FServices))) > 0,
    'Methodenhaltepunkte');
  Assert.IsTrue(Pos(TLspRaiseVisibility.cCommand, CommandsOf(TShellVisibilityRefactorings.Create(FServices))) > 0,
    'Sichtbarkeit');
end;

procedure TShellRefactoringsTests.RegistersCommandsOfAllParts;
var
  mCapability: TJSONObject;
  mText: string;
begin
  mCapability := FCommands.Capability;
  try
    mText := mCapability.ToJSON;
  finally
    mCapability.Free;
  end;
  Assert.IsTrue(Pos(TLspChangeSignature.cPrepareCommand, mText) > 0, 'Aufbau');
  Assert.IsTrue(Pos(TLspSafeDelete.cApplyCommand, mText) > 0, 'Aufbau');
  Assert.IsTrue(Pos(TLspTypeAlias.cInlineApplyCommand, mText) > 0, 'Typen');
  Assert.IsTrue(Pos(TLspDisableWarning.cApplyCommand, mText) > 0, 'Korrekturen');
  Assert.IsTrue(Pos(TLspUnitRename.cCommand, mText) > 0, 'Bearbeiten');
  Assert.IsTrue(Pos(TLspStepFilter.cCountsCommand, mText) > 0, 'Debugger');
  Assert.IsTrue(Pos(TLspMethodBreakpoints.cCommand, mText) > 0, 'Methodenhaltepunkte');
  Assert.IsTrue(Pos(TLspRaiseVisibility.cCommand, mText) > 0, 'Sichtbarkeit');
end;

procedure TShellRefactoringsTests.DisabledRefactoringsOfferNoActions;
var
  mRange: TTextRange;
begin
  FDocuments.Open(cUri, 'pascal', 1, cSource);
  mRange := TTextRange.Create(TTextPosition.Create(3, 11), TTextPosition.Create(3, 11));
  Assert.AreEqual(0, Integer(Length(FRefactorings.Actions(cUri, mRange))));
end;

procedure TShellRefactoringsTests.DisabledCommandNamesSetting;
var
  mCode: Integer;
  mMessage: string;
begin
  FDocuments.Open(cUri, 'pascal', 1, cSource);
  mMessage := ErrorOf(TLspSafeDelete.cPrepareCommand, '["' + cUri + '", {"line": 3, "character": 11}]', mCode);
  Assert.AreEqual(TLspErrorCode.cRequestFailed, mCode);
  Assert.IsTrue(Pos('refactoring.safeDelete', mMessage) > 0, mMessage);
end;

procedure TShellRefactoringsTests.MissingArgumentsAreInvalidParams;
var
  mCode: Integer;
begin
  ErrorOf(TLspChangeSignature.cApplyCommand, '["' + cUri + '"]', mCode);
  Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode);
  ErrorOf(TLspStepFilter.cCommand, '["' + cUri + '", "eins"]', mCode);
  Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode, 'Zeile keine Zahl');
  ErrorOf(TLspMethodBreakpoints.cCommand, '[{"muster": "Laden"}]', mCode);
  Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode, 'Muster fehlt');
end;

procedure TShellRefactoringsTests.ClosedDocumentIsRefused;
var
  mCode: Integer;
  mMessage: string;
begin
  FSettings.SafeDelete := True;
  mMessage := ErrorOf(TLspSafeDelete.cPrepareCommand, '["' + cUri + '", {"line": 3, "character": 11}]', mCode);
  Assert.AreEqual(TLspErrorCode.cRequestFailed, mCode);
  Assert.AreEqual('Die Datei ist nicht geöffnet.', mMessage);
end;

procedure TShellRefactoringsTests.UnitRenameFollowUpOff;
begin
  Assert.AreEqual('{"enabled":false}', Run(TLspUnitRename.cCommand, '["file:///tmp/Alt.pas", "' + cUri + '", []]'));
end;

procedure TShellRefactoringsTests.StepFilterFindsRoutineOfOpenDocument;
var
  mAnswer: TJSONObject;
begin
  FDocuments.Open(cUri, 'pascal', 1, cSource);
  mAnswer := TJSONObject.ParseJSONValue(Run(TLspStepFilter.cCommand, '["' + cUri + '", 4]')) as TJSONObject;
  try
    Assert.IsTrue(mAnswer.GetValue<Boolean>('found'));
  finally
    mAnswer.Free;
  end;
end;

procedure TShellRefactoringsTests.MethodBreakpointsFindRoutineOfOpenDocument;
var
  mPath: string;
  mAnswer: TJSONObject;
  mHits: TJSONArray;
begin
  // Index und Editor kennen dieselbe Datei; der Rumpf kommt aus dem offenen Dokument.
  mPath := TDocumentUris.ToPath(cUri);
  FServices.Index.AddUnit(TIndexExtractor.ExtractText(cSource, mPath, nil));
  FDocuments.Open(TDocumentUris.FromPath(mPath), 'pascal', 1, cSource);
  mAnswer := TJSONObject.ParseJSONValue(Run(TLspMethodBreakpoints.cCommand, '[{"pattern": "Kunden.*"}]')) as TJSONObject;
  try
    mHits := mAnswer.GetValue('hits') as TJSONArray;
    Assert.AreEqual(1, mHits.Count);
    Assert.AreEqual('Laden', (mHits.Items[0] as TJSONObject).GetValue('name').Value);
    // Leerer Rumpf: Zeile des end.
    Assert.AreEqual(5, ((mHits.Items[0] as TJSONObject).GetValue('line') as TJSONNumber).AsInt);
  finally
    mAnswer.Free;
  end;
end;

procedure TShellRefactoringsTests.MethodBreakpointsReportInvalidPattern;
var
  mAnswer: TJSONObject;
begin
  mAnswer := TJSONObject.ParseJSONValue(Run(TLspMethodBreakpoints.cCommand, '[{"pattern": "a..b"}]')) as TJSONObject;
  try
    Assert.IsTrue(Pos('a..b', mAnswer.GetValue('error').Value) > 0, mAnswer.ToJSON);
    Assert.IsNull(mAnswer.GetValue('hits'));
  finally
    mAnswer.Free;
  end;
end;

procedure TShellRefactoringsTests.RaiseVisibilityOnDeclaration;
const
  cClass = 'unit Kunden;'#10'interface'#10'type'#10'  TKunde = class'#10'  private'#10'    FName: string;'#10 +
    '  end;'#10'implementation'#10'end.'#10;
var
  mRange: TTextRange;
  mActions: TArray<TJSONObject>;
  mItem: TJSONObject;
begin
  FDocuments.Open(cUri, 'pascal', 1, cClass);
  mRange := TTextRange.Create(TTextPosition.Create(5, 6), TTextPosition.Create(5, 6));
  Assert.AreEqual(0, Integer(Length(FRefactorings.Actions(cUri, mRange))), 'abgeschaltet');
  FSettings.RaiseVisibility := True;
  mActions := FRefactorings.Actions(cUri, mRange);
  try
    Assert.AreEqual(2, Integer(Length(mActions)));
    Assert.AreEqual('Sichtbarkeit von FName auf protected anheben', mActions[0].GetValue<string>('title'));
  finally
    for mItem in mActions do
    begin
      mItem.Free;
    end;
  end;
end;

procedure TShellRefactoringsTests.MemberActionsNeedReadableFile;
var
  mCode: Integer;
begin
  ErrorOf(TLspRaiseVisibility.cCommand, '["' + cUri + '", {"line": 5, "character": 4}]', mCode);
  Assert.AreEqual(TJsonRpcErrorCode.cInvalidParams, mCode, 'Name fehlt');
  ErrorOf(TLspRaiseVisibility.cCommand, '["' + cUri + '", {"line": 5, "character": 4}, "FName"]', mCode);
  Assert.AreEqual(TLspErrorCode.cRequestFailed, mCode, 'nicht lesbar');
end;

initialization
  TDUnitX.RegisterTestFixture(TShellRefactoringsTests);

end.
