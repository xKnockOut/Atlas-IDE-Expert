unit Atlas.Common.Mcp.Prompts.Tests;

interface

uses
  System.JSON,
  DUnitX.TestFramework,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Prompts;

type
  [TestFixture]
  TMcpPromptsTests = class
  private
    FServer: TMcpServer;
    FPrompts: TMcpPrompts;
    FSettings: TServerSettings;
    FResolved: string;
    FChanges: TMcpChangeSet;
    function Get(const AName, AArguments: string): string;
    function Read(const AUri: string): string;
    function ListedNames: string;
    procedure AddTool(const AName: string; AKind: TMcpToolKind);
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ListsFiveBuiltinPromptsWithArguments;
    [Test]
    procedure UnitReviewEmbedsOutlineFindingsMetricsAndConventions;
    [Test]
    procedure MissingRequiredArgumentIsError;
    [Test]
    procedure UnitOutsideWorkspaceIsErrorWithReason;
    [Test]
    procedure ExplainFormEmbedsHandlerBodiesAndBindings;
    [Test]
    procedure WriteTestsEmbedsDeclarationCallersAndImpact;
    [Test]
    procedure FixFindingEmbedsExplanationSnippetAndFixes;
    /// <summary>--restricted: keine Korrekturen, keine schreibenden Schritte (#99).</summary>
    [Test]
    procedure RestrictedOffersNoWritingSteps;
    [Test]
    procedure PrepareCommitReportsChangesTestsAndPrefix;
    [Test]
    procedure PrepareCommitUsesAffectedTestsWhenAvailable;
    [Test]
    procedure EnglishInstructions;
    [Test]
    procedure CustomPromptReplacesPlaceholdersAndIncludes;
    [Test]
    procedure CustomPromptCannotShadowBuiltin;
    [Test]
    procedure PromptsOffEmptyPromptsAndTemplates;
    [Test]
    procedure TemplatesResolveUnitFormFindingsAndBuild;
    [Test]
    procedure LimitCutsAtLineEnd;
    [Test]
    procedure InterfacePartStopsBeforeImplementation;
    [Test]
    procedure HandlerBodiesReportMissingImplementation;
    [Test]
    procedure DataBindingsListDataControlsAndLiveBindings;
    [Test]
    procedure SnippetMarksLine;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Rules.Contract;

const
  cFormText =
    'object FormAuftrag: TFormAuftrag'#10 +
    '  Caption = ''Auftrag'''#10 +
    '  OnShow = FormShow'#10 +
    '  object BtnSpeichern: TButton'#10 +
    '    OnClick = BtnSpeichernClick'#10 +
    '  end'#10 +
    '  object EdtKunde: TDBEdit'#10 +
    '    DataField = ''Kunde'''#10 +
    '    DataSource = DsAuftrag'#10 +
    '  end'#10 +
    '  object BtnAbbrechen: TButton'#10 +
    '    OnClick = BtnSpeichernClick'#10 +
    '  end'#10 +
    'end'#10;

  cUnitText =
    'unit UI.Auftrag;'#10 +
    'interface'#10 +
    'uses Vcl.Forms;'#10 +
    'type'#10 +
    '  TFormAuftrag = class(TForm)'#10 +
    '    procedure FormShow(Sender: TObject);'#10 +
    '    procedure BtnSpeichernClick(Sender: TObject);'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TFormAuftrag.FormShow(Sender: TObject);'#10 +
    'begin'#10 +
    '  Caption := ''Neu'';'#10 +
    'end;'#10 +
    'procedure TFormAuftrag.BtnSpeichernClick(Sender: TObject);'#10 +
    'begin'#10 +
    '  Speichere;'#10 +
    'end;'#10 +
    'end.'#10;

function Joined(const AArguments: TJSONObject): string;
begin
  if AArguments = nil then
    Result := '{}'
  else
    Result := AArguments.ToJSON;
end;

procedure TMcpPromptsTests.AddTool(const AName: string; AKind: TMcpToolKind);
var
  mName: string;
begin
  mName := AName;
  FServer.AddTool(AName, AName, '{"type":"object"}',
    function(const AArguments: TJSONObject): string
    begin
      Result := 'Ergebnis ' + mName + ' ' + Joined(AArguments);
    end, AKind);
end;

procedure TMcpPromptsTests.Setup;
var
  mName: string;
begin
  FServer := TMcpServer.Create('Atlas', '1.0');
  for mName in TArray<string>.Create('get_unit_outline', 'get_diagnostics', 'get_metrics', 'find_unused_code',
    'get_dfm_info', 'get_declaration', 'get_call_hierarchy', 'get_impact', 'explain_finding', 'get_last_build',
    'get_unit_dependencies', 'get_todos') do
    AddTool(mName, TMcpToolKind.Read);
  AddTool('apply_code_action', TMcpToolKind.Write);
  AddTool('run_tests', TMcpToolKind.Process);
  FServer.AddResource('delphi://conventions', 'Konventionen', '', 'text/markdown',
    function: string
    begin
      Result := 'KONVENTIONEN DES PROJEKTS';
    end);
  FSettings := TServerSettings.Default;
  FResolved := '';
  FChanges := Default(TMcpChangeSet);
  FPrompts := TMcpPrompts.Create(FServer,
    function: TServerSettings
    begin
      Result := FSettings;
    end);
  FPrompts.ResolveUnit :=
    function(AUnit: string): string
    begin
      FResolved := AUnit;
      if AUnit = 'Fremd.Unit' then
        raise EMcpToolError.Create('"C:\Fremd\Fremd.Unit.pas" liegt außerhalb des Arbeitsbereichs (C:\P)');
      Result := 'C:\P\' + AUnit + '.pas';
    end;
  FPrompts.ResolveFile :=
    function(APath: string): string
    begin
      FResolved := APath;
      Result := 'C:\P\' + APath;
    end;
  FPrompts.ReadText :=
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(ExtractFileExt(AFileName), '.dfm') then
        AText := cFormText
      else if SameText(ExtractFileExt(AFileName), '.pas') then
        AText := cUnitText
      else
        Result := False;
    end;
  FPrompts.Changes :=
    function(const ABase: string): TMcpChangeSet
    begin
      // Wie Shell.Mcp: ohne Basis gegenüber HEAD.
      Result := FChanges;
      Result.Base := ABase;
      if ABase = '' then
        Result.Base := 'HEAD';
    end;
  FPrompts.Register;
end;

procedure TMcpPromptsTests.TearDown;
begin
  FPrompts.Free;
  FPrompts := nil;
  FServer.Free;
  FServer := nil;
  FSettings := Default(TServerSettings);
  FResolved := '';
  FChanges := Default(TMcpChangeSet);
end;

function TMcpPromptsTests.Get(const AName, AArguments: string): string;
var
  mParams: TJSONValue;
  mResult: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue('{"name":"' + AName + '","arguments":' + AArguments + '}');
  try
    mResult := FServer.GetPrompt(mParams);
    try
      Result := mResult.GetValue<TJSONArray>('messages').Items[0].GetValue<string>('content.text');
    finally
      mResult.Free;
    end;
  finally
    mParams.Free;
  end;
end;

function TMcpPromptsTests.Read(const AUri: string): string;
var
  mParams: TJSONObject;
  mResult: TJSONObject;
begin
  mParams := TJSONObject.Create;
  try
    mParams.AddPair('uri', AUri);
    mResult := FServer.ReadResource(mParams);
    try
      Result := mResult.GetValue<TJSONArray>('contents').Items[0].GetValue<string>('text');
    finally
      mResult.Free;
    end;
  finally
    mParams.Free;
  end;
end;

function TMcpPromptsTests.ListedNames: string;
var
  mResult: TJSONObject;
  mItem: TJSONValue;
begin
  Result := '';
  mResult := FServer.ListPrompts;
  try
    for mItem in mResult.GetValue<TJSONArray>('prompts') do
      Result := Result + mItem.GetValue<string>('name') + ',';
  finally
    mResult.Free;
  end;
end;

procedure TMcpPromptsTests.ListsFiveBuiltinPromptsWithArguments;
var
  mResult: TJSONObject;
  mPrompts, mArguments: TJSONArray;
begin
  Assert.AreEqual('unit_review,explain_form,write_tests,fix_finding,prepare_commit,', ListedNames);
  mResult := FServer.ListPrompts;
  try
    mPrompts := mResult.GetValue<TJSONArray>('prompts');
    Assert.AreNotEqual('', mPrompts.Items[0].GetValue<string>('description'));
    mArguments := mPrompts.Items[3].GetValue<TJSONArray>('arguments');
    Assert.AreEqual(3, Integer(mArguments.Count), 'fix_finding: file, line, rule');
    Assert.AreEqual('rule', mArguments.Items[2].GetValue<string>('name'));
    Assert.IsFalse(mArguments.Items[2].GetValue<Boolean>('required'));
    Assert.IsTrue(mArguments.Items[1].GetValue<Boolean>('required'));
    mArguments := mPrompts.Items[4].GetValue<TJSONArray>('arguments');
    Assert.IsFalse(mArguments.Items[0].GetValue<Boolean>('required'), 'prepare_commit: base optional');
  finally
    mResult.Free;
  end;
end;

procedure TMcpPromptsTests.UnitReviewEmbedsOutlineFindingsMetricsAndConventions;
var
  mText: string;
begin
  mText := Get('unit_review', '{"unit":"UI.Auftrag"}');
  Assert.AreEqual('UI.Auftrag', FResolved, 'Unit über ResolveUnit geprüft');
  Assert.Contains(mText, 'Ergebnis get_unit_outline');
  Assert.Contains(mText, 'Ergebnis get_diagnostics');
  Assert.Contains(mText, 'Ergebnis get_metrics');
  Assert.Contains(mText, 'Ergebnis find_unused_code');
  Assert.Contains(mText, 'KONVENTIONEN DES PROJEKTS');
  Assert.Contains(mText, 'Schweregrad');
  Assert.Contains(mText, 'check_code');
  Assert.Contains(mText, 'C:\\P\\UI.Auftrag.pas', 'Datei als Argument der Werkzeuge (JSON)');
end;

procedure TMcpPromptsTests.MissingRequiredArgumentIsError;
var
  mCode: Integer;
begin
  mCode := 0;
  try
    Get('fix_finding', '{"file":"A.pas"}');
  except
    on E: EJsonRpcError do
      mCode := E.Code;
  end;
  Assert.AreEqual(TJsonRpcErrorCode.InvalidParams, mCode);
end;

procedure TMcpPromptsTests.UnitOutsideWorkspaceIsErrorWithReason;
var
  mMessage: string;
begin
  mMessage := '';
  try
    Get('unit_review', '{"unit":"Fremd.Unit"}');
  except
    on E: EJsonRpcError do
      mMessage := E.Message;
  end;
  Assert.Contains(mMessage, 'außerhalb des Arbeitsbereichs');
  mMessage := '';
  try
    Read('delphi://unit/Fremd.Unit');
  except
    on E: EJsonRpcError do
      mMessage := E.Message;
  end;
  Assert.Contains(mMessage, 'außerhalb des Arbeitsbereichs', 'Vorlage mit Begründung');
end;

procedure TMcpPromptsTests.ExplainFormEmbedsHandlerBodiesAndBindings;
var
  mText: string;
begin
  mText := Get('explain_form', '{"file":"UI.Auftrag.pas"}');
  Assert.Contains(mText, 'Ergebnis get_dfm_info');
  Assert.Contains(mText, 'UI.Auftrag.dfm', '.pas führt zur .dfm');
  Assert.Contains(mText, 'Speichere;', 'Rumpf des Handlers');
  Assert.Contains(mText, 'BtnSpeichern.OnClick, BtnAbbrechen.OnClick', 'gemeinsamer Handler einmal');
  Assert.Contains(mText, 'DataSource = DsAuftrag');
end;

procedure TMcpPromptsTests.WriteTestsEmbedsDeclarationCallersAndImpact;
var
  mText: string;
begin
  FSettings.TestUnits.Pattern := 'Test.{unit}';
  mText := Get('write_tests', '{"name":"TAuftrag.Speichern"}');
  Assert.Contains(mText, 'Ergebnis get_declaration');
  Assert.Contains(mText, '"direction":"incoming"');
  Assert.Contains(mText, 'Ergebnis get_impact');
  Assert.Contains(mText, 'Test.{unit}', 'Namensmuster der Testunit');
  Assert.Contains(mText, 'run_tests');
end;

procedure TMcpPromptsTests.FixFindingEmbedsExplanationSnippetAndFixes;
var
  mText: string;
begin
  mText := Get('fix_finding', '{"file":"UI.Auftrag.pas","line":"16","rule":"empty-except"}');
  Assert.Contains(mText, 'Ergebnis explain_finding');
  Assert.Contains(mText, '"line":16');
  Assert.Contains(mText, '"rule":"empty-except"');
  Assert.Contains(mText, '>   16    Speichere;', 'Zeile markiert');
  Assert.Contains(mText, 'Ergebnis apply_code_action', 'Korrekturen gelistet');
  Assert.Contains(mText, 'Ursache');
end;

procedure TMcpPromptsTests.RestrictedOffersNoWritingSteps;
var
  mText: string;
begin
  FServer.Restricted := True;
  mText := Get('fix_finding', '{"file":"UI.Auftrag.pas","line":"16"}');
  Assert.DoesNotContain(mText, 'Ergebnis apply_code_action');
  Assert.DoesNotContain(mText, 'dryRun');
  Assert.Contains(mText, '--restricted');
  mText := Get('write_tests', '{"name":"TAuftrag.Speichern"}');
  Assert.DoesNotContain(mText, 'run_tests aus');
  Assert.Contains(mText, '--restricted');
  mText := Get('unit_review', '{"unit":"UI.Auftrag"}');
  Assert.Contains(mText, '--restricted');
  mText := Get('prepare_commit', '{}');
  Assert.Contains(mText, 'Committe nicht');
end;

procedure TMcpPromptsTests.PrepareCommitReportsChangesTestsAndPrefix;
var
  mText: string;
  mFinding: TRuleFinding;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'empty-except';
  mFinding.Message := 'Leerer except-Block';
  mFinding.Severity := TRuleSeverity.Warning;
  mFinding.Range := TTextRange.Create(11, 2, 11, 8);
  FChanges.Vcs := 'Git';
  FChanges.CommitPrefix := 'ATL-12 ';
  FChanges.Files := [Default(TMcpChangedFile)];
  FChanges.Files[0].Path := 'Source\UI.Auftrag.pas';
  FChanges.Files[0].Findings := [mFinding];
  mText := Get('prepare_commit', '{}');
  Assert.Contains(mText, 'Git, verglichen mit HEAD');
  Assert.Contains(mText, 'Source\UI.Auftrag.pas');
  Assert.Contains(mText, '12:3: warning [empty-except] Leerer except-Block');
  Assert.Contains(mText, '"ATL-12 "');
  Assert.Contains(mText, 'get_impact', 'ohne get_affected_tests der Weg über get_impact');
  mText := Get('prepare_commit', '{"base":"main"}');
  Assert.Contains(mText, 'seit main');
  FChanges.Error := 'Kein Git-Repository';
  mText := Get('prepare_commit', '{}');
  Assert.Contains(mText, 'Kein Git-Repository');
end;

procedure TMcpPromptsTests.PrepareCommitUsesAffectedTestsWhenAvailable;
var
  mText: string;
begin
  AddTool('get_affected_tests', TMcpToolKind.Read);
  FChanges.Vcs := 'Git';
  mText := Get('prepare_commit', '{"base":"main"}');
  Assert.Contains(mText, 'Ergebnis get_affected_tests {"base":"main"}');
end;

procedure TMcpPromptsTests.EnglishInstructions;
var
  mText: string;
  mResult: TJSONObject;
begin
  FSettings.McpPromptLanguage := 'en';
  mText := Get('unit_review', '{"unit":"UI.Auftrag"}');
  Assert.Contains(mText, 'Review the unit UI.Auftrag');
  Assert.Contains(mText, 'Project conventions');
  mResult := FServer.ListPrompts;
  try
    Assert.Contains(mResult.GetValue<TJSONArray>('prompts').Items[0].GetValue<string>('description'),
      'Code review of a unit');
  finally
    mResult.Free;
  end;
end;

procedure TMcpPromptsTests.CustomPromptReplacesPlaceholdersAndIncludes;
var
  mCustom: TMcpCustomPrompt;
  mArgument: TMcpCustomPromptArgument;
  mText: string;
  mResult: TJSONObject;
  mItem: TJSONValue;
begin
  mCustom := Default(TMcpCustomPrompt);
  mCustom.Name := 'check_unit';
  mCustom.Description := 'Unit prüfen';
  mArgument := Default(TMcpCustomPromptArgument);
  mArgument.Name := 'unit';
  mArgument.Description := 'Unit-Name';
  mArgument.Required := True;
  mCustom.Arguments := [mArgument];
  mCustom.Text := 'Prüfe {unit} gründlich, {unbekannt} bleibt.';
  mCustom.Include := TArray<string>.Create('diagnostics', 'metrics', 'conventions');
  FSettings.McpCustomPrompts := [mCustom];
  Assert.Contains(ListedNames, 'check_unit,');
  mResult := FServer.ListPrompts;
  try
    mItem := mResult.GetValue<TJSONArray>('prompts').Items[5];
    Assert.AreEqual('Unit prüfen', mItem.GetValue<string>('description'));
    Assert.AreEqual('unit', mItem.GetValue<TJSONArray>('arguments').Items[0].GetValue<string>('name'));
  finally
    mResult.Free;
  end;
  mText := Get('check_unit', '{"unit":"UI.Auftrag"}');
  Assert.Contains(mText, 'Prüfe UI.Auftrag gründlich, {unbekannt} bleibt.');
  Assert.Contains(mText, 'Ergebnis get_diagnostics {"file":"C:\\P\\UI.Auftrag.pas"}', 'Unit über ResolveUnit');
  Assert.Contains(mText, 'Ergebnis get_metrics');
  Assert.Contains(mText, 'KONVENTIONEN DES PROJEKTS');
end;

procedure TMcpPromptsTests.CustomPromptCannotShadowBuiltin;
var
  mCustom: TMcpCustomPrompt;
begin
  mCustom := Default(TMcpCustomPrompt);
  mCustom.Name := 'unit_review';
  mCustom.Text := 'Eigener Text';
  FSettings.McpCustomPrompts := [mCustom];
  Assert.AreEqual('unit_review,explain_form,write_tests,fix_finding,prepare_commit,', ListedNames);
  Assert.DoesNotContain(Get('unit_review', '{"unit":"UI.Auftrag"}'), 'Eigener Text');
end;

procedure TMcpPromptsTests.PromptsOffEmptyPromptsAndTemplates;
var
  mResult: TJSONObject;
begin
  FSettings.McpPrompts := False;
  Assert.AreEqual('', ListedNames);
  mResult := FServer.ListResourceTemplates;
  try
    Assert.AreEqual(0, Integer(mResult.GetValue<TJSONArray>('resourceTemplates').Count));
  finally
    mResult.Free;
  end;
  mResult := FServer.ListTools;
  try
    Assert.AreEqual(14, Integer(mResult.GetValue<TJSONArray>('tools').Count), 'Werkzeuge unverändert');
  finally
    mResult.Free;
  end;
  FSettings.McpPrompts := True;
  mResult := FServer.ListResourceTemplates;
  try
    Assert.AreEqual(3, Integer(mResult.GetValue<TJSONArray>('resourceTemplates').Count));
  finally
    mResult.Free;
  end;
end;

procedure TMcpPromptsTests.TemplatesResolveUnitFormFindingsAndBuild;
var
  mText: string;
begin
  mText := Read('delphi://unit/UI.Auftrag');
  Assert.Contains(mText, 'Ergebnis get_unit_outline');
  Assert.Contains(mText, 'TFormAuftrag = class(TForm)', 'interface-Teil');
  Assert.DoesNotContain(mText, 'Speichere;', 'kein implementation-Teil');
  mText := Read('delphi://form/UI%2FAuftrag.dfm');
  Assert.AreEqual('UI/Auftrag.dfm', FResolved, 'Pfad dekodiert über ResolveFile');
  Assert.Contains(mText, 'Ergebnis get_dfm_info');
  mText := Read('delphi://findings/UI.Auftrag.pas');
  Assert.Contains(mText, 'Ergebnis get_diagnostics');
  mText := Read('delphi://build/last');
  Assert.Contains(mText, 'Ergebnis get_last_build');
end;

procedure TMcpPromptsTests.LimitCutsAtLineEnd;
var
  mBuilder: TStringBuilder;
  mIndex: Integer;
  mText, mLimited: string;
begin
  mBuilder := TStringBuilder.Create;
  try
    for mIndex := 1 to 2000 do
      mBuilder.Append(Format('Zeile %d mit Umlauten äöü', [mIndex])).Append(#10);
    mText := mBuilder.ToString;
  finally
    mBuilder.Free;
  end;
  mLimited := TMcpPrompts.Limit(mText, 4096, 'get_unit_outline');
  Assert.IsTrue(TEncoding.UTF8.GetByteCount(mLimited) <= 4096, 'höchstens 4 KB');
  Assert.Contains(mLimited, 'gekürzt auf 4 KB; vollständig mit get_unit_outline');
  Assert.IsTrue(Pos('äöü' + sLineBreak + sLineBreak + '…', mLimited) > 0, 'ganze Zeile vor dem Hinweis');
  Assert.AreEqual('kurz', TMcpPrompts.Limit('kurz', 4096, 'x'));
end;

procedure TMcpPromptsTests.InterfacePartStopsBeforeImplementation;
var
  mText: string;
begin
  mText := TMcpPrompts.InterfacePart(cUnitText);
  Assert.IsTrue(mText.StartsWith('interface'));
  Assert.Contains(mText, 'procedure BtnSpeichernClick(Sender: TObject);');
  Assert.DoesNotContain(mText, 'Speichere');
  Assert.AreEqual('', TMcpPrompts.InterfacePart('program P; begin end.'));
end;

procedure TMcpPromptsTests.HandlerBodiesReportMissingImplementation;
var
  mText: string;
begin
  mText := TMcpPrompts.HandlerBodies(cFormText, cUnitText);
  Assert.Contains(mText, 'FormShow (FormAuftrag.OnShow), Zeile 10:');
  Assert.Contains(mText, 'Caption := ''Neu'';');
  mText := TMcpPrompts.HandlerBodies(cFormText, '');
  Assert.Contains(mText, 'Implementierung nicht gefunden');
  Assert.AreEqual('', TMcpPrompts.HandlerBodies('object F: TForm'#10'end'#10, cUnitText));
end;

procedure TMcpPromptsTests.DataBindingsListDataControlsAndLiveBindings;
var
  mText: string;
begin
  mText := TMcpPrompts.DataBindings(cFormText);
  Assert.Contains(mText, '- EdtKunde: TDBEdit – DataField = ''Kunde'', DataSource = DsAuftrag');
  mText := TMcpPrompts.DataBindings('object F: TForm'#10 +
    '  object Link1: TLinkControlToField'#10 + '    DataSource = Bind1'#10 + '    Control = Edit1'#10 + '  end'#10 +
    '  object Edit1: TEdit'#10 + '    Control = X'#10 + '  end'#10 + 'end'#10);
  Assert.Contains(mText, 'Link1: TLinkControlToField – DataSource = Bind1, Control = Edit1');
  Assert.DoesNotContain(mText, 'Edit1: TEdit', 'Control zählt nur bei LiveBindings');
end;

procedure TMcpPromptsTests.SnippetMarksLine;
var
  mText: string;
begin
  mText := TMcpPrompts.Snippet(TArray<string>.Create('a', 'b', 'c', 'd'), 2, 1);
  Assert.AreEqual('     1  a' + sLineBreak + '>    2  b' + sLineBreak + '     3  c', mText);
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpPromptsTests);

end.
