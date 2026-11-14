unit Atlas.Core.Signature.Tests;

// Tests für den Parameter-Hint ohne IDE (#436, #437).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasCallScannerTests = class
  public
    [Test]
    procedure CountsParametersOfFormat;
    [Test]
    procedure IgnoresCommasInStringsAndComments;
    [Test]
    procedure IgnoresInnerCallsAndGrouping;
    [Test]
    procedure KeywordParenthesesAreNoCall;
    [Test]
    procedure ClosedCallIsLeft;
    [Test]
    procedure NamesCallAndOuterCalls;
    [Test]
    procedure DetectsRemovedClosingParen;
    [Test]
    procedure OtherEditsAreNoRemovedParen;
  end;

  [TestFixture]
  TAtlasSignatureControllerTests = class
  public
    [Test]
    procedure SwitchesToFittingOverload;
    [Test]
    procedure ManualOverloadSwitchWraps;
    [Test]
    procedure ReadsLspSignatureHelp;
    [Test]
    procedure TypeMismatchDimsAndSkipsOverload;
    [Test]
    procedure ReadsArgumentFitFromServer;
    [Test]
    procedure TooManyArgumentsCountsOnly;
    [Test]
    procedure ReadsFormatPlaceholders;
    [Test]
    procedure UpdateFormatKeepsOverload;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Core.Signature.Contract,
  Atlas.Core.Signature.CallScanner,
  Atlas.Core.Signature.Controller,
  Atlas.Core.Signature.Providers.Server;

type
  TFakeSignatureView = class(TInterfacedObject, IAtlasSignatureView)
  public
    Shown: Boolean;
    Signature: Integer;
    Parameter: Integer;
    procedure ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
    procedure HideSignature;
  end;

procedure TFakeSignatureView.ShowSignature(const AHelp: TAtlasSignatureHelp; ASignature, AParameter: Integer);
begin
  Shown := True;
  Signature := ASignature;
  Parameter := AParameter;
end;

procedure TFakeSignatureView.HideSignature;
begin
  Shown := False;
end;

/// <summary>Caret am Ende von AText.</summary>
function ScanEnd(const AText: string): TAtlasCallSite;
begin
  Result := TAtlasCallScanner.Scan(AText, Length(AText));
end;

function Signature(const ALabel: string; const AParameters: array of string): TAtlasSignature;
var
  mName: string;
  mParameter: TAtlasSignatureParameter;
begin
  Result := Default(TAtlasSignature);
  Result.Label_ := ALabel;
  for mName in AParameters do
  begin
    mParameter := Default(TAtlasSignatureParameter);
    mParameter.Start := Pos(mName, ALabel) - 1;
    mParameter.Stop := mParameter.Start + Length(mName);
    Result.Parameters := Result.Parameters + [mParameter];
  end;
end;

function FormatHelp: TAtlasSignatureHelp;
begin
  Result := Default(TAtlasSignatureHelp);
  Result.ActiveSignature := -1;
  Result.ActiveParameter := -1;
  Result.Signatures := [
    Signature('function Format(const Format: string; const Args: array of const): string',
      ['const Format: string', 'const Args: array of const']),
    Signature('function Format(const Format: string; const Args: array of const; ' +
      'const AFormatSettings: TFormatSettings): string',
      ['const Format: string', 'const Args: array of const', 'const AFormatSettings: TFormatSettings'])];
end;

function StringListHelp: TAtlasSignatureHelp;
begin
  // Wie TStringList.Create('"', ';', (#498): Der Server hat die Variante mit TDuplicates als unverträglich markiert.
  Result := Default(TAtlasSignatureHelp);
  Result.ActiveSignature := -1;
  Result.ActiveParameter := 2;
  Result.Signatures := [
    Signature('constructor Create(Duplicates: TDuplicates; Sorted: Boolean; CaseSensitive: Boolean)',
      ['Duplicates: TDuplicates', 'Sorted: Boolean', 'CaseSensitive: Boolean']),
    Signature('constructor Create(QuoteChar, Delimiter: Char; Options: TStringsOptions)',
      ['QuoteChar', 'Delimiter', 'Options: TStringsOptions'])];
  Result.Signatures[0].TypeMismatch := True;
  Result.Signatures[0].MismatchArgument := 0;
end;

{ TAtlasCallScannerTests }

procedure TAtlasCallScannerTests.CountsParametersOfFormat;
var
  mSite: TAtlasCallSite;
begin
  mSite := ScanEnd('  S := Format(''%d'', [');
  Assert.IsTrue(mSite.Found);
  Assert.AreEqual(1, mSite.ActiveParameter, 'Format(''%d'', [ hebt Args hervor');
  Assert.AreEqual(Pos('(', '  S := Format(''%d'', [') - 1, mSite.OpenParen);
  Assert.AreEqual(0, ScanEnd('Foo(').ActiveParameter);
  Assert.AreEqual(2, ScanEnd('Foo(1, X,').ActiveParameter);
end;

procedure TAtlasCallScannerTests.IgnoresCommasInStringsAndComments;
begin
  Assert.AreEqual(1, ScanEnd('Foo(''a,b'', ').ActiveParameter, 'Kommas im String zählen nicht');
  Assert.AreEqual(1, ScanEnd('Foo(''it''''s, ok'', ').ActiveParameter, 'Doppeltes Anführungszeichen');
  Assert.AreEqual(1, ScanEnd('Foo(1 { , } , (* , *) ').ActiveParameter, 'Kommentare');
  Assert.AreEqual(1, ScanEnd('Foo(1, // a, b'#13#10'  ').ActiveParameter, 'Zeilenkommentar');
end;

procedure TAtlasCallScannerTests.IgnoresInnerCallsAndGrouping;
var
  mSite: TAtlasCallSite;
begin
  Assert.AreEqual(1, ScanEnd('Foo(Bar(1, 2), ').ActiveParameter, 'Innerer Aufruf ist geschlossen');
  mSite := ScanEnd('Foo(1, Bar(2, ');
  Assert.AreEqual(1, mSite.ActiveParameter, 'Im inneren Aufruf zählt dessen Komma');
  Assert.AreEqual(Integer(Length('Foo(1, Bar')), mSite.OpenParen);
  Assert.AreEqual(1, ScanEnd('Foo(1, (2 + 3').ActiveParameter, 'Klammer zur Gruppierung gehört zu Foo');
  Assert.AreEqual(1, ScanEnd('Foo(1, [2, 3').ActiveParameter, 'Mengen- bzw. Array-Klammern');
end;

procedure TAtlasCallScannerTests.NamesCallAndOuterCalls;
var
  mSite: TAtlasCallSite;
begin
  // Beispiel aus #438.
  mSite := ScanEnd('  ShowMessage(Format(''%d Zeilen'', [');
  Assert.AreEqual('Format', mSite.Name);
  Assert.AreEqual(1, Integer(Length(mSite.Outer)));
  Assert.AreEqual('ShowMessage', mSite.Outer[0]);
  // Nach der schließenden Klammer von Format wieder ShowMessage, ohne äußere Aufrufe.
  mSite := ScanEnd('  ShowMessage(Format(''%d'', [N])');
  Assert.AreEqual('ShowMessage', mSite.Name);
  Assert.AreEqual(0, Integer(Length(mSite.Outer)));
  // Qualifizierter Aufruf: letzter Bezeichner; Gruppierungsklammern zählen nicht als Ebene.
  mSite := ScanEnd('A(B((1 + 2), TStringList.Create(');
  Assert.AreEqual('Create', mSite.Name);
  Assert.AreEqual('A,B', String.Join(',', mSite.Outer));
  Assert.AreEqual('', ScanEnd('Liste[0](').Name, 'Nach ] kein Name');
end;

procedure TAtlasCallScannerTests.KeywordParenthesesAreNoCall;
begin
  Assert.IsFalse(ScanEnd('if (A').Found);
  Assert.IsFalse(ScanEnd('while not (A').Found);
  Assert.IsTrue(ScanEnd('X := Liste[0].Add(').Found, 'Nach ] und Punkt ist es ein Aufruf');
end;

procedure TAtlasCallScannerTests.ClosedCallIsLeft;
begin
  Assert.IsFalse(ScanEnd('Foo(1, 2)').Found, 'Nach ) ist der Aufruf verlassen');
  Assert.IsFalse(ScanEnd('Foo(1);'#13#10'  ').Found);
end;

{ TAtlasSignatureControllerTests }

procedure TAtlasSignatureControllerTests.SwitchesToFittingOverload;
var
  mView: TFakeSignatureView;
  mViewRef: IAtlasSignatureView;
  mController: TAtlasSignatureController;
begin
  mView := TFakeSignatureView.Create;
  mViewRef := mView;
  mController := TAtlasSignatureController.Create(mViewRef);
  try
    mController.Show(FormatHelp, 0);
    Assert.AreEqual(0, mView.Signature, 'Kürzeste passende Variante zuerst');
    mController.UpdateParameter(1);
    Assert.AreEqual(0, mView.Signature);
    Assert.AreEqual(1, mView.Parameter);
    // #437: Beim dritten Argument wechselt der Hint auf die Variante mit TFormatSettings.
    mController.UpdateParameter(2);
    Assert.AreEqual(1, mView.Signature);
    Assert.AreEqual(2, mView.Parameter);
    // Zurück (Rücktaste über das Komma): die gezeigte Variante passt weiter und bleibt.
    mController.UpdateParameter(1);
    Assert.AreEqual(1, mView.Signature);
    mController.Close;
    Assert.IsFalse(mView.Shown);
  finally
    mController.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.ManualOverloadSwitchWraps;
var
  mView: TFakeSignatureView;
  mViewRef: IAtlasSignatureView;
  mController: TAtlasSignatureController;
  mHelp: TAtlasSignatureHelp;
begin
  mView := TFakeSignatureView.Create;
  mViewRef := mView;
  mController := TAtlasSignatureController.Create(mViewRef);
  try
    mHelp := FormatHelp;
    mHelp.ActiveSignature := 1;
    mController.Show(mHelp, 0);
    Assert.AreEqual(1, mView.Signature, 'Vom Server gewählte Variante, wenn sie passt');
    mController.NextOverload;
    Assert.AreEqual(0, mView.Signature, 'Alt+↓ läuft im Kreis');
    mController.PreviousOverload;
    Assert.AreEqual(1, mView.Signature);
    // Klick auf eine Überladung im Hint.
    mController.SelectOverload(0);
    Assert.AreEqual(0, mView.Signature);
    // Beim dritten Argument passt nur noch die Variante mit TFormatSettings.
    mController.UpdateParameter(2);
    Assert.IsFalse(mController.OverloadFits(0));
    Assert.IsTrue(mController.OverloadFits(1));
    // Leere Hilfe schließt.
    mController.Show(Default(TAtlasSignatureHelp), 0);
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.TypeMismatchDimsAndSkipsOverload;
var
  mView: TFakeSignatureView;
  mViewRef: IAtlasSignatureView;
  mController: TAtlasSignatureController;
  mHelp: TAtlasSignatureHelp;
begin
  mView := TFakeSignatureView.Create;
  mViewRef := mView;
  mController := TAtlasSignatureController.Create(mViewRef);
  try
    // Gleich viele Parameter, aber nur die Variante mit Char passt nach den Typen.
    mController.Show(StringListHelp, 2);
    Assert.AreEqual(1, mView.Signature, 'Verträgliche Variante vorgewählt');
    Assert.IsFalse(mController.OverloadFits(0), 'TDuplicates gedämpft');
    Assert.IsTrue(mController.OverloadFits(1));
    // Auch eine vom Server gewählte, aber unverträgliche Variante wird nicht genommen.
    mHelp := StringListHelp;
    mHelp.ActiveSignature := 0;
    mController.Show(mHelp, 2);
    Assert.AreEqual(1, mView.Signature);
    // Von Hand bleibt sie erreichbar.
    mController.SelectOverload(0);
    Assert.AreEqual(0, mView.Signature);
    Assert.IsFalse(mController.OverloadFits(0));
  finally
    mController.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.ReadsArgumentFitFromServer;
var
  mResponse: TJSONValue;
  mHelp: TAtlasSignatureHelp;
begin
  mResponse := TJSONObject.ParseJSONValue(
    '{"signatures":[{"label":"constructor Create(OwnsObjects: Boolean)","parameters":[{"label":[19,39]}],' +
    '"data":{"fits":false,"mismatch":0}},{"label":"constructor Create(QuoteChar, Delimiter: Char)",' +
    '"parameters":[{"label":[19,28]},{"label":[30,39]}],"data":{"fits":true,"mismatch":-1}},' +
    '{"label":"constructor Create","parameters":[]}],"activeSignature":1,"activeParameter":0}');
  try
    mHelp := TAtlasServerSignatureProvider.HelpFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(3, Integer(Length(mHelp.Signatures)));
  Assert.IsTrue(mHelp.Signatures[0].TypeMismatch);
  Assert.AreEqual(0, mHelp.Signatures[0].MismatchArgument);
  Assert.IsFalse(mHelp.Signatures[1].TypeMismatch);
  Assert.IsFalse(mHelp.Signatures[2].TypeMismatch, 'Ohne Angabe passend');
end;

procedure TAtlasSignatureControllerTests.ReadsFormatPlaceholders;
var
  mResponse: TJSONValue;
  mHelp: TAtlasSignatureHelp;
begin
  // Platzhalter (#451) wie vom Server.
  mResponse := TJSONObject.ParseJSONValue(
    '{"signatures":[{"label":"function Format(const Format: string; const Args: array of const): string",' +
    '"parameters":[{"label":[16,37]},{"label":[39,66]}]}],"activeSignature":0,"activeParameter":1,' +
    '"format":{"formatParameter":0,"listParameter":1,"argumentCount":2,"activeArgument":1,"placeholders":[' +
    '{"text":"%s","type":"s","valid":true,"argument":0,"width":-1,"precision":-1,' +
    '"range":{"start":{"line":3,"character":15},"end":{"line":3,"character":17}}},' +
    '{"text":"%q","valid":false,"argument":-1,"width":-1,"precision":-1}],' +
    '"arguments":[{"start":{"line":3,"character":35},"end":{"line":3,"character":43}}],' +
    '"problem":{"kind":"typeConflict","placeholder":1,"argument":0,"argumentKind":"string"}}}');
  try
    mHelp := TAtlasServerSignatureProvider.HelpFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.IsTrue(mHelp.Format.Found);
  Assert.AreEqual(1, mHelp.Format.ActiveArgument);
  Assert.AreEqual(2, mHelp.Format.ArgumentCount);
  Assert.AreEqual(2, Integer(Length(mHelp.Format.Placeholders)));
  Assert.AreEqual('s', mHelp.Format.Placeholders[0].TypeChar);
  Assert.IsTrue(mHelp.Format.Placeholders[0].HasRange);
  Assert.AreEqual(15, mHelp.Format.Placeholders[0].Range.StartCharacter);
  Assert.IsFalse(mHelp.Format.Placeholders[1].Valid);
  Assert.IsFalse(mHelp.Format.Placeholders[1].HasRange);
  Assert.AreEqual(35, mHelp.Format.Arguments[0].StartCharacter);
  Assert.AreEqual(Ord(TAtlasFormatProblem.TypeConflict), Ord(mHelp.Format.Problem));
  Assert.AreEqual('string', mHelp.Format.ProblemKind);
  // Ohne "format" keine Platzhalter.
  Assert.IsFalse(TAtlasServerSignatureProvider.HelpFromLsp(nil).Format.Found);
end;

procedure TAtlasSignatureControllerTests.UpdateFormatKeepsOverload;
var
  mView: TFakeSignatureView;
  mViewRef: IAtlasSignatureView;
  mController: TAtlasSignatureController;
  mHelp: TAtlasSignatureHelp;
  mFormat: TAtlasSignatureFormat;
begin
  mView := TFakeSignatureView.Create;
  mViewRef := mView;
  mController := TAtlasSignatureController.Create(mViewRef);
  try
    mHelp := Default(TAtlasSignatureHelp);
    SetLength(mHelp.Signatures, 2);
    SetLength(mHelp.Signatures[0].Parameters, 1);
    SetLength(mHelp.Signatures[1].Parameters, 2);
    mHelp.ActiveSignature := 1;
    mController.Show(mHelp, 1);
    mFormat := Default(TAtlasSignatureFormat);
    mFormat.Found := True;
    mFormat.ActiveArgument := 2;
    mController.UpdateFormat(mFormat);
    Assert.AreEqual(1, mController.Signature);
    Assert.AreEqual(2, mController.Help.Format.ActiveArgument);
    mController.Close;
    // Geschlossen: nichts mehr.
    mController.UpdateFormat(mFormat);
    Assert.IsFalse(mController.Active);
  finally
    mController.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.ReadsLspSignatureHelp;
var
  mResponse: TJSONValue;
  mHelp: TAtlasSignatureHelp;
begin
  mResponse := TJSONObject.ParseJSONValue(
    '{"signatures":[{"label":"procedure Add(const S: string; Index: Integer)",' +
    '"documentation":{"kind":"markdown","value":"Fügt ein."},' +
    '"parameters":[{"label":[14,29],"documentation":"Der Text"},{"label":"Index: Integer"}]}],' +
    '"activeSignature":0,"activeParameter":1}');
  try
    mHelp := TAtlasServerSignatureProvider.HelpFromLsp(mResponse);
  finally
    mResponse.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mHelp.Signatures)));
  Assert.AreEqual(0, mHelp.ActiveSignature);
  Assert.AreEqual(1, mHelp.ActiveParameter);
  Assert.AreEqual('Fügt ein.', mHelp.Signatures[0].Documentation);
  Assert.AreEqual('const S: string', mHelp.Signatures[0].Parameters[0].Text(mHelp.Signatures[0].Label_));
  Assert.AreEqual('Der Text', mHelp.Signatures[0].Parameters[0].Documentation);
  Assert.AreEqual('Index: Integer', mHelp.Signatures[0].Parameters[1].Text(mHelp.Signatures[0].Label_));
  Assert.IsTrue(TAtlasServerSignatureProvider.HelpFromLsp(nil).IsEmpty);
end;

procedure TAtlasCallScannerTests.DetectsRemovedClosingParen;
const
  cTyped = '  myList := TStringList.Create(True)';
begin
  // Rücktaste hinter ")".
  Assert.IsTrue(TAtlasCallScanner.RemovedClosingParen(cTyped + ';', '  myList := TStringList.Create(True;'));
  Assert.IsTrue(TAtlasCallScanner.RemovedClosingParen(cTyped, '  myList := TStringList.Create(True'));
  // Entf vor ")" mitten in der Zeile, auch bei doppelter Klammer.
  Assert.IsTrue(TAtlasCallScanner.RemovedClosingParen('Foo(Bar()) + 1', 'Foo(Bar() + 1'));
  // Danach steht der Caret wieder im Aufruf.
  Assert.IsTrue(TAtlasCallScanner.Scan('  myList := TStringList.Create(True', 35).Found);
end;

procedure TAtlasCallScannerTests.OtherEditsAreNoRemovedParen;
begin
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('Foo(True)', 'Foo(Tru)'));
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('Foo(True)', 'Foo(True)'));
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('Foo(True)', 'Foo(True));'));
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('Foo(True)', 'Foo(Tr)'));
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('Foo(', 'Foo'));
  Assert.IsFalse(TAtlasCallScanner.RemovedClosingParen('', ''));
end;

procedure TAtlasSignatureControllerTests.TooManyArgumentsCountsOnly;
var
  mHelp: TAtlasSignatureHelp;
begin
  // StrToInt(Edit1.Text, 10 (#439): eine Überladung mit einem Parameter, zweites Argument zu viel.
  mHelp := Default(TAtlasSignatureHelp);
  SetLength(mHelp.Signatures, 2);
  SetLength(mHelp.Signatures[0].Parameters, 1);
  SetLength(mHelp.Signatures[1].Parameters, 1);
  Assert.IsFalse(TAtlasSignatureController.TooManyArguments(mHelp, 0));
  Assert.IsTrue(TAtlasSignatureController.TooManyArguments(mHelp, 1));
  // Nur die Anzahl zählt: ein unverträglicher Typ ist kein Fehlerzustand.
  mHelp.Signatures[0].TypeMismatch := True;
  Assert.IsFalse(TAtlasSignatureController.TooManyArguments(mHelp, 0));
  // Leere Klammern passen immer, ohne Signaturen gibt es keinen Fehler.
  Assert.IsTrue(TAtlasSignatureController.CountFits(Default(TAtlasSignature), 0));
  Assert.IsFalse(TAtlasSignatureController.CountFits(Default(TAtlasSignature), 1));
  Assert.IsFalse(TAtlasSignatureController.TooManyArguments(Default(TAtlasSignatureHelp), 3));
  mHelp := Default(TAtlasSignatureHelp);
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallScannerTests);
  TDUnitX.RegisterTestFixture(TAtlasSignatureControllerTests);

end.
