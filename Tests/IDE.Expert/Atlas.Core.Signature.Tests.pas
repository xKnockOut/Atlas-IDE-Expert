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
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
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
  Name: string;
  Parameter: TAtlasSignatureParameter;
begin
  Result := Default(TAtlasSignature);
  Result.Label_ := ALabel;
  for Name in AParameters do
  begin
    Parameter := Default(TAtlasSignatureParameter);
    Parameter.Start := Pos(Name, ALabel) - 1;
    Parameter.Stop := Parameter.Start + Length(Name);
    Result.Parameters := Result.Parameters + [Parameter];
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

{ TAtlasCallScannerTests }

procedure TAtlasCallScannerTests.CountsParametersOfFormat;
var
  Site: TAtlasCallSite;
begin
  Site := ScanEnd('  S := Format(''%d'', [');
  Assert.IsTrue(Site.Found);
  Assert.AreEqual(1, Site.ActiveParameter, 'Format(''%d'', [ hebt Args hervor');
  Assert.AreEqual(Pos('(', '  S := Format(''%d'', [') - 1, Site.OpenParen);
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
  Site: TAtlasCallSite;
begin
  Assert.AreEqual(1, ScanEnd('Foo(Bar(1, 2), ').ActiveParameter, 'Innerer Aufruf ist geschlossen');
  Site := ScanEnd('Foo(1, Bar(2, ');
  Assert.AreEqual(1, Site.ActiveParameter, 'Im inneren Aufruf zählt dessen Komma');
  Assert.AreEqual(Length('Foo(1, Bar'), Site.OpenParen);
  Assert.AreEqual(1, ScanEnd('Foo(1, (2 + 3').ActiveParameter, 'Klammer zur Gruppierung gehört zu Foo');
  Assert.AreEqual(1, ScanEnd('Foo(1, [2, 3').ActiveParameter, 'Mengen- bzw. Array-Klammern');
end;

procedure TAtlasCallScannerTests.NamesCallAndOuterCalls;
var
  Site: TAtlasCallSite;
begin
  // Beispiel aus #438.
  Site := ScanEnd('  ShowMessage(Format(''%d Zeilen'', [');
  Assert.AreEqual('Format', Site.Name);
  Assert.AreEqual(1, Integer(Length(Site.Outer)));
  Assert.AreEqual('ShowMessage', Site.Outer[0]);
  // Nach der schließenden Klammer von Format wieder ShowMessage, ohne äußere Aufrufe.
  Site := ScanEnd('  ShowMessage(Format(''%d'', [N])');
  Assert.AreEqual('ShowMessage', Site.Name);
  Assert.AreEqual(0, Integer(Length(Site.Outer)));
  // Qualifizierter Aufruf: letzter Bezeichner; Gruppierungsklammern zählen nicht als Ebene.
  Site := ScanEnd('A(B((1 + 2), TStringList.Create(');
  Assert.AreEqual('Create', Site.Name);
  Assert.AreEqual('A,B', String.Join(',', Site.Outer));
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
  View: TFakeSignatureView;
  ViewRef: IAtlasSignatureView;
  Controller: TAtlasSignatureController;
begin
  View := TFakeSignatureView.Create;
  ViewRef := View;
  Controller := TAtlasSignatureController.Create(ViewRef);
  try
    Controller.Show(FormatHelp, 0);
    Assert.AreEqual(0, View.Signature, 'Kürzeste passende Variante zuerst');
    Controller.UpdateParameter(1);
    Assert.AreEqual(0, View.Signature);
    Assert.AreEqual(1, View.Parameter);
    // #437: Beim dritten Argument wechselt der Hint auf die Variante mit TFormatSettings.
    Controller.UpdateParameter(2);
    Assert.AreEqual(1, View.Signature);
    Assert.AreEqual(2, View.Parameter);
    // Zurück (Rücktaste über das Komma): die gezeigte Variante passt weiter und bleibt.
    Controller.UpdateParameter(1);
    Assert.AreEqual(1, View.Signature);
    Controller.Close;
    Assert.IsFalse(View.Shown);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.ManualOverloadSwitchWraps;
var
  View: TFakeSignatureView;
  ViewRef: IAtlasSignatureView;
  Controller: TAtlasSignatureController;
  Help: TAtlasSignatureHelp;
begin
  View := TFakeSignatureView.Create;
  ViewRef := View;
  Controller := TAtlasSignatureController.Create(ViewRef);
  try
    Help := FormatHelp;
    Help.ActiveSignature := 1;
    Controller.Show(Help, 0);
    Assert.AreEqual(1, View.Signature, 'Vom Server gewählte Variante, wenn sie passt');
    Controller.NextOverload;
    Assert.AreEqual(0, View.Signature, 'Alt+↓ läuft im Kreis');
    Controller.PreviousOverload;
    Assert.AreEqual(1, View.Signature);
    // Klick auf eine Überladung im Hint.
    Controller.SelectOverload(0);
    Assert.AreEqual(0, View.Signature);
    // Beim dritten Argument passt nur noch die Variante mit TFormatSettings.
    Controller.UpdateParameter(2);
    Assert.IsFalse(Controller.OverloadFits(0));
    Assert.IsTrue(Controller.OverloadFits(1));
    // Leere Hilfe schließt.
    Controller.Show(Default(TAtlasSignatureHelp), 0);
    Assert.IsFalse(Controller.Active);
  finally
    Controller.Free;
  end;
end;

procedure TAtlasSignatureControllerTests.ReadsLspSignatureHelp;
var
  Response: TJSONValue;
  Help: TAtlasSignatureHelp;
begin
  Response := TJSONObject.ParseJSONValue(
    '{"signatures":[{"label":"procedure Add(const S: string; Index: Integer)",' +
    '"documentation":{"kind":"markdown","value":"Fügt ein."},' +
    '"parameters":[{"label":[14,29],"documentation":"Der Text"},{"label":"Index: Integer"}]}],' +
    '"activeSignature":0,"activeParameter":1}');
  try
    Help := TAtlasServerSignatureProvider.HelpFromLsp(Response);
  finally
    Response.Free;
  end;
  Assert.AreEqual(1, Integer(Length(Help.Signatures)));
  Assert.AreEqual(0, Help.ActiveSignature);
  Assert.AreEqual(1, Help.ActiveParameter);
  Assert.AreEqual('Fügt ein.', Help.Signatures[0].Documentation);
  Assert.AreEqual('const S: string', Help.Signatures[0].Parameters[0].Text(Help.Signatures[0].Label_));
  Assert.AreEqual('Der Text', Help.Signatures[0].Parameters[0].Documentation);
  Assert.AreEqual('Index: Integer', Help.Signatures[0].Parameters[1].Text(Help.Signatures[0].Label_));
  Assert.IsTrue(TAtlasServerSignatureProvider.HelpFromLsp(nil).IsEmpty);
end;

procedure TAtlasCallScannerTests.DetectsRemovedClosingParen;
const
  Typed = '  myList := TStringList.Create(True)';
begin
  // Rücktaste hinter ")".
  Assert.IsTrue(TAtlasCallScanner.RemovedClosingParen(Typed + ';', '  myList := TStringList.Create(True;'));
  Assert.IsTrue(TAtlasCallScanner.RemovedClosingParen(Typed, '  myList := TStringList.Create(True'));
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

initialization
  TDUnitX.RegisterTestFixture(TAtlasCallScannerTests);
  TDUnitX.RegisterTestFixture(TAtlasSignatureControllerTests);

end.
