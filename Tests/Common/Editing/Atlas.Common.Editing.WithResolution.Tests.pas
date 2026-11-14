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
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

/// <summary>Herkunft aus AOwners ("Name=0,Ort=1"); fehlende Namen sind Other, "?" ist Unknown.</summary>
function Lookup(const AOwners: string): TWithOwnerLookup;
var
  mOwners: string;
begin
  mOwners := ',' + AOwners + ',';
  Result :=
    function(AWith, AIdentifier: TSyntaxNode; out AElement: Integer): TWithOwner
    var
      At: Integer;
      Value: string;
    begin
      AElement := -1;
      Result := TWithOwner.Other;
      At := Pos(',' + LowerCase(AIdentifier.Name) + '=', LowerCase(mOwners));
      if At = 0 then
      begin
        Exit;
      end;
      Value := Copy(mOwners, At + Length(AIdentifier.Name) + 2, MaxInt);
      Value := Copy(Value, 1, Pos(',', Value) - 1);
      if Value = '?' then
      begin
        Exit(TWithOwner.Unknown);
      end;
      AElement := StrToInt(Value);
      Result := TWithOwner.Element;
    end;
end;

function Probe(const AName: string; AReference: Boolean): TTypeProbe;
var
  mName: string;
  mReference: Boolean;
begin
  mName := AName;
  mReference := AReference;
  Result :=
    function(const AText: string; const ANamePos: TTextPosition): TProbedType
    begin
      Result := Default(TProbedType);
      Result.Name := mName;
      Result.IsReference := mReference;
      Result.IsValue := not mReference;
    end;
end;

/// <summary>Ergebnis von „with auflösen“ am "|" in AMarked; '-' ohne Angebot.</summary>
function Resolve(const AMarked, AOwners: string; const AOptions: TExtractOptions): string;
var
  mText: string;
  mLine, mCharacter, mIndex: Integer;
  mTree: TSyntaxTree;
  mWithNode: TSyntaxNode;
  mResolved: TWithResolved;
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
  mText := StringReplace(AMarked, '|', '', []);
  mTree := TPascalParser.Parse(mText);
  try
    mWithNode := TWithResolution.WithAt(mTree, TTextPosition.Create(mLine, mCharacter));
    if (mWithNode = nil) or not TWithResolution.Resolve(mText, mTree, mWithNode, Lookup(AOwners), AOptions,
      mResolved) then
    begin
      Exit('-');
    end;
    Assert.AreEqual('with auflösen', mResolved.Action.Title);
    Result := TChangeSignature.ApplyEdits(mText, mResolved.Action.Edits);
  finally
    mTree.Free;
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
  mOptions: TExtractOptions;
begin
  mOptions := Plain;
  mOptions.Probe := Probe('TKunde', True);
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
    'end;']), 'Name=0', mOptions));
end;

procedure TWithResolutionTests.ComplexExpressionWithVarSection;
var
  mOptions: TExtractOptions;
begin
  mOptions := Plain;
  mOptions.InlineVar := False;
  mOptions.Probe := Probe('TKunde', True);
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
    'end;']), 'Name=0', mOptions));
end;

procedure TWithResolutionTests.RejectsComplexRecordExpression;
var
  mOptions: TExtractOptions;
begin
  mOptions := Plain;
  mOptions.Probe := Probe('TPunkt', False);
  Assert.AreEqual('-', Resolve(Join([
    'procedure Zeige;',
    'begin',
    '  |with HolePunkt(1) do',
    '    X := 2;',
    'end;']), 'X=0', mOptions));
end;

initialization
  TDUnitX.RegisterTestFixture(TWithResolutionTests);

end.
