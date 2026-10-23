unit Atlas.Common.Pascal.WarningCodes.Tests;

// Tests für die Zuordnung Meldungsnummer → {$WARN}-Bezeichner (#531).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TWarningCodesTests = class
  public
    /// <summary>Beispiele aus dem Issue: W1000 → SYMBOL_DEPRECATED, W1002 → SYMBOL_PLATFORM.</summary>
    [Test]
    procedure MapsKnownCodes;
    [Test]
    procedure IgnoresCaseAndSpaces;
    [Test]
    procedure UnknownCodeHasNoIdentifier;
    /// <summary>Ältere Version kennt den Bezeichner noch nicht; ohne gültige Version gilt die aktuelle.</summary>
    [Test]
    procedure RespectsDelphiVersion;
    [Test]
    procedure KindOfCodes;
    [Test]
    procedure RoutineWideCodes;
    /// <summary>Jeder Bezeichner der Tabelle ist ein gültiger {$WARN}-Name, keine Nummer doppelt.</summary>
    [Test]
    procedure TableIsConsistent;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.DirectiveNames,
  Atlas.Common.Pascal.WarningCodes;

procedure TWarningCodesTests.MapsKnownCodes;
begin
  Assert.AreEqual('SYMBOL_DEPRECATED', TWarningCodes.Identifier('W1000', ''));
  Assert.AreEqual('SYMBOL_PLATFORM', TWarningCodes.Identifier('W1002', ''));
  Assert.AreEqual('NO_RETVAL', TWarningCodes.Identifier('W1035', ''));
  Assert.AreEqual('IMPLICIT_STRING_CAST', TWarningCodes.Identifier('W1057', '37.0'));
  Assert.AreEqual('XML_NO_MATCHING_PARM', TWarningCodes.Identifier('W1208', '23.0'));
end;

procedure TWarningCodesTests.IgnoresCaseAndSpaces;
begin
  Assert.AreEqual('SYMBOL_DEPRECATED', TWarningCodes.Identifier(' w1000 ', ''));
end;

procedure TWarningCodesTests.UnknownCodeHasNoIdentifier;
begin
  Assert.AreEqual('', TWarningCodes.Identifier('W1999', ''));
  Assert.AreEqual('', TWarningCodes.Identifier('H2164', ''));
  Assert.AreEqual('', TWarningCodes.Identifier('E2003', ''));
  Assert.AreEqual('', TWarningCodes.Identifier('', ''));
end;

procedure TWarningCodesTests.RespectsDelphiVersion;
begin
  Assert.AreEqual('22.0', TWarningCodes.Since('W1071'));
  Assert.AreEqual('', TWarningCodes.Identifier('W1071', '21.0'), 'Delphi 10.4: noch ohne Bezeichner');
  Assert.AreEqual('IMPLICIT_INTEGER_CAST_LOSS', TWarningCodes.Identifier('W1071', '22.0'));
  Assert.AreEqual('IMPLICIT_INTEGER_CAST_LOSS', TWarningCodes.Identifier('W1071', ''), 'ohne Version: aktuell');
  Assert.AreEqual('IMPLICIT_INTEGER_CAST_LOSS', TWarningCodes.Identifier('W1071', 'kaputt'));
  Assert.AreEqual('', TWarningCodes.Identifier('W1057', '5.0'), 'vor Delphi 2009');
  Assert.AreEqual('SYMBOL_DEPRECATED', TWarningCodes.Identifier('W1000', '5.0'));
end;

procedure TWarningCodesTests.KindOfCodes;
begin
  Assert.IsTrue(TWarningCodes.KindOf('H2164') = TWarningCodeKind.Hint);
  Assert.IsTrue(TWarningCodes.KindOf('w1000') = TWarningCodeKind.Warning);
  Assert.IsTrue(TWarningCodes.KindOf('W9999') = TWarningCodeKind.Warning, 'unbekannte Warnung bleibt Warnung');
  Assert.IsTrue(TWarningCodes.KindOf('E2003') = TWarningCodeKind.None);
  Assert.IsTrue(TWarningCodes.KindOf('F2613') = TWarningCodeKind.None);
  Assert.IsTrue(TWarningCodes.KindOf('W10') = TWarningCodeKind.None);
  Assert.IsTrue(TWarningCodes.KindOf('W10x0') = TWarningCodeKind.None);
end;

procedure TWarningCodesTests.RoutineWideCodes;
begin
  Assert.IsTrue(TWarningCodes.IsRoutineWide('H2164'));
  Assert.IsTrue(TWarningCodes.IsRoutineWide('h2077'));
  Assert.IsTrue(TWarningCodes.IsRoutineWide('W1035'));
  Assert.IsFalse(TWarningCodes.IsRoutineWide('W1000'));
end;

procedure TWarningCodesTests.TableIsConsistent;
var
  Seen: TDictionary<string, Boolean>;
  Code, Name: string;
begin
  Seen := TDictionary<string, Boolean>.Create;
  try
    for Code in TWarningCodes.Codes do
    begin
      Assert.IsFalse(Seen.ContainsKey(Code), 'doppelt: ' + Code);
      Seen.Add(Code, True);
      Assert.IsTrue(TWarningCodes.KindOf(Code) = TWarningCodeKind.Warning, Code);
      Name := TWarningCodes.Identifier(Code, '');
      Assert.IsTrue(TDirectiveNames.IsWarning(Name), Code + ' → ' + Name);
    end;
    Assert.IsTrue(Seen.Count >= 70);
  finally
    Seen.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TWarningCodesTests);

end.
