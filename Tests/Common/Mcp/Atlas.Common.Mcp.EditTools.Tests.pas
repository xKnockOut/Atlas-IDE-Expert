unit Atlas.Common.Mcp.EditTools.Tests;

// Tests für die Sicherheit der MCP-Schicht (#99), schreibende Werkzeuge (#61),
// Projektkonventionen als Ressource (#272), Befund an KI (#158) und
// Sammelkorrektur fix_findings (#1352) und format_code (#1358).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMcpEditToolsTests = class
  public
    [Test]
    procedure DisabledAndRestrictedToolsAreHiddenAndRefused;
    [Test]
    procedure WritingCallsAreAudited;
    [Test]
    procedure ListsAndReadsResources;
    [Test]
    procedure AppliesEditsFromBackToFront;
    /// <summary>Zeichen hinter dem Zeilenende bleiben in ihrer Zeile; CR allein ist ein Zeilenende.</summary>
    [Test]
    procedure ClampsCharacterToLineEnd;
    [Test]
    procedure DryRunWritesNothingAndShowsDiff;
    [Test]
    procedure WritesAllFilesAndAuditsThem;
    [Test]
    procedure DirtyOrChangedFileAbortsWithoutChanges;
    [Test]
    procedure FailedWriteRestoresWrittenFiles;
    [Test]
    procedure CodeActionListsAndAppliesFix;
    [Test]
    procedure PromptHasRuleCodeAndExamples;
    [Test]
    procedure ConventionsListActiveRules;
    /// <summary>fix_findings (#1352): Vorschau, Schreiben, ungespeicherte Dateien, Untergrenze.</summary>
    [Test]
    procedure FixFindingsPreviewsAndWrites;
    [Test]
    procedure FixFindingsSkipsDirtyFiles;
    [Test]
    procedure FixFindingsRefusesLowerConfidence;
    /// <summary>#1358: format_code mit Text liefert den formatierten Text und schreibt nichts.</summary>
    [Test]
    procedure FormatCodeWithTextWritesNothing;
    /// <summary>#1358: Vorschau zeigt den Diff, dryRun=false schreibt über denselben Weg, nur den Bereich.</summary>
    [Test]
    procedure FormatCodeWritesFileOrRange;
    /// <summary>#1358: Syntaxfehler: nicht formatiert, Fehler statt Änderung.</summary>
    [Test]
    procedure FormatCodeRefusesSyntaxErrors;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Mcp.Server,
  Atlas.Common.Mcp.Contract,
  Atlas.Common.Editing.FormatCheck,
  Atlas.Common.Mcp.EditTools;

type
  /// <summary>Meldet jeden Bezeichner "Alt" mit der Korrektur "Neu".</summary>
  TRenameRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Meldet jeden Bezeichner "Alt" ohne Korrektur; nur Unterdrücken wird angeboten.</summary>
  TNoFixRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  /// <summary>Dateien im Speicher; FailOn lässt das Schreiben dieser Datei scheitern.</summary>
  TMemoryFiles = class
  public
    Files: TDictionary<string, string>;
    FailOn: string;
    Writes: Integer;
    constructor Create;
    destructor Destroy; override;
    function Read(const AFileName: string; out AText: string): Boolean;
    procedure Write(const AFileName, AText: string);
  end;

function TRenameRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('test-alt', TRuleSeverity.Warning, 'Alt durch Neu ersetzen');
end;

procedure TRenameRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mToken: TPascalToken;
  mRange: TTextRange;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'Alt') then
    begin
      mRange := TTextRange.Create(mToken.StartPos, mToken.EndPos);
      AReport.Add(mRange, 'Alt gefunden', [TRuleFix.Create('Alt durch Neu ersetzen', [TRuleEdit.Create(mRange, 'Neu')])]);
    end;
  end;
end;

function TNoFixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('test-ohne', TRuleSeverity.Warning, 'Alt ohne Korrektur');
end;

procedure TNoFixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mToken: TPascalToken;
begin
  for mToken in AContext.Tree.Tokens do
  begin
    if (mToken.Kind = TPascalTokenKind.Identifier) and SameText(mToken.Text, 'Alt') then
    begin
      AReport.Add(TTextRange.Create(mToken.StartPos, mToken.EndPos), 'Alt gefunden');
    end;
  end;
end;

constructor TMemoryFiles.Create;
begin
  inherited Create;
  Files := TDictionary<string, string>.Create;
end;

destructor TMemoryFiles.Destroy;
begin
  Files.Free;
  inherited Destroy;
end;

function TMemoryFiles.Read(const AFileName: string; out AText: string): Boolean;
begin
  Result := Files.TryGetValue(AFileName, AText);
end;

procedure TMemoryFiles.Write(const AFileName, AText: string);
begin
  if SameText(AFileName, FailOn) then
  begin
    raise Exception.Create('gesperrt');
  end;
  Files[AFileName] := AText;
  Inc(Writes);
end;

function Tools(AFiles: TMemoryFiles): TMcpEditTools;
begin
  Result := TMcpEditTools.Create(nil,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := AFiles.Read(AFileName, AText);
    end,
    procedure(const AFileName, AText: string)
    begin
      AFiles.Write(AFileName, AText);
    end,
    function: TArray<string>
    begin
      Result := nil;
    end,
    nil);
end;

function Edits: TArray<TMcpFileEdit>;
begin
  Result := [TMcpFileEdit.Create('A.pas', TTextRange.Create(0, 0, 0, 3), 'Neu'),
    TMcpFileEdit.Create('B.dfm', TTextRange.Create(1, 2, 1, 5), 'Neu')];
end;

/// <summary>Der Aufruf von AName scheitert mit einer Meldung, die AExpected enthält.</summary>
procedure AssertToolRefused(const AServer: TMcpServer; const AName, AExpected: string);
var
  mParams, mCalled: TJSONObject;
begin
  mParams := TJSONObject.ParseJSONValue('{"name":"' + AName + '"}') as TJSONObject;
  try
    mCalled := AServer.CallTool(mParams);
    try
      Assert.IsTrue(mCalled.GetValue<Boolean>('isError'));
      Assert.Contains(mCalled.ToJSON, AExpected);
    finally
      mCalled.Free;
    end;
  finally
    mParams.Free;
  end;
end;

procedure TMcpEditToolsTests.DisabledAndRestrictedToolsAreHiddenAndRefused;
var
  mServer: TMcpServer;
  mListed: TJSONObject;
begin
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mServer.AddTool('lesen', 'l', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'ok';
      end);
    mServer.AddTool('schreiben', 's', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'geschrieben';
      end, TMcpToolKind.Write);
    mServer.OnDisabledTools :=
      function: TArray<string>
      begin
        Result := ['Lesen'];
      end;
    mListed := mServer.ListTools;
    try
      Assert.AreEqual(1, Integer(TJSONArray(mListed.GetValue('tools')).Count), 'abgeschaltet fehlt');
    finally
      mListed.Free;
    end;
    AssertToolRefused(mServer, 'lesen', 'mcp.disabledTools');
    mServer.OnDisabledTools := nil;
    mServer.Restricted := True;
    mListed := mServer.ListTools;
    try
      Assert.AreEqual(1, Integer(TJSONArray(mListed.GetValue('tools')).Count), 'eingeschränkt: nur lesend');
      Assert.Contains(mListed.ToJSON, '"lesen"');
    finally
      mListed.Free;
    end;
    AssertToolRefused(mServer, 'schreiben', 'Modus aus');
  finally
    mServer.Free;
  end;
end;

procedure TMcpEditToolsTests.WritingCallsAreAudited;
var
  mServer: TMcpServer;
  mLog: TList<string>;
  mParams, mCalled: TJSONObject;
begin
  mLog := TList<string>.Create;
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mServer.AddTool('schreiben', 's', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'geschrieben';
      end, TMcpToolKind.Write);
    mServer.AddTool('lesen', 'l', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'ok';
      end);
    mServer.OnAudit :=
      procedure(AText: string)
      begin
        mLog.Add(AText);
      end;
    mParams := TJSONObject.ParseJSONValue('{"name":"schreiben","arguments":{"file":"A.pas"}}') as TJSONObject;
    try
      mServer.CallTool(mParams).Free;
    finally
      mParams.Free;
    end;
    mParams := TJSONObject.ParseJSONValue('{"name":"lesen"}') as TJSONObject;
    try
      mCalled := mServer.CallTool(mParams);
      mCalled.Free;
    finally
      mParams.Free;
    end;
    Assert.AreEqual(1, Integer(mLog.Count), 'nur der schreibende Aufruf');
    Assert.Contains(mLog[0], 'schreiben');
    Assert.Contains(mLog[0], 'A.pas');
  finally
    mServer.Free;
    mLog.Free;
  end;
end;

procedure TMcpEditToolsTests.ListsAndReadsResources;
var
  mServer: TMcpServer;
  mListed, mRead, mParams, mInit: TJSONObject;
begin
  mServer := TMcpServer.Create('Atlas', '0');
  try
    mServer.AddResource('delphi://conventions', 'Konventionen', 'd', 'text/markdown',
      function: string
      begin
        Result := '# Konventionen';
      end);
    mInit := mServer.Initialize(nil);
    try
      Assert.IsNotNull(mInit.GetValue<TJSONObject>('capabilities').GetValue('resources'));
    finally
      mInit.Free;
    end;
    mListed := mServer.ListResources;
    try
      Assert.Contains(mListed.ToJSON, 'delphi://conventions');
    finally
      mListed.Free;
    end;
    mParams := TJSONObject.ParseJSONValue('{"uri":"delphi://conventions"}') as TJSONObject;
    try
      mRead := mServer.ReadResource(mParams);
      try
        Assert.Contains(mRead.ToJSON, '# Konventionen');
      finally
        mRead.Free;
      end;
    finally
      mParams.Free;
    end;
  finally
    mServer.Free;
  end;
end;

procedure TMcpEditToolsTests.AppliesEditsFromBackToFront;
begin
  Assert.AreEqual('Neu x Neu'#13#10'Neu',
    TMcpEditTools.ApplyToText('Alt x Alt'#13#10'Alt', [
      TMcpFileEdit.Create('A', TTextRange.Create(0, 0, 0, 3), 'Neu'),
      TMcpFileEdit.Create('A', TTextRange.Create(0, 6, 0, 9), 'Neu'),
      TMcpFileEdit.Create('A', TTextRange.Create(1, 0, 1, 3), 'Neu')]));
  Assert.AreEqual('ab', TMcpEditTools.ApplyToText('aXb', [TMcpFileEdit.Create('A', TTextRange.Create(0, 1, 0, 2), '')]));
end;

procedure TMcpEditToolsTests.ClampsCharacterToLineEnd;
begin
  Assert.AreEqual('ab!'#10'cd',
    TMcpEditTools.ApplyToText('ab'#10'cd', [TMcpFileEdit.Create('A', TTextRange.Create(0, 9, 0, 9), '!')]));
  Assert.AreEqual('ab'#13'c!d',
    TMcpEditTools.ApplyToText('ab'#13'cd', [TMcpFileEdit.Create('A', TTextRange.Create(1, 1, 1, 1), '!')]));
  Assert.AreEqual('ab'#13#10'cd!',
    TMcpEditTools.ApplyToText('ab'#13#10'cd', [TMcpFileEdit.Create('A', TTextRange.Create(5, 0, 5, 0), '!')]));
end;

procedure TMcpEditToolsTests.DryRunWritesNothingAndShowsDiff;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mReport: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    mReport := mEdit.Apply('test', Edits, True);
    Assert.AreEqual(0, mFiles.Writes);
    Assert.AreEqual('Alt;', mFiles.Files['A.pas']);
    Assert.Contains(mReport, 'Vorschau');
    Assert.Contains(mReport, '- Alt;');
    Assert.Contains(mReport, '+ Neu;');
    Assert.Contains(mReport, '+   Neu');
    Assert.Contains(mReport, 'Zeile 2:', 'nur geänderte Zeilen mit Nummer');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.WritesAllFilesAndAuditsThem;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mLogged: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    mEdit.Audit :=
      procedure(const AText: string)
      begin
        mLogged := AText;
      end;
    mEdit.Apply('rename_symbol', Edits, False);
    Assert.AreEqual('Neu;', mFiles.Files['A.pas']);
    Assert.AreEqual('x'#10'  Neu'#10'y', mFiles.Files['B.dfm']);
    Assert.Contains(mLogged, 'rename_symbol');
    Assert.Contains(mLogged, 'B.dfm');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.DirtyOrChangedFileAbortsWithoutChanges;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    mEdit.DirtyFiles :=
      function: TArray<string>
      begin
        Result := ['b.dfm'];
      end;
    Assert.WillRaise(
      procedure
      begin
        mEdit.Apply('test', Edits, False);
      end, EMcpToolError);
    Assert.AreEqual(0, mFiles.Writes, 'ungespeichert im Editor: nichts geschrieben');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.FailedWriteRestoresWrittenFiles;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('A.pas', 'Alt;');
    mFiles.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    mFiles.FailOn := 'B.dfm';
    Assert.WillRaise(
      procedure
      begin
        mEdit.Apply('test', Edits, False);
      end, EMcpToolError);
    Assert.AreEqual('Alt;', mFiles.Files['A.pas'], 'zurückgesetzt');
    Assert.AreEqual('x'#10'  Alt'#10'y', mFiles.Files['B.dfm']);
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.CodeActionListsAndAppliesFix;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mListed: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('U.pas', 'unit U;'#10'interface'#10'var'#10'  Alt: Integer;'#10'implementation'#10'end.');
    mListed := mEdit.ApplyCodeAction(TMcpRuleScope.Create([TRenameRule.Create], Default(TServerSettings), ''),
      'U.pas', 4, '', False);
    Assert.Contains(mListed, 'Alt durch Neu ersetzen');
    Assert.AreEqual(0, mFiles.Writes, 'ohne title nur auflisten');
    mEdit.ApplyCodeAction(TMcpRuleScope.Create([TRenameRule.Create], Default(TServerSettings), ''),
      'U.pas', 4, 'test-alt', False);
    Assert.Contains(mFiles.Files['U.pas'], '  Neu: Integer;');
    // Die Regelkennung wählt nie das Unterdrücken (#1109); das geht nur über seinen Titel.
    mFiles.Files['U.pas'] := 'unit U;'#10'interface'#10'var'#10'  Alt: Integer;'#10'implementation'#10'end.';
    Assert.WillRaise(
      procedure
      begin
        mEdit.ApplyCodeAction(TMcpRuleScope.Create([TNoFixRule.Create], Default(TServerSettings), ''),
          'U.pas', 4, 'test-ohne', False);
      end, EMcpToolError);
    Assert.IsFalse(Pos('lsp-ignore', mFiles.Files['U.pas']) > 0, 'nichts unterdrückt');
    mEdit.ApplyCodeAction(TMcpRuleScope.Create([TNoFixRule.Create], Default(TServerSettings), ''), 'U.pas', 4,
      '"test-ohne" für diese Zeile unterdrücken', False);
    Assert.IsTrue(Pos('lsp-ignore: test-ohne', mFiles.Files['U.pas']) > 0, 'mit Titel unterdrückt');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.PromptHasRuleCodeAndExamples;
var
  mFinding: TRuleFinding;
  mCatalog: TRuleCatalog;
  mText: string;
begin
  mFinding := Default(TRuleFinding);
  mFinding.RuleId := 'empty-except';
  mFinding.Range := TTextRange.Create(2, 2, 2, 8);
  mFinding.Message := 'Leerer except-Block';
  mFinding.Severity := TRuleSeverity.Warning;
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    mText := TFindingPrompt.Markdown(mFinding, 'U.pas', 'a'#13#10'b'#13#10'c'#13#10'd', mCatalog, 1);
  finally
    mCatalog.Free;
  end;
  Assert.Contains(mText, '## Befund empty-except');
  Assert.Contains(mText, 'Zeile 3, Spalte 3');
  Assert.Contains(mText, '>    3 | c');
  Assert.Contains(mText, '     2 | b');
  Assert.IsFalse(mText.Contains('   1 | a'), 'nur ±1 Zeile');
  Assert.Contains(mText, '```pascal');
end;

procedure TMcpEditToolsTests.ConventionsListActiveRules;
var
  mSettings: TServerSettings;
  mCatalog: TRuleCatalog;
  mText: string;
begin
  mSettings := Default(TServerSettings);
  mCatalog := TFindingPrompt.GermanCatalog;
  try
    mText := TRuleConventions.Markdown(BuiltinRules, mSettings, mCatalog);
  finally
    mCatalog.Free;
  end;
  Assert.Contains(mText, '# Konventionen des Projekts');
  Assert.Contains(mText, 'Regelprofil: `standard`');
  Assert.Contains(mText, '## Aktive Regeln');
  Assert.IsFalse(mText.Contains('## Aktive Regeln (0)'), 'Standardprofil hat aktive Regeln');
  Assert.IsTrue(TRuleConventions.IsNamingRule('naming-convention'));
end;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

procedure TMcpEditToolsTests.FixFindingsPreviewsAndWrites;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mReport, mAudit: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mAudit := '';
    mEdit.Audit :=
      procedure(const AText: string)
      begin
        mAudit := mAudit + AText;
      end;
    mFiles.Files.Add('U.pas', cAssignedFree);
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''),
      ['U.pas'], ['redundant-assigned-free'], '', True);
    Assert.Contains(mReport, 'Vorschau: 1 Korrekturen in 1 Dateien');
    Assert.Contains(mReport, '--- a/U.pas');
    Assert.Contains(mReport, '-  if Assigned(AList) then');
    Assert.AreEqual(0, mFiles.Writes, 'Vorschau schreibt nichts');
    Assert.AreEqual('', mAudit);
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''),
      ['U.pas'], ['redundant-assigned-free'], '', False);
    Assert.Contains(mReport, '1 Korrekturen in 1 Dateien geschrieben');
    Assert.AreEqual(1, mFiles.Writes);
    Assert.IsFalse(Pos('Assigned', mFiles.Files['U.pas']) > 0, mFiles.Files['U.pas']);
    Assert.Contains(mAudit, 'fix_findings (redundant-assigned-free)');
    Assert.Contains(mAudit, 'U.pas');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.FixFindingsSkipsDirtyFiles;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mReport: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mEdit.DirtyFiles :=
      function: TArray<string>
      begin
        Result := ['u.pas'];
      end;
    mFiles.Files.Add('U.pas', cAssignedFree);
    mFiles.Files.Add('V.pas', StringReplace(cAssignedFree, 'unit U;', 'unit V;', []));
    mReport := mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas', 'V.pas'],
      ['redundant-assigned-free'], '', False);
    Assert.Contains(mReport, 'Nicht angefasst (ungespeicherte Änderungen im Editor): U.pas');
    Assert.AreEqual(cAssignedFree, mFiles.Files['U.pas']);
    Assert.AreEqual(1, mFiles.Writes, 'V.pas geschrieben');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.FixFindingsRefusesLowerConfidence;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('U.pas', cAssignedFree);
    Assert.WillRaise(
      procedure
      begin
        mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''),
          ['U.pas'], ['redundant-assigned-free'], 'medium', True);
      end, EMcpToolError);
    Assert.WillRaise(
      procedure
      begin
        mEdit.FixFindings(TMcpRuleScope.Create(BuiltinRules, TServerSettings.Default, ''), ['U.pas'], nil, '', True);
      end, EMcpToolError);
    Assert.AreEqual(0, mFiles.Writes);
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

const
  cSchief = 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'   P;'#10'     P;'#10'end;'#10 +
    'end.';

procedure TMcpEditToolsTests.FormatCodeWithTextWritesNothing;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mText: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mText := mEdit.FormatCode(TFormatStyle.Default, 'U.pas', cSchief, TFormatScope.All);
    Assert.Contains(mText, '2 Abweichungen');
    Assert.Contains(mText, 'Zeile 6: Einrückung 3 statt 2');
    Assert.Contains(mText, #10'  P;'#10'  P;'#10);
    Assert.AreEqual(0, mFiles.Writes);
    Assert.Contains(mEdit.FormatCode(TFormatStyle.Default, 'U.pas', 'unit U;'#10'interface'#10'implementation'#10 +
      'end.', TFormatScope.All), 'Keine Abweichung');
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.FormatCodeWritesFileOrRange;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
  mText: string;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('U.pas', cSchief);
    mText := mEdit.FormatCode(TFormatStyle.Default, 'U.pas', TFormatScope.All, True);
    Assert.Contains(mText, 'Vorschau');
    Assert.Contains(mText, '-    P;');
    Assert.AreEqual(0, mFiles.Writes);
    // Nur Zeile 7 (0-basiert 6).
    mEdit.FormatCode(TFormatStyle.Default, 'U.pas', TFormatScope.Lines([TFormatLineSpan.Create(6, 6)]), False);
    Assert.AreEqual(1, mFiles.Writes);
    Assert.AreEqual(StringReplace(cSchief, '     P;', '  P;', []), mFiles.Files['U.pas']);
    mEdit.FormatCode(TFormatStyle.Default, 'U.pas', TFormatScope.All, False);
    Assert.AreEqual(StringReplace(StringReplace(cSchief, '     P;', '  P;', []), '   P;', '  P;', []),
      mFiles.Files['U.pas']);
    Assert.Contains(mEdit.FormatCode(TFormatStyle.Default, 'U.pas', TFormatScope.All, False), 'keine Abweichung');
    Assert.AreEqual(2, mFiles.Writes);
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

procedure TMcpEditToolsTests.FormatCodeRefusesSyntaxErrors;
var
  mFiles: TMemoryFiles;
  mEdit: TMcpEditTools;
begin
  mFiles := TMemoryFiles.Create;
  mEdit := Tools(mFiles);
  try
    mFiles.Files.Add('U.pas', 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10'   if then;'#10 +
      'end;'#10'end.');
    Assert.WillRaise(
      procedure
      begin
        mEdit.FormatCode(TFormatStyle.Default, 'U.pas', TFormatScope.All, False);
      end, EMcpToolError);
    Assert.AreEqual(0, mFiles.Writes);
  finally
    mEdit.Free;
    mFiles.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMcpEditToolsTests);

end.
