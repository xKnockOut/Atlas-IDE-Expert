unit Atlas.Common.Editing.SmartPaste.Tests;

// Tests für Einfügen mit uses-Ergänzung (#515), Server-Kern: fehlende
// Bezeichner im eingefügten Bereich, eindeutige und mehrdeutige Kandidaten,
// Abschnitt nach der Einfügestelle und Kreisverweis im interface.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TSmartPasteTests = class
  public
    [Test]
    procedure FindsMissingNamesInRange;
    [Test]
    procedure InterfacePasteGoesToInterfaceUses;
    [Test]
    procedure ImplementationPasteGoesToImplementationUses;
    [Test]
    procedure ProgramHasOnlyOneUses;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.Contract,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.SmartPaste;

const
  cTarget =
    'unit Ziel;'#10 +                         // 0
    'interface'#10 +                          // 1
    'uses'#10 +                               // 2
    '  System.SysUtils;'#10 +                 // 3
    'type'#10 +                               // 4
    '  TFoo = class'#10 +                     // 5
    '    FData: TJSONObject;'#10 +            // 6
    '    FKunde: TKunde;'#10 +                // 7
    '    FList: TList;'#10 +                  // 8
    '    FText: string;'#10 +                 // 9
    '    FOwn: TFoo;'#10 +                    // 10
    '    FSet: TJSONObject.TEnumerator;'#10 + // 11
    '  end;'#10 +                             // 12
    'implementation'#10 +                     // 13
    'procedure Run;'#10 +                     // 14
    'var'#10 +                                // 15
    '  D: TDataSet;'#10 +                     // 16
    '  S: string;'#10 +                       // 17
    'begin'#10 +                              // 18
    '  S := Format(''%d'', [1]);'#10 +        // 19
    'end;'#10 +                               // 20
    'end.'#10;

function Declaring: TUnitsDeclaringFunc;
begin
  Result :=
    function(const AName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AName, 'TJSONObject') then
      begin
        Result := ['System.JSON'];
      end
      else if SameText(AName, 'TKunde') then
      begin
        Result := ['Kunden'];
      end
      else if SameText(AName, 'TList') then
      begin
        Result := ['System.Classes', 'System.Generics.Collections'];
      end
      else if SameText(AName, 'TDataSet') then
      begin
        Result := ['Data.DB'];
      end
      else if SameText(AName, 'Format') then
      begin
        Result := ['System.SysUtils'];
      end
      else if SameText(AName, 'TFoo') then
      begin
        Result := ['Fremd'];
      end;
    end;
end;

function InterfaceUses: TInterfaceUsesFunc;
begin
  // Kunden bindet Ziel im interface ein: Kreisverweis.
  Result :=
    function(const AUnitName: string): TArray<string>
    begin
      Result := nil;
      if SameText(AUnitName, 'Kunden') then
      begin
        Result := ['System.Classes', 'Ziel'];
      end;
    end;
end;

function Range(AFromLine, AToLine: Integer): TTextRange;
begin
  Result := TTextRange.Create(TTextPosition.Create(AFromLine, 0), TTextPosition.Create(AToLine + 1, 0));
end;

function Added(const AText: string; const APosition: TTextPosition; const AUnits: TArray<string>;
  out AMoved: string): string;
var
  mTarget: TSmartPasteTarget;
  mUses_: TSmartPasteUses;
begin
  AMoved := '';
  mTarget := Default(TSmartPasteTarget);
  mTarget.Tokens := TPascalLexer.Tokenize(AText);
  mTarget.Position := APosition;
  mTarget.InterfaceUses := InterfaceUses();
  mTarget.Namespaces := ['System'];
  mTarget.LineBreak := #10;
  if not TSmartPaste.UsesEdits(mTarget, AUnits, mUses_) then
  begin
    Exit('-');
  end;
  AMoved := string.Join('|', mUses_.ToImplementation);
  Result := TChangeSignature.ApplyEdits(AText, mUses_.Edits);
end;

procedure TSmartPasteTests.FindsMissingNamesInRange;
var
  mTree: TSyntaxTree;
  mNames: TArray<TSmartPasteName>;
  mText: string;
  mItem: TSmartPasteName;
begin
  mTree := TPascalParser.Parse(cTarget);
  try
    mNames := TSmartPaste.Missing(TPascalLexer.Tokenize(cTarget), mTree, Range(6, 11), Declaring(), ['System']);
    mText := '';
    for mItem in mNames do
    begin
      mText := mText + mItem.Name + '=' + string.Join(',', mItem.Units) + ';';
    end;
    // TFoo deklariert die Datei selbst, TEnumerator steht nach einem Punkt, string ist kein Treffer.
    Assert.AreEqual('TJSONObject=System.JSON;TKunde=Kunden;TList=System.Classes,System.Generics.Collections;', mText);
    Assert.AreEqual('System.JSON|Kunden', string.Join('|', TSmartPaste.Certain(mNames)), 'mehrdeutig nicht');
    // Format liefert System.SysUtils schon; außerhalb des Bereichs zählt nichts.
    mNames := TSmartPaste.Missing(TPascalLexer.Tokenize(cTarget), mTree, Range(16, 19), Declaring(), ['System']);
    Assert.AreEqual(1, Integer(Length(mNames)));
    Assert.AreEqual('TDataSet', mNames[0].Name);
    Assert.AreEqual(0, Integer(Length(TSmartPaste.Missing(TPascalLexer.Tokenize(cTarget), mTree, Range(6, 11), nil,
      nil))), 'ohne Index nichts');
  finally
    mTree.Free;
  end;
  mNames := nil;
end;

procedure TSmartPasteTests.InterfacePasteGoesToInterfaceUses;
var
  mMoved: string;
begin
  Assert.IsTrue(TSmartPaste.InInterface(TPascalLexer.Tokenize(cTarget), TTextPosition.Create(6, 4)));
  Assert.IsFalse(TSmartPaste.InInterface(TPascalLexer.Tokenize(cTarget), TTextPosition.Create(16, 2)));
  Assert.AreEqual(
    StringReplace(StringReplace(cTarget, '  System.SysUtils;', '  System.SysUtils,'#10'  System.JSON;', []),
      'implementation'#10, 'implementation'#10#10'uses'#10'  Kunden;'#10, []),
    Added(cTarget, TTextPosition.Create(6, 4), ['System.JSON', 'Kunden', 'System.SysUtils', 'system.json', 'Ziel'],
      mMoved));
  Assert.AreEqual('Kunden', mMoved, 'Kreisverweis ins implementation');
end;

procedure TSmartPasteTests.ImplementationPasteGoesToImplementationUses;
var
  mMoved: string;
begin
  Assert.AreEqual(StringReplace(cTarget, 'implementation'#10, 'implementation'#10#10'uses'#10'  Data.DB, System.JSON;'#10,
    []), Added(cTarget, TTextPosition.Create(16, 2), ['Data.DB', 'System.JSON'], mMoved));
  Assert.AreEqual('', mMoved);
  Assert.AreEqual('-', Added(cTarget, TTextPosition.Create(16, 2), ['System.SysUtils'], mMoved), 'schon da');
end;

procedure TSmartPasteTests.ProgramHasOnlyOneUses;
const
  cProgram_ = 'program P;'#10'uses'#10'  System.SysUtils;'#10'begin'#10'end.'#10;
var
  mMoved: string;
begin
  Assert.AreEqual(StringReplace(cProgram_, '  System.SysUtils;', '  System.SysUtils,'#10'  Kunden;', []),
    Added(cProgram_, TTextPosition.Create(4, 0), ['Kunden'], mMoved));
end;

initialization
  TDUnitX.RegisterTestFixture(TSmartPasteTests);

end.
