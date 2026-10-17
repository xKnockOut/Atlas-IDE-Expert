unit Atlas.Common.Editing.WithResolution.Tests;

// Tests für „with auflösen“ (#50) mit einer festen Herkunftstabelle statt der
// Namensauflösung des Servers.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWithResolutionTests = class
  public
    [Test]
    procedure QualifiesMembersOfEveryElement;
    [Test]
    procedure UnwrapsBeginEndAndKeepsOtherNames;
    [Test]
    procedure IndentsSingleStatementInBranch;
    [Test]
    procedure RejectsUnknownIdentifiers;
    [Test]
    procedure ComplexClassExpressionGoesIntoVariable;
    [Test]
    procedure ComplexExpressionWithVarSection;
    [Test]
    procedure RejectsComplexRecordExpression;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.CodeActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.Extract,
  Atlas.Common.Editing.WithResolution;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

/// <summary>Herkunft aus AOwners ("Name=0,Ort=1"); fehlende Namen sind Other, "?" ist Unknown.</summary>
function Lookup(const AOwners: string): TWithOwnerLookup;
var
  Owners: string;
begin
  Owners := ',' + AOwners + ',';
  Result :=
    function(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
    var
      At: Integer;
      Value: string;
    begin
      AElement := -1;
      Result := TWithOwner.Other;
      At := Pos(',' + LowerCase(AIdentifier.Name) + '=', LowerCase(Owners));
      if At = 0 then
        Exit;
      Value := Copy(Owners, At + Length(AIdentifier.Name) + 2, MaxInt);
      Value := Copy(Value, 1, Pos(',', Value) - 1);
      if Value = '?' then
        Exit(TWithOwner.Unknown);
      AElement := StrToInt(Value);
      Result := TWithOwner.Element;
    end;
end;

function Probe(const AName: string; AReference: Boolean): TTypeProbe;
var
  Name: string;
  Reference: Boolean;
begin
  Name := AName;
  Reference := AReference;
  Result :=
    function(const AText: string; const ANamePos: TTextPosition): TProbedType
    begin
      Result := Default(TProbedType);
      Result.Name := Name;
      Result.IsReference := Reference;
      Result.IsValue := not Reference;
    end;
end;

/// <summary>Ergebnis von „with auflösen“ am "|" in AMarked; '-' ohne Angebot.</summary>
function Resolve(const AMarked, AOwners: string; const AOptions: TExtractOptions): string;
var
  Text, Reason: string;
  Line, Character, Index: Integer;
  Tree: TSyntaxTree;
  WithNode: TSyntaxNode;
  Action: TCodeAction;
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
  Text := StringReplace(AMarked, '|', '', []);
  Tree := TPascalParser.Parse(Text);
  try
    WithNode := TWithResolution.WithAt(Tree, TTextPosition.Create(Line, Character));
    if (WithNode = nil) or not TWithResolution.Resolve(Text, Tree, WithNode, Lookup(AOwners), AOptions, Action,
      Reason) then
      Exit('-');
    Assert.AreEqual('with auflösen', Action.Title);
    Result := TChangeSignature.ApplyEdits(Text, Action.Edits);
  finally
    Tree.Free;
  end;
end;

function Plain: TExtractOptions;
begin
  Result := TExtractOptions.Default;
end;

procedure TWithResolutionTests.QualifiesMembersOfEveryElement;
begin
  // with A, B: Name gehört zu B (innerstes Element), Ort zu A.
  Assert.AreEqual(Join([
    'procedure Setze(K: TKunde; D: TAdresse);',
    'begin',
    '  D.Name := K.Ort;',
    'end;']), Resolve(Join([
    'procedure Setze(K: TKunde; D: TAdresse);',
    'begin',
    '  |with K, D do',
    '    Name := Ort;',
    'end;']), 'Name=1,Ort=0', Plain));
end;

procedure TWithResolutionTests.UnwrapsBeginEndAndKeepsOtherNames;
begin
  Assert.AreEqual(Join([
    'procedure Zeige(K: TKunde);',
    'begin',
    '  K.Name := ''x'';',
    '  // Alter ausgeben',
    '  Ausgabe(K.Alter);',
    '  Fertig;',
    'end;']), Resolve(Join([
    'procedure Zeige(K: TKunde);',
    'begin',
    '  with K do',
    '  begin',
    '    |Name := ''x'';',
    '    // Alter ausgeben',
    '    Ausgabe(Alter);',
    '  end;',
    '  Fertig;',
    'end;']), 'Name=0,Alter=0', Plain));
end;

procedure TWithResolutionTests.IndentsSingleStatementInBranch;
begin
  // Ohne Anweisungsliste bleibt begin … end auf der Höhe des with-Kopfs stehen.
  Assert.AreEqual(Join([
    'procedure Zeige(K: TKunde);',
    'begin',
    '  if K <> nil then',
    '    begin',
    '      K.Name := ''x'';',
    '    end;',
    'end;']), Resolve(Join([
    'procedure Zeige(K: TKunde);',
    'begin',
    '  if K <> nil then',
    '    |with K do',
    '    begin',
    '      Name := ''x'';',
    '    end;',
    'end;']), 'Name=0', Plain));
end;

procedure TWithResolutionTests.RejectsUnknownIdentifiers;
begin
  Assert.AreEqual('-', Resolve(Join([
    'procedure Zeige(K: TKunde);',
    'begin',
    '  |with K do',
    '    Name := Wert;',
    'end;']), 'Name=0,Wert=?', Plain));
end;

procedure TWithResolutionTests.ComplexClassExpressionGoesIntoVariable;
var
  Options: TExtractOptions;
begin
  Options := Plain;
  Options.Probe := Probe('TKunde', True);
  Assert.AreEqual(Join([
    'procedure Zeige;',
    'begin',
    '  var Kunde := HoleKunde(1);',
    '  Kunde.Name := ''x'';',
    'end;']), Resolve(Join([
    'procedure Zeige;',
    'begin',
    '  |with HoleKunde(1) do',
    '    Name := ''x'';',
    'end;']), 'Name=0', Options));
end;

procedure TWithResolutionTests.ComplexExpressionWithVarSection;
var
  Options: TExtractOptions;
begin
  Options := Plain;
  Options.InlineVar := False;
  Options.Probe := Probe('TKunde', True);
  Assert.AreEqual(Join([
    'procedure Zeige;',
    'var',
    '  Kunde: TKunde;',
    'begin',
    '  Kunde := HoleKunde(1);',
    '  Kunde.Name := ''x'';',
    'end;']), Resolve(Join([
    'procedure Zeige;',
    'begin',
    '  |with HoleKunde(1) do',
    '    Name := ''x'';',
    'end;']), 'Name=0', Options));
end;

procedure TWithResolutionTests.RejectsComplexRecordExpression;
var
  Options: TExtractOptions;
begin
  Options := Plain;
  Options.Probe := Probe('TPunkt', False);
  Assert.AreEqual('-', Resolve(Join([
    'procedure Zeige;',
    'begin',
    '  |with HolePunkt(1) do',
    '    X := 2;',
    'end;']), 'X=0', Options));
end;

initialization
  TDUnitX.RegisterTestFixture(TWithResolutionTests);

end.
