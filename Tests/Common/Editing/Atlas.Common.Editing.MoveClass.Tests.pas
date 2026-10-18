unit Atlas.Common.Editing.MoveClass.Tests;

// Tests für „Klasse in eigene Unit verschieben“ (#103 Teil B): neue Unit samt
// uses aus den benötigten Namen, Änderungen an der Ursprungs-Unit und an
// verwendenden Units, Ablehnungsgründe. Vorher und Nachher müssen parsen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TMoveClassTests = class
  public
    [Test]
    procedure DefaultUnitNameDropsT;
    [Test]
    procedure MovesClassWithMethods;
    [Test]
    procedure UsesOriginInterface;
    [Test]
    procedure RemovesTypeSectionForwardAndAttributes;
    [Test]
    procedure WithoutLookupCopiesUses;
    [Test]
    procedure RejectsImplementationLocals;
    [Test]
    procedure RejectsCircularInterfaces;
    [Test]
    procedure RejectsOtherCases;
    [Test]
    procedure UpdatesUsingUnits;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Editing.MoveClass;

function Join(const ALines: array of string): string;
var
  Index: Integer;
begin
  Result := '';
  for Index := 0 to High(ALines) do
    Result := Result + ALines[Index] + #10;
end;

procedure CheckParses(const AText: string);
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(Tree.Diagnostics)), AText);
  finally
    Tree.Free;
  end;
end;

/// <summary>Namensauflösung für Tests: TStrings aus System.Classes, Format aus System.SysUtils, Integer, string
/// und TObject aus System; Namen der Ursprungs-Unit und Unbekanntes nicht gefunden (die Unit erkennt sie selbst).
/// </summary>
function FakeLookup: TMoveClassLookup;
begin
  Result :=
    function(ATree: TSyntaxTree; const AFileName: string; const ANames: TArray<string>;
      AOffset: Integer): TMoveClassMeaning
    var
      Name: string;
    begin
      Result := Default(TMoveClassMeaning);
      Name := ANames[High(ANames)];
      if MatchText(Name, ['TStrings', 'TStringList']) then
        Result.UnitName := 'System.Classes'
      else if MatchText(Name, ['Format', 'IntToStr']) then
        Result.UnitName := 'System.SysUtils'
      else if MatchText(Name, ['Integer', 'string', 'TObject', 'Inc']) then
        Result.UnitName := 'System';
      Result.Found := Result.UnitName <> '';
    end;
end;

/// <summary>Verschiebt die Klasse auf der Zeile mit AMarker; '-' mit Grund, sonst neue Unit und geänderte
/// Ursprungs-Unit.</summary>
function Relocate(const AText, AMarker, ANewUnit: string; const ALookup: TMoveClassLookup; out ANewText, AOrigin,
  AReason: string): Boolean; overload;
var
  Tree: TSyntaxTree;
  Plan: TMoveClassPlan;
  Line, Index: Integer;
begin
  ANewText := '';
  AOrigin := '';
  CheckParses(AText);
  Line := 0;
  for Index := 1 to Pos(AMarker, AText) - 1 do
    if AText[Index] = #10 then
      Inc(Line);
  Tree := TPascalParser.Parse(AText);
  try
    Result := TMoveClass.Plan('lager.pas', AText, Tree, TTextPosition.Create(Line, 4), ANewUnit, ALookup, Plan,
      AReason);
    if not Result then
      Exit;
    ANewText := Plan.Text;
    AOrigin := TChangeSignature.ApplyEdits(AText, Plan.OriginEdits);
    CheckParses(ANewText);
    CheckParses(AOrigin);
  finally
    Tree.Free;
  end;
end;

function Relocate(const AText, AMarker: string; out ANewText, AOrigin: string): Boolean; overload;
var
  Reason: string;
begin
  Result := Relocate(AText, AMarker, 'Stock', FakeLookup(), ANewText, AOrigin, Reason);
  Assert.IsTrue(Result, Reason);
end;

function Rejected(const AText, AMarker: string): string;
var
  NewText, Origin: string;
begin
  Assert.IsFalse(Relocate(AText, AMarker, 'Stock', FakeLookup(), NewText, Origin, Result));
end;

procedure TMoveClassTests.DefaultUnitNameDropsT;
begin
  Assert.AreEqual('Kunde', TMoveClass.DefaultUnitName('TKunde'));
  Assert.AreEqual('Table', TMoveClass.DefaultUnitName('Table'));
  Assert.AreEqual('Tx', TMoveClass.DefaultUnitName('Tx'));
end;

procedure TMoveClassTests.MovesClassWithMethods;
var
  NewText, Origin: string;
begin
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '',
    'type', '  TBase = class', '  end;', '', '  /// <summary>Bestand.</summary>', '  TStock = class', '  private',
    '    FItems: TStrings;', '  public', '    function Count: Integer;', '    procedure Add(const AName: string);',
    '  end;', '', 'implementation', '', 'function TStock.Count: Integer;', 'begin', '  Result := FItems.Count;',
    'end;', '', 'procedure TStock.Add(const AName: string);', 'var', '  N: Integer;', 'begin', '  N := 1;',
    '  FItems.Add(Format(''%s %d'', [AName, N]));', 'end;', '', 'procedure Run;', 'begin', '  TStock.Create.Free;',
    'end;', '', 'end.']), 'TStock = class', NewText, Origin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'uses', '  System.Classes;', '', 'type',
    '  /// <summary>Bestand.</summary>', '  TStock = class', '  private', '    FItems: TStrings;', '  public',
    '    function Count: Integer;', '    procedure Add(const AName: string);', '  end;', '', 'implementation', '',
    'uses', '  System.SysUtils;', '', 'function TStock.Count: Integer;', 'begin', '  Result := FItems.Count;',
    'end;', '', 'procedure TStock.Add(const AName: string);', 'var', '  N: Integer;', 'begin', '  N := 1;',
    '  FItems.Add(Format(''%s %d'', [AName, N]));', 'end;', '', 'end.']), NewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '',
    'type', '  TBase = class', '  end;', '', 'implementation', '', 'uses', '  Stock;', '', 'procedure Run;',
    'begin', '  TStock.Create.Free;', 'end;', '', 'end.']), Origin);
end;

procedure TMoveClassTests.UsesOriginInterface;
var
  NewText, Origin: string;
begin
  // TBase und Max aus dem interface: Die neue Unit bindet Lager ein, Lager die neue Unit im implementation.
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '  end;', '',
    '  TStock = class(TBase)', '    function Count: Integer;', '  end;', '', 'const', '  Max = 10;', '',
    'implementation', '', 'uses', '  Helpers;', '', 'function TStock.Count: Integer;', 'begin', '  Result := Max;',
    'end;', '', 'initialization', '  TStock.Create.Free;', 'end.']), 'TStock = class', NewText, Origin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'uses', '  Lager;', '', 'type',
    '  TStock = class(TBase)', '    function Count: Integer;', '  end;', '', 'implementation', '',
    'function TStock.Count: Integer;', 'begin', '  Result := Max;', 'end;', '', 'end.']), NewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '  end;', '', 'const',
    '  Max = 10;', '', 'implementation', '', 'uses', '  Helpers,', '  Stock;', '', 'initialization',
    '  TStock.Create.Free;', 'end.']), Origin);
end;

procedure TMoveClassTests.RemovesTypeSectionForwardAndAttributes;
var
  NewText, Origin: string;
begin
  // Nur noch die Vorwärtsdeklaration und die Klasse im Typabschnitt: Er entfällt ganz.
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class;', '',
    '  // Lagerbestand', '  [Serializable]', '  TStock = class', '  end;', '', 'implementation', '', 'end.']),
    'TStock = class' + #10, NewText, Origin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'type', '  // Lagerbestand', '  [Serializable]',
    '  TStock = class', '  end;', '', 'implementation', '', 'end.']), NewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'implementation', '', 'end.']), Origin);
end;

procedure TMoveClassTests.WithoutLookupCopiesUses;
var
  NewText, Origin, Reason: string;
begin
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'uses', '  Classes;', '', 'type',
    '  TStock = class', '    FItems: TStrings;', '    procedure Add;', '  end;', '', 'implementation', '', 'uses',
    '  SysUtils;', '', 'procedure TStock.Add;', 'begin', '  FItems.Add(IntToStr(1));', 'end;', '', 'end.']),
    'TStock = class', 'Lager.Stock', nil, NewText, Origin, Reason), Reason);
  Assert.AreEqual(Join(['unit Lager.Stock;', '', 'interface', '', 'uses', '  Classes;', '', 'type',
    '  TStock = class', '    FItems: TStrings;', '    procedure Add;', '  end;', '', 'implementation', '', 'uses',
    '  SysUtils;', '', 'procedure TStock.Add;', 'begin', '  FItems.Add(IntToStr(1));', 'end;', '', 'end.']), NewText);
end;

procedure TMoveClassTests.RejectsImplementationLocals;
begin
  Assert.Contains(Rejected(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class',
    '    procedure Add;', '  end;', '', 'implementation', '', 'var', '  Hidden: Integer;', '',
    'procedure TStock.Add;', 'begin', '  Inc(Hidden);', 'end;', '', 'end.']), 'TStock = class'), 'Hidden');
  Assert.Contains(Rejected(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class',
    '    procedure Add;', '  end;', '', 'implementation', '', 'procedure Helper;', 'begin', 'end;', '',
    'procedure TStock.Add;', 'begin', '  Helper;', 'end;', '', 'end.']), 'TStock = class'), 'implementation');
end;

procedure TMoveClassTests.RejectsCircularInterfaces;
begin
  Assert.Contains(Rejected(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '  end;', '',
    '  TStock = class(TBase)', '  end;', '', '  TStocks = array of TStock;', '', 'implementation', '', 'end.']),
    'TStock = class'), 'Kreisverweis');
end;

procedure TMoveClassTests.RejectsOtherCases;
var
  NewText, Origin, Reason: string;
begin
  // Formularklasse.
  Assert.Contains(Rejected(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class(TForm)', '  end;',
    '', 'implementation', '', '{$R *.dfm}', '', 'end.']), 'TStock = class'), 'Formular');
  // Bedingte Übersetzung um einen Rumpf.
  Assert.Contains(Rejected(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class',
    '    procedure Add;', '  end;', '', 'implementation', '', '{$IFDEF DEBUG}', 'procedure TStock.Add;', 'begin',
    'end;', '{$ENDIF}', '', 'end.']), 'TStock = class'), 'bedingt');
  // Kein Klassentyp an der Stelle, ungültiger Name.
  Assert.IsFalse(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TKind = (kA, kB);', '',
    'implementation', '', 'end.']), 'TKind', 'Stock', FakeLookup(), NewText, Origin, Reason));
  Assert.IsFalse(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class', '  end;', '',
    'implementation', '', 'end.']), 'TStock', 'Neue Unit', FakeLookup(), NewText, Origin, Reason));
  Assert.Contains(Reason, 'gültig');
end;

procedure TMoveClassTests.UpdatesUsingUnits;
var
  Text: string;
  Tree: TSyntaxTree;
  Edits: TArray<TTextEdit>;
begin
  Text := Join(['unit Kasse;', '', 'interface', '', 'uses', '  System.Classes,', '  Lager;', '', 'implementation',
    '', 'procedure Run;', 'var', '  S: Lager.TStock;', 'begin', '  S := TStock.Create;', 'end;', '', 'end.']);
  Tree := TPascalParser.Parse(Text);
  try
    Assert.IsTrue(TMoveClass.UpdateUser(Text, Tree, 'Lager', 'Stock', 'TStock', nil, True, Edits));
    Assert.AreEqual(Join(['unit Kasse;', '', 'interface', '', 'uses', '  System.Classes,', '  Lager,', '  Stock;',
      '', 'implementation', '', 'procedure Run;', 'var', '  S: Stock.TStock;', 'begin', '  S := TStock.Create;',
      'end;', '', 'end.']), TChangeSignature.ApplyEdits(Text, Edits));
    // Ohne Vorkommen keine Änderung.
    Assert.IsFalse(TMoveClass.UpdateUser(Text, Tree, 'Lager', 'Stock', 'TOther', nil, True, Edits));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMoveClassTests);

end.
