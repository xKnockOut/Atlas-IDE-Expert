unit Atlas.Core.Editor.SmartIndent.Tests;

interface

uses
  DUnitX.TestFramework;

type
  /// <summary>Plugin-Kern der Einrückung beim Tippen (#1827): Argumente, Antwort, ob sie noch passt.</summary>
  [TestFixture]
  TAtlasSmartIndentTests = class
  public
    [Test]
    procedure BuildsArguments;
    [Test]
    procedure ReadsAnswer;
    [Test]
    procedure RejectsInvalidAnswers;
    [Test]
    procedure ReadsColumn;
    [Test]
    procedure DiscardsAnswerAfterTyping;
    [Test]
    procedure SkipsQuickCommandsAndOtherFiles;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Editor.SmartIndent;

/// <summary>AText gelesen; nil bei ungültigem JSON.</summary>
function Parsed(const AText: string): TJSONValue;
begin
  Result := TJSONObject.ParseJSONValue(AText);
end;

procedure TAtlasSmartIndentTests.BuildsArguments;
begin
  Assert.AreEqual('["file:///C:/P/U.pas",3,{"tabSize":2,"insertSpaces":true}]',
    TAtlasSmartIndent.Arguments('file:///C:/P/U.pas', 3, 2, True, False));
  Assert.AreEqual('["file:///C:/P/Ä.pas",0,{"tabSize":4,"insertSpaces":false},"column"]',
    TAtlasSmartIndent.Arguments('file:///C:/P/Ä.pas', 0, 4, False, True));
end;

procedure TAtlasSmartIndentTests.ReadsAnswer;
var
  mValue: TJSONValue;
  mAnswer: TAtlasSmartIndentAnswer;
begin
  mValue := Parsed('{"edits":[{"range":{"start":{"line":1,"character":0},"end":{"line":1,"character":2}},' +
    '"newText":"    "}],"cursor":{"line":1,"character":4}}');
  try
    Assert.IsTrue(TAtlasSmartIndent.ReadAnswer(mValue, mAnswer));
  finally
    mValue.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mAnswer.Edits)));
  Assert.AreEqual(2, mAnswer.Edits[0].EndPos.Character);
  Assert.AreEqual('    ', mAnswer.Edits[0].NewText);
  Assert.AreEqual(1, mAnswer.Cursor.Line);
  Assert.AreEqual(4, mAnswer.Cursor.Character);
  // Keine Änderung nötig: nur die Schreibmarke.
  mValue := Parsed('{"edits":[],"cursor":{"line":5,"character":2}}');
  try
    Assert.IsTrue(TAtlasSmartIndent.ReadAnswer(mValue, mAnswer));
  finally
    mValue.Free;
  end;
  Assert.AreEqual(0, Integer(Length(mAnswer.Edits)));
  Assert.AreEqual(5, mAnswer.Cursor.Line);
  mAnswer := Default(TAtlasSmartIndentAnswer);
end;

procedure TAtlasSmartIndentTests.RejectsInvalidAnswers;
var
  mValue: TJSONValue;
  mAnswer: TAtlasSmartIndentAnswer;
begin
  Assert.IsFalse(TAtlasSmartIndent.ReadAnswer(nil, mAnswer));
  mValue := Parsed('null');
  try
    Assert.IsFalse(TAtlasSmartIndent.ReadAnswer(mValue, mAnswer));
  finally
    mValue.Free;
  end;
  mValue := Parsed('{"edits":[]}');
  try
    Assert.IsFalse(TAtlasSmartIndent.ReadAnswer(mValue, mAnswer), 'ohne cursor');
  finally
    mValue.Free;
  end;
  mValue := Parsed('{"edits":[{"newText":"x"}],"cursor":{"line":1,"character":0}}');
  try
    Assert.IsFalse(TAtlasSmartIndent.ReadAnswer(mValue, mAnswer), 'Änderung ohne range');
  finally
    mValue.Free;
  end;
  mAnswer := Default(TAtlasSmartIndentAnswer);
end;

procedure TAtlasSmartIndentTests.ReadsColumn;
var
  mValue: TJSONValue;
  mColumn: Integer;
begin
  mValue := Parsed('{"column":6}');
  try
    Assert.IsTrue(TAtlasSmartIndent.ReadColumn(mValue, mColumn));
    Assert.AreEqual(6, mColumn);
  finally
    mValue.Free;
  end;
  mValue := Parsed('{"column":-1}');
  try
    Assert.IsFalse(TAtlasSmartIndent.ReadColumn(mValue, mColumn));
  finally
    mValue.Free;
  end;
  Assert.IsFalse(TAtlasSmartIndent.ReadColumn(nil, mColumn));
end;

procedure TAtlasSmartIndentTests.DiscardsAnswerAfterTyping;
var
  mAsked: TAtlasSmartIndentAsked;
begin
  mAsked := TAtlasSmartIndentAsked.Create('C:\P\U.pas', 2, '  ', '  if A then');
  Assert.IsTrue(TAtlasSmartIndent.StillValid(mAsked, mAsked, 2, 2));
  // Groß-/Kleinschreibung des Dateinamens zählt nicht.
  Assert.IsTrue(TAtlasSmartIndent.StillValid(mAsked, TAtlasSmartIndentAsked.Create('c:\p\u.pas', 2, '  ',
    '  if A then'), 2, 0));
  Assert.IsFalse(TAtlasSmartIndent.StillValid(mAsked, TAtlasSmartIndentAsked.Create('C:\P\U.pas', 2, '  B',
    '  if A then'), 2, 3), 'schon weitergetippt');
  Assert.IsFalse(TAtlasSmartIndent.StillValid(mAsked, TAtlasSmartIndentAsked.Create('C:\P\U.pas', 2, '  ',
    '  if A then X'), 2, 2), 'Zeile darüber geändert');
  Assert.IsFalse(TAtlasSmartIndent.StillValid(mAsked, mAsked, 3, 2), 'Schreibmarke in anderer Zeile');
  Assert.IsFalse(TAtlasSmartIndent.StillValid(mAsked, TAtlasSmartIndentAsked.Create('C:\P\V.pas', 2, '  ',
    '  if A then'), 2, 2), 'andere Datei');
  mAsked := Default(TAtlasSmartIndentAsked);
end;

procedure TAtlasSmartIndentTests.SkipsQuickCommandsAndOtherFiles;
begin
  Assert.IsTrue(TAtlasSmartIndent.Applies('  if A then'));
  Assert.IsFalse(TAtlasSmartIndent.Applies('  /todo'), 'Schnellbefehl');
  Assert.IsTrue(TAtlasSmartIndent.IsSource('C:\P\U.PAS'));
  Assert.IsTrue(TAtlasSmartIndent.IsSource('C:\P\Projekt.dpr'));
  Assert.IsTrue(TAtlasSmartIndent.IsSource('C:\P\Defs.inc'));
  Assert.IsFalse(TAtlasSmartIndent.IsSource('C:\P\Form.dfm'));
  Assert.IsFalse(TAtlasSmartIndent.IsSource('C:\P\Readme.md'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSmartIndentTests);

end.
