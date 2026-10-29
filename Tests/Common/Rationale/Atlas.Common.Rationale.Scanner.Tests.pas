unit Atlas.Common.Rationale.Scanner.Tests;

// Tests für Begründungen (#1123): Marken mit und ohne Doppelpunkt, Folgezeilen,
// Zuordnung über einer Deklaration (Leerzeilen, Attribute, XMLDoc, Kommentar
// hinter Code), im Rumpf einer Routine und zur Unit, Filter nach Marken ohne
// TODO/FIXME und Kodierung für den Index.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TRationaleScannerTests = class
  public
    [Test]
    procedure ParsesMarkers;
    [Test]
    procedure ContinuationLines;
    [Test]
    procedure AboveDeclaration;
    [Test]
    procedure RoutineBodyAndUnit;
    [Test]
    procedure FilterByMarkers;
    [Test]
    procedure EncodeRoundTrip;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Rationale.Contract,
  Atlas.Common.Rationale.Scanner;

function Joined(const AEntries: TArray<TRationaleEntry>): string;
var
  mEntry: TRationaleEntry;
begin
  Result := '';
  for mEntry in AEntries do
    Result := Result + Format('%s@%d:%s|', [mEntry.Marker, mEntry.Line, mEntry.Text]);
end;

function FirstNode(ANode: TSyntaxNode; AKind: TSyntaxKind; const AName: string): TSyntaxNode;
var
  mIndex: Integer;
begin
  if (ANode.Kind = AKind) and SameText(ANode.Name, AName) then
    Exit(ANode);
  for mIndex := 0 to ANode.ChildCount - 1 do
  begin
    Result := FirstNode(ANode[mIndex], AKind, AName);
    if Result <> nil then
      Exit;
  end;
  Result := nil;
end;

procedure TRationaleScannerTests.ParsesMarkers;
var
  mMarker, mText: string;
begin
  Assert.IsTrue(TRationaleScanner.ParseBody(' WHY: Delphi 12', mMarker, mText));
  Assert.AreEqual('WHY', mMarker);
  Assert.AreEqual('Delphi 12', mText);
  Assert.IsTrue(TRationaleScanner.ParseBody(' note : klein mit Doppelpunkt', mMarker, mText));
  Assert.AreEqual('NOTE', mMarker);
  Assert.AreEqual('klein mit Doppelpunkt', mText);
  Assert.IsTrue(TRationaleScanner.ParseBody(' HACK umgeht QC 12345', mMarker, mText));
  Assert.AreEqual('HACK', mMarker);
  Assert.AreEqual('umgeht QC 12345', mText);
  // Ohne Doppelpunkt nur in Großbuchstaben; einzelne Buchstaben und Wortteile nie.
  Assert.IsFalse(TRationaleScanner.ParseBody(' Note this is a sentence', mMarker, mText));
  Assert.IsFalse(TRationaleScanner.ParseBody(' I think', mMarker, mText));
  Assert.IsFalse(TRationaleScanner.ParseBody(' NOTES: Mehrzahl', mMarker, mText) and (mMarker = 'NOTE'));
  Assert.IsFalse(TRationaleScanner.ParseBody(' WHY2: Ziffer', mMarker, mText));
  Assert.AreEqual(' WHY: x ', TRationaleScanner.CommentBody('{ WHY: x }'));
  Assert.AreEqual(' WHY: x ', TRationaleScanner.CommentBody('(* WHY: x *)'));
end;

procedure TRationaleScannerTests.ContinuationLines;
const
  cSource = 'unit U;'#10'interface'#10'implementation'#10 +
    '// WHY: Delphi 12 kennt keinen'#10 +   // 3
    '//      if-Ausdruck.'#10 +
    '// Kein Teil mehr.'#10 +
    '{ HACK: Block'#10'  über zwei Zeilen }'#10 +   // 6
    '// NOTE: vor einer Lücke'#10 +   // 8
    #10 +
    '//      nicht fortgesetzt'#10 +
    'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual('WHY@3:Delphi 12 kennt keinen if-Ausdruck.|HACK@6:Block über zwei Zeilen|' +
      'NOTE@8:vor einer Lücke|', Joined(TRationaleScanner.InRange(mTree.Tokens, 0, Length(cSource))));
  finally
    mTree.Free;
  end;
end;

procedure TRationaleScannerTests.AboveDeclaration;
const
  cSource = 'unit U;'#10'interface'#10'type'#10 +
    '  // WHY: direkt darueber'#10 +   // 3
    '  TA = class'#10 +
    '  end;'#10 +
    '  // NOTE: eine Leerzeile'#10 +   // 6
    #10 +
    '  /// <summary>Doku</summary>'#10 +
    '  [Weak]'#10 +
    '  TB = class'#10 +
    '  end;'#10 +
    '  // NOTE: zwei Leerzeilen'#10 +   // 12
    #10#10 +
    '  TC = class'#10 +
    '    FX: Integer; // WHY: gehoert zu FX'#10 +
    '    FY: Integer;'#10 +
    '  end;'#10 +
    'implementation'#10'end.';
var
  mTree: TSyntaxTree;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    Assert.AreEqual('WHY@3:direkt darueber|', Joined(TRationaleScanner.ForNode(mTree.Tokens,
      FirstNode(mTree.Root, TSyntaxKind.TypeDecl, 'TA'))));
    Assert.AreEqual('NOTE@6:eine Leerzeile|', Joined(TRationaleScanner.ForNode(mTree.Tokens,
      FirstNode(mTree.Root, TSyntaxKind.TypeDecl, 'TB'))));
    Assert.AreEqual('', Joined(TRationaleScanner.ForNode(mTree.Tokens,
      FirstNode(mTree.Root, TSyntaxKind.TypeDecl, 'TC'))));
    Assert.AreEqual('', Joined(TRationaleScanner.ForNode(mTree.Tokens,
      FirstNode(mTree.Root, TSyntaxKind.Field, 'FY'))));
  finally
    mTree.Free;
  end;
end;

procedure TRationaleScannerTests.RoutineBodyAndUnit;
const
  cSource = '// RATIONALE: Kopf der Unit'#10 +   // 0
    'unit U;'#10'interface'#10 +
    '// IMPORTANT: vor den Typen'#10 +   // 3
    'uses'#10'  System.SysUtils;'#10 +
    '// WHY: zur Konstante'#10 +   // 6
    'const'#10'  // WHY: zu cMax'#10'  cMax = 3;'#10 +   // 8
    'type'#10'  // NOTE: zu TA'#10'  TA = class'#10'    procedure Lauf;'#10'  end;'#10 +
    'implementation'#10 +
    '// WHY: ueber der Implementierung'#10 +   // 16
    'procedure TA.Lauf;'#10 +
    'var'#10'  // NOTE: lokale Variable'#10'  mX: Integer;'#10 +   // 19
    'begin'#10'  // HACK: im Rumpf'#10'  mX := 1;'#10'end;'#10 +   // 22
    '// WHY: nach der Routine'#10 +
    'end.';
var
  mTree: TSyntaxTree;
  mImpl: TSyntaxNode;
begin
  mTree := TPascalParser.Parse(cSource);
  try
    mImpl := FirstNode(mTree.Root.FindChild(TSyntaxKind.ImplementationSection), TSyntaxKind.RoutineDecl, 'TA.Lauf');
    Assert.IsNotNull(mImpl);
    Assert.AreEqual('WHY@16:ueber der Implementierung|NOTE@19:lokale Variable|HACK@22:im Rumpf|',
      Joined(TRationaleScanner.ForNode(mTree.Tokens, mImpl)));
    // Unit: Kopf und interface vor dem ersten type-Abschnitt, ohne die Kommentare der Konstante.
    Assert.AreEqual('RATIONALE@0:Kopf der Unit|IMPORTANT@3:vor den Typen|WHY@6:zur Konstante|',
      Joined(TRationaleScanner.ForUnit(mTree)));
  finally
    mTree.Free;
  end;
end;

procedure TRationaleScannerTests.FilterByMarkers;
var
  mEntries: TArray<TRationaleEntry>;
begin
  mEntries := [TRationaleEntry.Create('WHY', 'a', 1), TRationaleEntry.Create('TODO', 'b', 2),
    TRationaleEntry.Create('API', 'c', 3), TRationaleEntry.Create('WARUM', 'd', 4)];
  Assert.AreEqual('WHY@1:a|', Joined(TRationale.Filter(mEntries, TRationale.DefaultMarkers,
    TArray<string>.Create('TODO', 'FIXME'))));
  // Eigene Marke; TODO bleibt bei der TODO-Übersicht, auch wenn es in den Marken steht.
  Assert.AreEqual('WHY@1:a|WARUM@4:d|', Joined(TRationale.Filter(mEntries,
    TArray<string>.Create('why', 'warum', 'todo'), TArray<string>.Create('TODO', 'FIXME'))));
end;

procedure TRationaleScannerTests.EncodeRoundTrip;
var
  mEntry: TRationaleEntry;
begin
  Assert.IsTrue(TRationale.TryDecode(TRationale.Encode(TRationaleEntry.Create('WHY', 'Text: mit Tab'#9'?', 42)),
    mEntry));
  Assert.AreEqual('WHY', mEntry.Marker);
  Assert.AreEqual(42, mEntry.Line);
  Assert.AreEqual('Text: mit Tab'#9'?', mEntry.Text);
  Assert.IsFalse(TRationale.TryDecode('kaputt', mEntry));
  Assert.AreEqual(1, Integer(Length(TRationale.DecodeAll(TArray<string>.Create('A'#9'1'#9'x', 'kaputt')))));
end;

initialization
  TDUnitX.RegisterTestFixture(TRationaleScannerTests);

end.
