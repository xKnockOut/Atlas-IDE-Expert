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
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.UsesActions,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.SmartPaste;

const
  Target =
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
        Result := ['System.JSON']
      else if SameText(AName, 'TKunde') then
        Result := ['Kunden']
      else if SameText(AName, 'TList') then
        Result := ['System.Classes', 'System.Generics.Collections']
      else if SameText(AName, 'TDataSet') then
        Result := ['Data.DB']
      else if SameText(AName, 'Format') then
        Result := ['System.SysUtils']
      else if SameText(AName, 'TFoo') then
        Result := ['Fremd'];
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
        Result := ['System.Classes', 'Ziel'];
    end;
end;

function Range(AFromLine, AToLine: Integer): TTextRange;
begin
  Result := TTextRange.Create(TTextPosition.Create(AFromLine, 0), TTextPosition.Create(AToLine + 1, 0));
end;

function Added(const AText: string; const APosition: TTextPosition; const AUnits: TArray<string>;
  out AMoved: string): string;
var
  Edits: TArray<TTextEdit>;
  Units, Moved: TArray<string>;
begin
  AMoved := '';
  if not TSmartPaste.UsesEdits(TPascalLexer.Tokenize(AText), APosition, AUnits, InterfaceUses(), ['System'], #10,
    Edits, Units, Moved) then
    Exit('-');
  AMoved := string.Join('|', Moved);
  Result := TChangeSignature.ApplyEdits(AText, Edits);
end;

procedure TSmartPasteTests.FindsMissingNamesInRange;
var
  Tree: TSyntaxTree;
  Names: TArray<TSmartPasteName>;
  Text: string;
  Item: TSmartPasteName;
begin
  Tree := TPascalParser.Parse(Target);
  try
    Names := TSmartPaste.Missing(TPascalLexer.Tokenize(Target), Tree, Range(6, 11), Declaring(), ['System']);
    Text := '';
    for Item in Names do
      Text := Text + Item.Name + '=' + string.Join(',', Item.Units) + ';';
    // TFoo deklariert die Datei selbst, TEnumerator steht nach einem Punkt, string ist kein Treffer.
    Assert.AreEqual('TJSONObject=System.JSON;TKunde=Kunden;TList=System.Classes,System.Generics.Collections;', Text);
    Assert.AreEqual('System.JSON|Kunden', string.Join('|', TSmartPaste.Certain(Names)), 'mehrdeutig nicht');
    // Format liefert System.SysUtils schon; außerhalb des Bereichs zählt nichts.
    Names := TSmartPaste.Missing(TPascalLexer.Tokenize(Target), Tree, Range(16, 19), Declaring(), ['System']);
    Assert.AreEqual(1, Integer(Length(Names)));
    Assert.AreEqual('TDataSet', Names[0].Name);
    Assert.AreEqual(0, Integer(Length(TSmartPaste.Missing(TPascalLexer.Tokenize(Target), Tree, Range(6, 11), nil,
      nil))), 'ohne Index nichts');
  finally
    Tree.Free;
  end;
  Names := nil;
end;

procedure TSmartPasteTests.InterfacePasteGoesToInterfaceUses;
var
  Moved: string;
begin
  Assert.IsTrue(TSmartPaste.InInterface(TPascalLexer.Tokenize(Target), TTextPosition.Create(6, 4)));
  Assert.IsFalse(TSmartPaste.InInterface(TPascalLexer.Tokenize(Target), TTextPosition.Create(16, 2)));
  Assert.AreEqual(
    StringReplace(StringReplace(Target, '  System.SysUtils;', '  System.SysUtils,'#10'  System.JSON;', []),
      'implementation'#10, 'implementation'#10#10'uses'#10'  Kunden;'#10, []),
    Added(Target, TTextPosition.Create(6, 4), ['System.JSON', 'Kunden', 'System.SysUtils', 'system.json', 'Ziel'],
      Moved));
  Assert.AreEqual('Kunden', Moved, 'Kreisverweis ins implementation');
end;

procedure TSmartPasteTests.ImplementationPasteGoesToImplementationUses;
var
  Moved: string;
begin
  Assert.AreEqual(StringReplace(Target, 'implementation'#10, 'implementation'#10#10'uses'#10'  Data.DB, System.JSON;'#10,
    []), Added(Target, TTextPosition.Create(16, 2), ['Data.DB', 'System.JSON'], Moved));
  Assert.AreEqual('', Moved);
  Assert.AreEqual('-', Added(Target, TTextPosition.Create(16, 2), ['System.SysUtils'], Moved), 'schon da');
end;

procedure TSmartPasteTests.ProgramHasOnlyOneUses;
const
  Program_ = 'program P;'#10'uses'#10'  System.SysUtils;'#10'begin'#10'end.'#10;
var
  Moved: string;
begin
  Assert.AreEqual(StringReplace(Program_, '  System.SysUtils;', '  System.SysUtils,'#10'  Kunden;', []),
    Added(Program_, TTextPosition.Create(4, 0), ['Kunden'], Moved));
end;

initialization
  TDUnitX.RegisterTestFixture(TSmartPasteTests);

end.
