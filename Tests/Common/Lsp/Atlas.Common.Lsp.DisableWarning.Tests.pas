unit Atlas.Common.Lsp.DisableWarning.Tests;

// Tests für die Code-Aktionen und den Befehl atlas.server.disableWarning (#531).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspDisableWarningTests = class
  public
    [Test]
    procedure OffersScopesForWarning;
    /// <summary>Ablaufmeldung: keine Aktion um die Zeile, die Routine ist bevorzugt.</summary>
    [Test]
    procedure RoutineWideHintPrefersRoutine;
    [Test]
    procedure WarningWithoutIdentifierSaysAllWarnings;
    [Test]
    procedure IgnoresErrorsOtherLinesAndDisabled;
    [Test]
    procedure ExecuteReturnsWorkspaceEdit;
    [Test]
    procedure ExecuteRefusesBadArguments;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Compiler.Contract,
  Atlas.Common.JsonRpc.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Lsp.DisableWarning;

const
  Uri = 'file:///C:/Projekt/A.pas';
  Source =
    'unit A;' + #10 +                    // 0
    'interface' + #10 +                  // 1
    'implementation' + #10 +             // 2
    'procedure Foo;' + #10 +             // 3
    'var' + #10 +                        // 4
    '  X: Integer;' + #10 +              // 5
    'begin' + #10 +                      // 6
    '  Alt;' + #10 +                     // 7
    'end;' + #10 +                       // 8
    'end.';                              // 9

function Msg(ALine: Integer; const ACode: string; ASeverity: TCompilerSeverity): TCompilerMessage;
begin
  Result := Default(TCompilerMessage);
  Result.FileName := 'C:\Projekt\A.pas';
  Result.Line := ALine;
  Result.Code := ACode;
  Result.Severity := ASeverity;
end;

function Options: TDisableWarningOptions;
begin
  Result.Enabled := True;
  Result.AskReason := True;
  Result.Version := '';
end;

function Summary(const AActions: TArray<TJSONObject>): string;
var
  Action: TJSONObject;
begin
  Result := '';
  for Action in AActions do
  begin
    Result := Result + Action.GetValue<string>('title', '');
    if Action.GetValue<Boolean>('isPreferred', False) then
      Result := Result + ' *';
    Result := Result + '|';
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  Action: TJSONObject;
begin
  for Action in AActions do
    Action.Free;
end;

function ActionsFor(const AOptions: TDisableWarningOptions; AFirst, ALast: Integer;
  const AMessages: TArray<TCompilerMessage>): TArray<TJSONObject>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Result := TLspDisableWarning.Actions(AOptions, Tree, Uri, AFirst, ALast, AMessages);
  finally
    Tree.Free;
  end;
end;

procedure TLspDisableWarningTests.OffersScopesForWarning;
var
  Actions: TArray<TJSONObject>;
  Arguments: TJSONArray;
begin
  Actions := ActionsFor(Options, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual('W1000 hier abschalten ({$WARN SYMBOL_DEPRECATED OFF}) *|' +
      'W1000 in Foo abschalten ({$WARN SYMBOL_DEPRECATED OFF})|' +
      'W1000 in der ganzen Unit abschalten ({$WARN SYMBOL_DEPRECATED OFF})|' +
      'W1000 im ganzen Projekt abschalten (Projektoptionen)|', Summary(Actions));
    Arguments := Actions[0].GetValue<TJSONObject>('command').GetValue<TJSONArray>('arguments');
    Assert.AreEqual(TLspDisableWarning.ClientCommand, Actions[0].GetValue<TJSONObject>('command').GetValue<string>(
      'command', ''));
    Assert.AreEqual('["file:///C:/Projekt/A.pas",7,"W1000","line",true]', Arguments.ToJSON);
    Assert.AreEqual(TLspDisableWarning.ProjectCommand, Actions[3].GetValue<TJSONObject>('command').GetValue<string>(
      'command', ''));
    Assert.AreEqual('["file:///C:/Projekt/A.pas","W1000","SYMBOL_DEPRECATED"]',
      Actions[3].GetValue<TJSONObject>('command').GetValue<TJSONArray>('arguments').ToJSON);
    Assert.AreEqual('quickfix', Actions[0].GetValue<string>('kind', ''));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspDisableWarningTests.RoutineWideHintPrefersRoutine;
var
  Actions: TArray<TJSONObject>;
begin
  Actions := ActionsFor(Options, 5, 5, [Msg(5, 'H2164', TCompilerSeverity.Hint)]);
  try
    Assert.AreEqual('H2164 in Foo abschalten ({$HINTS OFF}) *|' +
      'H2164 in der ganzen Unit abschalten ({$HINTS OFF})|', Summary(Actions));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspDisableWarningTests.WarningWithoutIdentifierSaysAllWarnings;
var
  Actions: TArray<TJSONObject>;
begin
  Actions := ActionsFor(Options, 7, 7, [Msg(7, 'W1999', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual('W1999 hier abschalten ({$WARNINGS OFF}: betrifft alle Warnungen) *|' +
      'W1999 in Foo abschalten ({$WARNINGS OFF}: betrifft alle Warnungen)|' +
      'W1999 in der ganzen Unit abschalten ({$WARNINGS OFF}: betrifft alle Warnungen)|', Summary(Actions));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspDisableWarningTests.IgnoresErrorsOtherLinesAndDisabled;
var
  Actions: TArray<TJSONObject>;
  Disabled: TDisableWarningOptions;
begin
  Actions := ActionsFor(Options, 7, 7, [Msg(7, 'E2003', TCompilerSeverity.Error),
    Msg(5, 'W1000', TCompilerSeverity.Warning), Msg(-1, 'W1000', TCompilerSeverity.Warning)]);
  Assert.AreEqual(0, Integer(Length(Actions)));
  Disabled := Options;
  Disabled.Enabled := False;
  Actions := ActionsFor(Disabled, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning)]);
  Assert.AreEqual(0, Integer(Length(Actions)));
  // Dieselbe Meldung zweimal (zwei Plattformen): nur einmal anbieten.
  Actions := ActionsFor(Options, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning),
    Msg(7, 'w1000', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual(4, Integer(Length(Actions)));
  finally
    FreeAll(Actions);
  end;
end;

procedure TLspDisableWarningTests.ExecuteReturnsWorkspaceEdit;
var
  Tree: TSyntaxTree;
  Arguments: TJSONArray;
  Answer: TJSONValue;
begin
  Tree := TPascalParser.Parse(Source);
  try
    Arguments := TJSONObject.ParseJSONValue('["' + Uri + '", 7, "W1000", "line", "bewusst"]') as TJSONArray;
    try
      Answer := TLspDisableWarning.Execute(Arguments, Source, Tree, '');
    finally
      Arguments.Free;
    end;
    try
      Assert.AreEqual('{"edit":{"documentChanges":[{"textDocument":{"uri":"' + Uri + '","version":null},' +
        '"edits":[{"range":{"start":{"line":7,"character":0},"end":{"line":7,"character":0}},' +
        '"newText":"  {$WARN SYMBOL_DEPRECATED OFF} // bewusst\n"},' +
        '{"range":{"start":{"line":7,"character":6},"end":{"line":7,"character":6}},' +
        '"newText":"\n  {$WARN SYMBOL_DEPRECATED ON}"}]}]},"allWarnings":false}', Answer.ToJSON);
    finally
      Answer.Free;
    end;
  finally
    Tree.Free;
  end;
end;

procedure TLspDisableWarningTests.ExecuteRefusesBadArguments;
var
  Tree: TSyntaxTree;

  procedure Expect(const AJson: string);
  var
    Arguments: TJSONArray;
    Raised: Boolean;
  begin
    Arguments := TJSONObject.ParseJSONValue(AJson) as TJSONArray;
    try
      Raised := False;
      try
        TLspDisableWarning.Execute(Arguments, Source, Tree, '').Free;
      except
        on EJsonRpcError do
          Raised := True;
      end;
      Assert.IsTrue(Raised, AJson);
    finally
      Arguments.Free;
    end;
  end;

begin
  Tree := TPascalParser.Parse(Source);
  try
    Expect('["' + Uri + '", 7, "W1000"]');
    Expect('["' + Uri + '", 7, "W1000", "projekt"]');
    Expect('["' + Uri + '", 7, "E2003", "line"]');
    Expect('["' + Uri + '", 1, "W1000", "routine"]');
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDisableWarningTests);

end.
