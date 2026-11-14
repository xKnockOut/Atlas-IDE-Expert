unit Atlas.Common.Editing.MoveClass.Tests;

// Tests für „Klasse in eigene Unit verschieben“ (#103 Teil B): neue Unit samt
// uses aus den benötigten Namen, Änderungen an der Ursprungs-Unit und an
// verwendenden Units, Ablehnungsgründe, Typkommentar (#1838). Vorher und
// Nachher müssen parsen.

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
    [Test]
    procedure MovesTypeComment;
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
  mIndex: Integer;
begin
  Result := '';
  for mIndex := 0 to High(ALines) do
  begin
    Result := Result + ALines[mIndex] + #10;
  end;
end;

procedure CheckParses(const AText: string);
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(AText);
  try
    Assert.AreEqual(0, Integer(Length(mTree.Diagnostics)), AText);
  finally
    mTree.Free;
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
      begin
        Result.UnitName := 'System.Classes';
      end
      else if MatchText(Name, ['Format', 'IntToStr']) then
      begin
        Result.UnitName := 'System.SysUtils';
      end
      else if MatchText(Name, ['Integer', 'string', 'TObject', 'Inc']) then
      begin
        Result.UnitName := 'System';
      end;
      Result.Found := Result.UnitName <> '';
    end;
end;

type
  /// <summary>Ziel-Unit einer Verschiebung und das Lookup für die Units, die sie verwenden.</summary>
  TMoveTarget = record
    NewUnit: string;
    Lookup: TMoveClassLookup;
  end;

function Into(const ANewUnit: string; const ALookup: TMoveClassLookup): TMoveTarget;
begin
  Result := Default(TMoveTarget);
  Result.NewUnit := ANewUnit;
  Result.Lookup := ALookup;
end;

/// <summary>Verschiebt die Klasse auf der Zeile mit AMarker nach ATarget; '-' mit Grund, sonst neue Unit und
/// geänderte Ursprungs-Unit.</summary>
function Relocate(const AText, AMarker: string; const ATarget: TMoveTarget; out ANewText, AOrigin,
  AReason: string): Boolean; overload;
var
  mTree: TSyntaxTree;
  mPlan: TMoveClassPlan;
  mLine, mIndex: Integer;
begin
  ANewText := '';
  AOrigin := '';
  CheckParses(AText);
  mLine := 0;
  for mIndex := 1 to Pos(AMarker, AText) - 1 do
  begin
    if AText[mIndex] = #10 then
    begin
      Inc(mLine);
    end;
  end;
  mTree := TPascalParser.Parse(AText);
  try
    Result := TMoveClass.Plan(TMoveClassSource.Create('lager.pas', AText, mTree), TTextPosition.Create(mLine, 4),
      ATarget.NewUnit, ATarget.Lookup, mPlan, AReason);
    if not Result then
    begin
      Exit;
    end;
    ANewText := mPlan.Text;
    AOrigin := TChangeSignature.ApplyEdits(AText, mPlan.OriginEdits);
    CheckParses(ANewText);
    CheckParses(AOrigin);
  finally
    mTree.Free;
  end;
end;

function Relocate(const AText, AMarker: string; out ANewText, AOrigin: string): Boolean; overload;
var
  mReason: string;
begin
  Result := Relocate(AText, AMarker, Into('Stock', FakeLookup()), ANewText, AOrigin, mReason);
  Assert.IsTrue(Result, mReason);
end;

function Rejected(const AText, AMarker: string): string;
var
  mNewText, mOrigin: string;
begin
  Assert.IsFalse(Relocate(AText, AMarker, Into('Stock', FakeLookup()), mNewText, mOrigin, Result));
end;

procedure TMoveClassTests.DefaultUnitNameDropsT;
begin
  Assert.AreEqual('Kunde', TMoveClass.DefaultUnitName('TKunde'));
  Assert.AreEqual('Table', TMoveClass.DefaultUnitName('Table'));
  Assert.AreEqual('Tx', TMoveClass.DefaultUnitName('Tx'));
end;

procedure TMoveClassTests.MovesClassWithMethods;
var
  mNewText, mOrigin: string;
begin
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '',
    'type', '  TBase = class', '  end;', '', '  /// <summary>Bestand.</summary>', '  TStock = class', '  private',
    '    FItems: TStrings;', '  public', '    function Count: Integer;', '    procedure Add(const AName: string);',
    '  end;', '', 'implementation', '', 'function TStock.Count: Integer;', 'begin', '  Result := FItems.Count;',
    'end;', '', 'procedure TStock.Add(const AName: string);', 'var', '  N: Integer;', 'begin', '  N := 1;',
    '  FItems.Add(Format(''%s %d'', [AName, N]));', 'end;', '', 'procedure Run;', 'begin', '  TStock.Create.Free;',
    'end;', '', 'end.']), 'TStock = class', mNewText, mOrigin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'uses', '  System.Classes;', '', 'type',
    '  /// <summary>Bestand.</summary>', '  TStock = class', '  private', '    FItems: TStrings;', '  public',
    '    function Count: Integer;', '    procedure Add(const AName: string);', '  end;', '', 'implementation', '',
    'uses', '  System.SysUtils;', '', 'function TStock.Count: Integer;', 'begin', '  Result := FItems.Count;',
    'end;', '', 'procedure TStock.Add(const AName: string);', 'var', '  N: Integer;', 'begin', '  N := 1;',
    '  FItems.Add(Format(''%s %d'', [AName, N]));', 'end;', '', 'end.']), mNewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'uses', '  System.SysUtils, System.Classes;', '',
    'type', '  TBase = class', '  end;', '', 'implementation', '', 'uses', '  Stock;', '', 'procedure Run;',
    'begin', '  TStock.Create.Free;', 'end;', '', 'end.']), mOrigin);
end;

procedure TMoveClassTests.MovesTypeComment;
var
  mNewText, mOrigin: string;
begin
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '    procedure Go;',
    '  end;', '', '  TStock = class', '    function Count: Integer;', '  end;', '', 'implementation', '',
    '{ TBase }', '', 'procedure TBase.Go;', 'begin', 'end;', '', '{ TStock }', '', 'function TStock.Count: Integer;',
    'begin', '  Result := 0;', 'end;', '', 'end.']), 'TStock = class', mNewText, mOrigin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'type', '  TStock = class',
    '    function Count: Integer;', '  end;', '', 'implementation', '', '{ TStock }', '',
    'function TStock.Count: Integer;', 'begin', '  Result := 0;', 'end;', '', 'end.']), mNewText,
    'Kommentar steht in der neuen Unit vor den Rümpfen (#1838)');
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '    procedure Go;',
    '  end;', '', 'implementation', '', '{ TBase }', '', 'procedure TBase.Go;', 'begin', 'end;', '', 'end.']),
    mOrigin, 'kein { TStock } bleibt zurück');
end;

procedure TMoveClassTests.UsesOriginInterface;
var
  mNewText, mOrigin: string;
begin
  // TBase und Max aus dem interface: Die neue Unit bindet Lager ein, Lager die neue Unit im implementation.
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '  end;', '',
    '  TStock = class(TBase)', '    function Count: Integer;', '  end;', '', 'const', '  Max = 10;', '',
    'implementation', '', 'uses', '  Helpers;', '', 'function TStock.Count: Integer;', 'begin', '  Result := Max;',
    'end;', '', 'initialization', '  TStock.Create.Free;', 'end.']), 'TStock = class', mNewText, mOrigin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'uses', '  Lager;', '', 'type',
    '  TStock = class(TBase)', '    function Count: Integer;', '  end;', '', 'implementation', '',
    'function TStock.Count: Integer;', 'begin', '  Result := Max;', 'end;', '', 'end.']), mNewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'type', '  TBase = class', '  end;', '', 'const',
    '  Max = 10;', '', 'implementation', '', 'uses', '  Helpers,', '  Stock;', '', 'initialization',
    '  TStock.Create.Free;', 'end.']), mOrigin);
end;

procedure TMoveClassTests.RemovesTypeSectionForwardAndAttributes;
var
  mNewText, mOrigin: string;
begin
  // Nur noch die Vorwärtsdeklaration und die Klasse im Typabschnitt: Er entfällt ganz.
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class;', '',
    '  // Lagerbestand', '  [Serializable]', '  TStock = class', '  end;', '', 'implementation', '', 'end.']),
    'TStock = class' + #10, mNewText, mOrigin));
  Assert.AreEqual(Join(['unit Stock;', '', 'interface', '', 'type', '  // Lagerbestand', '  [Serializable]',
    '  TStock = class', '  end;', '', 'implementation', '', 'end.']), mNewText);
  Assert.AreEqual(Join(['unit Lager;', '', 'interface', '', 'implementation', '', 'end.']), mOrigin);
end;

procedure TMoveClassTests.WithoutLookupCopiesUses;
var
  mNewText, mOrigin, mReason: string;
begin
  Assert.IsTrue(Relocate(Join(['unit Lager;', '', 'interface', '', 'uses', '  Classes;', '', 'type',
    '  TStock = class', '    FItems: TStrings;', '    procedure Add;', '  end;', '', 'implementation', '', 'uses',
    '  SysUtils;', '', 'procedure TStock.Add;', 'begin', '  FItems.Add(IntToStr(1));', 'end;', '', 'end.']),
    'TStock = class', Into('Lager.Stock', nil), mNewText, mOrigin, mReason), mReason);
  Assert.AreEqual(Join(['unit Lager.Stock;', '', 'interface', '', 'uses', '  Classes;', '', 'type',
    '  TStock = class', '    FItems: TStrings;', '    procedure Add;', '  end;', '', 'implementation', '', 'uses',
    '  SysUtils;', '', 'procedure TStock.Add;', 'begin', '  FItems.Add(IntToStr(1));', 'end;', '', 'end.']), mNewText);
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
  mNewText, mOrigin, mReason: string;
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
    'implementation', '', 'end.']), 'TKind', Into('Stock', FakeLookup()), mNewText, mOrigin, mReason));
  Assert.IsFalse(Relocate(Join(['unit Lager;', '', 'interface', '', 'type', '  TStock = class', '  end;', '',
    'implementation', '', 'end.']), 'TStock', Into('Neue Unit', FakeLookup()), mNewText, mOrigin, mReason));
  Assert.Contains(mReason, 'gültig');
end;

procedure TMoveClassTests.UpdatesUsingUnits;
var
  mText: string;
  mTree: TSyntaxTree;
  mEdits: TArray<TTextEdit>;
begin
  mText := Join(['unit Kasse;', '', 'interface', '', 'uses', '  System.Classes,', '  Lager;', '', 'implementation',
    '', 'procedure Run;', 'var', '  S: Lager.TStock;', 'begin', '  S := TStock.Create;', 'end;', '', 'end.']);
  mTree := TPascalParser.Parse(mText);
  try
    Assert.IsTrue(TMoveClass.UpdateUser(mText, mTree, TMoveClassNames.Create('Lager', 'Stock', 'TStock'), nil, True,
      mEdits));
    Assert.AreEqual(Join(['unit Kasse;', '', 'interface', '', 'uses', '  System.Classes,', '  Lager,', '  Stock;',
      '', 'implementation', '', 'procedure Run;', 'var', '  S: Stock.TStock;', 'begin', '  S := TStock.Create;',
      'end;', '', 'end.']), TChangeSignature.ApplyEdits(mText, mEdits));
    // Ohne Vorkommen keine Änderung.
    Assert.IsFalse(TMoveClass.UpdateUser(mText, mTree, TMoveClassNames.Create('Lager', 'Stock', 'TOther'), nil, True,
      mEdits));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TMoveClassTests);

end.
