unit Atlas.Common.Editing.TestFromDebug.Tests;

// Tests für den Test aus dem Debug-Halt (#1873): Literale aus dem Text des
// Debuggers, vorgeschlagener Name, Felder der Klasse und der fertige Entwurf
// (WillRaise, TODO statt geratener Werte, Toleranz bei Gleitkomma).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TTestFromDebugTests = class
  public
    [Test]
    procedure NumbersBecomeLiterals;
    [Test]
    procedure StringsStayAsTheDebuggerShowsThem;
    [Test]
    procedure BooleansEnumsAndSets;
    [Test]
    procedure ObjectsPointersAndRecordsAreNotGuessed;
    [Test]
    procedure ArraysUpToTheLimit;
    [Test]
    procedure NameFromMethodAndMainArgument;
    [Test]
    procedure FieldsOfTheClass;
    [Test]
    procedure RaisesBuildsWillRaiseWithValues;
    [Test]
    procedure WorksWithExpectedUsesTolerance;
    [Test]
    procedure ObjectArgumentGetsTodoAndStillDeclares;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Editing.TestDrafts,
  Atlas.Common.Editing.TestFromDebug;

const
  GewichtText =
    'unit Gewichte;'#13#10 +                                                         // 0
    'interface'#13#10 +                                                              // 1
    'uses Classes;'#13#10 +                                                          // 2
    'type'#13#10 +                                                                   // 3
    '  TGewicht = class'#13#10 +                                                     // 4
    '  private'#13#10 +                                                              // 5
    '    FEinheit: string;'#13#10 +                                                  // 6
    '  public'#13#10 +                                                               // 7
    '    Genau: Boolean;'#13#10 +                                                    // 8
    '    function Parse(const AText: string): Double;'#13#10 +                       // 9
    '    procedure Lade(AListe: TStringList; AZahl: Integer);'#13#10 +               // 10
    '  end;'#13#10 +                                                                 // 11
    'implementation'#13#10 +                                                         // 12
    'function TGewicht.Parse(const AText: string): Double;'#13#10 +                  // 13
    'begin'#13#10 +                                                                  // 14
    '  Result := StrToFloat(AText);'#13#10 +                                         // 15
    'end;'#13#10 +                                                                   // 16
    'procedure TGewicht.Lade(AListe: TStringList; AZahl: Integer);'#13#10 +          // 17
    'begin'#13#10 +                                                                  // 18
    'end;'#13#10 +                                                                   // 19
    'end.'#13#10;

function GewichtIndex: TUnitIndex;
begin
  Result := TIndexExtractor.ExtractText(GewichtText, 'Gewichte.pas', nil);
end;

function DraftAt(ALine: Integer; out ADraft: TTestDraft): Boolean;
begin
  Result := TTestDrafts.DraftAt(GewichtText, TPascalLexer.Tokenize(GewichtText), GewichtIndex, ALine, ADraft);
  ADraft.Fixture := 'TGewichtTests';
  ADraft.UnitName := 'Gewichte';
  ADraft.Subject := 'FSubject';
end;

/// <summary>Der Rumpf AMethod in einer Testunit parst ohne Fehler.</summary>
function Parses(const AMethod: string): Boolean;
var
  Tree: TSyntaxTree;
begin
  Tree := TSyntaxTreeCache.Parse('unit T;'#13#10'interface'#13#10'implementation'#13#10 + AMethod + #13#10'end.');
  try
    Result := Length(Tree.Diagnostics) = 0;
  finally
    Tree.Free;
  end;
end;

function Literal(const AText, ATypeName: string): string;
begin
  if not TTestFromDebug.Literal(AText, ATypeName, TTestFromDebug.cDefaultMaxArray, Result) then
  begin
    Result := '<kein Literal>';
  end;
end;

procedure TTestFromDebugTests.NumbersBecomeLiterals;
begin
  Assert.AreEqual('12', Literal('12', 'Integer'));
  Assert.AreEqual('-3', Literal(' -3 ', 'Integer'));
  Assert.AreEqual('12.5', Literal('12,5', 'Double'));
  Assert.AreEqual('12.5', Literal('12.5', 'Double'));
  Assert.AreEqual('1.5E+3', Literal('1,5E+3', 'Extended'));
  Assert.AreEqual('<kein Literal>', Literal('1,2,3', 'Double'));
  Assert.AreEqual('<kein Literal>', Literal('', 'Integer'));
end;

procedure TTestFromDebugTests.StringsStayAsTheDebuggerShowsThem;
begin
  Assert.AreEqual('''12,5 kg''', Literal('''12,5 kg''', 'string'));
  Assert.AreEqual('''O''''Neil''', Literal('''O''''Neil''', 'string'));
  Assert.AreEqual('''a''#13#10''b''', Literal('''a''#13#10''b''', 'string'));
  Assert.AreEqual('''''', Literal('''''', 'string'));
  Assert.AreEqual('<kein Literal>', Literal('''offen', 'string'));
end;

procedure TTestFromDebugTests.BooleansEnumsAndSets;
begin
  Assert.AreEqual('True', Literal('True', 'Boolean'));
  Assert.AreEqual('clRed', Literal('clRed', 'TColor'));
  Assert.AreEqual('TState.Error', Literal('TState.Error', 'TState'));
  Assert.AreEqual('[fsBold, fsItalic]', Literal('[fsBold,fsItalic]', 'TFontStyles'));
  Assert.AreEqual('[]', Literal('[]', 'TFontStyles'));
  Assert.AreEqual('[1, 3]', Literal('[1, 3]', 'TZahlen'));
end;

procedure TTestFromDebugTests.ObjectsPointersAndRecordsAreNotGuessed;
begin
  Assert.AreEqual('<kein Literal>', Literal('nil', 'TStringList'));
  Assert.AreEqual('<kein Literal>', Literal('$02A3F2C0', 'Pointer'));
  Assert.AreEqual('<kein Literal>', Literal('($2A3F2C0, ''x'', 3)', 'TKunde'));
  Assert.AreEqual('<kein Literal>', Literal('(X: 1; Y: 2)', 'TPoint'));
  Assert.AreEqual('<kein Literal>', Literal('(1, 2)', 'TPoint'));
end;

procedure TTestFromDebugTests.ArraysUpToTheLimit;
var
  Text: string;
begin
  Assert.AreEqual('[1, 2, 3]', Literal('(1, 2, 3)', 'TArray<Integer>'));
  Assert.AreEqual('[''a'', ''b, c'']', Literal('(''a'', ''b, c'')', 'TArray<string>'));
  Assert.AreEqual('[]', Literal('()', 'TIntegerDynArray'));
  Assert.IsFalse(TTestFromDebug.Literal('(1, 2, 3)', 'TArray<Integer>', 2, Text), 'ueber der Grenze');
  Assert.IsFalse(TTestFromDebug.Literal('(1, 2)', 'TArray<Integer>', 0, Text), 'Grenze 0');
end;

procedure TTestFromDebugTests.NameFromMethodAndMainArgument;
var
  Name: string;
begin
  Name := TTestFromDebug.SuggestName('Parse', [TDebugStopValue.Create('AZahl', '3'),
    TDebugStopValue.Create('AText', '''12,5 kg''')], TTestDraftKind.Works, '');
  Assert.IsTrue(StartsStr('Parse', Name), Name);
  Assert.IsTrue(EndsStr('12_5Kg', Name), Name);
  Name := TTestFromDebug.SuggestName('Parse', [TDebugStopValue.Create('AText', '''12,5 kg''')],
    TTestDraftKind.Raises, 'EConvertError');
  Assert.IsTrue(EndsStr('ConvertError', Name), Name);
  Assert.IsFalse(ContainsStr(Name, 'EConvert'), Name);
  Assert.AreEqual('Leer', TTestFromDebug.SuggestName('Leer', nil, TTestDraftKind.Works, ''));
  Name := TTestFromDebug.SuggestName('Parse', [TDebugStopValue.Create('AText',
    '''eins zwei drei vier fuenf''')], TTestDraftKind.Works, '');
  Assert.IsTrue(EndsStr('EinsZweiDrei', Name), 'hoechstens drei Woerter: ' + Name);
end;

procedure TTestFromDebugTests.FieldsOfTheClass;
var
  Fields: TArray<TTestDraftValue>;
begin
  Fields := TTestFromDebug.FieldsOf(GewichtIndex, 'TGewicht');
  Assert.AreEqual(2, Integer(Length(Fields)));
  Assert.AreEqual('FEinheit', Fields[0].Name);
  Assert.AreEqual('string', Fields[0].TypeName);
  Assert.IsFalse(Fields[0].Accessible, 'privat');
  Assert.AreEqual('Genau', Fields[1].Name);
  Assert.IsTrue(Fields[1].Accessible, 'oeffentlich');
end;

procedure TTestFromDebugTests.RaisesBuildsWillRaiseWithValues;
var
  Draft: TTestDraft;
  Request: TDebugStopRequest;
  Text: string;
begin
  Assert.IsTrue(DraftAt(15, Draft));
  Request := TDebugStopRequest.Empty;
  Request.Parameters := [TDebugStopValue.Create('AText', '''12,5 kg''')];
  Request.Fields := [TDebugStopValue.Create('FEinheit', '''kg'''), TDebugStopValue.Create('Genau', 'True')];
  Request.Kind := TTestDraftKind.Raises;
  Request.ExceptionClass := 'EConvertError';
  Request.StoppedAt := '2026-11-13 14:05';
  TTestFromDebug.Apply(Request, TTestFromDebug.FieldsOf(GewichtIndex, 'TGewicht'), Draft);
  Assert.IsFalse(Draft.Draft, 'WillRaise ist vollständig');
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(ContainsStr(Text, '''12,5 kg'''), Text);
  Assert.IsTrue(ContainsStr(Text, 'Assert.WillRaise('), Text);
  Assert.IsTrue(ContainsStr(Text, 'EConvertError);'), Text);
  Assert.IsTrue(ContainsStr(Text, '2026-11-13 14:05, EConvertError'), 'Kommentar: ' + Text);
  Assert.IsTrue(ContainsStr(Text, 'FSubject.Genau := True;'), 'oeffentliches Feld: ' + Text);
  Assert.IsTrue(ContainsStr(Text, '// FEinheit = ''kg'''), 'privates Feld als Kommentar: ' + Text);
  Assert.IsFalse(ContainsStr(Text, 'Assert.Fail'), Text);
  Assert.IsTrue(ContainsStr(Text, 'ConvertError;'), 'Name: ' + Text);
  Assert.IsTrue(Parses(Text), Text);
end;

procedure TTestFromDebugTests.WorksWithExpectedUsesTolerance;
var
  Draft: TTestDraft;
  Request: TDebugStopRequest;
  Text: string;
begin
  Assert.IsTrue(DraftAt(9, Draft));
  Request := TDebugStopRequest.Empty;
  Request.Parameters := [TDebugStopValue.Create('AText', '''12.5''')];
  Request.Expected := '12,5';
  Request.TestName := 'ParseMitPunkt';
  TTestFromDebug.Apply(Request, nil, Draft);
  Assert.IsFalse(Draft.Draft);
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(ContainsStr(Text, 'procedure TGewichtTests.ParseMitPunkt;'), Text);
  Assert.IsTrue(ContainsStr(Text, 'Assert.AreEqual(12.5, Actual, ' + TTestDrafts.cFloatTolerance + ');'), Text);
  Assert.IsFalse(ContainsStr(Text, 'Assert.Fail'), Text);
  Assert.IsTrue(Parses(Text), Text);
  // Ohne erwarteten Wert bleibt der Entwurf rot.
  Assert.IsTrue(DraftAt(9, Draft));
  Request.Expected := '';
  TTestFromDebug.Apply(Request, nil, Draft);
  Assert.IsTrue(Draft.Draft);
end;

procedure TTestFromDebugTests.ObjectArgumentGetsTodoAndStillDeclares;
var
  Draft: TTestDraft;
  Request: TDebugStopRequest;
  Text: string;
begin
  Assert.IsTrue(DraftAt(18, Draft));
  Request := TDebugStopRequest.Empty;
  Request.Parameters := [TDebugStopValue.Create('AListe', '$02A3F2C0'), TDebugStopValue.Create('AZahl', '7')];
  TTestFromDebug.Apply(Request, nil, Draft);
  Assert.IsTrue(Draft.Parameters[0].Todo);
  Assert.AreEqual('7', Draft.Parameters[1].Value);
  Text := TTestDrafts.MethodText(Draft, #13#10);
  Assert.IsTrue(ContainsStr(Text, 'Liste := Default(TStringList); // TODO'), Text);
  Assert.IsTrue(ContainsStr(Text, 'procedure TGewichtTests.LadeMit7;'), 'Name ohne Adresse: ' + Text);
  Assert.IsTrue(ContainsStr(Text, ':= 7;'), Text);
  Assert.IsTrue(Parses(Text), Text);
end;

initialization
  TDUnitX.RegisterTestFixture(TTestFromDebugTests);

end.
