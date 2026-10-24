unit Atlas.Core.Lsp.Session.Tests;

// Parameter von initialize und Antwort auf workspace/applyEdit (S-03a): Klassenfunktionen von TLspSession
// ohne Server und ohne Windows. Die Tests mit Client und Server stehen in Atlas.Core.Lsp.Tests.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspInitializeParamsTests = class
  public
    [Test]
    procedure InitializeParamsAnnouncesApplyEditOnlyWithHandler;
    [Test]
    procedure InitializeParamsHasPlainTextHoverAndSnippets;
    [Test]
    procedure InitializeParamsCarriesWorkspaceFolders;
    [Test]
    procedure InitializeParamsMergesSettingsAndContexts;
    [Test]
    procedure InitializeParamsWithoutOptionsHasNoInitializationOptions;
    [Test]
    procedure ApplyEditAnswerOmitsEmptyReason;
    /// <summary>#621: data.tag einer CodeAction landet in Tag.</summary>
    [Test]
    procedure CodeActionCarriesTag;
    /// <summary>#503: Gliederung flach, Container = Elternsymbol; SymbolInformation ebenso.</summary>
    [Test]
    procedure DocumentSymbolsAreFlattened;
    [Test]
    procedure InlineValueRefsAreVariableLookups;
  end;

implementation

uses
  System.Generics.Collections,
  System.SysUtils,
  System.JSON,
  Atlas.Core.Projects.Contract,
  Atlas.Core.Lsp.Contract,
  Atlas.Core.Lsp.Session;

function Context(const AProject: string): TAtlasProjectContext;
begin
  Result := Default(TAtlasProjectContext);
  Result.Project := AProject;
  Result.Configuration := 'Debug';
  Result.Platform := 'Win64';
end;

procedure TLspInitializeParamsTests.InitializeParamsAnnouncesApplyEditOnlyWithHandler;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(nil, '', nil, True);
  try
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.workspace.applyEdit'));
  finally
    Params.Free;
  end;
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsFalse(Params.GetValue<Boolean>('capabilities.workspace.applyEdit'));
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.workspace.diagnostics.refreshSupport'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsHasPlainTextHoverAndSnippets;
var
  Params: TJSONObject;
  Formats: TJSONArray;
begin
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Formats := Params.GetValue<TJSONArray>('capabilities.textDocument.hover.contentFormat');
    Assert.AreEqual(1, Integer(Formats.Count));
    Assert.AreEqual('plaintext', Formats.Items[0].Value);
    Assert.IsTrue(Params.GetValue<Boolean>('capabilities.textDocument.completion.completionItem.snippetSupport'));
    Assert.IsFalse(Params.GetValue<Boolean>('capabilities.textDocument.diagnostic.dynamicRegistration'));
    Assert.AreEqual('Atlas IDE Expert', Params.GetValue<string>('clientInfo.name'));
    Assert.IsTrue(Params.GetValue('processId') is TJSONNull);
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsCarriesWorkspaceFolders;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(['C:\A\Eins.dproj', 'C:\B\Zwei.dproj'], '', nil, False);
  try
    Assert.AreEqual(2, Params.GetValue<TJSONArray>('workspaceFolders').Count);
    Assert.AreEqual('Eins', TJSONObject(Params.GetValue<TJSONArray>('workspaceFolders').Items[0])
      .GetValue<string>('name'));
  finally
    Params.Free;
  end;
  Params := TLspSession.InitializeParams(nil, '', nil, False);
  try
    Assert.IsNull(Params.GetValue('workspaceFolders'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsMergesSettingsAndContexts;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(nil, '{"rules":{"x":"off"}}',
    [Context('C:\A\Eins.dproj'), Context('C:\B\Zwei.dproj')], False);
  try
    Assert.AreEqual('off', Params.GetValue<string>('initializationOptions.settings.atlas.rules.x'));
    Assert.AreEqual(2, Params.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.AreEqual('Win64', TJSONObject(Params.GetValue<TJSONArray>('initializationOptions.projectContexts')
      .Items[1]).GetValue<string>('platform'));
  finally
    Params.Free;
  end;
  // Nur Kontexte: initializationOptions entsteht trotzdem.
  Params := TLspSession.InitializeParams(nil, '', [Context('C:\A\Eins.dproj')], False);
  try
    Assert.AreEqual(1, Params.GetValue<TJSONArray>('initializationOptions.projectContexts').Count);
    Assert.IsNull(Params.GetValue<TJSONObject>('initializationOptions').GetValue('settings'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.InitializeParamsWithoutOptionsHasNoInitializationOptions;
var
  Params: TJSONObject;
begin
  Params := TLspSession.InitializeParams(['C:\A\Eins.dproj'], '', nil, True);
  try
    Assert.IsNull(Params.GetValue('initializationOptions'));
  finally
    Params.Free;
  end;
end;

procedure TLspInitializeParamsTests.ApplyEditAnswerOmitsEmptyReason;
var
  Answer: TJSONObject;
begin
  Answer := TLspSession.ApplyEditAnswer(True, '');
  try
    Assert.IsTrue(Answer.GetValue<Boolean>('applied'));
    Assert.IsNull(Answer.GetValue('failureReason'));
  finally
    Answer.Free;
  end;
  Answer := TLspSession.ApplyEditAnswer(False, 'Datei schreibgeschützt');
  try
    Assert.IsFalse(Answer.GetValue<Boolean>('applied'));
    Assert.AreEqual('Datei schreibgeschützt', Answer.GetValue<string>('failureReason'));
  finally
    Answer.Free;
  end;
end;

procedure TLspInitializeParamsTests.CodeActionCarriesTag;
var
  Value: TJSONValue;
  Action: TLspCodeAction;
begin
  Value := TJSONObject.ParseJSONValue('{"title":"Vcl.Grids entfernen","kind":"quickfix","data":{"tag":"uses.remove"}}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(Value, Action));
    Assert.AreEqual('uses.remove', Action.Tag);
  finally
    Value.Free;
  end;
  Value := TJSONObject.ParseJSONValue('{"title":"Ohne","kind":"quickfix"}');
  try
    Assert.IsTrue(TLspCodeAction.FromJson(Value, Action));
    Assert.AreEqual('', Action.Tag);
  finally
    Value.Free;
  end;
end;

procedure TLspInitializeParamsTests.DocumentSymbolsAreFlattened;
var
  Response: TJSONValue;
  Symbols: TArray<TAtlasSymbol>;
begin
  Response := TJSONObject.ParseJSONValue('[{"name":"TKunde","kind":5,"range":{"start":{"line":3,"character":2}},' +
    '"selectionRange":{"start":{"line":3,"character":4}},"children":[{"name":"Laden","kind":6,' +
    '"selectionRange":{"start":{"line":9,"character":14}}}]},{"name":"Hilfe","kind":12,' +
    '"range":{"start":{"line":20,"character":0}}}]');
  try
    Symbols := TLspSession.SymbolsOfDocument(Response, 'C:\P\Kunden.pas');
  finally
    Response.Free;
  end;
  Assert.AreEqual(3, Integer(Length(Symbols)));
  Assert.AreEqual('TKunde', Symbols[0].Name);
  Assert.AreEqual(4, Symbols[0].Character);
  Assert.AreEqual('Laden', Symbols[1].Name);
  Assert.AreEqual('TKunde', Symbols[1].Container);
  Assert.AreEqual(9, Symbols[1].Line);
  Assert.AreEqual('C:\P\Kunden.pas', Symbols[1].FileName);
  Assert.AreEqual('Hilfe', Symbols[2].Name);
  Assert.AreEqual(20, Symbols[2].Line);
  Assert.AreEqual('', Symbols[2].Container);
  Response := TJSONObject.ParseJSONValue('[{"name":"Laden","kind":6,"containerName":"TKunde",' +
    '"location":{"uri":"file:///C:/P/Kunden.pas","range":{"start":{"line":7,"character":3}}}}]');
  try
    Symbols := TLspSession.SymbolsOfDocument(Response, 'C:\P\Kunden.pas');
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Symbols)));
  Assert.AreEqual('TKunde', Symbols[0].Container);
  Assert.AreEqual(7, Symbols[0].Line);
  Assert.AreEqual(Integer(0), Integer(Length(TLspSession.SymbolsOfDocument(nil, 'x'))));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInitializeParamsTests);

procedure TLspInitializeParamsTests.InlineValueRefsAreVariableLookups;
var
  Response: TJSONValue;
  Refs: TAtlasInlineValueRefs;
begin
  // #508: nur variableName; Text- und Ausdrucks-Werte wertet Atlas nicht aus (keine Nebenwirkungen).
  Response := TJSONObject.ParseJSONValue('[{"range":{"start":{"line":23,"character":2},"end":{"line":23,' +
    '"character":7}},"variableName":"Summe","caseSensitiveLookup":false,"atlasType":"Integer"},' +
    '{"range":{"start":{"line":24,"character":0}},"text":"x"},' +
    '{"range":{"start":{"line":24,"character":4}},"expression":"Liste.Count"},' +
    '{"range":{"start":{"line":24,"character":9}},"variableName":"Datum"}]');
  try
    Refs := TLspSession.InlineValueRefsOf(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(2, Integer(Length(Refs)));
  Assert.AreEqual('Summe', Refs[0].Name);
  Assert.AreEqual(23, Refs[0].Line);
  Assert.AreEqual(2, Refs[0].Character);
  Assert.AreEqual('Integer', Refs[0].TypeName);
  Assert.AreEqual('Datum', Refs[1].Name);
  Assert.AreEqual('', Refs[1].TypeName);
  Assert.AreEqual(0, Integer(Length(TLspSession.InlineValueRefsOf(nil))), 'ohne Antwort');
end;

end.
