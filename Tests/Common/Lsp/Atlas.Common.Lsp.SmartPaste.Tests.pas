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
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.SmartPaste,
  Atlas.Common.Lsp.SmartPaste;

const
  cTarget =
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
      begin
        Result := ['System.JSON'];
      end
      else if SameText(AName, 'TList') then
      begin
        Result := ['System.Classes', 'System.Generics.Collections'];
      end;
    end;
end;

function Run(const AArguments: string): string;
var
  mArguments: TJSONValue;
  mTree: TSyntaxTree;
  mAnswer: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue(AArguments);
  mTree := TPascalParser.Parse(cTarget);
  try
    mAnswer := TLspSmartPaste.Execute(TJSONArray(mArguments), 'file:///c%3A/p/Ziel.pas', cTarget, mTree, Context, nil);
    try
      Result := mAnswer.ToJSON;
    finally
      mAnswer.Free;
    end;
  finally
    mTree.Free;
    mArguments.Free;
  end;
end;

procedure TLspSmartPasteTests.AnalyzesAndEdits;
const
  cRange = '{"start":{"line":6,"character":0},"end":{"line":8,"character":0}}';
begin
  Assert.AreEqual('{"units":["System.JSON"],"choices":[{"name":"TList","units":["System.Classes",' +
    '"System.Generics.Collections"]}],"interface":true}', Run('["u",' + cRange + ']'));
  Assert.AreEqual('{"edit":{"changes":{"file:///c%3A/p/Ziel.pas":[{"range":{"start":{"line":3,"character":17},' +
    '"end":{"line":3,"character":17}},"newText":",\n  System.JSON, System.Classes"}]}},' +
    '"added":["System.JSON","System.Classes"],"toImplementation":[]}',
    Run('["u",' + cRange + ',["System.JSON","System.Classes"]]'));
  Assert.AreEqual('{"edit":null,"added":[],"toImplementation":[]}', Run('["u",' + cRange + ',["System.SysUtils"]]'));
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
