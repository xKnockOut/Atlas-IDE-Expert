unit Atlas.Common.Lsp.References.Tests;

// Tests für die Referenzsuche (#29).

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Lsp.References;

type
  [TestFixture]
  TLspReferencesTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function FindAt(const AMarker: string; ADeclaration: Boolean): TArray<TReferenceLocation>;
    function Describe(const ALocations: TArray<TReferenceLocation>): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure FindsUsesAcrossUnits;
    [Test]
    procedure WithoutDeclaration;
    [Test]
    procedure IncludesFormReferences;
    [Test]
    procedure ReadsDfmEventsAndObjects;
    [Test]
    procedure NothingOutsideIdentifiers;
    /// <summary>Viele Vorkommen in einer Datei, Ergebnis vollständig und in Reihenfolge.</summary>
    [Test]
    procedure FindManyOccurrencesSameResult;
    /// <summary>Find pinnt Fremdbäume über dem Baum des Aufrufers und löst nur diese; danach
    /// ist der Baum des Aufrufers weiter gepinnt, ohne Aufrufer-Pin ist nichts mehr gepinnt.</summary>
    [Test]
    procedure FindResolverStaysPinnedAfterForeignTree;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Dfm.FormModel;

const
  cWerkzeugFile = 'C:\P\Werkzeug.pas';
  cWerkzeugDfm = 'C:\P\Werkzeug.dfm';
  cHauptFile = 'C:\P\Haupt.pas';

  cUnitWerkzeug =
    'unit Werkzeug;'#10 +                            // 0
    'interface'#10 +                                 // 1
    'type'#10 +                                      // 2
    '  TRechner = class'#10 +                        // 3
    '    function Summe(A, B: Integer): Integer;'#10 + // 4
    '  end;'#10 +                                    // 5
    'implementation'#10 +                            // 6
    '{$R *.dfm}'#10 +                                // 7
    'function TRechner.Summe(A, B: Integer): Integer;'#10 + // 8
    'begin'#10 +                                     // 9
    '  Result := A + B;'#10 +                        // 10
    'end;'#10 +                                      // 11
    'end.';

  cFormWerkzeug =
    'object Rechner: TRechner'#10 +
    '  OnSumme = Summe'#10 +
    '  object Summe: TButton'#10 +
    '    Caption = ''Summe'''#10 +
    '  end'#10 +
    'end';

  cUnitHaupt =
    'unit Haupt;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'uses Werkzeug;'#10 +                            // 2
    'implementation'#10 +                            // 3
    'procedure Lauf;'#10 +                           // 4
    'var'#10 +                                       // 5
    '  R: TRechner;'#10 +                            // 6
    'begin'#10 +                                     // 7
    '  R.Summe(1, 2);'#10 +                          // 8
    '  R.Summe(R.Summe(3, 4), 5);'#10 +              // 9
    'end;'#10 +                                      // 10
    'end.';

function PositionOf(const AText, AMarker: string): TTextPosition;
var
  mIndex, mLine, mLineStart, I: Integer;
begin
  mIndex := Pos(AMarker, AText);
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  end;
  mLine := 0;
  mLineStart := 1;
  for I := 1 to mIndex - 1 do
  begin
    if AText[I] = #10 then
    begin
      Inc(mLine);
      mLineStart := I + 1;
    end;
  end;
  Result := TTextPosition.Create(mLine, mIndex - mLineStart);
end;

{ TLspReferencesTests }

procedure TLspReferencesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(cUnitWerkzeug, cWerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspReferencesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspReferencesTests.FindAt(const AMarker: string; ADeclaration: Boolean): TArray<TReferenceLocation>;
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    Result := TLspReferences.Find(FResolver, FIndex, mTree,
      TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt, AMarker),
      ADeclaration, [cWerkzeugFile, cHauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, cWerkzeugFile) then
        begin
          AText := cUnitWerkzeug;
        end
        else if SameText(AFileName, cWerkzeugDfm) then
        begin
          AText := cFormWerkzeug;
        end
        else
        begin
          Result := False;
        end;
      end));
  finally
    mTree.Free;
  end;
end;

function TLspReferencesTests.Describe(const ALocations: TArray<TReferenceLocation>): string;
var
  mLocation: TReferenceLocation;
begin
  Result := '';
  for mLocation in ALocations do
  begin
    Result := Result + Format('%s:%d:%d ', [ExtractFileName(mLocation.FileName), mLocation.Range.StartPos.Line,
      mLocation.Range.StartPos.Character]);
  end;
  Result := Trim(Result);
end;

procedure TLspReferencesTests.FindsUsesAcrossUnits;
begin
  Assert.AreEqual('Haupt.pas:8:4 Haupt.pas:9:4 Haupt.pas:9:12 Werkzeug.pas:4:13 Werkzeug.pas:8:18 ' +
    'Werkzeug.dfm:1:12 Werkzeug.dfm:2:9', Describe(FindAt('Summe(1', True)));
end;

procedure TLspReferencesTests.WithoutDeclaration;
begin
  Assert.AreEqual('Haupt.pas:8:4 Haupt.pas:9:4 Haupt.pas:9:12 Werkzeug.pas:8:18 Werkzeug.dfm:1:12 Werkzeug.dfm:2:9',
    Describe(FindAt('Summe(1', False)));
end;

procedure TLspReferencesTests.IncludesFormReferences;
begin
  // Der Typname kommt in der .dfm als Klasse, nicht als Objektname vor.
  Assert.AreEqual('Haupt.pas:6:5 Werkzeug.pas:3:2 Werkzeug.pas:8:9', Describe(FindAt('TRechner;', True)));
end;

procedure TLspReferencesTests.ReadsDfmEventsAndObjects;
var
  mRanges: TArray<TTextRange>;
  mModel: TFormModel;
begin
  mModel := TFormModel.Create(cFormWerkzeug);
  try
    mRanges := mModel.Occurrences('summe');
  finally
    mModel.Free;
  end;
  Assert.AreEqual<NativeInt>(2, Length(mRanges));
  Assert.AreEqual(1, mRanges[0].StartPos.Line);
  Assert.AreEqual(12, mRanges[0].StartPos.Character);
  Assert.AreEqual(17, mRanges[0].EndPos.Character);
  Assert.AreEqual(2, mRanges[1].StartPos.Line);
  Assert.AreEqual(9, mRanges[1].StartPos.Character);
  // Strings und Eigenschaften ohne "On" zählen nicht.
  mModel := TFormModel.Create('object F: TF'#10'  Caption = Summe'#10'  Tag = Summe'#10'end');
  try
    Assert.AreEqual<NativeInt>(0, Length(mModel.Occurrences('Summe')));
  finally
    mModel.Free;
  end;
end;

procedure TLspReferencesTests.NothingOutsideIdentifiers;
begin
  Assert.AreEqual('', Describe(FindAt('begin', True)));
end;

procedure TLspReferencesTests.FindManyOccurrencesSameResult;
const
  cCount = 200;
var
  mText: string;
  mTree: TSyntaxTree;
  mFound: TArray<TReferenceLocation>;
  mIndex: Integer;
begin
  mText := 'unit Haupt;'#10'interface'#10'uses Werkzeug;'#10'implementation'#10'procedure Lauf;'#10'var'#10 +
    '  R: TRechner;'#10'begin'#10;
  for mIndex := 1 to cCount do
  begin
    mText := mText + '  R.Summe(1, 2);'#10;
  end;
  mText := mText + 'end;'#10'end.';
  mTree := TPascalParser.Parse(mText);
  try
    mFound := TLspReferences.Find(FResolver, FIndex, mTree,
      TReferenceSearch.Create(cHauptFile, TTextPosition.Create(8, 4), False,
      [cWerkzeugFile, cHauptFile, cWerkzeugFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := SameText(AFileName, cWerkzeugFile);
        if Result then
        begin
          AText := cUnitWerkzeug;
        end;
      end));
  finally
    mTree.Free;
  end;
  // 200 Aufrufe und der Rumpf in Werkzeug.pas; die Deklaration fehlt (ADeclaration = False), doppelt
  // genannte Dateien zählen einmal.
  Assert.AreEqual(cCount + 1, Integer(Length(mFound)));
  for mIndex := 0 to cCount - 1 do
  begin
    Assert.AreEqual(cHauptFile, mFound[mIndex].FileName);
    Assert.AreEqual(8 + mIndex, mFound[mIndex].Range.StartPos.Line);
    Assert.AreEqual(4, mFound[mIndex].Range.StartPos.Character);
  end;
  Assert.AreEqual(cWerkzeugFile, mFound[cCount].FileName);
  Assert.AreEqual(8, mFound[cCount].Range.StartPos.Line);
end;

procedure TLspReferencesTests.FindResolverStaysPinnedAfterForeignTree;
var
  mTree: TSyntaxTree;
  mPinned, mAgain: TUnitIndex;
  mFound: TArray<TReferenceLocation>;
begin
  mTree := TPascalParser.Parse(cUnitHaupt);
  try
    FResolver.PinTree(mTree, cHauptFile);
    try
      mPinned := FResolver.ExtractedUnit(mTree, cHauptFile);
      mFound := TLspReferences.Find(FResolver, FIndex, mTree,
        TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt, 'Summe(1'), False,
        [cWerkzeugFile, cHauptFile],
        function(const AFileName: string; out AText: string): Boolean
        begin
          Result := SameText(AFileName, cWerkzeugFile);
          if Result then
          begin
            AText := cUnitWerkzeug;
          end;
        end));
      Assert.AreEqual('Haupt.pas:8:4 Haupt.pas:9:4 Haupt.pas:9:12 Werkzeug.pas:8:18', Describe(mFound));
      mAgain := FResolver.ExtractedUnit(mTree, cHauptFile);
      Assert.AreEqual<Pointer>(Pointer(mAgain.Symbols), Pointer(mPinned.Symbols));
    finally
      FResolver.UnpinTree;
    end;
    // Ohne Pin des Aufrufers bleibt nach Find nichts gepinnt.
    mFound := TLspReferences.Find(FResolver, FIndex, mTree,
      TReferenceSearch.Create(cHauptFile, PositionOf(cUnitHaupt, 'Summe(1'), True,
      [cHauptFile], nil));
    Assert.AreEqual(3, Integer(Length(mFound)));
  finally
    mTree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspReferencesTests);

end.
