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
  System.Generics.Collections,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Documents.Uris,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Configuration.Parser,
  Atlas.Common.Todos.Contract,
  Atlas.Common.Lsp.Metrics,
  Atlas.Common.Lsp.Todos;

const
  cMainFile = 'C:\P\Main.pas';
  cHelperFile = 'C:\P\Source\Helper.pas';
  /// <summary>Liegt im Ordner, gehört aber nicht zum Projekt.</summary>
  cForeignFile = 'C:\P\Fremd.pas';
  cMainText = 'unit Main;'#10'// TODO 1 -oMarco -cGUI : Fokus'#10'{ DONE -oAnna : Index }'#10 +
    '// HACK Umweg'#10'end.';
  cHelperText = 'unit Helper;'#10'// FIXME Rabatt'#10'end.';

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
      begin
        ASource.Files := [cMainFile, cHelperFile, 'C:\P\Main.dfm'];
      end;
      Result := True;
    end,
    function(const AFileName: string; out AText: string): Boolean
    begin
      Result := True;
      if SameText(AFileName, cMainFile) then
      begin
        AText := cMainText;
      end
      else if SameText(AFileName, cHelperFile) then
      begin
        AText := cHelperText;
      end
      else if SameText(AFileName, cForeignFile) then
      begin
        AText := 'unit Fremd;'#10'// TODO fremd'#10'end.';
      end
      else
      begin
        Result := False;
      end;
    end);
end;

function Run(ATodos: TLspTodos; const AFileName, AMode, AFilter: string): string;
var
  mArgs: TJSONArray;
  mAnswer: TJSONValue;
begin
  mArgs := TJSONArray.Create;
  try
    if AFileName = '' then
    begin
      mArgs.AddElement(TJSONNull.Create);
    end
    else
    begin
      mArgs.Add(TDocumentUris.FromPath(AFileName));
    end;
    if (AMode <> '') or (AFilter <> '') then
    begin
      mArgs.Add(AMode);
    end;
    if AFilter <> '' then
    begin
      mArgs.AddElement(TJSONObject.ParseJSONValue(AFilter));
    end;
    mAnswer := ATodos.Execute(mArgs);
    try
      if mAnswer is TJSONString then
      begin
        Result := mAnswer.Value;
      end
      else
      begin
        Result := mAnswer.ToJSON;
      end;
    finally
      mAnswer.Free;
    end;
  finally
    mArgs.Free;
  end;
end;

{ TLspTodosTests }

procedure TLspTodosTests.SummaryCountsOpenAndDone;
var
  mTodos: TLspTodos;
  mText: string;
begin
  mTodos := NewTodos('{}');
  try
    mText := Run(mTodos, 'C:\P\Demo.dproj', '', '');
    Assert.AreEqual('{"format":1,"summary":{"files":2,"open":2,"done":1,"keywords":{"FIXME":1,"TODO":1}}}', mText);
    Assert.AreEqual(mText, Run(mTodos, 'C:\P\Demo.dproj', 'summary', '{"owner": "Marco"}'),
      'die Zusammenfassung zählt immer alles');
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.JsonWithRootAndFilter;
var
  mTodos: TLspTodos;
  mText: string;
begin
  mTodos := NewTodos('{}');
  try
    mText := Run(mTodos, '', 'json', '');
    Assert.Contains(mText, '"root":"C:\\P"');
    // Ohne „/“ verglichen: ToJSON darf ihn maskieren.
    Assert.Contains(mText, '"unit":"Helper"');
    // DUnitX vergleicht ohne Groß-/Kleinschreibung: „"DONE"“ allein träfe den Schlüssel „"done"“.
    Assert.DoesNotContain(mText, '"keyword":"DONE"');
    Assert.DoesNotContain(mText, 'fremd');
    mText := Run(mTodos, '', 'json', '{"owner": "anna", "includeDone": true}');
    Assert.Contains(mText, '"keyword":"DONE","done":true');
    Assert.DoesNotContain(mText, 'Helper');
    mText := Run(mTodos, '', 'json', '{"unit": "Helper", "keyword": "FIXME"}');
    Assert.Contains(mText, '"open":1');
    Assert.Contains(mText, '"text":"Rabatt"');
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.MarkdownOverProject;
var
  mTodos: TLspTodos;
  mText: string;
begin
  mTodos := NewTodos('{}');
  try
    mText := Run(mTodos, '', 'markdown', '');
    Assert.StartsWith('# TODOs: Demo', mText);
    Assert.Contains(mText, '## Helper (1)');
    Assert.Contains(mText, '`Source/Helper.pas`');
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.SingleFileIsJson;
var
  mTodos: TLspTodos;
  mText: string;
begin
  mTodos := NewTodos('{}');
  try
    mText := Run(mTodos, cForeignFile, '', '');
    Assert.Contains(mText, '"file":"Fremd.pas"');
    Assert.Contains(mText, '"open":1');
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.KeywordsFromConfiguration;
var
  mTodos: TLspTodos;
begin
  mTodos := NewTodos('{"rules": {"todo-comment": {"keywords": ["TODO", "FIXME", "HACK"]}}}');
  try
    Assert.Contains(Run(mTodos, 'C:\P\Demo.dproj', 'summary', ''), '"open":3');
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.UnknownModeIsRejected;
var
  mTodos: TLspTodos;
begin
  mTodos := NewTodos('{}');
  try
    Assert.WillRaise(
      procedure
      begin
        Run(mTodos, '', 'html', '');
      end, EJsonRpcError);
  finally
    mTodos.Free;
  end;
end;

procedure TLspTodosTests.ParsesModeAndFilter;
var
  mMode: TLspTodosMode;
  mValue: TJSONValue;
  mFilter: TTodoFilter;
begin
  Assert.IsTrue(TLspTodos.TryParseMode('', True, mMode));
  Assert.AreEqual(Ord(TLspTodosMode.Summary), Ord(mMode));
  Assert.IsTrue(TLspTodos.TryParseMode('', False, mMode));
  Assert.AreEqual(Ord(TLspTodosMode.Json), Ord(mMode));
  Assert.IsTrue(TLspTodos.TryParseMode('Markdown', True, mMode));
  Assert.AreEqual(Ord(TLspTodosMode.Markdown), Ord(mMode));
  Assert.IsFalse(TLspTodos.TryParseMode('html', True, mMode));
  mFilter := TLspTodos.FilterOf(nil);
  Assert.IsFalse(mFilter.IncludeDone);
  Assert.AreEqual('', mFilter.Owner);
  mValue := TJSONObject.ParseJSONValue('{"category": " GUI ", "owner": "Marco", "unit": "Main", "keyword": "TODO", ' +
    '"includeDone": true}');
  try
    mFilter := TLspTodos.FilterOf(mValue);
  finally
    mValue.Free;
  end;
  Assert.AreEqual('GUI', mFilter.Category);
  Assert.AreEqual('Marco', mFilter.Owner);
  Assert.AreEqual('Main', mFilter.UnitName);
  Assert.AreEqual('TODO', mFilter.Keyword);
  Assert.IsTrue(mFilter.IncludeDone);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspTodosTests);

end.
