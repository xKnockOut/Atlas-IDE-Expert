unit Atlas.Common.Lsp.ParameterHeaders.Tests;

// Tests für Parameter in Deklarations- und Rumpfkopf (#2425): Umbenennen und Verweise aus jedem Kopf und jeder
// Verwendung liefern dieselben sicheren Stellen, gleichnamige Parameter anderer Routinen sind keine Stellen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TLspParameterHeadersTests = class
  public
    [Test]
    procedure RenamesFromBodyHeader;
    [Test]
    procedure RenamesFromDeclarationHeader;
    [Test]
    procedure RenamesFromUse;
    [Test]
    procedure IgnoresSameNameInOtherRoutines;
    [Test]
    procedure RenamesOnlyMatchingOverload;
    [Test]
    procedure RenamesClassMethodAndConstructor;
    [Test]
    procedure RenamesInterfaceAndForwardRoutines;
    [Test]
    procedure RenamesAbstractDeclarationAlone;
    [Test]
    procedure FindsCounterpartHeader;
    [Test]
    procedure ReferencesIncludeBothHeaders;
  end;

implementation

uses
  System.SysUtils,
  System.Classes,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.SymbolIndex,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Lsp.References,
  Atlas.Common.Lsp.Rename,
  Atlas.Common.Lsp.ParameterHeaders;

const
  cProbeFile = 'C:\P\Probe.pas';

  cUnitProbe =
    'unit Probe;'#10 +                                                       // 0
    'interface'#10 +                                                         // 1
    'type'#10 +                                                              // 2
    '  TQuelle = class'#10 +                                                 // 3
    '  public'#10 +                                                          // 4
    '    function Lade(ANummer: Integer): string; virtual;'#10 +             // 5
    '    procedure Abstrakt(AWert: Integer); virtual; abstract;'#10 +        // 6
    '  end;'#10 +                                                            // 7
    '  TDbQuelle = class(TQuelle)'#10 +                                      // 8
    '  public'#10 +                                                          // 9
    '    function Lade(ANummer: Integer): string; override;'#10 +            // 10
    '    procedure Speichere(ANummer: Integer; const AName: string);'#10 +   // 11
    '    procedure Teile(AWert: Integer); overload;'#10 +                    // 12
    '    procedure Teile(AWert: string); overload;'#10 +                     // 13
    '    class function Neu(AName: string): TDbQuelle;'#10 +                 // 14
    '    constructor Create(AName: string);'#10 +                            // 15
    '  end;'#10 +                                                            // 16
    'procedure Frei(AZahl: Integer);'#10 +                                   // 17
    'implementation'#10 +                                                    // 18
    'procedure Vorab(AText: string); forward;'#10 +                          // 19
    'function TQuelle.Lade(ANummer: Integer): string;'#10 +                  // 20
    'begin'#10 +                                                             // 21
    '  Result := IntToStr(ANummer);'#10 +                                    // 22
    'end;'#10 +                                                              // 23
    'function TDbQuelle.Lade(ANummer: Integer): string;'#10 +                // 24
    'begin'#10 +                                                             // 25
    '  Result := '''';'#10 +                                                 // 26
    'end;'#10 +                                                              // 27
    'procedure TDbQuelle.Speichere(ANummer: Integer; const AName: string);'#10 + // 28
    'begin'#10 +                                                             // 29
    '  Lade(ANummer);'#10 +                                                  // 30
    '  Vorab(AName);'#10 +                                                   // 31
    'end;'#10 +                                                              // 32
    'procedure TDbQuelle.Teile(AWert: Integer);'#10 +                        // 33
    'begin'#10 +                                                             // 34
    '  Frei(AWert);'#10 +                                                    // 35
    'end;'#10 +                                                              // 36
    'procedure TDbQuelle.Teile(AWert: string);'#10 +                         // 37
    'begin'#10 +                                                             // 38
    '  Vorab(AWert);'#10 +                                                   // 39
    'end;'#10 +                                                              // 40
    'class function TDbQuelle.Neu(AName: string): TDbQuelle;'#10 +           // 41
    'begin'#10 +                                                             // 42
    '  Result := Create(AName);'#10 +                                        // 43
    'end;'#10 +                                                              // 44
    'constructor TDbQuelle.Create(AName: string);'#10 +                      // 45
    'begin'#10 +                                                             // 46
    '  inherited Create;'#10 +                                               // 47
    '  Vorab(AName);'#10 +                                                   // 48
    'end;'#10 +                                                              // 49
    'procedure Frei(AZahl: Integer);'#10 +                                   // 50
    'begin'#10 +                                                             // 51
    '  Vorab(IntToStr(AZahl));'#10 +                                         // 52
    'end;'#10 +                                                              // 53
    'procedure Vorab(AText: string);'#10 +                                   // 54
    'begin'#10 +                                                             // 55
    '  Frei(Length(AText));'#10 +                                            // 56
    'end;'#10 +                                                              // 57
    'end.';

/// <summary>Stelle des ersten ganzen Worts AName in Zeile ALine (0-basiert) des Probetexts.</summary>
function SpotOf(ALine: Integer; const AName: string): TTextPosition;
var
  mLines: TStringList;
  mText: string;
  mIndex: Integer;
begin
  mLines := TStringList.Create;
  try
    mLines.Text := cUnitProbe;
    mText := mLines[ALine];
  finally
    mLines.Free;
  end;
  mIndex := Pos(AName, mText);
  while (mIndex > 0) and (CharInSet(mText[mIndex + Length(AName)], ['A'..'Z', 'a'..'z', '0'..'9', '_']) or
    ((mIndex > 1) and CharInSet(mText[mIndex - 1], ['A'..'Z', 'a'..'z', '0'..'9', '_']))) do
  begin
    mIndex := Pos(AName, mText, mIndex + 1);
  end;
  if mIndex = 0 then
  begin
    raise Exception.CreateFmt('"%s" fehlt in Zeile %d', [AName, ALine]);
  end;
  Result := TTextPosition.Create(ALine, mIndex - 1);
end;

function SpotText(const APosition: TTextPosition): string;
begin
  Result := Format('%d:%d', [APosition.Line, APosition.Character]);
end;

/// <summary>Erwartete Stellen: je Zeile das erste ganze Wort AName, als "Zeile:Spalte" aufsteigend.</summary>
function Expected(const ALines: TArray<Integer>; const AName: string): string;
var
  mLine: Integer;
begin
  Result := '';
  for mLine in ALines do
  begin
    Result := Result + ' ' + SpotText(SpotOf(mLine, AName));
  end;
  Result := Trim(Result);
end;

function ReadProbe(const AFileName: string; out AText: string): Boolean;
begin
  Result := SameText(AFileName, cProbeFile);
  if Result then
  begin
    AText := cUnitProbe;
  end;
end;

/// <summary>APositions als "Zeile:Spalte", aufsteigend sortiert.</summary>
function SpotsText(const APositions: TArray<TTextPosition>): string;
var
  mList: TStringList;
  mPosition: TTextPosition;
  mIndex: Integer;
begin
  mList := TStringList.Create;
  try
    for mPosition in APositions do
    begin
      mList.Add(Format('%.4d:%.4d', [mPosition.Line, mPosition.Character]));
    end;
    mList.Sort;
    Result := '';
    for mIndex := 0 to mList.Count - 1 do
    begin
      Result := Result + ' ' + Format('%d:%d', [StrToInt(Copy(mList[mIndex], 1, 4)),
        StrToInt(Copy(mList[mIndex], 6, 4))]);
    end;
    Result := Trim(Result);
  finally
    mList.Free;
  end;
end;

/// <summary>Stellen der Ersetzungen wie SpotsText; jede Ersetzung muss ANewName schreiben.</summary>
function EditsText(const AEdits: TArray<TRenameEdit>; const ANewName: string): string;
var
  mEdit: TRenameEdit;
  mPositions: TArray<TTextPosition>;
begin
  mPositions := nil;
  for mEdit in AEdits do
  begin
    Assert.AreEqual(ANewName, mEdit.NewText);
    mPositions := mPositions + [mEdit.Range.StartPos];
  end;
  Result := SpotsText(mPositions);
end;

/// <summary>Umbenennen des Namens AName in Zeile ALine in ANewName; AUnchanged: Anzahl erschlossener Stellen.
/// </summary>
function RenameAt(ALine: Integer; const AName, ANewName: string; out AUnchanged: Integer): string;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mUnchanged: TArray<TReferenceLocation>;
  mEdits: TArray<TRenameEdit>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitProbe, cProbeFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TSyntaxTreeCache.Parse(cUnitProbe);
  try
    mEdits := TLspRename.Edits(mResolver, mIndex, mTree, TReferenceSearch.Create(cProbeFile, SpotOf(ALine, AName),
      True, [cProbeFile], ReadProbe), TRenameRequest.Create(ANewName, True, TReferenceSettings.Default, nil),
      mUnchanged);
    AUnchanged := Length(mUnchanged);
    Result := EditsText(mEdits, ANewName);
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

{ TLspParameterHeadersTests }

procedure TLspParameterHeadersTests.RenamesFromBodyHeader;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([11, 28, 31], 'AName'), RenameAt(28, 'AName', 'ANeuerName', mUnchanged));
  Assert.AreEqual(0, mUnchanged, 'keine erschlossenen Stellen');
end;

procedure TLspParameterHeadersTests.RenamesFromDeclarationHeader;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([11, 28, 31], 'AName'), RenameAt(11, 'AName', 'ANeuerName', mUnchanged));
  Assert.AreEqual(0, mUnchanged, 'keine erschlossenen Stellen');
end;

procedure TLspParameterHeadersTests.RenamesFromUse;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([11, 28, 31], 'AName'), RenameAt(31, 'AName', 'ANeuerName', mUnchanged));
  Assert.AreEqual(0, mUnchanged, 'keine erschlossenen Stellen');
end;

procedure TLspParameterHeadersTests.IgnoresSameNameInOtherRoutines;
var
  mUnchanged: Integer;
begin
  // ANummer steht auch in den Köpfen von TQuelle.Lade und TDbQuelle.Lade (Zeilen 5, 10, 20, 22, 24).
  Assert.AreEqual(Expected([11, 28, 30], 'ANummer'), RenameAt(28, 'ANummer', 'AKunde', mUnchanged));
  Assert.AreEqual(0, mUnchanged, 'gleichnamige Parameter anderer Routinen sind keine erschlossenen Stellen');
  Assert.AreEqual(Expected([11, 28, 30], 'ANummer'), RenameAt(11, 'ANummer', 'AKunde', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
end;

procedure TLspParameterHeadersTests.RenamesOnlyMatchingOverload;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([13, 37, 39], 'AWert'), RenameAt(13, 'AWert', 'AText', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
  Assert.AreEqual(Expected([12, 33, 35], 'AWert'), RenameAt(35, 'AWert', 'AZahl', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
end;

procedure TLspParameterHeadersTests.RenamesClassMethodAndConstructor;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([14, 41, 43], 'AName'), RenameAt(14, 'AName', 'ATitel', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
  Assert.AreEqual(Expected([15, 45, 48], 'AName'), RenameAt(45, 'AName', 'ATitel', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
end;

procedure TLspParameterHeadersTests.RenamesInterfaceAndForwardRoutines;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([17, 50, 52], 'AZahl'), RenameAt(17, 'AZahl', 'AWert', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
  Assert.AreEqual(Expected([19, 54, 56], 'AText'), RenameAt(19, 'AText', 'AName', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
  Assert.AreEqual(Expected([19, 54, 56], 'AText'), RenameAt(56, 'AText', 'AName', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
end;

procedure TLspParameterHeadersTests.RenamesAbstractDeclarationAlone;
var
  mUnchanged: Integer;
begin
  Assert.AreEqual(Expected([6], 'AWert'), RenameAt(6, 'AWert', 'AZahl', mUnchanged));
  Assert.AreEqual(0, mUnchanged);
end;

procedure TLspParameterHeadersTests.FindsCounterpartHeader;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mHeaders: TParameterHeaders;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitProbe, cProbeFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TSyntaxTreeCache.Parse(cUnitProbe);
  try
    Assert.IsTrue(TParameterHeaders.Find(mResolver, mIndex, mTree, cProbeFile, SpotOf(11, 'AName'), mHeaders));
    Assert.IsTrue(mHeaders.HasBody);
    Assert.AreEqual(SpotText(SpotOf(28, 'AName')), SpotText(mHeaders.Body.StartPos));
    Assert.AreEqual(1, Integer(Length(mHeaders.Declarations)));
    Assert.AreEqual(SpotText(SpotOf(11, 'AName')), SpotText(mHeaders.Declarations[0].StartPos));
    // Der Typ hinter dem Namen ist kein Parameter.
    Assert.IsFalse(TParameterHeaders.Find(mResolver, mIndex, mTree, cProbeFile, SpotOf(11, 'Integer'), mHeaders));
    // Eine lokale Verwendung, die kein Parameter ist, ebenso wenig.
    Assert.IsFalse(TParameterHeaders.Find(mResolver, mIndex, mTree, cProbeFile, SpotOf(22, 'Result'), mHeaders));
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

procedure TLspParameterHeadersTests.ReferencesIncludeBothHeaders;
var
  mIndex: ISymbolIndex;
  mResolver: TNameResolver;
  mTree: TSyntaxTree;
  mLocation: TReferenceLocation;
  mPositions: TArray<TTextPosition>;
begin
  mIndex := TSymbolIndex.Create;
  mIndex.AddUnit(TIndexExtractor.ExtractText(cUnitProbe, cProbeFile, nil));
  mResolver := TNameResolver.Create(mIndex);
  mTree := TSyntaxTreeCache.Parse(cUnitProbe);
  try
    mPositions := nil;
    for mLocation in TLspReferences.Find(mResolver, mIndex, mTree, TReferenceSearch.Create(cProbeFile,
      SpotOf(11, 'ANummer'), True, [cProbeFile], ReadProbe), TReferenceSettings.Default, nil) do
    begin
      Assert.IsTrue(mLocation.Confidence.IsSure, SpotText(mLocation.Range.StartPos));
      mPositions := mPositions + [mLocation.Range.StartPos];
    end;
    Assert.AreEqual(Expected([11, 28, 30], 'ANummer'), SpotsText(mPositions));
  finally
    mTree.Free;
    mResolver.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TLspParameterHeadersTests);

end.
