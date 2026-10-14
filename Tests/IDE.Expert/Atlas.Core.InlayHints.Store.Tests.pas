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
  end;

implementation

uses
  System.SysUtils,
  Atlas.Core.InlayHints.Store;

function H(ALine, ACharacter: Integer; const AName: string): TAtlasInlayHint;
begin
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
    Assert.AreEqual('Source,FailIfExists', string.Join(',', Store.OnLine('c:\p\a.pas', 1)));
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
    Store.SetText('A.pas', 'F(1);');
    Store.Put('A.pas', 'F(1);', 0, 0, [H(0, 2, 'Wert')]);
    Assert.AreEqual(1, Integer(Length(Store.OnLine('A.pas', 0))));
    // Antwort zu einem älteren Text wird verworfen.
    Store.Put('A.pas', 'F(2);', 0, 0, [H(0, 2, 'Anderer')]);
    Assert.AreEqual('Wert', Store.OnLine('A.pas', 0)[0]);
    Store.SetText('A.pas', 'F(1, 2);');
    Assert.AreEqual(0, Integer(Length(Store.OnLine('A.pas', 0))));
    Assert.IsTrue(Store.LineText('A.pas', 0, Line));
    Assert.AreEqual('F(1, 2);', Line);
  finally
    Store.Free;
  end;
end;

initialization
  TDUnitX.RegisterTestFixture(TAtlasInlayHintStoreTests);

end.
