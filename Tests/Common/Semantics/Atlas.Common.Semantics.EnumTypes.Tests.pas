unit Atlas.Common.Semantics.EnumTypes.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract;

type
  [TestFixture]
  TEnumTypesTests = class
  private
    FIndex: ISymbolIndex;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    /// <summary>case über eine Aufzählung: alle Werte in Deklarationsreihenfolge, ohne Präfix.</summary>
    [Test]
    procedure CaseValuesOfEnum;
    /// <summary>{$SCOPEDENUMS ON} an der Deklaration: Präfix mit dem Typnamen.</summary>
    [Test]
    procedure CaseValuesScoped;
    /// <summary>case über eine Zahl: keine Aufzählung.</summary>
    [Test]
    procedure CaseValuesWithoutEnum;
    /// <summary>Am Wert eines Aufzählungstyps alle Werte des Typs.</summary>
    [Test]
    procedure EnumValuesAtMember;
    /// <summary>Mengentyp: die Werte des Elementtyps, als Menge erkannt.</summary>
    [Test]
    procedure EnumOfTypeFollowsSet;
    /// <summary>Bereichstext über mehrere Zeilen: ab dem Anfang, Folgezeilen ganz.</summary>
    [Test]
    procedure RangeTextAcrossLines;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.EnumTypes;

const
  cFileName = 'C:\P\Haupt.pas';
  cText =
    'unit Haupt;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TModus = (mLesen, mSchreiben, mAnhaengen);'#10 +
    '  TModi = set of TModus;'#10 +
    '{$SCOPEDENUMS ON}'#10 +
    '  TArt = (Klein, Gross);'#10 +
    '{$SCOPEDENUMS OFF}'#10 +
    '  TDatei = class'#10 +
    '  public'#10 +
    '    Modus: TModus;'#10 +
    '    Art: TArt;'#10 +
    '    Zahl: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure Rechne(D: TDatei);'#10 +
    'begin'#10 +
    '  D.Modus := mSchreiben;'#10 +
    '  case D.Modus of'#10 +
    '  end;'#10 +
    '  case D.Art of'#10 +
    '  end;'#10 +
    '  case D.Zahl of'#10 +
    '  end;'#10 +
    'end;'#10 +
    'end.';

/// <summary>Position am Ende von AMarker in cText.</summary>
function PositionAfter(const AMarker: string): TTextPosition;
var
  mEnd, mLine, mLineStart, mIndex: Integer;
begin
  mEnd := Pos(AMarker, cText) + Length(AMarker) - 1;
  mLine := 0;
  mLineStart := 0;
  for mIndex := 1 to mEnd do
  begin
    if cText[mIndex] = #10 then
    begin
      Inc(mLine);
      mLineStart := mIndex;
    end;
  end;
  Result := TTextPosition.Create(mLine, mEnd - mLineStart);
end;

type
  /// <summary>Prüfung mit dem Lookup über cText.</summary>
  TLookupCheck = reference to procedure(const ALookup: TEnumLookup);

procedure WithLookup(const AIndex: ISymbolIndex; const ACheck: TLookupCheck);
var
  mLookup: TEnumLookup;
  mTree: TSyntaxTree;
  mResolver: TNameResolver;
begin
  AIndex.AddUnit(TIndexExtractor.ExtractText(cText, cFileName, nil));
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mResolver := TNameResolver.Create(AIndex);
    try
      mLookup := Default(TEnumLookup);
      mLookup.Resolver := mResolver;
      mLookup.Index := AIndex;
      mLookup.Tree := mTree;
      mLookup.Text := cText;
      mLookup.FileName := cFileName;
      ACheck(mLookup);
    finally
      mResolver.Free;
    end;
  finally
    mTree.Free;
  end;
end;

{ TEnumTypesTests }

procedure TEnumTypesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
end;

procedure TEnumTypesTests.TearDown;
begin
  FIndex := nil;
end;

procedure TEnumTypesTests.CaseValuesOfEnum;
begin
  WithLookup(FIndex,
    procedure(const ALookup: TEnumLookup)
    var
      mValues: TArray<string>;
      mPrefix: string;
    begin
      Assert.IsTrue(TEnumTypes.CaseValues(ALookup, PositionAfter('case D.Modus of'), mValues, mPrefix));
      Assert.AreEqual('mLesen,mSchreiben,mAnhaengen', string.Join(',', mValues));
      Assert.AreEqual('', mPrefix);
    end);
end;

procedure TEnumTypesTests.CaseValuesScoped;
begin
  WithLookup(FIndex,
    procedure(const ALookup: TEnumLookup)
    var
      mValues: TArray<string>;
      mPrefix: string;
    begin
      Assert.IsTrue(TEnumTypes.CaseValues(ALookup, PositionAfter('case D.Art of'), mValues, mPrefix));
      Assert.AreEqual('Klein,Gross', string.Join(',', mValues));
      Assert.AreEqual('TArt.', mPrefix);
    end);
end;

procedure TEnumTypesTests.CaseValuesWithoutEnum;
begin
  WithLookup(FIndex,
    procedure(const ALookup: TEnumLookup)
    var
      mValues: TArray<string>;
      mPrefix: string;
    begin
      Assert.IsFalse(TEnumTypes.CaseValues(ALookup, PositionAfter('case D.Zahl of'), mValues, mPrefix));
      Assert.AreEqual(0, Integer(Length(mValues)));
    end);
end;

procedure TEnumTypesTests.EnumValuesAtMember;
begin
  WithLookup(FIndex,
    procedure(const ALookup: TEnumLookup)
    var
      mValues: TArray<string>;
    begin
      Assert.IsTrue(TEnumTypes.EnumValuesAt(ALookup, PositionAfter('D.Modus := mSch'), mValues));
      Assert.AreEqual('mLesen,mSchreiben,mAnhaengen', string.Join(',', mValues));
      Assert.IsFalse(TEnumTypes.EnumValuesAt(ALookup, PositionAfter('procedure Rech'), mValues));
    end);
end;

procedure TEnumTypesTests.EnumOfTypeFollowsSet;
begin
  WithLookup(FIndex,
    procedure(const ALookup: TEnumLookup)
    var
      mValues: TArray<string>;
      mIsSet: Boolean;
      mPrefix: string;
    begin
      Assert.IsTrue(TEnumTypes.EnumOfType(ALookup, Pos('D.Modus :=', cText) - 1, 'TModi', mValues, mIsSet,
        mPrefix));
      Assert.AreEqual('mLesen,mSchreiben,mAnhaengen', string.Join(',', mValues));
      Assert.IsTrue(mIsSet);
      Assert.IsTrue(TEnumTypes.EnumOfType(ALookup, Pos('D.Modus :=', cText) - 1, 'TModus', mValues, mIsSet,
        mPrefix));
      Assert.IsFalse(mIsSet);
      Assert.IsFalse(TEnumTypes.EnumOfType(ALookup, Pos('D.Modus :=', cText) - 1, 'TDatei', mValues, mIsSet,
        mPrefix));
    end);
end;

procedure TEnumTypesTests.RangeTextAcrossLines;
begin
  // Ab dem Anfang des Bereichs, Folgezeilen ganz.
  Assert.AreEqual('b'#10'cde', TEnumTypes.RangeText('ab'#10'cde', TTextRange.Create(0, 1, 1, 2)));
end;

initialization
  TDUnitX.RegisterTestFixture(TEnumTypesTests);

end.
