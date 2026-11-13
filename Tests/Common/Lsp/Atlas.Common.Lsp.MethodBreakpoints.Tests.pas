unit Atlas.Common.Lsp.MethodBreakpoints.Tests;

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Lsp.MethodBreakpoints;

type
  [TestFixture]
  TLspMethodBreakpointsTests = class
  private
    FIndex: ISymbolIndex;
    FTexts: TArray<string>;
    FFiles: TArray<string>;
    procedure AddUnit(const AFileName, AText: string; ALibrary: Boolean = False);
    function BodySource: TMethodBodySource;
    function Find(const APattern: string; const AOptions: TMethodBreakpointOptions): TArray<TMethodBreakpointHit>;
      overload;
    function Find(const APattern: string): TArray<TMethodBreakpointHit>; overload;
    function Names(const AHits: TArray<TMethodBreakpointHit>): string;
    function LineOf(const AMarker: string): Integer;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParsesPatterns;
    [Test]
    procedure RejectsInvalidPatterns;
    [Test]
    procedure MatchesWildcards;
    [Test]
    procedure WildcardFindsMethodsAndRoutines;
    [Test]
    procedure PlacesBreakpointOnFirstStatement;
    [Test]
    procedure AddsOverridesOfVirtualMatches;
    [Test]
    procedure OverridesOffDropsOverrideMethods;
    [Test]
    procedure OverloadsOffKeepsFirstDeclaration;
    [Test]
    procedure ParameterListPicksOverload;
    [Test]
    procedure InterfaceMemberFindsImplementations;
    [Test]
    procedure UnitPatternListsWholeUnit;
    [Test]
    procedure SkipsAbstractMethods;
    [Test]
    procedure WithoutSourceLineIsMissing;
    [Test]
    procedure LibraryOnlyWithExactQualifier;
    [Test]
    procedure TruncatesAtMaximum;
    [Test]
    procedure FirstLineSkipsTryLabelsAndDeclarations;
    [Test]
    procedure ReadsRequestAndWritesAnswer;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor;

const
  cKunden = 'C:\P\Kunden.pas';
  cAndere = 'C:\P\Andere.pas';
  cRtl = 'C:\Lib\Rtl.Basis.pas';

  UnitKunden =
    'unit Kunden;'#10 +
    'interface'#10 +
    'type'#10 +
    '  IAuftrag = interface'#10 +
    '    procedure Pruefe;'#10 +
    '  end;'#10 +
    '  TBasis = class(TInterfacedObject, IAuftrag)'#10 +
    '    procedure Pruefe; virtual;'#10 +
    '    procedure Validiere; virtual;'#10 +
    '    procedure ValidiereName(const A: string); overload;'#10 +
    '    procedure ValidiereName(A: Integer); overload;'#10 +
    '    procedure Abstrakt; virtual; abstract;'#10 +
    '  end;'#10 +
    '  TKunde = class(TBasis)'#10 +
    '    procedure Validiere; override;'#10 +
    '    procedure Speichere;'#10 +
    '  end;'#10 +
    '  TAndere = class(TInterfacedObject, IAuftrag)'#10 +
    '    procedure IAuftrag.Pruefe = Meine;'#10 +
    '    procedure Meine;'#10 +
    '  end;'#10 +
    'procedure FreiValidiere;'#10 +
    'implementation'#10 +
    'procedure TBasis.Pruefe;'#10 +
    'begin'#10 +
    '  Validiere; // basis-pruefe'#10 +
    'end;'#10 +
    'procedure TBasis.Validiere;'#10 +
    'var'#10 +
    '  X: Integer;'#10 +
    'begin'#10 +
    '  X := 1; // basis-validiere'#10 +
    'end;'#10 +
    'procedure TBasis.ValidiereName(const A: string);'#10 +
    'begin'#10 +
    '  Pruefe; // name-string'#10 +
    'end;'#10 +
    'procedure TBasis.ValidiereName(A: Integer);'#10 +
    'begin'#10 +
    '  Pruefe; // name-integer'#10 +
    'end;'#10 +
    'procedure TKunde.Validiere;'#10 +
    'begin'#10 +
    '  inherited; // kunde-validiere'#10 +
    'end;'#10 +
    'procedure TKunde.Speichere;'#10 +
    'begin'#10 +
    'end; // kunde-speichere'#10 +
    'procedure TAndere.Meine;'#10 +
    'begin'#10 +
    '  Exit; // andere-meine'#10 +
    'end;'#10 +
    'procedure FreiValidiere;'#10 +
    'begin'#10 +
    '  Exit; // frei-validiere'#10 +
    'end;'#10 +
    'procedure NurHier;'#10 +
    'begin'#10 +
    '  Exit; // nur-hier'#10 +
    'end;'#10 +
    'end.';

  UnitAndere =
    'unit Andere;'#10 +
    'interface'#10 +
    'uses Kunden;'#10 +
    'type'#10 +
    '  TSpezial = class(TKunde)'#10 +
    '    procedure Validiere; override;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TSpezial.Validiere;'#10 +
    'begin'#10 +
    '  inherited; // spezial-validiere'#10 +
    'end;'#10 +
    'end.';

  UnitRtl =
    'unit Rtl.Basis;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TListe = class'#10 +
    '    procedure Validiere;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TListe.Validiere;'#10 +
    'begin'#10 +
    '  Exit; // rtl-validiere'#10 +
    'end;'#10 +
    'end.';

{ TLspMethodBreakpointsTests }

procedure TLspMethodBreakpointsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  AddUnit(cKunden, UnitKunden);
  AddUnit(cAndere, UnitAndere);
  AddUnit(cRtl, UnitRtl, True);
end;

procedure TLspMethodBreakpointsTests.TearDown;
begin
  FIndex := nil;
  FTexts := nil;
  FFiles := nil;
end;

procedure TLspMethodBreakpointsTests.AddUnit(const AFileName, AText: string; ALibrary: Boolean);
var
  mUnit: TUnitIndex;
begin
  mUnit := TIndexExtractor.ExtractText(AText, AFileName, nil);
  mUnit.Library_ := ALibrary;
  FIndex.AddUnit(mUnit);
  FFiles := FFiles + [AFileName];
  FTexts := FTexts + [AText];
end;

function TLspMethodBreakpointsTests.BodySource: TMethodBodySource;
var
  mFiles, mTexts: TArray<string>;
begin
  mFiles := FFiles;
  mTexts := FTexts;
  Result :=
    function(const AFileName: string): TArray<TMethodBody>
    var
      mIndex: Integer;
      mTree: TSyntaxTree;
    begin
      Result := nil;
      for mIndex := 0 to High(mFiles) do
      begin
        if SameText(mFiles[mIndex], AFileName) then
        begin
          mTree := TSyntaxTreeCache.Parse(mTexts[mIndex]);
          try
            Result := TLspMethodBreakpoints.Bodies(mTree);
          finally
            mTree.Free;
          end;
        end;
      end;
    end;
end;

function TLspMethodBreakpointsTests.Find(const APattern: string;
  const AOptions: TMethodBreakpointOptions): TArray<TMethodBreakpointHit>;
var
  mPattern: TMethodPattern;
  mTruncated: Boolean;
begin
  Assert.IsTrue(TMethodPattern.Parse(APattern, FIndex, mPattern), APattern);
  Result := TLspMethodBreakpoints.Search(FIndex, mPattern, AOptions, BodySource, mTruncated);
end;

function TLspMethodBreakpointsTests.Find(const APattern: string): TArray<TMethodBreakpointHit>;
begin
  Result := Find(APattern, TMethodBreakpointOptions.Default);
end;

function TLspMethodBreakpointsTests.Names(const AHits: TArray<TMethodBreakpointHit>): string;
var
  mHit: TMethodBreakpointHit;
begin
  Result := '';
  for mHit in AHits do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    if mHit.Container <> '' then
    begin
      Result := Result + mHit.Container + '.';
    end;
    Result := Result + mHit.Name;
  end;
end;

function TLspMethodBreakpointsTests.LineOf(const AMarker: string): Integer;
var
  mText: string;
  mLines: TArray<string>;
  mLine: Integer;
begin
  for mText in FTexts do
  begin
    mLines := mText.Split([#10]);
    for mLine := 0 to High(mLines) do
    begin
      if Pos(AMarker, mLines[mLine]) > 0 then
      begin
        Exit(mLine);
      end;
    end;
  end;
  Result := -2;
end;

procedure TLspMethodBreakpointsTests.ParsesPatterns;
var
  mPattern: TMethodPattern;
begin
  Assert.IsTrue(TMethodPattern.Parse('TKunde.*', FIndex, mPattern));
  Assert.AreEqual('', mPattern.UnitName);
  Assert.AreEqual('TKunde', mPattern.ContainerMask);
  Assert.AreEqual('*', mPattern.NameMask);
  Assert.IsTrue(mPattern.Exact);

  Assert.IsTrue(TMethodPattern.Parse('*.Validiere*', FIndex, mPattern));
  Assert.AreEqual('*', mPattern.ContainerMask);
  Assert.AreEqual('Validiere*', mPattern.NameMask);
  Assert.IsFalse(mPattern.Exact);

  Assert.IsTrue(TMethodPattern.Parse('Validiere', FIndex, mPattern));
  Assert.AreEqual('*', mPattern.ContainerMask);
  Assert.IsFalse(mPattern.Exact);

  // Der Teil vor dem Namen ist eine Unit bzw. Unit und Typ.
  Assert.IsTrue(TMethodPattern.Parse('Rtl.Basis.*', FIndex, mPattern));
  Assert.AreEqual('Rtl.Basis', mPattern.UnitName);
  Assert.AreEqual('*', mPattern.ContainerMask);
  Assert.IsTrue(TMethodPattern.Parse('Rtl.Basis.TListe.Validiere', FIndex, mPattern));
  Assert.AreEqual('Rtl.Basis', mPattern.UnitName);
  Assert.AreEqual('TListe', mPattern.ContainerMask);

  Assert.IsTrue(TMethodPattern.Parse(' TKunde.Speichere(Integer, const B: string) ', FIndex, mPattern));
  Assert.IsTrue(mPattern.HasParams);
  Assert.AreEqual(2, Integer(Length(mPattern.ParamTypes)));
  Assert.AreEqual('Integer', mPattern.ParamTypes[0]);
  Assert.AreEqual('string', mPattern.ParamTypes[1]);
  Assert.IsTrue(TMethodPattern.Parse('TKunde.Speichere()', FIndex, mPattern));
  Assert.IsTrue(mPattern.HasParams);
  Assert.AreEqual(0, Integer(Length(mPattern.ParamTypes)));

  // Typargumente stören nicht, Umlaute sind Bezeichnerzeichen.
  Assert.IsTrue(TMethodPattern.Parse('TListe<T>.Prüfe', FIndex, mPattern));
  Assert.AreEqual('TListe', mPattern.ContainerMask);
  Assert.AreEqual('Prüfe', mPattern.NameMask);
end;

procedure TLspMethodBreakpointsTests.RejectsInvalidPatterns;
var
  mPattern: TMethodPattern;
begin
  Assert.IsFalse(TMethodPattern.Parse('', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('   ', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('TKunde..Speichere', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('TKunde.', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('TKunde-Speichere', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('TKunde.Speichere(Integer', FIndex, mPattern));
  Assert.IsFalse(TMethodPattern.Parse('TKunde.Speichere(A:)', FIndex, mPattern));
end;

procedure TLspMethodBreakpointsTests.MatchesWildcards;
begin
  Assert.IsTrue(TMethodPattern.Matches('Validiere*', 'ValidiereName'));
  Assert.IsTrue(TMethodPattern.Matches('validiere*', 'Validiere'));
  Assert.IsTrue(TMethodPattern.Matches('*Name', 'ValidiereName'));
  Assert.IsTrue(TMethodPattern.Matches('V?lidiere', 'Validiere'));
  Assert.IsTrue(TMethodPattern.Matches('*', ''));
  Assert.IsTrue(TMethodPattern.Matches('*a*e*', 'Validiere'));
  Assert.IsFalse(TMethodPattern.Matches('Validiere', 'ValidiereName'));
  Assert.IsFalse(TMethodPattern.Matches('?', ''));
  Assert.IsFalse(TMethodPattern.Matches('*x*', 'Validiere'));
end;

procedure TLspMethodBreakpointsTests.WildcardFindsMethodsAndRoutines;
var
  mHits: TArray<TMethodBreakpointHit>;
begin
  // Ohne Bibliotheken (TListe), Deklaration und Rumpf nur einmal, freie Routinen mit.
  mHits := Find('*.Validiere*');
  Assert.AreEqual('TSpezial.Validiere TBasis.Validiere TBasis.ValidiereName TBasis.ValidiereName ' +
    'TKunde.Validiere', Names(mHits));
  Assert.AreEqual(Names(mHits), Names(Find('validiere*')));
  Assert.AreEqual(Names(mHits) + ' FreiValidiere', Names(Find('*Validiere*')));
  // Überschreibungen auch aus anderen Units (TSpezial); sortiert nach Unit und Zeile.
  Assert.AreEqual('TSpezial.Validiere TKunde.Validiere TKunde.Speichere', Names(Find('TKunde.*')));
end;

procedure TLspMethodBreakpointsTests.PlacesBreakpointOnFirstStatement;
var
  mHits: TArray<TMethodBreakpointHit>;
begin
  mHits := Find('TBasis.Validiere');
  Assert.AreEqual('TSpezial.Validiere TBasis.Validiere TKunde.Validiere', Names(mHits));
  Assert.AreEqual(LineOf('basis-validiere'), mHits[1].Line);
  Assert.AreEqual(LineOf('procedure TBasis.Validiere;'), mHits[1].HeaderLine);
  Assert.AreEqual(LineOf('procedure Validiere; virtual;'), mHits[1].DeclarationLine);
  Assert.IsTrue(mHits[1].HasSource);
  Assert.StartsWith('procedure Validiere; virtual', mHits[1].Signature);
  // Leerer Rumpf: Zeile des end.
  mHits := Find('TKunde.Speichere');
  Assert.AreEqual(LineOf('kunde-speichere'), mHits[0].Line);
  // Routine nur im implementation-Teil.
  mHits := Find('NurHier');
  Assert.AreEqual('NurHier', Names(mHits));
  Assert.AreEqual(LineOf('nur-hier'), mHits[0].Line);
end;

procedure TLspMethodBreakpointsTests.AddsOverridesOfVirtualMatches;
var
  mHits: TArray<TMethodBreakpointHit>;
begin
  mHits := Find('TBasis.Validiere');
  Assert.AreEqual(3, Integer(Length(mHits)));
  Assert.IsTrue(mHits[1].Reason = TMethodHitReason.Match);
  Assert.AreEqual('', mHits[1].Via);
  Assert.IsTrue(mHits[2].Reason = TMethodHitReason.Override_);
  Assert.AreEqual('TBasis.Validiere', mHits[2].Via);
  // Über mehrere Stufen und Units hinweg.
  Assert.AreEqual('Andere', mHits[0].UnitName);
  Assert.IsTrue(mHits[0].Reason = TMethodHitReason.Override_);
  Assert.AreEqual(LineOf('spezial-validiere'), mHits[0].Line);
end;

procedure TLspMethodBreakpointsTests.OverridesOffDropsOverrideMethods;
var
  mOptions: TMethodBreakpointOptions;
begin
  mOptions := TMethodBreakpointOptions.Default;
  mOptions.Overrides := False;
  Assert.AreEqual('TBasis.Validiere', Names(Find('TBasis.Validiere', mOptions)));
  Assert.AreEqual('TBasis.Validiere TBasis.ValidiereName TBasis.ValidiereName FreiValidiere',
    Names(Find('*Validiere*', mOptions)));
end;

procedure TLspMethodBreakpointsTests.OverloadsOffKeepsFirstDeclaration;
var
  mOptions: TMethodBreakpointOptions;
  mHits: TArray<TMethodBreakpointHit>;
begin
  mHits := Find('TBasis.ValidiereName');
  Assert.AreEqual(2, Integer(Length(mHits)));
  Assert.AreEqual(LineOf('name-string'), mHits[0].Line);
  Assert.AreEqual(LineOf('name-integer'), mHits[1].Line);
  mOptions := TMethodBreakpointOptions.Default;
  mOptions.Overloads := False;
  mHits := Find('TBasis.ValidiereName', mOptions);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(LineOf('name-string'), mHits[0].Line);
end;

procedure TLspMethodBreakpointsTests.ParameterListPicksOverload;
var
  mOptions: TMethodBreakpointOptions;
  mHits: TArray<TMethodBreakpointHit>;
begin
  // Eine Parameterliste gilt auch mit ausgeschalteten Überladungen.
  mOptions := TMethodBreakpointOptions.Default;
  mOptions.Overloads := False;
  mHits := Find('TBasis.ValidiereName(integer)', mOptions);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(LineOf('name-integer'), mHits[0].Line);
  Assert.AreEqual(0, Integer(Length(Find('TBasis.ValidiereName(Double)'))));
end;

procedure TLspMethodBreakpointsTests.InterfaceMemberFindsImplementations;
var
  mHits: TArray<TMethodBreakpointHit>;
begin
  // TBasis setzt direkt um, TAndere über die Methodenzuordnung; der Interface-Member selbst hat keinen Rumpf.
  mHits := Find('IAuftrag.Pruefe');
  Assert.AreEqual('TBasis.Pruefe TAndere.Meine', Names(mHits));
  Assert.IsTrue(mHits[0].Reason = TMethodHitReason.Implementation_);
  Assert.AreEqual('IAuftrag.Pruefe', mHits[0].Via);
  Assert.AreEqual(LineOf('basis-pruefe'), mHits[0].Line);
  Assert.AreEqual(LineOf('andere-meine'), mHits[1].Line);
  Assert.AreEqual('TBasis.Pruefe TAndere.Meine', Names(Find('IAuftrag.*')));
end;

procedure TLspMethodBreakpointsTests.UnitPatternListsWholeUnit;
begin
  Assert.AreEqual('TSpezial.Validiere', Names(Find('Andere.*')));
  Assert.AreEqual('TSpezial.Validiere TKunde.Validiere', Names(Find('Kunden.TKunde.Validiere')));
  Assert.AreEqual('TSpezial.Validiere TBasis.Pruefe TBasis.Validiere TBasis.ValidiereName TBasis.ValidiereName ' +
    'TKunde.Validiere TKunde.Speichere TAndere.Meine FreiValidiere NurHier', Names(Find('Kunden.*')));
end;

procedure TLspMethodBreakpointsTests.SkipsAbstractMethods;
begin
  Assert.AreEqual('', Names(Find('*.Abstrakt')));
end;

procedure TLspMethodBreakpointsTests.WithoutSourceLineIsMissing;
var
  mPattern: TMethodPattern;
  mHits: TArray<TMethodBreakpointHit>;
  mTruncated: Boolean;
begin
  Assert.IsTrue(TMethodPattern.Parse('TKunde.Speichere', FIndex, mPattern));
  mHits := TLspMethodBreakpoints.Search(FIndex, mPattern, TMethodBreakpointOptions.Default, nil, mTruncated);
  Assert.AreEqual(1, Integer(Length(mHits)));
  Assert.AreEqual(-1, mHits[0].Line);
  Assert.AreEqual(-1, mHits[0].HeaderLine);
  Assert.IsFalse(mHits[0].HasSource);
end;

procedure TLspMethodBreakpointsTests.LibraryOnlyWithExactQualifier;
var
  mHits: TArray<TMethodBreakpointHit>;
begin
  mHits := Find('TListe.Validiere');
  Assert.AreEqual('TListe.Validiere', Names(mHits));
  Assert.AreEqual(LineOf('rtl-validiere'), mHits[0].Line);
  Assert.AreEqual('', Names(Find('TList*.Validiere')));
end;

procedure TLspMethodBreakpointsTests.TruncatesAtMaximum;
var
  mPattern: TMethodPattern;
  mOptions: TMethodBreakpointOptions;
  mHits: TArray<TMethodBreakpointHit>;
  mTruncated: Boolean;
begin
  Assert.IsTrue(TMethodPattern.Parse('*.Validiere*', FIndex, mPattern));
  mOptions := TMethodBreakpointOptions.Default;
  mOptions.MaxHits := 2;
  mHits := TLspMethodBreakpoints.Search(FIndex, mPattern, mOptions, BodySource, mTruncated);
  Assert.AreEqual(2, Integer(Length(mHits)));
  Assert.IsTrue(mTruncated);
  mOptions.MaxHits := 100;
  TLspMethodBreakpoints.Search(FIndex, mPattern, mOptions, BodySource, mTruncated);
  Assert.IsFalse(mTruncated);
end;

procedure TLspMethodBreakpointsTests.FirstLineSkipsTryLabelsAndDeclarations;
const
  cText =
    'unit U;'#10 +                       // 0
    'interface'#10 +                     // 1
    'implementation'#10 +                // 2
    'procedure A;'#10 +                  // 3
    'label L;'#10 +                      // 4
    'begin'#10 +                         // 5
    '  var X: Integer;'#10 +             // 6
    '  ;'#10 +                           // 7
    '  try'#10 +                         // 8
    '    begin'#10 +                     // 9
    '      L: X := 1;'#10 +              // 10
    '    end;'#10 +                      // 11
    '  finally'#10 +                     // 12
    '  end;'#10 +                        // 13
    'end;'#10 +                          // 14
    'procedure B;'#10 +                  // 15
    'begin'#10 +                         // 16
    '  var Y := 2;'#10 +                 // 17
    'end;'#10 +                          // 18
    'procedure C;'#10 +                  // 19
    'begin'#10 +                         // 20
    '  try'#10 +                         // 21
    '  finally'#10 +                     // 22
    '    C;'#10 +                        // 23
    '  end;'#10 +                        // 24
    '  repeat'#10 +                      // 25
    '    C;'#10 +                        // 26
    '  until True;'#10 +                 // 27
    'end;'#10 +                          // 28
    'procedure D;'#10 +                  // 29
    '  procedure Lokal;'#10 +            // 30
    '  begin'#10 +                       // 31
    '  end;'#10 +                        // 32
    'begin'#10 +                         // 33
    '  repeat'#10 +                      // 34
    '    Lokal;'#10 +                    // 35
    '  until False;'#10 +                // 36
    'end;'#10 +                          // 37
    'end.';
var
  mTree: TSyntaxTree;
  mBodies: TArray<TMethodBody>;
begin
  mTree := TSyntaxTreeCache.Parse(cText);
  try
    mBodies := TLspMethodBreakpoints.Bodies(mTree);
  finally
    mTree.Free;
  end;
  // Lokale Routinen zählen nicht.
  Assert.AreEqual(4, Integer(Length(mBodies)));
  Assert.AreEqual('A', mBodies[0].Name);
  Assert.AreEqual(3, mBodies[0].HeaderLine);
  Assert.AreEqual(10, mBodies[0].Line);
  Assert.AreEqual(17, mBodies[1].Line);
  Assert.AreEqual(23, mBodies[2].Line);
  Assert.AreEqual('D', mBodies[3].Name);
  Assert.AreEqual(35, mBodies[3].Line);
end;

procedure TLspMethodBreakpointsTests.ReadsRequestAndWritesAnswer;
var
  mArguments: TJSONArray;
  mPattern: string;
  mOptions: TMethodBreakpointOptions;
  mAnswer: TJSONObject;
  mHit: TJSONObject;
begin
  mArguments := TJSONObject.ParseJSONValue('[{"pattern": "TBasis.*", "overrides": false}]') as TJSONArray;
  try
    Assert.IsTrue(TLspMethodBreakpoints.ReadRequest(mArguments, mPattern, mOptions));
    Assert.AreEqual('TBasis.*', mPattern);
    Assert.IsFalse(mOptions.Overrides);
    Assert.IsTrue(mOptions.Overloads);
  finally
    mArguments.Free;
  end;
  mArguments := TJSONObject.ParseJSONValue('[{"muster": "x"}]') as TJSONArray;
  try
    Assert.IsFalse(TLspMethodBreakpoints.ReadRequest(mArguments, mPattern, mOptions));
  finally
    mArguments.Free;
  end;
  Assert.IsFalse(TLspMethodBreakpoints.ReadRequest(nil, mPattern, mOptions));

  mAnswer := TLspMethodBreakpoints.ToJson('IAuftrag.Pruefe', Find('IAuftrag.Pruefe'), False);
  try
    Assert.AreEqual(1, (mAnswer.GetValue('format') as TJSONNumber).AsInt);
    Assert.AreEqual(2, (mAnswer.GetValue('hits') as TJSONArray).Count);
    mHit := (mAnswer.GetValue('hits') as TJSONArray).Items[0] as TJSONObject;
    Assert.AreEqual('Kunden', mHit.GetValue('unit').Value);
    Assert.AreEqual('TBasis', mHit.GetValue('container').Value);
    Assert.AreEqual('Pruefe', mHit.GetValue('name').Value);
    Assert.AreEqual('implementation', mHit.GetValue('reason').Value);
    Assert.AreEqual('IAuftrag.Pruefe', mHit.GetValue('via').Value);
    Assert.AreEqual(LineOf('basis-pruefe'), (mHit.GetValue('line') as TJSONNumber).AsInt);
    Assert.IsTrue((mHit.GetValue('source') as TJSONBool).AsBoolean);
  finally
    mAnswer.Free;
  end;
  mAnswer := TLspMethodBreakpoints.ErrorToJson(TLspMethodBreakpoints.InvalidPattern('a..b'));
  try
    Assert.IsTrue(mAnswer.GetValue('error').Value.EndsWith('a..b'));
  finally
    mAnswer.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspMethodBreakpointsTests);

end.
