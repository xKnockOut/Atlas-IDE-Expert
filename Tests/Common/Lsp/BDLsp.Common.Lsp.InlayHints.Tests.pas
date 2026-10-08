unit BDLsp.Common.Lsp.InlayHints.Tests;

interface

uses
  DUnitX.TestFramework,
  BDLsp.Common.Index.Contract,
  BDLsp.Common.Semantics.NameResolver,
  BDLsp.Common.Lsp.InlayHints;

type
  [TestFixture]
  TLspInlayHintsTests = class
  private
    FIndex: ISymbolIndex;
    FResolver: TNameResolver;
    function Describe(const AHints: TArray<TInlayHint>): string;
  public
    [Setup]
    procedure Setup;
    [TearDown]
    procedure TearDown;
    [Test]
    procedure ParameterNamesBeforeArguments;
    [Test]
    procedure InferredTypesOfInlineVariables;
    [Test]
    procedure EndMarkersBehindLongBlocks;
    [Test]
    procedure SettingsSwitchHintsOffAndSort;
  end;

implementation

uses
  System.SysUtils,
  BDLsp.Common.Documents.Contract,
  BDLsp.Common.Configuration.Contract,
  BDLsp.Common.Pascal.SyntaxTree,
  BDLsp.Common.Pascal.Parser,
  BDLsp.Common.Index.SymbolIndex,
  BDLsp.Common.Index.Extractor;

const
  HauptFile = 'C:\P\Haupt.pas';
  WerkzeugFile = 'C:\P\Werkzeug.pas';

  UnitWerkzeug =
    'unit Werkzeug;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TFarbe = (Rot, Gruen);'#10 +
    '  TFoo = class'#10 +
    '    constructor Create;'#10 +
    '  end;'#10 +
    'function Rechne(Wert: Integer; const Faktor: Double): Integer;'#10 +
    'implementation'#10 +
    'constructor TFoo.Create;'#10 +
    'begin'#10 +
    'end;'#10 +
    'function Rechne(Wert: Integer; const Faktor: Double): Integer;'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.';

  UnitHaupt =
    'unit Haupt;'#10 +                               // 0
    'interface'#10 +                                 // 1
    'uses Werkzeug;'#10 +                            // 2
    'implementation'#10 +                            // 3
    'procedure Arbeite(Wert: Integer);'#10 +         // 4
    'begin'#10 +                                     // 5
    '  Rechne(1, 2.5);'#10 +                         // 6
    '  Rechne(Wert, Wert);'#10 +                     // 7
    '  var A := 1;'#10 +                             // 8
    '  var B := ''Text'';'#10 +                      // 9
    '  var C := TFoo.Create;'#10 +                   // 10
    '  var D := Rechne(1, 2);'#10 +                  // 11
    '  var E: Integer := 3;'#10 +                    // 12
    '  var F := Rot;'#10 +                           // 13
    '  if Assigned(nil) then'#10 +                   // 14
    '  begin'#10 +                                   // 15
    '    A := 2;'#10 +                               // 16
    '  end;'#10 +                                    // 17
    'end;'#10 +                                      // 18
    'end.';

function ReadFile(const AFileName: string; out AText: string): Boolean;
begin
  AText := UnitWerkzeug;
  Result := SameText(AFileName, WerkzeugFile);
end;

function WholeFile: TTextRange;
begin
  Result := TTextRange.Create(TTextPosition.Create(0, 0), TTextPosition.Create(100, 0));
end;

{ TLspInlayHintsTests }

procedure TLspInlayHintsTests.Setup;
begin
  FIndex := TSymbolIndex.Create;
  FIndex.AddUnit(TIndexExtractor.ExtractText(UnitWerkzeug, WerkzeugFile, nil));
  FResolver := TNameResolver.Create(FIndex);
end;

procedure TLspInlayHintsTests.TearDown;
begin
  FResolver.Free;
  FIndex := nil;
end;

function TLspInlayHintsTests.Describe(const AHints: TArray<TInlayHint>): string;
var
  Hint: TInlayHint;
begin
  Result := '';
  for Hint in AHints do
    Result := Result + Format('%d:%d %s|', [Hint.Position.Line, Hint.Position.Character, Hint.Text]);
end;

procedure TLspInlayHintsTests.ParameterNamesBeforeArguments;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Zeile 7: Wert heißt schon so, Faktor nicht. Zeile 11 ebenso; der Kopf in Zeile 4 bekommt keine.
    Assert.AreEqual('6:9 Wert:|6:12 Faktor:|7:15 Faktor:|11:18 Wert:|11:21 Faktor:|',
      Describe(TLspInlayHints.ParameterNames(FResolver, FIndex, Tree, UnitHaupt, HauptFile, WholeFile, ReadFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.InferredTypesOfInlineVariables;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Assert.AreEqual('8:7 : Integer|9:7 : string|10:7 : TFoo|11:7 : Integer|13:7 : TFarbe|',
      Describe(TLspInlayHints.InferredTypes(FResolver, Tree, HauptFile, WholeFile)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.EndMarkersBehindLongBlocks;
var
  Tree: TSyntaxTree;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    // Reihenfolge der Knoten im Baum; Collect sortiert nach Position.
    Assert.AreEqual('18:4 // Arbeite|17:6 // if Assigned(nil)|',
      Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 4)));
    // Die Routine hat 15 Zeilen, der if-Block 4.
    Assert.AreEqual('18:4 // Arbeite|', Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 5)));
    Assert.AreEqual('', Describe(TLspInlayHints.EndMarkers(Tree, WholeFile, 20)));
  finally
    Tree.Free;
  end;
end;

procedure TLspInlayHintsTests.SettingsSwitchHintsOffAndSort;
var
  Tree: TSyntaxTree;
  Settings: TInlayHintSettings;
  Hints: TArray<TInlayHint>;
begin
  Tree := TPascalParser.Parse(UnitHaupt);
  try
    Settings := TInlayHintSettings.Default;
    Settings.ParameterNames := False;
    Settings.EndMarkerMinLines := 5;
    Hints := TLspInlayHints.Collect(FResolver, FIndex, Tree, UnitHaupt, HauptFile,
      TTextRange.Create(TTextPosition.Create(9, 0), TTextPosition.Create(30, 0)), Settings, ReadFile);
    Assert.AreEqual('9:7 : string|10:7 : TFoo|11:7 : Integer|13:7 : TFarbe|18:4 // Arbeite|', Describe(Hints));
  finally
    Tree.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspInlayHintsTests);

end.
