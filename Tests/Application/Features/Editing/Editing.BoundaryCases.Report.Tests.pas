unit Editing.BoundaryCases.Report.Tests;

// Bericht der Grenzfälle (#2173): Routine nach Namen, Markdown-Tabelle, Bericht für MCP als JSON und Markdown,
// Höchstzahl.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TBoundaryCaseReportsTests = class
  public
    [Test]
    procedure RoutineByName;
    [Test]
    procedure MarkdownTable;
    [Test]
    procedure ReportForMcp;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections, // Inline-Funktionen von TJSONArray (H2443)
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Editing.BoundaryCases,
  Editing.BoundaryCases.Report,
  Atlas.Text.Json;

const
  cBreak = #13#10;
  cText = 'unit Rabatt;' + cBreak + 'interface' + cBreak + 'implementation' + cBreak +
    'function Rabatt(ABetrag: Integer; AKunde: TObject): Integer;' + cBreak + 'begin' + cBreak +
    '  Result := 0;' + cBreak + '  if (ABetrag >= 100) and (AKunde <> nil) then' + cBreak + '    Result := 5;' +
    cBreak + 'end;' + cBreak + 'end.';

{ TBoundaryCaseReportsTests }

procedure TBoundaryCaseReportsTests.RoutineByName;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    Assert.IsNotNull(TBoundaryCaseReports.RoutineOf(mTree, -1, 'rabatt'));
    Assert.IsNull(TBoundaryCaseReports.RoutineOf(mTree, -1, 'Fehlt'));
    Assert.IsNull(TBoundaryCaseReports.RoutineOf(mTree, -1, ''));
  finally
    mTree.Free;
  end;
end;

procedure TBoundaryCaseReportsTests.MarkdownTable;
var
  mTree: TSyntaxTree;
  mRoutine: TSyntaxNode;
  mText: string;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mRoutine := TBoundaryCaseReports.RoutineOf(mTree, 6, '');
    mText := TBoundaryCaseReports.ToMarkdown('Rabatt.pas', mRoutine.StartPos.Line,
      TBoundaryCases.Find(mTree, mRoutine, 20));
  finally
    mTree.Free;
  end;
  Assert.Contains(mText, 'Rabatt.pas');
  Assert.Contains(mText, 'ABetrag: Integer (0)');
  Assert.Contains(mText, '| ABetrag | `100` |');
  Assert.Contains(mText, '| 7 | `100, nil` |');
  Assert.Contains(mText, '[TestCase]');
end;

procedure TBoundaryCaseReportsTests.ReportForMcp;
var
  mReport: string;
  mValue: TJSONValue;
  mRequest: TBoundaryCaseRequest;
begin
  mRequest := Default(TBoundaryCaseRequest);
  mRequest.FileName := 'Rabatt.pas';
  mRequest.Line := -1;
  mRequest.Routine := 'Rabatt';
  mRequest.Json := True;
  Assert.IsTrue(TBoundaryCaseReports.Report(cText, mRequest, mReport));
  mValue := TJSONObject.ParseJSONValue(mReport);
  try
    Assert.AreEqual(4, TJsonRead.Items(mValue as TJSONObject, 'cases').Count);
    Assert.AreEqual('Rabatt.pas', (mValue as TJSONObject).GetValue<string>('uri'));
  finally
    mValue.Free;
  end;
  mRequest.Line := 6;
  mRequest.Routine := '';
  mRequest.Max := 1;
  mRequest.Json := False;
  Assert.IsTrue(TBoundaryCaseReports.Report(cText, mRequest, mReport));
  Assert.Contains(mReport, 'maxCases');
  mRequest.Line := 0;
  Assert.IsFalse(TBoundaryCaseReports.Report(cText, mRequest, mReport));
  Assert.AreEqual(TBoundaryCases.cDefaultMax, TBoundaryCaseReports.MaxCases(0));
  Assert.AreEqual(TBoundaryCaseReports.cMaxMax, TBoundaryCaseReports.MaxCases(1000));
  Assert.AreEqual(TBoundaryCaseReports.cMinMax, TBoundaryCaseReports.MaxCases(-5));
end;

end.
