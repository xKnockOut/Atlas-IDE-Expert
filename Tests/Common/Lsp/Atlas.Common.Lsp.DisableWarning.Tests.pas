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
  cUri = 'file:///C:/Projekt/A.pas';
  cSource =
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
  mAction: TJSONObject;
begin
  Result := '';
  for mAction in AActions do
  begin
    Result := Result + mAction.GetValue<string>('title', '');
    if mAction.GetValue<Boolean>('isPreferred', False) then
    begin
      Result := Result + ' *';
    end;
    Result := Result + '|';
  end;
end;

procedure FreeAll(const AActions: TArray<TJSONObject>);
var
  mAction: TJSONObject;
begin
  for mAction in AActions do
  begin
    mAction.Free;
  end;
end;

function ActionsFor(const AOptions: TDisableWarningOptions; AFirst, ALast: Integer;
  const AMessages: TArray<TCompilerMessage>): TArray<TJSONObject>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Result := TLspDisableWarning.Actions(AOptions, mTree, cUri, AFirst, ALast, AMessages);
  finally
    mTree.Free;
  end;
end;

procedure TLspDisableWarningTests.OffersScopesForWarning;
var
  mActions: TArray<TJSONObject>;
  mArguments: TJSONArray;
begin
  mActions := ActionsFor(Options, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual('W1000 hier abschalten ({$WARN SYMBOL_DEPRECATED OFF}) *|' +
      'W1000 in Foo abschalten ({$WARN SYMBOL_DEPRECATED OFF})|' +
      'W1000 in der ganzen Unit abschalten ({$WARN SYMBOL_DEPRECATED OFF})|' +
      'W1000 im ganzen Projekt abschalten (Projektoptionen)|', Summary(mActions));
    mArguments := mActions[0].GetValue<TJSONObject>('command').GetValue<TJSONArray>('arguments');
    Assert.AreEqual(TLspDisableWarning.cClientCommand, mActions[0].GetValue<TJSONObject>('command').GetValue<string>(
      'command', ''));
    Assert.AreEqual('["file:///C:/Projekt/A.pas",7,"W1000","line",true]', mArguments.ToJSON);
    Assert.AreEqual(TLspDisableWarning.cProjectCommand, mActions[3].GetValue<TJSONObject>('command').GetValue<string>(
      'command', ''));
    Assert.AreEqual('["file:///C:/Projekt/A.pas","W1000","SYMBOL_DEPRECATED"]',
      mActions[3].GetValue<TJSONObject>('command').GetValue<TJSONArray>('arguments').ToJSON);
    Assert.AreEqual('quickfix', mActions[0].GetValue<string>('kind', ''));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspDisableWarningTests.RoutineWideHintPrefersRoutine;
var
  mActions: TArray<TJSONObject>;
begin
  mActions := ActionsFor(Options, 5, 5, [Msg(5, 'H2164', TCompilerSeverity.Hint)]);
  try
    Assert.AreEqual('H2164 in Foo abschalten ({$HINTS OFF}) *|' +
      'H2164 in der ganzen Unit abschalten ({$HINTS OFF})|', Summary(mActions));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspDisableWarningTests.WarningWithoutIdentifierSaysAllWarnings;
var
  mActions: TArray<TJSONObject>;
begin
  mActions := ActionsFor(Options, 7, 7, [Msg(7, 'W1999', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual('W1999 hier abschalten ({$WARNINGS OFF}: betrifft alle Warnungen) *|' +
      'W1999 in Foo abschalten ({$WARNINGS OFF}: betrifft alle Warnungen)|' +
      'W1999 in der ganzen Unit abschalten ({$WARNINGS OFF}: betrifft alle Warnungen)|', Summary(mActions));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspDisableWarningTests.IgnoresErrorsOtherLinesAndDisabled;
var
  mActions: TArray<TJSONObject>;
  mDisabled: TDisableWarningOptions;
begin
  mActions := ActionsFor(Options, 7, 7, [Msg(7, 'E2003', TCompilerSeverity.Error),
    Msg(5, 'W1000', TCompilerSeverity.Warning), Msg(-1, 'W1000', TCompilerSeverity.Warning)]);
  Assert.AreEqual(0, Integer(Length(mActions)));
  mDisabled := Options;
  mDisabled.Enabled := False;
  mActions := ActionsFor(mDisabled, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning)]);
  Assert.AreEqual(0, Integer(Length(mActions)));
  // Dieselbe Meldung zweimal (zwei Plattformen): nur einmal anbieten.
  mActions := ActionsFor(Options, 7, 7, [Msg(7, 'W1000', TCompilerSeverity.Warning),
    Msg(7, 'w1000', TCompilerSeverity.Warning)]);
  try
    Assert.AreEqual(4, Integer(Length(mActions)));
  finally
    FreeAll(mActions);
  end;
end;

procedure TLspDisableWarningTests.ExecuteReturnsWorkspaceEdit;
var
  mTree: TSyntaxTree;
  mArguments: TJSONArray;
  mAnswer: TJSONValue;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mArguments := TJSONObject.ParseJSONValue('["' + cUri + '", 7, "W1000", "line", "bewusst"]') as TJSONArray;
    try
      mAnswer := TLspDisableWarning.Execute(mArguments, cSource, mTree, '');
    finally
      mArguments.Free;
    end;
    try
      Assert.AreEqual('{"edit":{"documentChanges":[{"textDocument":{"uri":"' + cUri + '","version":null},' +
        '"edits":[{"range":{"start":{"line":7,"character":0},"end":{"line":7,"character":0}},' +
        '"newText":"  {$WARN SYMBOL_DEPRECATED OFF} // bewusst\n"},' +
        '{"range":{"start":{"line":7,"character":6},"end":{"line":7,"character":6}},' +
        '"newText":"\n  {$WARN SYMBOL_DEPRECATED ON}"}]}]},"allWarnings":false}', mAnswer.ToJSON);
    finally
      mAnswer.Free;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TLspDisableWarningTests.ExecuteRefusesBadArguments;
var
  mTree: TSyntaxTree;

  procedure Expect(const AJson: string);
  var
    mArguments: TJSONArray;
    mRaised: Boolean;
  begin
    mArguments := TJSONObject.ParseJSONValue(AJson) as TJSONArray;
    try
      mRaised := False;
      try
        TLspDisableWarning.Execute(mArguments, cSource, mTree, '').Free;
      except
        on EJsonRpcError do
          mRaised := True;
      end;
      Assert.IsTrue(mRaised, AJson);
    finally
      mArguments.Free;
    end;
  end;

begin
  mTree := TPascalParser.Parse(cSource);
  try
    Expect('["' + cUri + '", 7, "W1000"]');
    Expect('["' + cUri + '", 7, "W1000", "projekt"]');
    Expect('["' + cUri + '", 7, "E2003", "line"]');
    Expect('["' + cUri + '", 1, "W1000", "routine"]');
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspDisableWarningTests);

end.
