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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.CreateMethod;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

/// <summary>Aufrufstelle am "|" in AMarked.</summary>
function SiteOf(const AMarked: string; out ASite: TCreateCallSite; out ATree: TSyntaxTree): Boolean;
var
  Index, Line, Character: Integer;
begin
  Line := 0;
  Character := 0;
  for Index := 1 to Pos('|', AMarked) - 1 do
    if AMarked[Index] = #10 then
    begin
      Inc(Line);
      Character := 0;
    end
    else
      Inc(Character);
  ATree := TPascalParser.Parse(StringReplace(AMarked, '|', '', []));
  Result := TCreateMethod.Site(ATree.Tokens, TTextPosition.Create(Line, Character), ASite);
end;

function Describe(const AMarked: string): string;
var
  Site: TCreateCallSite;
  Tree: TSyntaxTree;
  Argument: TCallArgument;
begin
  Tree := nil;
  try
    if not SiteOf(AMarked, Site, Tree) then
      Exit('-');
    Result := Site.Name;
    if Site.Qualifier <> '' then
      Result := Site.Qualifier + '.' + Result;
    Result := Result + '(';
    for Argument in Site.Arguments do
      Result := Result + Argument.Text + '|';
    Result := Result + ') ' + IntToStr(Ord(Site.Context));
    if Site.Target <> '' then
      Result := Result + ' ' + Site.Target;
    if Site.CloseIndex < 0 then
      Result := Result + ' offen';
    Result := Result + ' @' + Tree.Tokens[Site.StatementStart].Text;
  finally
    Tree.Free;
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
  Site: TCreateCallSite;
  Tree: TSyntaxTree;
  Names: string;
  Argument: TCallArgument;
  Unique: TArray<string>;
begin
  Tree := nil;
  try
    Assert.IsTrue(SiteOf('begin'#10'  Nimm|(FKunde, ARate, LZiel, 0.1, 2.5, 42, ''x'', True, GetName, Liste.Count, ' +
      'TKunde(Obj), Hole(1), @Puffer, Self, nil, -0.5);'#10'end.', Site, Tree));
    Names := '';
    for Argument in Site.Arguments do
      Names := Names + TCreateMethod.ArgumentName(Tree.Tokens, Argument) + ',';
    Assert.AreEqual('Kunde,Rate,Ziel,Rate,Value,Value,Text,Flag,Name,Count,Kunde,Hole,Puffer,,,Value,', Names);
    Assert.AreEqual('Double', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[3]));
    Assert.AreEqual('Integer', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[5]));
    Assert.AreEqual('string', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[6]));
    Assert.AreEqual('Boolean', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[7]));
    Assert.AreEqual('Double', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[15]));
    Assert.AreEqual('', TCreateMethod.LiteralType(Tree.Tokens, Site.Arguments[0]));
  finally
    Tree.Free;
  end;
  Assert.AreEqual('Customer', TCreateMethod.NameFromType('TCustomer'));
  Assert.AreEqual('Exporter', TCreateMethod.NameFromType('IExporter'));
  Assert.AreEqual('List', TCreateMethod.NameFromType('System.Generics.Collections.TList<TKunde>'));
  Assert.AreEqual('Text', TCreateMethod.NameFromType('string'));
  Assert.AreEqual('Value', TCreateMethod.NameFromType('Integer'));
  Assert.AreEqual('Value', TCreateMethod.NameFromType(TCreateMethod.TypePlaceholder));
  Unique := TCreateMethod.UniqueNames(['Value', 'Value', 'Rate', 'value']);
  Assert.AreEqual('Value,Value2,Rate,value3', Unique[0] + ',' + Unique[1] + ',' + Unique[2] + ',' + Unique[3]);
end;

procedure TCreateMethodTests.HeaderWithConstAndResult;
var
  Plan: TCreateMethodPlan;
  Parameter: TCreateParameter;
begin
  Plan := Default(TCreateMethodPlan);
  Plan.Name := 'CalcDiscount';
  Parameter.Name := 'Customer';
  Parameter.TypeName := 'TCustomer';
  Parameter.IsConst := TCreateMethod.WantsConst('TCustomer', False, False);
  Plan.Parameters := [Parameter];
  Parameter.Name := 'Rate';
  Parameter.TypeName := 'Double';
  Parameter.IsConst := False;
  Plan.Parameters := Plan.Parameters + [Parameter];
  Plan.ResultType := 'Currency';
  Assert.AreEqual('function CalcDiscount(Customer: TCustomer; Rate: Double): Currency',
    TCreateMethod.Header(Plan, False));
  Plan.TypeName := 'TRechner';
  Plan.IsClassMethod := True;
  Plan.ResultType := '';
  Plan.Parameters[0].TypeName := 'string';
  Plan.Parameters[0].IsConst := TCreateMethod.WantsConst('string', False, False);
  Assert.AreEqual('class procedure TRechner.CalcDiscount(const Customer: string; Rate: Double)',
    TCreateMethod.Header(Plan, True));
  Assert.IsTrue(TCreateMethod.WantsConst('TPunkt', True, False));
  Assert.IsTrue(TCreateMethod.WantsConst('IExporter', False, True));
  Assert.IsFalse(TCreateMethod.WantsConst('Integer', False, False));
end;

procedure TCreateMethodTests.MethodGoesIntoSectionAndBody;
var
  Text: string;
  Tree: TSyntaxTree;
  Plan: TCreateMethodPlan;
  Edits: TArray<TTextEdit>;
begin
  Text := Join([
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
  Plan := Default(TCreateMethodPlan);
  Plan.Name := 'Pruefe';
  Plan.TypeName := 'TRechner';
  Plan.Section := 'private';
  Plan.CaretInBody := True;
  Plan.Style := TFormatStyle.Default;
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TCreateMethod.MethodEdits(Text, Tree, Plan, Edits));
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
      'end.']), TChangeSignature.ApplyEdits(Text, Edits));
    // public vorhanden: dort am Ende.
    Plan.Section := 'public';
    Plan.CaretInBody := False;
    Assert.IsTrue(TCreateMethod.MethodEdits(Text, Tree, Plan, Edits));
    Assert.IsTrue(TChangeSignature.ApplyEdits(Text, Edits).Contains(
      '    procedure Rechne;'#10'    procedure Pruefe;'#10'  end;'), TChangeSignature.ApplyEdits(Text, Edits));
    // Unbekannte Klasse: nichts.
    Plan.TypeName := 'TFremd';
    Assert.IsFalse(TCreateMethod.MethodEdits(Text, Tree, Plan, Edits));
  finally
    Tree.Free;
  end;
end;

procedure TCreateMethodTests.RoutineGoesBeforeCurrentRoutine;
var
  Text: string;
  Tree: TSyntaxTree;
  Plan: TCreateMethodPlan;
begin
  Text := Join([
    'program P;',
    '',
    '// Hauptarbeit',
    'procedure Arbeite;',
    'begin',
    '  X := Hole(1);',
    'end;',
    'begin',
    'end.']);
  Plan := Default(TCreateMethodPlan);
  Plan.Name := 'Hole';
  Plan.ResultType := 'Integer';
  Plan.Style := TFormatStyle.Default;
  Tree := TPascalParser.Parse(Text);
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
      'end.']), TChangeSignature.ApplyEdits(Text, [TCreateMethod.RoutineEdit(Text,
      TRoutineBody.RoutineAt(Tree, Pos('Hole', Text) - 1), Plan)]));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TCreateMethodTests);

end.
