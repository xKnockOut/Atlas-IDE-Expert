unit Atlas.Common.Editing.CreateMethod.Tests;

// Tests für „Methode aus Aufruf anlegen“ (#472) ohne Namensauflösung: Aufrufstelle, Namen, Kopf und Einfügen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TCreateMethodTests = class
  public
    [Test]
    procedure SiteOnNameAndAfterParen;
    [Test]
    procedure SiteContexts;
    [Test]
    procedure SiteRejectsDeclarationsAndComplexQualifiers;
    [Test]
    procedure NamesFromArguments;
    [Test]
    procedure HeaderWithConstAndResult;
    [Test]
    procedure MethodGoesIntoSectionAndBody;
    [Test]
    procedure RoutineGoesBeforeCurrentRoutine;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.CreateMethod;

function Join(const ALines: array of string): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Aufrufstelle am "|" in AMarked.</summary>
function SiteOf(const AMarked: string; out ASite: TCreateCallSite; out ATree: TSyntaxTree): Boolean;
var
  mIndex, mLine, mCharacter: Integer;
begin
  mLine := 0;
  mCharacter := 0;
  for mIndex := 1 to Pos('|', AMarked) - 1 do
  begin
    if AMarked[mIndex] = #10 then
    begin
      Inc(mLine);
      mCharacter := 0;
    end
    else
    begin
      Inc(mCharacter);
    end;
  end;
  ATree := TPascalParser.Parse(StringReplace(AMarked, '|', '', []));
  Result := TCreateMethod.Site(ATree.Tokens, TTextPosition.Create(mLine, mCharacter), ASite);
end;

function Describe(const AMarked: string): string;
var
  mSite: TCreateCallSite;
  mTree: TSyntaxTree;
  mArgument: TCallArgument;
begin
  mTree := nil;
  try
    if not SiteOf(AMarked, mSite, mTree) then
    begin
      Exit('-');
    end;
    Result := mSite.Name;
    if mSite.Qualifier <> '' then
    begin
      Result := mSite.Qualifier + '.' + Result;
    end;
    Result := Result + '(';
    for mArgument in mSite.Arguments do
    begin
      Result := Result + mArgument.Text + '|';
    end;
    Result := Result + ') ' + IntToStr(Ord(mSite.Context));
    if mSite.Target <> '' then
    begin
      Result := Result + ' ' + mSite.Target;
    end;
    if mSite.CloseIndex < 0 then
    begin
      Result := Result + ' offen';
    end;
    Result := Result + ' @' + mTree.Tokens[mSite.StatementStart].Text;
  finally
    mTree.Free;
  end;
end;

procedure TCreateMethodTests.SiteOnNameAndAfterParen;
begin
  Assert.AreEqual('CalcDiscount(Customer|0.1|) 1 Total @Total',
    Describe('begin'#10'  Total := Calc|Discount(Customer, 0.1);'#10'end.'));
  // Auslöser "(": Argumente fehlen noch.
  Assert.AreEqual('CalcDiscount() 1 Total offen @Total', Describe('begin'#10'  Total := CalcDiscount(|'#10'end.'));
  Assert.AreEqual('Kunde.Speichern(True|) 0 @Kunde', Describe('begin'#10'  Kunde.Speichern|(True);'#10'end.'));
  // Kein Aufruf: Name ohne "(".
  Assert.AreEqual('-', Describe('begin'#10'  Total := Calc|Discount;'#10'end.'));
end;

procedure TCreateMethodTests.SiteContexts;
begin
  Assert.AreEqual('Pruefe(X|) 2 @if', Describe('begin'#10'  if Pruefe|(X) then'#10'    Exit;'#10'end.'));
  Assert.AreEqual('Teil(A|) 3 @Total', Describe('begin'#10'  Total := Teil|(A) * 2;'#10'end.'));
  Assert.AreEqual('Teil(A|B|) 3 @Zeige', Describe('begin'#10'  Zeige(Teil|(A, B));'#10'end.'));
  Assert.AreEqual('Nimm(F(1, 2)|L[3]|) 0 @Nimm', Describe('begin'#10'  X := 1;'#10'  Nimm|(F(1, 2), L[3])'#10'end.'));
end;

procedure TCreateMethodTests.SiteRejectsDeclarationsAndComplexQualifiers;
begin
  Assert.AreEqual('-', Describe('procedure Fo|o(A: Integer);'#10'begin'#10'end;'));
  Assert.AreEqual('-', Describe('begin'#10'  Liste[0].Spei|chern(1);'#10'end.'));
  Assert.AreEqual('-', Describe('begin'#10'  Hole(1).Spei|chern(1);'#10'end.'));
end;

procedure TCreateMethodTests.NamesFromArguments;
var
  mSite: TCreateCallSite;
  mTree: TSyntaxTree;
  mNames: string;
  mArgument: TCallArgument;
  mUnique: TArray<string>;
begin
  mTree := nil;
  try
    Assert.IsTrue(SiteOf('begin'#10'  Nimm|(FKunde, ARate, LZiel, 0.1, 2.5, 42, ''x'', True, GetName, Liste.Count, ' +
      'TKunde(Obj), Hole(1), @Puffer, Self, nil, -0.5);'#10'end.', mSite, mTree));
    mNames := '';
    for mArgument in mSite.Arguments do
    begin
      mNames := mNames + TCreateMethod.ArgumentName(mTree.Tokens, mArgument) + ',';
    end;
    Assert.AreEqual('Kunde,Rate,Ziel,Rate,Value,Value,Text,Flag,Name,Count,Kunde,Hole,Puffer,,,Value,', mNames);
    Assert.AreEqual('Double', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[3]));
    Assert.AreEqual('Integer', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[5]));
    Assert.AreEqual('string', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[6]));
    Assert.AreEqual('Boolean', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[7]));
    Assert.AreEqual('Double', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[15]));
    Assert.AreEqual('', TCreateMethod.LiteralType(mTree.Tokens, mSite.Arguments[0]));
  finally
    mTree.Free;
  end;
  Assert.AreEqual('Customer', TCreateMethod.NameFromType('TCustomer'));
  Assert.AreEqual('Exporter', TCreateMethod.NameFromType('IExporter'));
  Assert.AreEqual('List', TCreateMethod.NameFromType('System.Generics.Collections.TList<TKunde>'));
  Assert.AreEqual('Text', TCreateMethod.NameFromType('string'));
  Assert.AreEqual('Value', TCreateMethod.NameFromType('Integer'));
  Assert.AreEqual('Value', TCreateMethod.NameFromType(TCreateMethod.cTypePlaceholder));
  mUnique := TCreateMethod.UniqueNames(['Value', 'Value', 'Rate', 'value']);
  Assert.AreEqual('Value,Value2,Rate,value3', mUnique[0] + ',' + mUnique[1] + ',' + mUnique[2] + ',' + mUnique[3]);
end;

procedure TCreateMethodTests.HeaderWithConstAndResult;
var
  mPlan: TCreateMethodPlan;
  mParameter: TCreateParameter;
begin
  mPlan := Default(TCreateMethodPlan);
  mPlan.Name := 'CalcDiscount';
  mParameter.Name := 'Customer';
  mParameter.TypeName := 'TCustomer';
  mParameter.IsConst := TCreateMethod.WantsConst('TCustomer', False, False);
  mPlan.Parameters := [mParameter];
  mParameter.Name := 'Rate';
  mParameter.TypeName := 'Double';
  mParameter.IsConst := False;
  mPlan.Parameters := mPlan.Parameters + [mParameter];
  mPlan.ResultType := 'Currency';
  Assert.AreEqual('function CalcDiscount(Customer: TCustomer; Rate: Double): Currency',
    TCreateMethod.Header(mPlan, False));
  mPlan.TypeName := 'TRechner';
  mPlan.IsClassMethod := True;
  mPlan.ResultType := '';
  mPlan.Parameters[0].TypeName := 'string';
  mPlan.Parameters[0].IsConst := TCreateMethod.WantsConst('string', False, False);
  Assert.AreEqual('class procedure TRechner.CalcDiscount(const Customer: string; Rate: Double)',
    TCreateMethod.Header(mPlan, True));
  Assert.IsTrue(TCreateMethod.WantsConst('TPunkt', True, False));
  Assert.IsTrue(TCreateMethod.WantsConst('IExporter', False, True));
  Assert.IsFalse(TCreateMethod.WantsConst('Integer', False, False));
end;

/// <summary>Klasse TRechner, deren Methode Rechne das noch fehlende Pruefe aufruft.</summary>
function RechnerCallsPruefe: string;
begin
  Result := Join([
    'unit U;',
    'interface',
    'type',
    '  TRechner = class',
    '  public',
    '    procedure Rechne;',
    '  end;',
    'implementation',
    'procedure TRechner.Rechne;',
    'begin',
    '  Pruefe;',
    'end;',
    'end.']);
end;

procedure TCreateMethodTests.MethodGoesIntoSectionAndBody;
var
  mText: string;
  mTree: TSyntaxTree;
  mPlan: TCreateMethodPlan;
  mEdits: TArray<TTextEdit>;
begin
  mText := RechnerCallsPruefe;
  mPlan := Default(TCreateMethodPlan);
  mPlan.Name := 'Pruefe';
  mPlan.TypeName := 'TRechner';
  mPlan.Section := 'private';
  mPlan.CaretInBody := True;
  mPlan.Style := TFormatStyle.Default;
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TCreateMethod.MethodEdits(mText, mTree, mPlan, mEdits));
    Assert.AreEqual(Join([
      'unit U;',
      'interface',
      'type',
      '  TRechner = class',
      '  public',
      '    procedure Rechne;',
      '  private',
      '    procedure Pruefe;',
      '  end;',
      'implementation',
      'procedure TRechner.Rechne;',
      'begin',
      '  Pruefe;',
      'end;',
      '',
      'procedure TRechner.Pruefe;',
      'begin',
      '  $0',
      'end;',
      'end.']), TChangeSignature.ApplyEdits(mText, mEdits));
    // public vorhanden: dort am Ende.
    mPlan.Section := 'public';
    mPlan.CaretInBody := False;
    Assert.IsTrue(TCreateMethod.MethodEdits(mText, mTree, mPlan, mEdits));
    Assert.IsTrue(TChangeSignature.ApplyEdits(mText, mEdits).Contains(
      '    procedure Rechne;'#10'    procedure Pruefe;'#10'  end;'), TChangeSignature.ApplyEdits(mText, mEdits));
    // Unbekannte Klasse: nichts.
    mPlan.TypeName := 'TFremd';
    Assert.IsFalse(TCreateMethod.MethodEdits(mText, mTree, mPlan, mEdits));
  finally
    mTree.Free;
  end;
end;

procedure TCreateMethodTests.RoutineGoesBeforeCurrentRoutine;
var
  mText: string;
  mTree: TSyntaxTree;
  mPlan: TCreateMethodPlan;
begin
  mText := Join([
    'program P;',
    '',
    '// Hauptarbeit',
    'procedure Arbeite;',
    'begin',
    '  X := Hole(1);',
    'end;',
    'begin',
    'end.']);
  mPlan := Default(TCreateMethodPlan);
  mPlan.Name := 'Hole';
  mPlan.ResultType := 'Integer';
  mPlan.Style := TFormatStyle.Default;
  mTree := TPascalParser.Parse(mText);
  try
    Assert.AreEqual(Join([
      'program P;',
      '',
      'function Hole: Integer;',
      'begin',
      '',
      'end;',
      '',
      '// Hauptarbeit',
      'procedure Arbeite;',
      'begin',
      '  X := Hole(1);',
      'end;',
      'begin',
      'end.']), TChangeSignature.ApplyEdits(mText, [TCreateMethod.RoutineEdit(mText,
      TRoutineBody.RoutineAt(mTree, Pos('Hole', mText) - 1), mPlan)]));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCreateMethodTests);

end.
