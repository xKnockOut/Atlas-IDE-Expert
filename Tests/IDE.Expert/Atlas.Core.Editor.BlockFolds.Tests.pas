unit Atlas.Core.Editor.BlockFolds.Tests;

// Tests für das Einklappen großer Blöcke (#2795): Antwort des Servers lesen,
// Blöcke wählen, Marken in derselben Zeile setzen, wiederfinden und entfernen.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasBlockFoldsTests = class
  public
    [Test]
    procedure ReadsServerAnswer;
    [Test]
    procedure SkipsIncompleteEntries;
    [Test]
    procedure InnermostRespectsMinLines;
    [Test]
    procedure LargeKeepsOutermostOnly;
    [Test]
    procedure FoldInsertsMarkersInSameLines;
    [Test]
    procedure FoldSkipsFoldedBlocks;
    [Test]
    procedure FindsAndPairsMarkers;
    [Test]
    procedure RemoveRestoresText;
    [Test]
    procedure CaptionCannotCloseMarker;
    [Test]
    procedure ParamsNameDocument;
  end;

implementation

uses
  System.SysUtils,
  System.JSON,
  Atlas.Text.Lines,
  Atlas.Core.Editor.Contract,
  Atlas.Core.Editor.BlockFolds;

const
  cIfElse =
    'procedure A;'#13#10 +            // 0
    'begin'#13#10 +                   // 1
    '  if X then begin'#13#10 +       // 2
    '    Y;'#13#10 +                  // 3
    '  end else begin'#13#10 +        // 4
    '    Z;'#13#10 +                  // 5
    '  end;'#13#10 +                  // 6
    'end;';                           // 7

function Fold(const AKind, ACaption: string; AOpenLine, AOpenChar, ACloseLine, ACloseChar: Integer): TAtlasBlockFold;
begin
  Result := Default(TAtlasBlockFold);
  Result.Kind := AKind;
  Result.Caption := ACaption;
  Result.OpenPos := TTextPosition.Create(AOpenLine, AOpenChar);
  Result.ClosePos := TTextPosition.Create(ACloseLine, ACloseChar);
end;

function IfElseBlocks: TArray<TAtlasBlockFold>;
begin
  Result := TArray<TAtlasBlockFold>.Create(Fold('if', 'if X then', 2, 17, 4, 5), Fold('else', 'else', 4, 16, 6, 5));
end;

function Applied(const AText: string; const AEdits: TAtlasTextEdits): string;
var
  mIndex: Integer;
begin
  // Von hinten, damit die Versätze davor gelten.
  Result := AText;
  for mIndex := High(AEdits) downto 0 do
  begin
    Result := Copy(Result, 1, AEdits[mIndex].Start) + AEdits[mIndex].Insert +
      Copy(Result, AEdits[mIndex].Start + AEdits[mIndex].Count + 1, MaxInt);
  end;
end;

{ TAtlasBlockFoldsTests }

procedure TAtlasBlockFoldsTests.ReadsServerAnswer;
var
  mJson: TJSONValue;
  mBlocks: TArray<TAtlasBlockFold>;
begin
  mJson := TJSONObject.ParseJSONValue('{"blocks":[{"kind":"if","open":{"line":2,"character":17},' +
    '"close":{"line":4,"character":5},"caption":"if X then"}]}');
  try
    mBlocks := TAtlasBlockFolds.FromJson(mJson);
  finally
    mJson.Free;
  end;
  Assert.AreEqual(1, Integer(Length(mBlocks)));
  Assert.AreEqual('if', mBlocks[0].Kind);
  Assert.AreEqual('if X then', mBlocks[0].Caption);
  Assert.AreEqual(2, mBlocks[0].OpenPos.Line);
  Assert.AreEqual(17, mBlocks[0].OpenPos.Character);
  Assert.AreEqual(3, mBlocks[0].LineCount);
end;

procedure TAtlasBlockFoldsTests.SkipsIncompleteEntries;
var
  mJson: TJSONValue;
begin
  mJson := TJSONObject.ParseJSONValue('{"blocks":[{"kind":"if","open":{"line":2}},1,' +
    '{"kind":"if","open":{"line":4,"character":1},"close":{"line":2,"character":1}}]}');
  try
    Assert.AreEqual(0, Integer(Length(TAtlasBlockFolds.FromJson(mJson))), 'ohne Ende, kein Objekt, verkehrt herum');
  finally
    mJson.Free;
  end;
  Assert.AreEqual(0, Integer(Length(TAtlasBlockFolds.FromJson(nil))));
end;

procedure TAtlasBlockFoldsTests.InnermostRespectsMinLines;
var
  mBlocks: TArray<TAtlasBlockFold>;
begin
  mBlocks := TArray<TAtlasBlockFold>.Create(Fold('if', 'if A then', 2, 10, 40, 5), Fold('for', 'for', 5, 10, 9, 5));
  Assert.AreEqual(1, TAtlasBlockFolds.Innermost(mBlocks, 6, 3), 'innerer Block');
  Assert.AreEqual(0, TAtlasBlockFolds.Innermost(mBlocks, 6, 6), 'innerer zu kurz: der äußere');
  Assert.AreEqual(-1, TAtlasBlockFolds.Innermost(mBlocks, 41, 3), 'außerhalb');
end;

procedure TAtlasBlockFoldsTests.LargeKeepsOutermostOnly;
var
  mBlocks, mLarge: TArray<TAtlasBlockFold>;
begin
  mBlocks := TArray<TAtlasBlockFold>.Create(Fold('if', 'if A then', 2, 10, 40, 5), Fold('for', 'for', 5, 10, 30, 5),
    Fold('else', 'else', 40, 12, 60, 5), Fold('try', 'try', 70, 5, 72, 5));
  mLarge := TAtlasBlockFolds.Large(mBlocks, 15);
  Assert.AreEqual(2, Integer(Length(mLarge)));
  Assert.AreEqual('if', mLarge[0].Kind);
  Assert.AreEqual('else', mLarge[1].Kind, 'beginnt hinter dem Ende von if; for liegt innen, try ist zu kurz');
end;

procedure TAtlasBlockFoldsTests.FoldInsertsMarkersInSameLines;
var
  mText: string;
  mLines: TArray<string>;
begin
  mText := Applied(cIfElse, TAtlasBlockFolds.FoldEdits(cIfElse, IfElseBlocks));
  mLines := mText.Split([#13#10]);
  Assert.AreEqual(8, Integer(Length(mLines)), 'keine neuen Zeilen');
  Assert.AreEqual('  if X then begin(*$REGION ''if X then''*)', mLines[2]);
  Assert.AreEqual('  end(*$ENDREGION*) else begin(*$REGION ''else''*)', mLines[4]);
  Assert.AreEqual('  end(*$ENDREGION*);', mLines[6]);
end;

procedure TAtlasBlockFoldsTests.FoldSkipsFoldedBlocks;
var
  mFolded: string;
begin
  mFolded := Applied(cIfElse, TAtlasBlockFolds.FoldEdits(cIfElse, [IfElseBlocks[0]]));
  // Der Server meldet die Stellen hinter den Token; die Marke steht schon dort.
  Assert.AreEqual(0, Integer(Length(TAtlasBlockFolds.FoldEdits(mFolded, [IfElseBlocks[0]]))));
end;

procedure TAtlasBlockFoldsTests.FindsAndPairsMarkers;
var
  mText: string;
  mMarkers: TArray<TAtlasBlockMarker>;
  mFolded: TArray<TAtlasFoldedBlock>;
begin
  mText := Applied(cIfElse, TAtlasBlockFolds.FoldEdits(cIfElse, IfElseBlocks));
  mMarkers := TAtlasBlockFolds.Markers(mText);
  Assert.AreEqual(4, Integer(Length(mMarkers)));
  Assert.IsTrue(mMarkers[0].Opening);
  Assert.AreEqual(2, mMarkers[0].Line);
  Assert.IsFalse(mMarkers[1].Opening);
  Assert.AreEqual(4, mMarkers[1].Line);
  Assert.AreEqual(6, mMarkers[3].Line);
  mFolded := TAtlasBlockFolds.Folded(mMarkers);
  Assert.AreEqual(2, Integer(Length(mFolded)));
  Assert.AreEqual(2, mFolded[0].Open.Line);
  Assert.AreEqual(4, mFolded[0].Close.Line);
  Assert.AreEqual(1, TAtlasBlockFolds.FoldedAt(mFolded, 5), 'else-Zweig');
  Assert.AreEqual(0, TAtlasBlockFolds.FoldedAt(mFolded, 3), 'if-Zweig');
  Assert.AreEqual(-1, TAtlasBlockFolds.FoldedAt(mFolded, 7));
end;

procedure TAtlasBlockFoldsTests.RemoveRestoresText;
var
  mText: string;
begin
  mText := Applied(cIfElse, TAtlasBlockFolds.FoldEdits(cIfElse, IfElseBlocks));
  Assert.AreEqual(cIfElse, Applied(mText, TAtlasBlockFolds.RemoveEdits(TAtlasBlockFolds.Markers(mText))));
  // Eine Region von Hand ({$REGION}) bleibt unberührt.
  Assert.AreEqual(0, Integer(Length(TAtlasBlockFolds.Markers('{$REGION ''x''}'#13#10'{$ENDREGION}'))));
end;

procedure TAtlasBlockFoldsTests.CaptionCannotCloseMarker;
begin
  Assert.AreEqual('(*$REGION ''if S = "a* )" then''*)', TAtlasBlockFolds.OpenMarker('if S = ''a*)'' then'));
end;

procedure TAtlasBlockFoldsTests.ParamsNameDocument;
begin
  Assert.AreEqual('{"textDocument":{"uri":"file:///C:/A.pas"}}', TAtlasBlockFolds.Params('file:///C:/A.pas'));
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasBlockFoldsTests);

end.
