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
  Line = 'F(''a'', 12, -3, $FF, #13, True, nil, X, TrueValue, False)';
begin
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 2), 'String');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 6), 'Zahl nach Leerraum');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 10), 'negative Zahl');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 14), 'Hex');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 19), 'Zeichen');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 24), 'True');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 30), 'nil');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(Line, 35), 'Variable');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(Line, 38), 'Bezeichner, der mit True beginnt');
  Assert.IsTrue(TAtlasInlayHintStore.IsLiteralAt(Line, 49), 'False');
  Assert.IsFalse(TAtlasInlayHintStore.IsLiteralAt(Line, 100), 'hinter dem Zeilenende');
end;

procedure TAtlasInlayHintStoreTests.KeepsOnlyHintsBeforeLiterals;
var
  Store: TAtlasInlayHintStore;
  Text: string;
begin
  Store := TAtlasInlayHintStore.Create;
  try
    Text := 'begin'#13#10'  CopyFile(''a.txt'', Target, True);'#13#10'end.';
    Store.SetText('C:\P\A.pas', Text);
    Store.Put('C:\P\A.pas', Text, 0, 2, [H(1, 28, 'FailIfExists'), H(1, 11, 'Source'), H(1, 20, 'Dest')]);
    Assert.AreEqual('Source = ''a.txt'',FailIfExists = True', string.Join(',', Store.OnLine('c:\p\a.pas', 1)));
    Assert.AreEqual(0, Integer(Length(Store.OnLine('C:\P\A.pas', 0))));
    // Derselbe Hinweis aus einem zweiten Abruf erscheint nicht doppelt.
    Store.Put('C:\P\A.pas', Text, 1, 1, [H(1, 11, 'Source')]);
    Assert.AreEqual(2, Integer(Length(Store.OnLine('C:\P\A.pas', 1))));
  finally
    Store.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.FetchesOnlyMissingVisibleLines;
var
  Store: TAtlasInlayHintStore;
  Text: string;
  Index, From, Till: Integer;
begin
  Store := TAtlasInlayHintStore.Create;
  try
    Text := '';
    for Index := 1 to 200 do
      Text := Text + 'X;'#13#10;
    Store.SetText('A.pas', Text);
    Assert.IsTrue(Store.Missing('A.pas', 50, 80, From, Till));
    Assert.AreEqual(50 - TAtlasInlayHintStore.Margin, From);
    Assert.AreEqual(80 + TAtlasInlayHintStore.Margin, Till);
    Store.Put('A.pas', Text, From, Till, nil);
    Assert.IsFalse(Store.Missing('A.pas', 50, 80, From, Till));
    // Ein Stück weiter gescrollt: nur der neue Teil.
    Assert.IsTrue(Store.Missing('A.pas', 70, 110, From, Till));
    Assert.AreEqual(101, From);
    Assert.AreEqual(130, Till);
    // Am Anfang und Ende der Datei begrenzt.
    Assert.IsTrue(Store.Missing('A.pas', 0, 5, From, Till));
    Assert.AreEqual(0, From);
    Assert.IsTrue(Store.Missing('A.pas', 190, 230, From, Till));
    Assert.AreEqual(200, Till, 'letzte (leere) Zeile');
    Assert.IsFalse(Store.Missing('B.pas', 0, 5, From, Till), 'unbekannte Datei');
  finally
    Store.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.DropsEverythingWhenTheTextChanges;
var
  Store: TAtlasInlayHintStore;
  Line: string;
begin
  Store := TAtlasInlayHintStore.Create;
  try
    Store.SetText('A.pas', 'F(1, X);');
    Store.Put('A.pas', 'F(1, X);', 0, 0, [H(0, 2, 'Wert')]);
    Assert.AreEqual(1, Integer(Length(Store.OnLine('A.pas', 0))));
    // Antwort zu einem älteren Text wird verworfen.
    Store.Put('A.pas', 'F(2, X);', 0, 0, [H(0, 2, 'Anderer')]);
    Assert.AreEqual('Wert = 1', Store.OnLine('A.pas', 0)[0]);
    Store.SetText('A.pas', 'F(1, 2);');
    Assert.AreEqual(0, Integer(Length(Store.OnLine('A.pas', 0))));
    Assert.IsTrue(Store.LineText('A.pas', 0, Line));
    Assert.AreEqual('F(1, 2);', Line);
  finally
    Store.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.ShowsValueAndSkipsHintsThatSayNothing;
const
  //            0         1         2         3         4         5         6         7
  //            0123456789012345678901234567890123456789012345678901234567890123456789012
  Line0 = '  Local := GetEnvironmentVariable(''LOCALAPPDATA'');';
  Line1 = '  if SameText(ParamStr(Index), ''/uninstall'') then';
  Line2 = '  Open(nil, True, ''sehr langer Dateiname, der gekürzt wird.pas'', OpenName);';
  Line3 = '  Show(''Name: x'', 3);';
var
  Store: TAtlasInlayHintStore;
  Text: string;
begin
  Assert.IsTrue(TAtlasInlayHintStore.IsVagueName('S2'));
  Assert.IsTrue(TAtlasInlayHintStore.IsVagueName('X'));
  Assert.IsFalse(TAtlasInlayHintStore.IsVagueName('Name'));
  Assert.AreEqual('''a, b''', TAtlasInlayHintStore.ArgumentAt('F(''a, b'', G(1, 2))', 2));
  Assert.AreEqual('G(1, 2)', TAtlasInlayHintStore.ArgumentAt('F(''a, b'', G(1, 2))', 10));
  Store := TAtlasInlayHintStore.Create;
  try
    Text := Line0 + #13#10 + Line1 + #13#10 + Line2 + #13#10 + Line3;
    Store.SetText('A.pas', Text);
    Store.Put('A.pas', Text, 0, 3, [H(0, 34, 'Name'), H(1, 31, 'S2'), H(2, 7, 'AOwner'), H(2, 12, 'Exclusive'),
      H(2, 18, 'FileName'), H(3, 7, 'Name'), H(3, 18, 'Count')]);
    Assert.AreEqual(0, Integer(Length(Store.OnLine('A.pas', 0))), 'einziges Argument');
    Assert.AreEqual(0, Integer(Length(Store.OnLine('A.pas', 1))), 'S2 sagt nichts');
    Assert.AreEqual('AOwner = nil|Exclusive = True|FileName = ''sehr langer Dateiname,…',
      string.Join('|', Store.OnLine('A.pas', 2)));
    Assert.AreEqual('Count = 3', string.Join('|', Store.OnLine('A.pas', 3)), 'Name steht schon im Argument');
  finally
    Store.Free;
  end;
end;

procedure TAtlasInlayHintStoreTests.KeepsEndLabelsApart;
var
  Store: TAtlasInlayHintStore;
  Text, Anchor, Caption: string;
  Ends: TArray<TAtlasInlayHint>;
begin
  Text := 'begin' + sLineBreak +
    'end;' + sLineBreak +
    'end; // schon kommentiert' + sLineBreak +
    'end;' + sLineBreak +
    'end;';
  Ends := [H(1, 4, 'TKunde.Speichern'), H(2, 4, 'TKunde.Laden'), H(3, 4, StringOfChar('x', 50)),
    H(4, 4, ''), H(1, 4, 'doppelt')];
  Ends[0].EndLabel := True;
  Ends[1].EndLabel := True;
  Ends[2].EndLabel := True;
  Ends[3].EndLabel := True;
  Ends[4].EndLabel := True;
  Store := TAtlasInlayHintStore.Create;
  try
    Store.SetText('A.pas', Text);
    Store.Put('A.pas', Text, 0, 4, Ends);
    Assert.IsTrue(Store.EndLabelOn('A.pas', 1, Anchor, Caption));
    Assert.AreEqual('TKunde.Speichern', Anchor);
    Assert.AreEqual('// TKunde.Speichern', Caption);
    Assert.AreEqual(0, Integer(Length(Store.OnLine('A.pas', 1))), 'keine Parameternamen');
    Assert.IsFalse(Store.EndLabelOn('A.pas', 2, Anchor, Caption), 'Kommentar steht schon dahinter');
    Assert.IsTrue(Store.EndLabelOn('A.pas', 3, Anchor, Caption));
    Assert.AreEqual(Integer(Length('// ') + TAtlasInlayHintStore.MaxEndLabelLength), Integer(Length(Caption)));
    Assert.IsTrue(Caption.EndsWith('…'));
    Assert.IsFalse(Store.EndLabelOn('A.pas', 4, Anchor, Caption), 'ohne Text');
    Assert.IsFalse(TAtlasInlayHintStore.HasCommentAfter('end; // ''x''', 10));
    Assert.IsFalse(TAtlasInlayHintStore.HasCommentAfter('S := ''//''; ', 4));
    Assert.IsTrue(TAtlasInlayHintStore.HasCommentAfter('end; { Ende }', 4));
  finally
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlayHintStoreTests);

end.
