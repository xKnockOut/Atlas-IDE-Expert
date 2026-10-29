unit Atlas.Core.Editor.SafeDelete.Tests;

// Tests für „Sicher löschen“ im Plugin (#716): Argumente für Alt+Entf und
// mit den Antworten, Antwort der Prüfung, welche Verwendungen blockieren,
// wann die Vorschau kommt, Einstellungen ask/always/never und die Liste für
// Rückfragen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasSafeDeleteTests = class
  public
    [Test]
    procedure ArgumentsCarryPosition;
    [Test]
    procedure ApplyArgumentsAddChoices;
    [Test]
    procedure ReadsPrepareAnswer;
    [Test]
    procedure ForeignAnswerGivesDefaults;
    [Test]
    procedure BlockingAndPreview;
    [Test]
    procedure AnswerModes;
    [Test]
    procedure ListingIsCapped;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Editor.SafeDelete;

const
  Prepared =
    '{"kind":"Methode","name":"Draw","title":"Methode Draw sicher loeschen","usages":[' +
    '{"file":"C:\\P\\Use.pas","line":7,"character":9,"text":"AShape.Draw;","kind":"code"}],' +
    '"overrides":[{"file":"C:\\P\\Circle.pas","line":7,"character":4,"text":"TCircle.Draw","kind":"override"}],' +
    '"cascade":["FCache","uses Helpers"],"warnings":["published"],"previewWhenUnused":true,' +
    '"cascadeMode":"always","overridesMode":"never"}';

function Info(const AJson: string): TAtlasSafeDeleteInfo;
var
  Value: TJSONValue;
begin
  Value := TJSONObject.ParseJSONValue(AJson);
  try
    Result := TAtlasSafeDeleteInfo.FromJson(Value);
  finally
    Value.Free;
  end;
end;

procedure TAtlasSafeDeleteTests.ArgumentsCarryPosition;
begin
  Assert.AreEqual('["file:///C:/a.pas",{"line":4,"character":7}]',
    TAtlasSafeDelete.Arguments('file:///C:/a.pas', 4, 7));
end;

procedure TAtlasSafeDeleteTests.ApplyArgumentsAddChoices;
begin
  Assert.AreEqual('["file:///C:/a.pas",{"line":4,"character":7},' +
    '{"overrides":true,"cascade":false,"force":true}]',
    TAtlasSafeDelete.ApplyArguments(TAtlasSafeDelete.Arguments('file:///C:/a.pas', 4, 7), True, False, True));
  Assert.AreEqual('kaputt', TAtlasSafeDelete.ApplyArguments('kaputt', True, True, True));
end;

procedure TAtlasSafeDeleteTests.ReadsPrepareAnswer;
var
  Read: TAtlasSafeDeleteInfo;
begin
  Read := Info(Prepared);
  Assert.AreEqual('Draw', Read.Name);
  Assert.AreEqual('Methode', Read.Kind);
  Assert.AreEqual(1, Integer(Length(Read.Usages)));
  Assert.AreEqual('C:\P\Use.pas', Read.Usages[0].FileName);
  Assert.AreEqual(7, Read.Usages[0].Line);
  Assert.AreEqual(9, Read.Usages[0].Character);
  Assert.AreEqual('code', Read.Usages[0].Kind);
  Assert.AreEqual(1, Integer(Length(Read.Overrides)));
  Assert.AreEqual(2, Integer(Length(Read.Cascade)));
  Assert.AreEqual('uses Helpers', Read.Cascade[1]);
  Assert.AreEqual(1, Integer(Length(Read.Warnings)));
  Assert.IsTrue(Read.PreviewWhenUnused);
  Assert.AreEqual('always', Read.CascadeMode);
  Assert.AreEqual('never', Read.OverridesMode);
  Assert.IsFalse(Read.IsUnit);
end;

procedure TAtlasSafeDeleteTests.ForeignAnswerGivesDefaults;
var
  Read: TAtlasSafeDeleteInfo;
begin
  Read := TAtlasSafeDeleteInfo.FromJson(nil);
  Assert.AreEqual('ask', Read.CascadeMode);
  Assert.AreEqual('ask', Read.OverridesMode);
  Assert.AreEqual(0, Integer(Length(Read.Usages)));
  Read := Info('[1, 2]');
  Assert.AreEqual('', Read.Name);
end;

procedure TAtlasSafeDeleteTests.BlockingAndPreview;
var
  Read: TAtlasSafeDeleteInfo;
begin
  Read := Info(Prepared);
  Assert.AreEqual(2, Integer(Length(Read.Blocking(False))), 'Ueberschreibungen bleiben: sie blockieren');
  Assert.AreEqual(1, Integer(Length(Read.Blocking(True))));
  Assert.IsTrue(Read.NeedsPreview(False), 'previewWhenUnused');
  Read := Info('{"kind":"Feld","name":"FA"}');
  Assert.AreEqual(0, Integer(Length(Read.Blocking(False))));
  Assert.IsFalse(Read.NeedsPreview(False), 'ohne Verwendungen sofort');
  Assert.IsTrue(Read.NeedsPreview(True), 'trotzdem loeschen zeigt die Vorschau');
  Assert.IsTrue(Info('{"kind":"Unit","name":"U"}').NeedsPreview(False), 'eine Unit immer mit Vorschau');
end;

procedure TAtlasSafeDeleteTests.AnswerModes;
begin
  Assert.AreEqual(Ord(TAtlasSafeDeleteAnswer.Always), Ord(TAtlasSafeDelete.AnswerOf('Always')));
  Assert.AreEqual(Ord(TAtlasSafeDeleteAnswer.Never), Ord(TAtlasSafeDelete.AnswerOf('never')));
  Assert.AreEqual(Ord(TAtlasSafeDeleteAnswer.Ask), Ord(TAtlasSafeDelete.AnswerOf('ask')));
  Assert.AreEqual(Ord(TAtlasSafeDeleteAnswer.Ask), Ord(TAtlasSafeDelete.AnswerOf('')));
end;

procedure TAtlasSafeDeleteTests.ListingIsCapped;
begin
  Assert.AreEqual('a' + sLineBreak + 'b', TAtlasSafeDelete.Listing(['a', 'b'], 3, '+%d'));
  Assert.AreEqual('a' + sLineBreak + 'b' + sLineBreak + '+2', TAtlasSafeDelete.Listing(['a', 'b', 'c', 'd'], 2,
    '+%d'));
  Assert.AreEqual('', TAtlasSafeDelete.Listing(nil, 2, '+%d'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasSafeDeleteTests);

end.
