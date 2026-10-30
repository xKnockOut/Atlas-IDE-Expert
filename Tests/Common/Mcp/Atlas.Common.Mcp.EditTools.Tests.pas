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
    /// <summary>Zeichen hinter dem Zeilenende bleiben in ihrer Zeile; CR allein ist ein Zeilenende (D-04).</summary>
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
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Catalog,
  Atlas.Common.Rules.Prompt,
  Atlas.Common.Rules.Conventions,
  Atlas.Common.Rules.Builtin,
  Atlas.Common.Mcp.Server,
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
  Token: TPascalToken;
  Range: TTextRange;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Alt') then
    begin
      Range := TTextRange.Create(Token.StartPos, Token.EndPos);
      AReport.Add(Range, 'Alt gefunden', [TRuleFix.Create('Alt durch Neu ersetzen', [TRuleEdit.Create(Range, 'Neu')])]);
    end;
end;

function TNoFixRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('test-ohne', TRuleSeverity.Warning, 'Alt ohne Korrektur');
end;

procedure TNoFixRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Token: TPascalToken;
begin
  for Token in AContext.Tree.Tokens do
    if (Token.Kind = TPascalTokenKind.Identifier) and SameText(Token.Text, 'Alt') then
      AReport.Add(TTextRange.Create(Token.StartPos, Token.EndPos), 'Alt gefunden');
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
    raise Exception.Create('gesperrt');
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

procedure TMcpEditToolsTests.DisabledAndRestrictedToolsAreHiddenAndRefused;
var
  Server: TMcpServer;
  Listed, Called, Params: TJSONObject;
begin
  Server := TMcpServer.Create('Atlas', '0');
  try
    Server.AddTool('lesen', 'l', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'ok';
      end);
    Server.AddTool('schreiben', 's', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'geschrieben';
      end, TMcpToolKind.Write);
    Server.OnDisabledTools :=
      function: TArray<string>
      begin
        Result := ['Lesen'];
      end;
    Listed := Server.ListTools;
    try
      Assert.AreEqual(1, Integer(TJSONArray(Listed.GetValue('tools')).Count), 'abgeschaltet fehlt');
    finally
      Listed.Free;
    end;
    Params := TJSONObject.ParseJSONValue('{"name":"lesen"}') as TJSONObject;
    try
      Called := Server.CallTool(Params);
      try
        Assert.IsTrue(Called.GetValue<Boolean>('isError'));
        Assert.Contains(Called.ToJSON, 'mcp.disabledTools');
      finally
        Called.Free;
      end;
    finally
      Params.Free;
    end;
    Server.OnDisabledTools := nil;
    Server.Restricted := True;
    Listed := Server.ListTools;
    try
      Assert.AreEqual(1, Integer(TJSONArray(Listed.GetValue('tools')).Count), 'eingeschränkt: nur lesend');
      Assert.Contains(Listed.ToJSON, '"lesen"');
    finally
      Listed.Free;
    end;
    Params := TJSONObject.ParseJSONValue('{"name":"schreiben"}') as TJSONObject;
    try
      Called := Server.CallTool(Params);
      try
        Assert.IsTrue(Called.GetValue<Boolean>('isError'));
        Assert.Contains(Called.ToJSON, 'Modus aus');
      finally
        Called.Free;
      end;
    finally
      Params.Free;
    end;
  finally
    Server.Free;
  end;
end;

procedure TMcpEditToolsTests.WritingCallsAreAudited;
var
  Server: TMcpServer;
  Log: TList<string>;
  Params, Called: TJSONObject;
begin
  Log := TList<string>.Create;
  Server := TMcpServer.Create('Atlas', '0');
  try
    Server.AddTool('schreiben', 's', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'geschrieben';
      end, TMcpToolKind.Write);
    Server.AddTool('lesen', 'l', '{}',
      function(const AArguments: TJSONObject): string
      begin
        Result := 'ok';
      end);
    Server.OnAudit :=
      procedure(AText: string)
      begin
        Log.Add(AText);
      end;
    Params := TJSONObject.ParseJSONValue('{"name":"schreiben","arguments":{"file":"A.pas"}}') as TJSONObject;
    try
      Server.CallTool(Params).Free;
    finally
      Params.Free;
    end;
    Params := TJSONObject.ParseJSONValue('{"name":"lesen"}') as TJSONObject;
    try
      Called := Server.CallTool(Params);
      Called.Free;
    finally
      Params.Free;
    end;
    Assert.AreEqual(1, Integer(Log.Count), 'nur der schreibende Aufruf');
    Assert.Contains(Log[0], 'schreiben');
    Assert.Contains(Log[0], 'A.pas');
  finally
    Server.Free;
    Log.Free;
  end;
end;

procedure TMcpEditToolsTests.ListsAndReadsResources;
var
  Server: TMcpServer;
  Listed, Read, Params, Init: TJSONObject;
begin
  Server := TMcpServer.Create('Atlas', '0');
  try
    Server.AddResource('delphi://conventions', 'Konventionen', 'd', 'text/markdown',
      function: string
      begin
        Result := '# Konventionen';
      end);
    Init := Server.Initialize(nil);
    try
      Assert.IsNotNull(Init.GetValue<TJSONObject>('capabilities').GetValue('resources'));
    finally
      Init.Free;
    end;
    Listed := Server.ListResources;
    try
      Assert.Contains(Listed.ToJSON, 'delphi://conventions');
    finally
      Listed.Free;
    end;
    Params := TJSONObject.ParseJSONValue('{"uri":"delphi://conventions"}') as TJSONObject;
    try
      Read := Server.ReadResource(Params);
      try
        Assert.Contains(Read.ToJSON, '# Konventionen');
      finally
        Read.Free;
      end;
    finally
      Params.Free;
    end;
  finally
    Server.Free;
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
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
  Report: string;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('A.pas', 'Alt;');
    Files.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    Report := Edit.Apply('test', Edits, True);
    Assert.AreEqual(0, Files.Writes);
    Assert.AreEqual('Alt;', Files.Files['A.pas']);
    Assert.Contains(Report, 'Vorschau');
    Assert.Contains(Report, '- Alt;');
    Assert.Contains(Report, '+ Neu;');
    Assert.Contains(Report, '+   Neu');
    Assert.Contains(Report, 'Zeile 2:', 'nur geänderte Zeilen mit Nummer');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.WritesAllFilesAndAuditsThem;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
  Logged: string;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('A.pas', 'Alt;');
    Files.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    Edit.Audit :=
      procedure(const AText: string)
      begin
        Logged := AText;
      end;
    Edit.Apply('rename_symbol', Edits, False);
    Assert.AreEqual('Neu;', Files.Files['A.pas']);
    Assert.AreEqual('x'#10'  Neu'#10'y', Files.Files['B.dfm']);
    Assert.Contains(Logged, 'rename_symbol');
    Assert.Contains(Logged, 'B.dfm');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.DirtyOrChangedFileAbortsWithoutChanges;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('A.pas', 'Alt;');
    Files.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    Edit.DirtyFiles :=
      function: TArray<string>
      begin
        Result := ['b.dfm'];
      end;
    Assert.WillRaise(
      procedure
      begin
        Edit.Apply('test', Edits, False);
      end, EMcpToolError);
    Assert.AreEqual(0, Files.Writes, 'ungespeichert im Editor: nichts geschrieben');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.FailedWriteRestoresWrittenFiles;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('A.pas', 'Alt;');
    Files.Files.Add('B.dfm', 'x'#10'  Alt'#10'y');
    Files.FailOn := 'B.dfm';
    Assert.WillRaise(
      procedure
      begin
        Edit.Apply('test', Edits, False);
      end, EMcpToolError);
    Assert.AreEqual('Alt;', Files.Files['A.pas'], 'zurückgesetzt');
    Assert.AreEqual('x'#10'  Alt'#10'y', Files.Files['B.dfm']);
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.CodeActionListsAndAppliesFix;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
  Listed: string;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('U.pas', 'unit U;'#10'interface'#10'var'#10'  Alt: Integer;'#10'implementation'#10'end.');
    Listed := Edit.ApplyCodeAction([TRenameRule.Create], Default(TServerSettings), '', 'U.pas', 4, '', False);
    Assert.Contains(Listed, 'Alt durch Neu ersetzen');
    Assert.AreEqual(0, Files.Writes, 'ohne title nur auflisten');
    Edit.ApplyCodeAction([TRenameRule.Create], Default(TServerSettings), '', 'U.pas', 4, 'test-alt', False);
    Assert.Contains(Files.Files['U.pas'], '  Neu: Integer;');
    // Die Regelkennung wählt nie das Unterdrücken (#1109); das geht nur über seinen Titel.
    Files.Files['U.pas'] := 'unit U;'#10'interface'#10'var'#10'  Alt: Integer;'#10'implementation'#10'end.';
    Assert.WillRaise(
      procedure
      begin
        Edit.ApplyCodeAction([TNoFixRule.Create], Default(TServerSettings), '', 'U.pas', 4, 'test-ohne', False);
      end, EMcpToolError);
    Assert.IsFalse(Pos('lsp-ignore', Files.Files['U.pas']) > 0, 'nichts unterdrückt');
    Edit.ApplyCodeAction([TNoFixRule.Create], Default(TServerSettings), '', 'U.pas', 4,
      '"test-ohne" für diese Zeile unterdrücken', False);
    Assert.IsTrue(Pos('lsp-ignore: test-ohne', Files.Files['U.pas']) > 0, 'mit Titel unterdrückt');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.PromptHasRuleCodeAndExamples;
var
  Finding: TRuleFinding;
  Catalog: TRuleCatalog;
  Text: string;
begin
  Finding := Default(TRuleFinding);
  Finding.RuleId := 'empty-except';
  Finding.Range := TTextRange.Create(2, 2, 2, 8);
  Finding.Message := 'Leerer except-Block';
  Finding.Severity := TRuleSeverity.Warning;
  Catalog := TFindingPrompt.GermanCatalog;
  try
    Text := TFindingPrompt.Markdown(Finding, 'U.pas', 'a'#13#10'b'#13#10'c'#13#10'd', Catalog, 1);
  finally
    Catalog.Free;
  end;
  Assert.Contains(Text, '## Befund empty-except');
  Assert.Contains(Text, 'Zeile 3, Spalte 3');
  Assert.Contains(Text, '>    3 | c');
  Assert.Contains(Text, '     2 | b');
  Assert.IsFalse(Text.Contains('   1 | a'), 'nur ±1 Zeile');
  Assert.Contains(Text, '```pascal');
end;

procedure TMcpEditToolsTests.ConventionsListActiveRules;
var
  Settings: TServerSettings;
  Catalog: TRuleCatalog;
  Text: string;
begin
  Settings := Default(TServerSettings);
  Catalog := TFindingPrompt.GermanCatalog;
  try
    Text := TRuleConventions.Markdown(BuiltinRules, Settings, Catalog);
  finally
    Catalog.Free;
  end;
  Assert.Contains(Text, '# Konventionen des Projekts');
  Assert.Contains(Text, 'Regelprofil: `standard`');
  Assert.Contains(Text, '## Aktive Regeln');
  Assert.IsFalse(Text.Contains('## Aktive Regeln (0)'), 'Standardprofil hat aktive Regeln');
  Assert.IsTrue(TRuleConventions.IsNamingRule('naming-convention'));
end;

const
  cAssignedFree = 'unit U;'#10#10'interface'#10#10'uses'#10'  System.Classes;'#10#10'implementation'#10#10 +
    'procedure Weg(AList: TStringList);'#10'begin'#10'  if Assigned(AList) then'#10'    AList.Free;'#10'end;'#10#10 +
    'end.'#10;

procedure TMcpEditToolsTests.FixFindingsPreviewsAndWrites;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
  Report, Audit: string;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Audit := '';
    Edit.Audit :=
      procedure(const AText: string)
      begin
        Audit := Audit + AText;
      end;
    Files.Files.Add('U.pas', cAssignedFree);
    Report := Edit.FixFindings(BuiltinRules, TServerSettings.Default, '', ['U.pas'], ['redundant-assigned-free'], '',
      True);
    Assert.Contains(Report, 'Vorschau: 1 Korrekturen in 1 Dateien');
    Assert.Contains(Report, '--- a/U.pas');
    Assert.Contains(Report, '-  if Assigned(AList) then');
    Assert.AreEqual(0, Files.Writes, 'Vorschau schreibt nichts');
    Assert.AreEqual('', Audit);
    Report := Edit.FixFindings(BuiltinRules, TServerSettings.Default, '', ['U.pas'], ['redundant-assigned-free'], '',
      False);
    Assert.Contains(Report, '1 Korrekturen in 1 Dateien geschrieben');
    Assert.AreEqual(1, Files.Writes);
    Assert.IsFalse(Pos('Assigned', Files.Files['U.pas']) > 0, Files.Files['U.pas']);
    Assert.Contains(Audit, 'fix_findings (redundant-assigned-free)');
    Assert.Contains(Audit, 'U.pas');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.FixFindingsSkipsDirtyFiles;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
  Report: string;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Edit.DirtyFiles :=
      function: TArray<string>
      begin
        Result := ['u.pas'];
      end;
    Files.Files.Add('U.pas', cAssignedFree);
    Files.Files.Add('V.pas', StringReplace(cAssignedFree, 'unit U;', 'unit V;', []));
    Report := Edit.FixFindings(BuiltinRules, TServerSettings.Default, '', ['U.pas', 'V.pas'],
      ['redundant-assigned-free'], '', False);
    Assert.Contains(Report, 'Nicht angefasst (ungespeicherte Änderungen im Editor): U.pas');
    Assert.AreEqual(cAssignedFree, Files.Files['U.pas']);
    Assert.AreEqual(1, Files.Writes, 'V.pas geschrieben');
  finally
    Edit.Free;
    Files.Free;
  end;
end;

procedure TMcpEditToolsTests.FixFindingsRefusesLowerConfidence;
var
  Files: TMemoryFiles;
  Edit: TMcpEditTools;
begin
  Files := TMemoryFiles.Create;
  Edit := Tools(Files);
  try
    Files.Files.Add('U.pas', cAssignedFree);
    Assert.WillRaise(
      procedure
      begin
        Edit.FixFindings(BuiltinRules, TServerSettings.Default, '', ['U.pas'], ['redundant-assigned-free'], 'medium',
          True);
      end, EMcpToolError);
    Assert.WillRaise(
      procedure
      begin
        Edit.FixFindings(BuiltinRules, TServerSettings.Default, '', ['U.pas'], nil, '', True);
      end, EMcpToolError);
    Assert.AreEqual(0, Files.Writes);
  finally
    Edit.Free;
    Files.Free;
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
