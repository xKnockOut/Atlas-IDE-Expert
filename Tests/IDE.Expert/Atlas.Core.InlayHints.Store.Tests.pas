unit Atlas.Core.InlayHints.Store.Tests;

// Tests für den Zwischenspeicher der Inlay-Hints (#401).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TAtlasInlayHintStoreTests = class
  public
    [Test]
    procedure RecognizesLiterals;
    [Test]
    procedure KeepsOnlyHintsBeforeLiterals;
    [Test]
    procedure FetchesOnlyMissingVisibleLines;
    [Test]
    procedure DropsEverythingWhenTheTextChanges;
    /// <summary>Am Zeilenende fehlt der Bezug: Wert dabei, nur aussagekräftige Hinweise.</summary>
    [Test]
    procedure ShowsValueAndSkipsHintsThatSayNothing;
    /// <summary>Blockende-Beschriftungen (#620): getrennt von den Parameternamen, nicht hinter einem
    /// Kommentar, lange Texte gekürzt.</summary>
    [Test]
    procedure KeepsEndLabelsApart;
    /// <summary>Typmarken (#453): getrennt von den Parameternamen, auch vor Nicht-Literalen, je Stelle einmal.
    /// </summary>
    [Test]
    procedure KeepsTypeHintsApart;
    /// <summary>Include-Symbole (#860): getrennt von Typmarken und Parameternamen, je Stelle einmal.</summary>
    [Test]
    procedure KeepsDefineHintsApart;
    /// <summary>Steuerzeichen-Codes (#862): eigene Liste, je Stelle einmal.</summary>
    [Test]
    procedure KeepsCharHintsApart;
    /// <summary>Marken für Methoden ohne Self (#686): eigene Liste.</summary>
    [Test]
    procedure KeepsMethodHintsApart;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.InlayHints.Store;

function H(ALine, ACharacter: Integer; const AName: string): TAtlasInlayHint;
begin
  Result := Default(TAtlasInlayHint);
  Result.Line := ALine;
  Result.Character := ACharacter;
  Result.Name := AName;
end;

procedure TAtlasInlayHintStoreTests.RecognizesLiterals;
const
  cLine = 'F(''a'', 12, -3, $FF, #13, True, nil, X, TrueValue, False)';
begin
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 2), 'String');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 6), 'Zahl nach Leerraum');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 10), 'negative Zahl');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 14), 'Hex');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 19), 'Zeichen');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 24), 'True');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 30), 'nil');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(cLine, 35), 'Variable');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(cLine, 38), 'Bezeichner, der mit True beginnt');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(cLine, 49), 'False');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(cLine, 100), 'hinter dem Zeilenende');
end;

procedure TAtlasInlayHintStoreTests.KeepsOnlyHintsBeforeLiterals;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
begin
  mStore := TAtlasInlayHintStore.Create;
  try
    mText := 'begin'#13#10'  CopyFile(''a.txt'', Target, True);'#13#10'end.';
    mStore.SetText('C:\P\A.pas', mText);
    mStore.Put('C:\P\A.pas', mText, 0, 2, [H(1, 28, 'FailIfExists'), H(1, 11, 'Source'), H(1, 20, 'Dest')]);
    Assert.AreEqual('Source = ''a.txt'',FailIfExists = True', string.Join(',', mStore.OnLine('c:\p\a.pas', 1)));
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('C:\P\A.pas', 0))));
    // Derselbe Hinweis aus einem zweiten Abruf erscheint nicht doppelt.
    mStore.Put('C:\P\A.pas', mText, 1, 1, [H(1, 11, 'Source')]);
    Assert.AreEqual(2, Integer(Length(mStore.OnLine('C:\P\A.pas', 1))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.FetchesOnlyMissingVisibleLines;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
  mIndex, mFrom, mTill: Integer;
begin
  mStore := TAtlasInlayHintStore.Create;
  try
    mText := '';
    for mIndex := 1 to 200 do
    begin
      mText := mText + 'X;'#13#10;
    end;
    mStore.SetText('A.pas', mText);
    Assert.IsTrue(mStore.Missing('A.pas', 50, 80, mFrom, mTill));
    Assert.AreEqual(50 - TAtlasInlayHintStore.cMargin, mFrom);
    Assert.AreEqual(80 + TAtlasInlayHintStore.cMargin, mTill);
    mStore.Put('A.pas', mText, mFrom, mTill, nil);
    Assert.IsFalse(mStore.Missing('A.pas', 50, 80, mFrom, mTill));
    // Ein Stück weiter gescrollt: nur der neue Teil.
    Assert.IsTrue(mStore.Missing('A.pas', 70, 110, mFrom, mTill));
    Assert.AreEqual(101, mFrom);
    Assert.AreEqual(130, mTill);
    // Am Anfang und Ende der Datei begrenzt.
    Assert.IsTrue(mStore.Missing('A.pas', 0, 5, mFrom, mTill));
    Assert.AreEqual(0, mFrom);
    Assert.IsTrue(mStore.Missing('A.pas', 190, 230, mFrom, mTill));
    Assert.AreEqual(200, mTill, 'letzte (leere) Zeile');
    Assert.IsFalse(mStore.Missing('B.pas', 0, 5, mFrom, mTill), 'unbekannte Datei');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.DropsEverythingWhenTheTextChanges;
var
  mStore: TAtlasInlayHintStore;
  mLine: string;
begin
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', 'F(1, X);');
    mStore.Put('A.pas', 'F(1, X);', 0, 0, [H(0, 2, 'Wert')]);
    Assert.AreEqual(1, Integer(Length(mStore.OnLine('A.pas', 0))));
    // Antwort zu einem älteren Text wird verworfen.
    mStore.Put('A.pas', 'F(2, X);', 0, 0, [H(0, 2, 'Anderer')]);
    Assert.AreEqual('Wert = 1', mStore.OnLine('A.pas', 0)[0]);
    mStore.SetText('A.pas', 'F(1, 2);');
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 0))));
    Assert.IsTrue(mStore.LineText('A.pas', 0, mLine));
    Assert.AreEqual('F(1, 2);', mLine);
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.ShowsValueAndSkipsHintsThatSayNothing;
const
  //            0         1         2         3         4         5         6         7
  //            0123456789012345678901234567890123456789012345678901234567890123456789012
  cLine0 = '  Local := GetEnvironmentVariable(''LOCALAPPDATA'');';
  cLine1 = '  if SameText(ParamStr(Index), ''/uninstall'') then';
  cLine2 = '  Open(nil, True, ''sehr langer Dateiname, der gekürzt wird.pas'', OpenName);';
  cLine3 = '  Show(''Name: x'', 3);';
var
  mStore: TAtlasInlayHintStore;
  mText: string;
begin
  Assert.IsTrue(TAtlasInlayHintStore.IsVagueName('S2'));
  Assert.IsTrue(TAtlasInlayHintStore.IsVagueName('X'));
  Assert.IsFalse(TAtlasInlayHintStore.IsVagueName('Name'));
  Assert.AreEqual('''a, b''', TAtlasInlayHintStore.ArgumentAt('F(''a, b'', G(1, 2))', 2));
  Assert.AreEqual('G(1, 2)', TAtlasInlayHintStore.ArgumentAt('F(''a, b'', G(1, 2))', 10));
  mStore := TAtlasInlayHintStore.Create;
  try
    mText := cLine0 + #13#10 + cLine1 + #13#10 + cLine2 + #13#10 + cLine3;
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 3, [H(0, 34, 'Name'), H(1, 31, 'S2'), H(2, 7, 'AOwner'), H(2, 12, 'Exclusive'),
      H(2, 18, 'FileName'), H(3, 7, 'Name'), H(3, 18, 'Count')]);
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 0))), 'einziges Argument');
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'S2 sagt nichts');
    Assert.AreEqual('AOwner = nil|Exclusive = True|FileName = ''sehr langer Dateiname,…',
      string.Join('|', mStore.OnLine('A.pas', 2)));
    Assert.AreEqual('Count = 3', string.Join('|', mStore.OnLine('A.pas', 3)), 'Name steht schon im Argument');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsTypeHintsApart;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
  mTypes: TArray<TAtlasInlayHint>;
  mIndex: Integer;
begin
  mText := 'begin' + sLineBreak +
    '  var Count := Lines.Count;' + sLineBreak +
    '  for var Item in Liste do' + sLineBreak +
    'end;';
  mTypes := [H(1, 11, 'Integer'), H(2, 14, StringOfChar('T', 60)), H(1, 11, 'Integer'), H(3, 0, '')];
  for mIndex := 0 to High(mTypes) do
  begin
    mTypes[mIndex].TypeHint := True;
  end;
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 3, mTypes);
    Assert.AreEqual(': Integer', string.Join('|', mStore.TypesOnLine('A.pas', 1)), 'einmal');
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'keine Parameternamen');
    Assert.IsTrue(mStore.TypesOnLine('A.pas', 2)[0].EndsWith('…'), 'gekürzt');
    Assert.AreEqual(Integer(TAtlasInlayHintStore.cMaxTypeLength + 2), Integer(Length(mStore.TypesOnLine('A.pas', 2)[0])));
    Assert.AreEqual(0, Integer(Length(mStore.TypesOnLine('A.pas', 3))), 'ohne Typ');
    // Neuer Text verwirft auch die Typmarken.
    mStore.SetText('A.pas', mText + ' ');
    Assert.AreEqual(0, Integer(Length(mStore.TypesOnLine('A.pas', 1))));
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsDefineHintsApart;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
  mDefines: TArray<TAtlasInlayHint>;
  mIndex: Integer;
begin
  mText := 'unit U;' + sLineBreak + '{$I JVCL.INC}' + sLineBreak + '{$IFDEF COMPLIB_VCL}' + sLineBreak + '{$ENDIF}';
  mDefines := [H(1, 13, 'COMPLIB_VCL'), H(1, 13, 'COMPLIB_VCL'), H(2, 0, '')];
  for mIndex := 0 to High(mDefines) do
  begin
    mDefines[mIndex].DefineHint := True;
  end;
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 3, mDefines);
    Assert.AreEqual('COMPLIB_VCL', string.Join('|', mStore.DefinesOnLine('A.pas', 1)), 'einmal');
    Assert.AreEqual(0, Integer(Length(mStore.TypesOnLine('A.pas', 1))), 'keine Typmarke');
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'keine Parameternamen');
    Assert.AreEqual(0, Integer(Length(mStore.DefinesOnLine('A.pas', 2))), 'ohne Symbol');
    mStore.SetText('A.pas', mText + ' ');
    Assert.AreEqual(0, Integer(Length(mStore.DefinesOnLine('A.pas', 1))), 'neuer Text');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsCharHintsApart;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
  mChars: TArray<TAtlasInlayHint>;
  mIndex: Integer;
begin
  mText := 'const' + sLineBreak + '  CtrlC = ^C; Esc = ^[;';
  mChars := [H(1, 12, '#3'), H(1, 12, '#3'), H(1, 22, '#27')];
  for mIndex := 0 to High(mChars) do
  begin
    mChars[mIndex].CharHint := True;
  end;
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 1, mChars);
    Assert.AreEqual('#3|#27', string.Join('|', mStore.CharsOnLine('A.pas', 1)));
    Assert.AreEqual(0, Integer(Length(mStore.DefinesOnLine('A.pas', 1))), 'keine Include-Symbole');
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'keine Parameternamen');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsMethodHintsApart;
var
  mStore: TAtlasInlayHintStore;
  mText: string;
  mMarks: TArray<TAtlasInlayHint>;
  mCharacter: Integer;
begin
  mText := 'implementation' + sLineBreak + 'function TA.Mal(N: Integer): Integer;';
  mMarks := [H(1, 37, 'braucht kein Self'), H(1, 37, 'braucht kein Self')];
  mMarks[0].MethodHint := True;
  mMarks[1].MethodHint := True;
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 1, mMarks);
    Assert.IsTrue(mStore.MethodOnLine('A.pas', 1, mCharacter));
    // Ziel des Klicks auf die Marke: Ende des Kopfs.
    Assert.AreEqual(37, mCharacter, 'Stelle der Marke');
    Assert.IsFalse(mStore.MethodOnLine('A.pas', 0, mCharacter));
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'keine Parameternamen');
    Assert.AreEqual(0, Integer(Length(mStore.TypesOnLine('A.pas', 1))), 'keine Typmarken');
  finally
    mStore.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsEndLabelsApart;
var
  mStore: TAtlasInlayHintStore;
  mText, mAnchor, mCaption: string;
  mEnds: TArray<TAtlasInlayHint>;
  mHint: TAtlasInlayHint;
begin
  mText := 'begin' + sLineBreak +
    'end;' + sLineBreak +
    'end; // schon kommentiert' + sLineBreak +
    'end;' + sLineBreak +
    'end;';
  mEnds := [H(1, 4, 'TKunde.Speichern'), H(2, 4, 'TKunde.Laden'), H(3, 4, StringOfChar('x', 50)),
    H(4, 4, ''), H(1, 4, 'doppelt')];
  mEnds[0].EndLabel := True;
  mEnds[1].EndLabel := True;
  mEnds[2].EndLabel := True;
  mEnds[3].EndLabel := True;
  mEnds[4].EndLabel := True;
  mEnds[0].BlockLine := 0;
  mEnds[0].BlockCharacter := 2;
  mEnds[0].HasBlock := True;
  mStore := TAtlasInlayHintStore.Create;
  try
    mStore.SetText('A.pas', mText);
    mStore.Put('A.pas', mText, 0, 4, mEnds);
    Assert.IsTrue(mStore.EndLabelOn('A.pas', 1, mAnchor, mCaption));
    Assert.AreEqual('TKunde.Speichern', mAnchor);
    Assert.AreEqual('// TKunde.Speichern', mCaption);
    Assert.IsTrue(mStore.EndLabelOn('A.pas', 1, mAnchor, mCaption, mHint), 'mit Blockanfang (#620)');
    Assert.IsTrue(mHint.HasBlock);
    Assert.AreEqual(0, mHint.BlockLine);
    Assert.AreEqual(2, mHint.BlockCharacter);
    Assert.AreEqual(0, Integer(Length(mStore.OnLine('A.pas', 1))), 'keine Parameternamen');
    Assert.IsFalse(mStore.EndLabelOn('A.pas', 2, mAnchor, mCaption), 'Kommentar steht schon dahinter');
    Assert.IsTrue(mStore.EndLabelOn('A.pas', 3, mAnchor, mCaption));
    Assert.AreEqual(Integer(Length('// ') + TAtlasInlayHintStore.cMaxEndLabelLength), Integer(Length(mCaption)));
    Assert.IsTrue(mCaption.EndsWith('…'));
    Assert.IsFalse(mStore.EndLabelOn('A.pas', 4, mAnchor, mCaption), 'ohne Text');
    Assert.IsFalse(TAtlasInlayHintStore.HasCommentAfter('end; // ''x''', 10));
    Assert.IsFalse(TAtlasInlayHintStore.HasCommentAfter('S := ''//''; ', 4));
    Assert.IsTrue(TAtlasInlayHintStore.HasCommentAfter('end; { Ende }', 4));
  finally
    mStore.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlayHintStoreTests);

end.
