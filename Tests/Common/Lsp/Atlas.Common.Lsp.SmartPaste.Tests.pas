unit Atlas.Common.Lsp.SmartPaste.Tests;

// Tests für Einfügen mit uses-Ergänzung über das Protokoll (#515): Analyse
// mit eindeutigen und mehrdeutigen Units, Edit für die gewählten.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspSmartPasteTests = class
  public
    [Test]
    procedure AnalyzesAndEdits;
    [Test]
    procedure RejectsMissingRange;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.SmartPaste;

const
  Target =
    'unit Ziel;'#10'interface'#10'uses'#10'  System.SysUtils;'#10'type'#10'  TFoo = class'#10 +
    '    FData: TJSONObject;'#10'    FList: TList;'#10'  end;'#10'implementation'#10'end.'#10;

function Context: TUsesContext;
begin
  Result := Default(TUsesContext);
  Result.Namespaces := ['System'];
  Result.Declaring :=
    function(const AName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AName, 'TJSONObject') then
        Result := ['System.JSON']
      else if SameText(AName, 'TList') then
        Result := ['System.Classes', 'System.Generics.Collections'];
    end;
end;

function Run(const AArguments: string): string;
var
  Arguments: TJSONValue;
  Tree: TSyntaxTree;
  Answer: TJSONObject;
begin
  Arguments := TJSONObject.ParseJSONValue(AArguments);
  Tree := TPascalParser.Parse(Target);
  try
    Answer := TLspSmartPaste.Execute(TJSONArray(Arguments), 'file:///c%3A/p/Ziel.pas', Target, Tree, Context, nil);
    try
      Result := Answer.ToJSON;
    finally
      Answer.Free;
    end;
  finally
    Tree.Free;
    Arguments.Free;
  end;
end;

procedure TLspSmartPasteTests.AnalyzesAndEdits;
const
  Range = '{"start":{"line":6,"character":0},"end":{"line":8,"character":0}}';
begin
  Assert.AreEqual('{"units":["System.JSON"],"choices":[{"name":"TList","units":["System.Classes",' +
    '"System.Generics.Collections"]}],"interface":true}', Run('["u",' + Range + ']'));
  Assert.AreEqual('{"edit":{"changes":{"file:///c%3A/p/Ziel.pas":[{"range":{"start":{"line":3,"character":17},' +
    '"end":{"line":3,"character":17}},"newText":",\n  System.JSON, System.Classes"}]}},' +
    '"added":["System.JSON","System.Classes"],"toImplementation":[]}',
    Run('["u",' + Range + ',["System.JSON","System.Classes"]]'));
  Assert.AreEqual('{"edit":null,"added":[],"toImplementation":[]}', Run('["u",' + Range + ',["System.SysUtils"]]'));
end;

procedure TLspSmartPasteTests.RejectsMissingRange;
begin
  Assert.WillRaise(
    procedure
    begin
      Run('["u"]');
    end, EArgumentException);
end;

initialization
  TDUnitX.RegisterTestFixture(TLspSmartPasteTests);

end.
