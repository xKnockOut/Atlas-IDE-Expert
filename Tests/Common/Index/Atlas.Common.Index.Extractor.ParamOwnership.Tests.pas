unit Atlas.Common.Index.Extractor.ParamOwnership.Tests;

// Tests der Besitz-Zusammenfassung im Symbolindex (TIndexSymbol.ParamOwnership): Deklaration und Implementierung,
// Methoden und Konstruktoren, Überladungen und der Weg durch den Index-Cache.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexParamOwnershipTests = class
  public
    [Test]
    procedure DeclarationAndImplementationCarryIt;
    [Test]
    procedure MethodsAndConstructors;
    [Test]
    procedure OverloadsWithParameterLists;
    [Test]
    procedure SurvivesTheCache;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Extractor;

const
  cHelfer = 'unit Helfer;'#10'interface'#10'uses System.Classes;'#10'type'#10'  THalter = class'#10 +
    '  private'#10'    FListe: TStrings;'#10'  public'#10'    constructor Create(AListe: TStrings);'#10 +
    '    procedure Lesen(AListe: TStrings);'#10'  end;'#10 +
    'procedure Zerlegen(const S: string; Teile: TStrings);'#10'procedure Weg(A: TObject); overload;'#10 +
    'procedure Weg(A: TObject; B: Integer); overload;'#10'implementation'#10 +
    'constructor THalter.Create(AListe: TStrings);'#10'begin'#10'  FListe := AListe;'#10'end;'#10 +
    'procedure THalter.Lesen(AListe: TStrings);'#10'begin'#10'  AListe.Clear;'#10'end;'#10 +
    'procedure Zerlegen(const S: string; Teile: TStrings);'#10'begin'#10'  Teile.Add(S);'#10'end;'#10 +
    'procedure Weg(A: TObject);'#10'begin'#10'  A.Free;'#10'end;'#10 +
    'procedure Weg(A: TObject; B: Integer);'#10'begin'#10'  Weg(A);'#10'end;'#10'end.';

/// <summary>ParamOwnership aller Symbole namens AName mit Container AContainer, mit '|' verbunden.</summary>
function Summaries(const AUnit: TUnitIndex; const AName, AContainer: string): string;
var
  mSymbol: TIndexSymbol;
begin
  Result := '';
  for mSymbol in AUnit.Symbols do
  begin
    if SameText(mSymbol.Name, AName) and SameText(mSymbol.Container, AContainer) then
    begin
      Result := Result + mSymbol.ParamOwnership + '|';
    end;
  end;
end;

procedure TIndexParamOwnershipTests.DeclarationAndImplementationCarryIt;
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(cHelfer, 'Helfer.pas', nil);
  Assert.AreEqual('-;b|-;b|', Summaries(mUnit, 'Zerlegen', ''));
end;

procedure TIndexParamOwnershipTests.MethodsAndConstructors;
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(cHelfer, 'Helfer.pas', nil);
  Assert.AreEqual('k|k|', Summaries(mUnit, 'Create', 'THalter'));
  Assert.AreEqual('b|b|', Summaries(mUnit, 'Lesen', 'THalter'));
end;

procedure TIndexParamOwnershipTests.OverloadsWithParameterLists;
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(cHelfer, 'Helfer.pas', nil);
  Assert.AreEqual('f|b>Weg#0;-|f|b>Weg#0;-|', Summaries(mUnit, 'Weg', ''));
end;

procedure TIndexParamOwnershipTests.SurvivesTheCache;
var
  mUnits: TArray<TUnitIndex>;
begin
  mUnits := TIndexCache.Deserialize(TIndexCache.Serialize([TIndexExtractor.ExtractText(cHelfer, 'Helfer.pas',
    nil)]));
  Assert.AreEqual(1, Integer(Length(mUnits)));
  Assert.AreEqual('-;b|-;b|', Summaries(mUnits[0], 'Zerlegen', ''));
  mUnits := nil;
end;

end.
