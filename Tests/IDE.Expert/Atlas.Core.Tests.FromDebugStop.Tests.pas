unit Atlas.Core.Tests.FromDebugStop.Tests;

// Tests von „Test daraus anlegen …“ (#1873) ohne IDE: Argumente der
// Kopfzeile, Antworten von describe und create, Vorauswahl und die Argumente
// für den Server.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  [Category('Atlas.IDE.Tests')]
  TAtlasTestFromDebugStopTests = class
  public
    [Test]
    procedure HeaderArgumentsRespectStringsAndBrackets;
    [Test]
    procedure HeaderWithoutArguments;
    [Test]
    procedure DescriptionReadsParametersAndFields;
    [Test]
    procedure BrokenAnswerGivesFallbackReason;
    [Test]
    procedure ArgumentsGoToParametersInOrder;
    [Test]
    procedure PreselectSkipsInaccessibleAndTodoFields;
    [Test]
    procedure KeepValuesAcrossAnswers;
    [Test]
    procedure ArgumentsContainOnlyChosenValues;
    [Test]
    procedure CreatedWithEditHasNoReason;
    [Test]
    procedure TestLineFindsBodyNotDeclaration;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Core.Tests.FromDebugStop;

const
  cDescribe = '{"target":"TGewicht.Parse","className":"TGewicht","method":"Parse","classMethod":false,' +
    '"callable":true,"resultType":"Double","parameters":[{"name":"AText","type":"string","modifier":"const",' +
    '"accessible":true},{"name":"ARunden","type":"Boolean","modifier":"","accessible":true}],' +
    '"fields":[{"name":"FEinheit","type":"string","modifier":"","accessible":true},' +
    '{"name":"FListe","type":"TStringList","modifier":"","accessible":true},' +
    '{"name":"FGeheim","type":"Integer","modifier":"","accessible":false}],"testUnit":"Gewicht.Tests",' +
    '"testUnitExists":true,"testName":"Parse"}';

function Described: TAtlasStopDescription;
begin
  Result := TAtlasTestFromDebugStop.ReadDescription(cDescribe, 'kaputt');
end;

procedure TAtlasTestFromDebugStopTests.HeaderArgumentsRespectStringsAndBrackets;
var
  mArguments: TArray<string>;
begin
  mArguments := TAtlasTestFromDebugStop.HeaderArguments('Gewicht.TGewicht.Parse(''12,5 kg'', [a, b], f(1, 2), ' +
    '''it''''s)'')');
  Assert.AreEqual(4, Integer(Length(mArguments)));
  Assert.AreEqual('''12,5 kg''', mArguments[0]);
  Assert.AreEqual('[a, b]', mArguments[1]);
  Assert.AreEqual('f(1, 2)', mArguments[2]);
  Assert.AreEqual('''it''''s)''', mArguments[3]);
end;

procedure TAtlasTestFromDebugStopTests.HeaderWithoutArguments;
begin
  Assert.AreEqual(0, Integer(Length(TAtlasTestFromDebugStop.HeaderArguments('Unit1.TForm1.Laden()'))));
  Assert.AreEqual(0, Integer(Length(TAtlasTestFromDebugStop.HeaderArguments('Unit1.Laden'))));
  Assert.AreEqual(1, Integer(Length(TAtlasTestFromDebugStop.HeaderArguments('Unit1.Laden(42)'))));
end;

procedure TAtlasTestFromDebugStopTests.DescriptionReadsParametersAndFields;
var
  mDescription: TAtlasStopDescription;
begin
  mDescription := Described;
  Assert.AreEqual('', mDescription.Reason);
  Assert.AreEqual('TGewicht.Parse', mDescription.Target);
  Assert.AreEqual('Double', mDescription.ResultType);
  Assert.AreEqual('Gewicht.Tests', mDescription.TestUnit);
  Assert.IsTrue(mDescription.TestUnitExists);
  Assert.AreEqual(5, Integer(Length(mDescription.Rows)));
  Assert.AreEqual(2, mDescription.ParameterCount);
  Assert.IsFalse(mDescription.Rows[0].Field);
  Assert.AreEqual('const', mDescription.Rows[0].Modifier);
  Assert.IsTrue(mDescription.Rows[2].Field);
  Assert.IsFalse(mDescription.Rows[4].Accessible);
  Assert.AreEqual('Self.FEinheit', TAtlasTestFromDebugStop.Expression(mDescription.Rows[2]));
  Assert.AreEqual('AText', TAtlasTestFromDebugStop.Expression(mDescription.Rows[0]));
end;

procedure TAtlasTestFromDebugStopTests.BrokenAnswerGivesFallbackReason;
begin
  Assert.AreEqual('kaputt', TAtlasTestFromDebugStop.ReadDescription('', 'kaputt').Reason);
  Assert.AreEqual('kaputt', TAtlasTestFromDebugStop.ReadDescription('[1]', 'kaputt').Reason);
  Assert.AreEqual('keine Methode', TAtlasTestFromDebugStop.ReadDescription('{"reason":"keine Methode"}',
    'kaputt').Reason);
  Assert.AreEqual('kaputt', TAtlasTestFromDebugStop.ReadCreated('', 'kaputt').Reason);
end;

procedure TAtlasTestFromDebugStopTests.ArgumentsGoToParametersInOrder;
var
  mDescription: TAtlasStopDescription;
begin
  mDescription := Described;
  TAtlasTestFromDebugStop.TakeArguments(mDescription, TArray<string>.Create('''12,5 kg''', 'True', 'zuviel'));
  Assert.AreEqual('''12,5 kg''', mDescription.Rows[0].Text);
  Assert.AreEqual('True', mDescription.Rows[1].Text);
  Assert.AreEqual('', mDescription.Rows[2].Text, 'Felder kommen nicht aus der Kopfzeile');
  mDescription := Described;
  TAtlasTestFromDebugStop.TakeArguments(mDescription, TArray<string>.Create('''x'''));
  Assert.AreEqual('', mDescription.Rows[1].Text, 'fehlendes Argument bleibt leer');
end;

procedure TAtlasTestFromDebugStopTests.PreselectSkipsInaccessibleAndTodoFields;
var
  mDescription: TAtlasStopDescription;
  mIndex: Integer;
begin
  mDescription := Described;
  for mIndex := 0 to High(mDescription.Rows) do
  begin
    mDescription.Rows[mIndex].Text := 'x';
  end;
  mDescription.Rows[1].Text := '';
  mDescription.Rows[3].Todo := True;
  TAtlasTestFromDebugStop.Preselect(mDescription);
  Assert.IsTrue(mDescription.Rows[0].Chosen);
  Assert.IsFalse(mDescription.Rows[1].Chosen, 'ohne Wert');
  Assert.IsTrue(mDescription.Rows[2].Chosen);
  Assert.IsFalse(mDescription.Rows[3].Chosen, 'Objekt wird TODO');
  Assert.IsFalse(mDescription.Rows[4].Chosen, 'privates Feld');
end;

procedure TAtlasTestFromDebugStopTests.KeepValuesAcrossAnswers;
var
  mOld, mNew: TAtlasStopDescription;
begin
  mOld := Described;
  mOld.Rows[0].Text := '''12,5 kg''';
  mOld.Rows[0].Chosen := True;
  mOld.Rows[2].Text := '''kg''';
  mNew := TAtlasTestFromDebugStop.ReadDescription(StringReplace(cDescribe, '"accessible":true}',
    '"accessible":true,"literal":"''12.5 kg''","todo":false}', []), '');
  TAtlasTestFromDebugStop.KeepValues(mNew, mOld);
  Assert.AreEqual('''12,5 kg''', mNew.Rows[0].Text);
  Assert.IsTrue(mNew.Rows[0].Chosen);
  Assert.AreEqual('''12.5 kg''', mNew.Rows[0].Literal);
  Assert.AreEqual('''kg''', mNew.Rows[2].Text);
  Assert.IsFalse(mNew.Rows[2].Chosen);
end;

procedure TAtlasTestFromDebugStopTests.ArgumentsContainOnlyChosenValues;
var
  mDescription: TAtlasStopDescription;
  mChoice: TAtlasStopChoice;
  mValue: TJSONValue;
  mRequest: TJSONObject;
begin
  mDescription := Described;
  mDescription.Rows[0].Text := '''12,5 kg''';
  mDescription.Rows[0].Chosen := True;
  mDescription.Rows[1].Text := 'True';
  mDescription.Rows[2].Text := '''kg''';
  mDescription.Rows[2].Chosen := True;
  mChoice := Default(TAtlasStopChoice);
  mChoice.Raises := True;
  mChoice.ExceptionClass := 'EConvertError';
  mChoice.TestName := 'ParseWirft';
  mChoice.MaxArray := 7;
  mValue := TJSONObject.ParseJSONValue(TAtlasTestFromDebugStop.Arguments('file:///c%3A/Gewicht.pas', 41,
    TAtlasTestFromDebugStop.cModeCreate, mDescription, mChoice));
  try
    Assert.IsTrue(mValue is TJSONArray);
    Assert.AreEqual(3, TJSONArray(mValue).Count);
    Assert.AreEqual('41', TJSONArray(mValue).Items[1].Value);
    mRequest := TJSONArray(mValue).Items[2] as TJSONObject;
    Assert.AreEqual('create', mRequest.GetValue('mode').Value);
    Assert.AreEqual('raises', mRequest.GetValue('kind').Value);
    Assert.AreEqual(1, (mRequest.GetValue('parameters') as TJSONArray).Count, 'nicht gewählt fehlt');
    Assert.AreEqual(1, (mRequest.GetValue('fields') as TJSONArray).Count);
    Assert.AreEqual('EConvertError', mRequest.GetValue('exceptionClass').Value);
    Assert.AreEqual('ParseWirft', mRequest.GetValue('testName').Value);
    Assert.AreEqual('7', mRequest.GetValue('maxArray').Value);
  finally
    mValue.Free;
  end;
end;

procedure TAtlasTestFromDebugStopTests.CreatedWithEditHasNoReason;
var
  mCreated: TAtlasStopCreated;
begin
  mCreated := TAtlasTestFromDebugStop.ReadCreated('{"edit":{"changes":{}},"uri":"file:///c%3A/T.pas",' +
    '"testName":"ParseMit12_5Kg","fixture":"TGewichtTests"}', 'kaputt');
  Assert.AreEqual('', mCreated.Reason);
  Assert.AreEqual('ParseMit12_5Kg', mCreated.TestName);
  Assert.AreEqual('TGewichtTests', mCreated.Fixture);
  mCreated := TAtlasTestFromDebugStop.ReadCreated('{"reason":"nicht eingetragen"}', 'kaputt');
  Assert.AreEqual('nicht eingetragen', mCreated.Reason);
end;

procedure TAtlasTestFromDebugStopTests.TestLineFindsBodyNotDeclaration;
const
  cUnit = 'unit Gewicht.Tests;'#13#10'type'#13#10'  TGewichtTests = class'#13#10'    procedure ParseMit12_5Kg;' +
    #13#10'  end;'#13#10'implementation'#13#10'procedure TGewichtTests.ParseMit12_5KgLang;'#13#10'begin end;' +
    #13#10'procedure TGewichtTests.ParseMit12_5Kg;'#13#10'begin end;';
begin
  Assert.AreEqual(8, TAtlasTestFromDebugStop.TestLine(cUnit, 'TGewichtTests', 'ParseMit12_5Kg'));
  Assert.AreEqual(6, TAtlasTestFromDebugStop.TestLine(cUnit, 'tgewichttests', 'ParseMit12_5KgLang'));
  Assert.AreEqual(-1, TAtlasTestFromDebugStop.TestLine(cUnit, 'TGewichtTests', 'Fehlt'));
end;

end.
