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
  WerkzeugFile = 'C:\P\Werkzeug.pas';
  WerkzeugDfm = 'C:\P\Werkzeug.dfm';
  HauptFile = 'C:\P\Haupt.pas';

  UnitWerkzeug =
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

  FormWerkzeug =
    'object Rechner: TRechner'#10 +
    '  OnSumme = Summe'#10 +
    '  object Summe: TButton'#10 +
    '    Caption = ''Summe'''#10 +
    '  end'#10 +
    'end';

  UnitHaupt =
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
  Index, Line, LineStart, I: Integer;
begin
  Index := Pos(AMarker, AText);
  if Index = 0 then
    raise Exception.CreateFmt('"%s" nicht gefunden', [AMarker]);
  Line := 0;
  LineStart := 1;
  for I := 1 to Index - 1 do
    if AText[I] = #10 then
    begin
      Inc(Line);
      LineStart := I + 1;
    end;
  Result := TTextPosition.Create(Line, Index - LineStart);
end;

{ TLspReferencesTests }

procedure TLspReferencesTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspReferencesTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspReferencesTests.FindAt(const AMarker: string; ADeclaration: Boolean): TArray<TReferenceLocation>;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Result := TLspReferences.Find(FResolver, FIndex, Tree, HauptFile, PositionOf(UnitHaupt, AMarker),
      ADeclaration, [WerkzeugFile, HauptFile],
      function(const AFileName: string; out AText: string): Boolean
      begin
        Result := True;
        if SameText(AFileName, WerkzeugFile) then
          AText := UnitWerkzeug
        else if SameText(AFileName, WerkzeugDfm) then
          AText := FormWerkzeug
        else
          Result := False;
      end);
  finally
    Tree.Free;
  end;
end;

function TLspReferencesTests.Describe(const ALocations: TArray<TReferenceLocation>): string;
var
  Location: TReferenceLocation;
begin
  Result := '';
  for Location in ALocations do
    Result := Result + Format('%s:%d:%d ', [ExtractFileName(Location.FileName), Location.Range.StartPos.Line,
      Location.Range.StartPos.Character]);
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
  Ranges: TArray<TTextRange>;
  Model: TFormModel;
begin
  Model := TFormModel.Create(FormWerkzeug);
  try
    Ranges := Model.Occurrences('summe');
  finally
    Model.Free;
  end;
  Assert.AreEqual<NativeInt>(2, Length(Ranges));
  Assert.AreEqual(1, Ranges[0].StartPos.Line);
  Assert.AreEqual(12, Ranges[0].StartPos.Character);
  Assert.AreEqual(17, Ranges[0].EndPos.Character);
  Assert.AreEqual(2, Ranges[1].StartPos.Line);
  Assert.AreEqual(9, Ranges[1].StartPos.Character);
  // Strings und Eigenschaften ohne "On" zählen nicht.
  Model := TFormModel.Create('object F: TF'#10'  Caption = Summe'#10'  Tag = Summe'#10'end');
  try
    Assert.AreEqual<NativeInt>(0, Length(Model.Occurrences('Summe')));
  finally
    Model.Free;
  end;
end;

procedure TLspReferencesTests.NothingOutsideIdentifiers;
begin
  Assert.AreEqual('', Describe(FindAt('begin', True)));
end;

initialization
  TDUnitX.RegisterTestFixture(TLspReferencesTests);

end.
