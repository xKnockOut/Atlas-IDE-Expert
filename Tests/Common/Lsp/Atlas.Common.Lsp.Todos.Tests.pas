unit Atlas.Common.Lsp.Todos.Tests;

// Tests des Befehls atlas.server.todos (#68): Zusammenfassung für die
// Projekt-Zusammenfassung (#758), Liste mit Filter für das Plugin, Markdown,
// eine einzelne Datei und nur die Dateien des Projekts.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspTodosTests = class
  public
    [Test]
    procedure SummaryCountsOpenAndDone;
    [Test]
    procedure JsonWithRootAndFilter;
    [Test]
    procedure MarkdownOverProject;
    [Test]
    procedure SingleFileIsJson;
    [Test]
    procedure KeywordsFromConfiguration;
    [Test]
    procedure UnknownModeIsRejected;
    [Test]
    procedure ParsesModeAndFilter;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos;

const
  MainFile = 'C:\P\Main.pas';
  HelperFile = 'C:\P\Source\Helper.pas';
  /// <summary>Liegt im Ordner, gehört aber nicht zum Projekt.</summary>
  ForeignFile = 'C:\P\Fremd.pas';
  MainText = 'unit Main;'#10'// TODO 1 -oMarco -cGUI : Fokus'#10'{ DONE -oAnna : Index }'#10 +
    '// HACK Umweg'#10'end.';
  HelperText = 'unit Helper;'#10'// FIXME Rabatt'#10'end.';

function NewTodos(const AConfig: string): TLspTodos;
begin
  Result := TLspTodos.Create(
    function(const AFileName: string; AProject: Boolean; out ASource: TLspMetricsSource): Boolean
    var
      Issues: TArray<TConfigurationIssue>;
    begin
      ASource := Default(TLspMetricsSource);
      ASource.Settings := TConfigurationParser.Parse(AConfig, Issues);
      ASource.Root := 'C:\P';
      ASource.Title := 'Demo';
      if AProject then
        ASource.Files := [MainFile, HelperFile, 'C:\P\Main.dfm'];
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, MainFile) then
        AText := MainText
      else if SameText(AFileName, HelperFile) then
        AText := HelperText
      else if SameText(AFileName, ForeignFile) then
        AText := 'unit Fremd;'#10'// TODO fremd'#10'end.'
      else
        Result := False;
    end);
end;

function Run(ATodos: TLspTodos; const AFileName, AMode, AFilter: string): string;
var
  Args: TJSONArray;
  Answer: TJSONValue;
begin
  Args := TJSONArray.Create;
  try
    if AFileName = '' then
      Args.AddElement(TJSONNull.Create)
    else
      Args.Add(TDocumentUris.FromPath(AFileName));
    if (AMode <> '') or (AFilter <> '') then
      Args.Add(AMode);
    if AFilter <> '' then
      Args.AddElement(TJSONObject.ParseJSONValue(AFilter));
    Answer := ATodos.Execute(Args);
    try
      if Answer is TJSONString then
        Result := Answer.Value
      else
        Result := Answer.ToJSON;
    finally
      Answer.Free;
    end;
  finally
    Args.Free;
  end;
end;

{ TLspTodosTests }

procedure TLspTodosTests.SummaryCountsOpenAndDone;
var
  Todos: TLspTodos;
  Text: string;
begin
  Todos := NewTodos('{}');
  try
    Text := Run(Todos, 'C:\P\Demo.dproj', '', '');
    Assert.AreEqual('{"format":1,"summary":{"files":2,"open":2,"done":1,"keywords":{"FIXME":1,"TODO":1}}}', Text);
    Assert.AreEqual(Text, Run(Todos, 'C:\P\Demo.dproj', 'summary', '{"owner": "Marco"}'),
      'die Zusammenfassung zählt immer alles');
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.JsonWithRootAndFilter;
var
  Todos: TLspTodos;
  Text: string;
begin
  Todos := NewTodos('{}');
  try
    Text := Run(Todos, '', 'json', '');
    Assert.Contains(Text, '"root":"C:\\P"');
    // Ohne „/“ verglichen: ToJSON darf ihn maskieren.
    Assert.Contains(Text, '"unit":"Helper"');
    Assert.DoesNotContain(Text, '"DONE"');
    Assert.DoesNotContain(Text, 'fremd');
    Text := Run(Todos, '', 'json', '{"owner": "anna", "includeDone": true}');
    Assert.Contains(Text, '"keyword":"DONE","done":true');
    Assert.DoesNotContain(Text, 'Helper');
    Text := Run(Todos, '', 'json', '{"unit": "Helper", "keyword": "FIXME"}');
    Assert.Contains(Text, '"open":1');
    Assert.Contains(Text, '"text":"Rabatt"');
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.MarkdownOverProject;
var
  Todos: TLspTodos;
  Text: string;
begin
  Todos := NewTodos('{}');
  try
    Text := Run(Todos, '', 'markdown', '');
    Assert.StartsWith('# TODOs: Demo', Text);
    Assert.Contains(Text, '## Helper (1)');
    Assert.Contains(Text, '`Source/Helper.pas`');
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.SingleFileIsJson;
var
  Todos: TLspTodos;
  Text: string;
begin
  Todos := NewTodos('{}');
  try
    Text := Run(Todos, ForeignFile, '', '');
    Assert.Contains(Text, '"file":"Fremd.pas"');
    Assert.Contains(Text, '"open":1');
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.KeywordsFromConfiguration;
var
  Todos: TLspTodos;
begin
  Todos := NewTodos('{"rules": {"todo-comment": {"keywords": ["TODO", "FIXME", "HACK"]}}}');
  try
    Assert.Contains(Run(Todos, 'C:\P\Demo.dproj', 'summary', ''), '"open":3');
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.UnknownModeIsRejected;
var
  Todos: TLspTodos;
begin
  Todos := NewTodos('{}');
  try
    Assert.WillRaise(
      procedure
      begin
        Run(Todos, '', 'html', '');
      end, EJsonRpcError);
  finally
    Todos.Free;
  end;
end;

procedure TLspTodosTests.ParsesModeAndFilter;
var
  Mode: TLspTodosMode;
  Value: TJSONValue;
  Filter: TTodoFilter;
begin
  Assert.IsTrue(TLspTodos.TryParseMode('', True, Mode));
  Assert.AreEqual(Ord(TLspTodosMode.Summary), Ord(Mode));
  Assert.IsTrue(TLspTodos.TryParseMode('', False, Mode));
  Assert.AreEqual(Ord(TLspTodosMode.Json), Ord(Mode));
  Assert.IsTrue(TLspTodos.TryParseMode('Markdown', True, Mode));
  Assert.AreEqual(Ord(TLspTodosMode.Markdown), Ord(Mode));
  Assert.IsFalse(TLspTodos.TryParseMode('html', True, Mode));
  Filter := TLspTodos.FilterOf(nil);
  Assert.IsFalse(Filter.IncludeDone);
  Assert.AreEqual('', Filter.Owner);
  Value := TJSONObject.ParseJSONValue('{"category": " GUI ", "owner": "Marco", "unit": "Main", "keyword": "TODO", ' +
    '"includeDone": true}');
  try
    Filter := TLspTodos.FilterOf(Value);
  finally
    Value.Free;
  end;
  Assert.AreEqual('GUI', Filter.Category);
  Assert.AreEqual('Marco', Filter.Owner);
  Assert.AreEqual('Main', Filter.UnitName);
  Assert.AreEqual('TODO', Filter.Keyword);
  Assert.IsTrue(Filter.IncludeDone);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTodosTests);

end.
