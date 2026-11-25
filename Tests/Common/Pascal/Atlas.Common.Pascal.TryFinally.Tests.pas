unit Atlas.Common.Pascal.TryFinally.Tests;

// Tests für "try/finally ergänzen" (#42, #43).

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TPascalTryFinallyTests = class
  public
    [Test]
    procedure TryFinallyAfterCreate;
    [Test]
    procedure TryFinallyResultCompilesStructurally;
    [Test]
    procedure NoTryFinallyWhenAlreadyProtected;
    [Test]
    procedure ResultGetsTryExceptInsteadOfFree;
    [Test]
    procedure NoTryFinallyWithoutCreate;
    /// <summary>Felder (auch Self.F) bekommen keine Aktion; wem sie gehören, sieht man hier nicht (#42).</summary>
    [Test]
    procedure NoTryFinallyForFields;
    [Test]
    procedure NoTryFinallyWhenNothingFollows;
    /// <summary>Zurückgegeben, an eine Liste übergeben, mittendrin freigegeben, mit Owner oder Interface.</summary>
    [Test]
    procedure NoTryFinallyWhenObjectEscapes;
    [Test]
    procedure TryFinallyEnclosesSelectionOnly;
    [Test]
    procedure TryFinallyEndsWithInnerBlock;
    [Test]
    procedure TryFinallyFollowsFormatStyle;
    /// <summary>Lokale und Inline-Variable, mehrzeiliger Create-Aufruf, vorhandene Freigabe, Result.</summary>
    [Test]
    procedure TryFinallyMatchesGoldenFile;
  end;

implementation

uses
  System.SysUtils,
  System.IOUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.CodeActions.Contract,
  Atlas.Common.Pascal.TryFinally,
  Atlas.Tests.Files,
  Atlas.Tests.SourceText;

const
  cLB = #13#10;
  cBody =
    'procedure P;' + cLB +
    'var' + cLB +
    '  L: TStringList;' + cLB +
    'begin' + cLB +
    '  L := TStringList.Create;' + cLB +
    '  L.Add(''x'');' + cLB +
    'end;';

  cTryFinallyBefore =
    'unit Atlas.Common.Pascal.TryFinallyGolden;'#13#10 +
    #13#10 +
    '// Golden-Datei für "try/finally ergänzen" (#42): genau das, was die Aktion'#13#10 +
    '// aus den Routinen ohne try erzeugt. Der Test wendet die Aktion auf jede'#13#10 +
    '// Create-Zeile an und vergleicht mit dieser Datei; dass das Ergebnis'#13#10 +
    '// übersetzt, zeigt der Delphi-Testlauf. Nicht von Hand ändern, sondern neu'#13#10 +
    '// erzeugen.'#13#10 +
    #13#10 +
    'interface'#13#10 +
    #13#10 +
    'uses'#13#10 +
    '  System.Classes,'#13#10 +
    '  System.SysUtils;'#13#10 +
    #13#10 +
    'type'#13#10 +
    '  TFeldHalter = class'#13#10 +
    '  private'#13#10 +
    '    FListe: TStringList;'#13#10 +
    '  public'#13#10 +
    '    procedure Fuelle;'#13#10 +
    '    procedure FuelleUeberSelf;'#13#10 +
    '  end;'#13#10 +
    #13#10 +
    'function Zeilen: Integer;'#13#10 +
    'function InlineZeilen: Integer;'#13#10 +
    'function Mehrzeilig: Integer;'#13#10 +
    'procedure Freigabe;'#13#10 +
    'function Liste: TStringList;'#13#10 +
    #13#10 +
    'implementation'#13#10 +
    #13#10 +
    'procedure TFeldHalter.Fuelle;'#13#10 +
    'begin'#13#10 +
    '  FListe := TStringList.Create;'#13#10 +
    '  FListe.Add(''Feld'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'procedure TFeldHalter.FuelleUeberSelf;'#13#10 +
    'begin'#13#10 +
    '  Self.FListe := TStringList.Create;'#13#10 +
    '  Self.FListe.Add(''Feld'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Zeilen: Integer;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create;'#13#10 +
    '  Text.Add(''a'');'#13#10 +
    #13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function InlineZeilen: Integer;'#13#10 +
    'begin'#13#10 +
    '  var Text := TStringList.Create;'#13#10 +
    '  Text.Add(''a'');'#13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Mehrzeilig: Integer;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create('#13#10 +
    '    True);'#13#10 +
    '  Result := Text.Count;'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'procedure Freigabe;'#13#10 +
    'var'#13#10 +
    '  Text: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Text := TStringList.Create;'#13#10 +
    '  Text.Add(''x'');'#13#10 +
    '  FreeAndNil(Text);'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'function Liste: TStringList;'#13#10 +
    'begin'#13#10 +
    '  Result := TStringList.Create;'#13#10 +
    '  Result.Add(''x'');'#13#10 +
    'end;'#13#10 +
    #13#10 +
    'end.'#13#10;

function Apply(const AText: string; const AEdit: TTextEdit): string;
var
  mLines: TArray<string>;
  I, mOffset: Integer;
  function OffsetOf(const APos: TTextPosition): Integer;
  var
    L: Integer;
  begin
    Result := 0;
    for L := 0 to APos.Line - 1 do
    begin
      Inc(Result, Length(mLines[L]) + 1);
    end;
    Inc(Result, APos.Character);
  end;
begin
  mLines := AText.Split([#10]);
  mOffset := OffsetOf(AEdit.Range.StartPos);
  I := OffsetOf(AEdit.Range.EndPos);
  Result := Copy(AText, 1, mOffset) + AEdit.NewText + Copy(AText, I + 1, MaxInt);
end;

/// <summary>try/finally mit Stil AStyle für ARange; AText bleibt bei False unverändert.</summary>
function TryWith(const AText: string; const ARange: TTextRange; const AStyle: TFormatStyle;
  out ANewText: string): Boolean;
var
  mTree: TSyntaxTree;
  mAction: TCodeAction;
begin
  ANewText := AText;
  mTree := TPascalParser.Parse(AText);
  try
    Result := TPascalTryFinally.Offer(AText, mTree, ARange, AStyle, mAction);
  finally
    mTree.Free;
  end;
  if Result then
  begin
    ANewText := Apply(AText, mAction.Edits[0]);
  end;
end;

{ TPascalTryFinallyTests }

procedure TPascalTryFinallyTests.TryFinallyAfterCreate;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TPascalTryFinally.Offer(cBody, 4, mAction));
  Assert.AreEqual(cRewriteKind, mAction.Kind);
  Assert.AreEqual(1, Integer(Length(mAction.Edits)));
  Assert.AreEqual(4, mAction.Edits[0].Range.StartPos.Line);
  Assert.AreEqual(Integer(Length('  L := TStringList.Create;')), mAction.Edits[0].Range.StartPos.Character);
end;

procedure TPascalTryFinallyTests.TryFinallyResultCompilesStructurally;
var
  mAction: TCodeAction;
  mNewText: string;
begin
  Assert.IsTrue(TPascalTryFinally.Offer(cBody, 4, mAction));
  mNewText := Apply(cBody, mAction.Edits[0]);
  // Die folgenden Anweisungen stehen im try, der Block bleibt nicht leer.
  Assert.AreEqual(
    'procedure P;' + cLB + 'var' + cLB + '  L: TStringList;' + cLB + 'begin' + cLB +
    '  L := TStringList.Create;' + cLB + '  try' + cLB + '    L.Add(''x'');' + cLB + '  finally' + cLB + '    L.Free;' + cLB +
    '  end;' + cLB + 'end;', mNewText);
  Assert.AreEqual(0, TTestSource.SyntaxErrors(mNewText));
end;

procedure TPascalTryFinallyTests.NoTryFinallyWhenAlreadyProtected;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TPascalTryFinally.Offer('procedure P;' + cLB + 'var' + cLB + '  L: T;' + cLB + 'begin' + cLB +
    '  L := T.Create;' + cLB + cLB + '  try' + cLB + '    L.Run;' + cLB + '  finally' + cLB + '    L.Free;' + cLB + '  end;' + cLB +
    'end;', 4, mAction));
end;

procedure TPascalTryFinallyTests.ResultGetsTryExceptInsteadOfFree;
var
  mAction: TCodeAction;
  mText, mNewText: string;
begin
  // Ein Rückgabewert darf nicht im finally freigegeben werden, nur im Fehlerfall.
  mText := 'function F: TList;' + cLB + 'begin' + cLB + '  Result := TList.Create;' + cLB + '  Result.Add(nil);' + cLB +
    'end;';
  Assert.IsTrue(TPascalTryFinally.Offer(mText, 2, mAction));
  mNewText := Apply(mText, mAction.Edits[0]);
  Assert.AreEqual('function F: TList;' + cLB + 'begin' + cLB + '  Result := TList.Create;' + cLB + '  try' + cLB +
    '    Result.Add(nil);' + cLB + '  except' + cLB + '    Result.Free;' + cLB + '    raise;' + cLB + '  end;' + cLB + 'end;',
    mNewText);
  Assert.AreEqual(0, Pos('finally', mNewText));
  Assert.AreEqual(0, TTestSource.SyntaxErrors(mNewText));
end;

procedure TPascalTryFinallyTests.NoTryFinallyWithoutCreate;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TPascalTryFinally.Offer(cBody, 5, mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cBody, 2, mAction));
end;

procedure TPascalTryFinallyTests.NoTryFinallyForFields;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TPascalTryFinally.Offer('procedure TA.P;' + cLB + 'begin' + cLB + '  FList := TList.Create;' + cLB +
    '  FList.Add(nil);' + cLB + 'end;', 2, mAction));
  Assert.IsFalse(TPascalTryFinally.Offer('procedure TA.P;' + cLB + 'begin' + cLB + '  Self.FList := TList.Create;' + cLB +
    '  FList.Add(nil);' + cLB + 'end;', 2, mAction));
  // Gleicher Name wie ein Feld, aber lokal deklariert: Aktion.
  Assert.IsTrue(TPascalTryFinally.Offer('procedure TA.P;' + cLB + 'var' + cLB + '  FList: TList;' + cLB + 'begin' + cLB +
    '  FList := TList.Create;' + cLB + '  FList.Add(nil);' + cLB + 'end;', 4, mAction));
end;

procedure TPascalTryFinallyTests.NoTryFinallyWhenNothingFollows;
var
  mAction: TCodeAction;
begin
  Assert.IsFalse(TPascalTryFinally.Offer('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB +
    '  L := TList.Create;' + cLB + 'end;', 4, mAction));
  // Nur die Freigabe folgt: Der try-Block bliebe leer.
  Assert.IsFalse(TPascalTryFinally.Offer('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB +
    '  L := TList.Create;' + cLB + '  L.Free;' + cLB + 'end;', 4, mAction));
  // Einzelne Anweisung hinter then: kein Platz für try.
  Assert.IsFalse(TPascalTryFinally.Offer('procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' +
    cLB + '  if B then' + cLB + '    L := TList.Create;' + cLB + '  L.Add(nil);' + cLB + 'end;', 5, mAction));
end;

procedure TPascalTryFinallyTests.NoTryFinallyWhenObjectEscapes;
const
  cHead = 'procedure P(AOwner: TComponent; AItems: TList);' + cLB + 'var' + cLB + '  L: TList;' + cLB + '  I: IInterface;' +
    cLB + 'begin' + cLB;
var
  mAction: TCodeAction;
begin
  Assert.IsTrue(TPascalTryFinally.Offer(cHead + '  L := TList.Create;' + cLB + '  L.Add(nil);' + cLB + 'end;', 5, mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cHead + '  L := TList.Create;' + cLB + '  AItems.Add(L);' + cLB + 'end;', 5,
    mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cHead + '  L := TList.Create;' + cLB + '  FKeep := L;' + cLB + 'end;', 5, mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cHead + '  L := TList.Create;' + cLB + '  L.Free;' + cLB + '  L.Add(nil);' + cLB +
    'end;', 5, mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cHead + '  L := TList.Create(AOwner);' + cLB + '  L.Add(nil);' + cLB + 'end;', 5,
    mAction));
  Assert.IsFalse(TPascalTryFinally.Offer(cHead + '  I := TInterfacedObject.Create;' + cLB + '  I._AddRef;' + cLB +
    'end;', 5, mAction));
end;

procedure TPascalTryFinallyTests.TryFinallyEnclosesSelectionOnly;
const
  cText = 'procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  L := TList.Create;' + cLB +
    '  L.Add(nil);' + cLB + '  L.Add(nil);' + cLB + '  Done;' + cLB + 'end;';
var
  mNewText: string;
begin
  // Auswahl von der Create-Zeile bis in die zweite Add-Zeile: Done bleibt hinter dem try.
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 2, 6, 5), TFormatStyle.Default, mNewText));
  Assert.AreEqual('procedure P;' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  L := TList.Create;' + cLB +
    '  try' + cLB + '    L.Add(nil);' + cLB + '    L.Add(nil);' + cLB + '  finally' + cLB + '    L.Free;' + cLB + '  end;' +
    cLB + '  Done;' + cLB + 'end;', mNewText);
  // Auswahl bis zum Anfang der Zeile von Done: Die Zeile zählt nicht mit.
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 7, 0), TFormatStyle.Default, mNewText));
  Assert.IsTrue(Pos('  end;' + cLB + '  Done;', mNewText) > 0, mNewText);
end;

procedure TPascalTryFinallyTests.TryFinallyEndsWithInnerBlock;
const
  cText = 'procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  if B then' + cLB +
    '  begin' + cLB + '    L := TList.Create;' + cLB + '    L.Add(nil);' + cLB + '  end;' + cLB + '  Done;' + cLB + 'end;';
var
  mNewText: string;
begin
  Assert.IsTrue(TryWith(cText, TTextRange.Create(6, 0, 6, 0), TFormatStyle.Default, mNewText));
  Assert.AreEqual('procedure P(B: Boolean);' + cLB + 'var' + cLB + '  L: TList;' + cLB + 'begin' + cLB + '  if B then' + cLB +
    '  begin' + cLB + '    L := TList.Create;' + cLB + '    try' + cLB + '      L.Add(nil);' + cLB + '    finally' + cLB +
    '      L.Free;' + cLB + '    end;' + cLB + '  end;' + cLB + '  Done;' + cLB + 'end;', mNewText);
  Assert.AreEqual(0, TTestSource.SyntaxErrors(mNewText));
end;

procedure TPascalTryFinallyTests.TryFinallyFollowsFormatStyle;
const
  cText = 'procedure P;' + cLB + 'var' + cLB + '    L: TList;' + cLB + 'begin' + cLB + '    L := TList.Create;' + cLB +
    '    L.Add(nil);' + cLB + 'end;';
var
  mStyle: TFormatStyle;
  mNewText: string;
begin
  mStyle := TFormatStyle.Default;
  mStyle.IndentSize := 4;
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 4, 0), mStyle, mNewText));
  Assert.IsTrue(Pos('    try' + cLB + '        L.Add(nil);' + cLB + '    finally' + cLB + '        L.Free;' + cLB +
    '    end;', mNewText) > 0, mNewText);
  mStyle.UseTabs := True;
  Assert.IsTrue(TryWith(cText, TTextRange.Create(4, 0, 4, 0), mStyle, mNewText));
  Assert.IsTrue(Pos('    try' + cLB + #9'    L.Add(nil);' + cLB + '    finally' + cLB + '    '#9'L.Free;', mNewText) > 0,
    mNewText);
end;

procedure TPascalTryFinallyTests.TryFinallyMatchesGoldenFile;
const
  // Zeilen mit Create, von unten nach oben, damit die Zeilennummern darüber gelten.
  cLines: array[0..6] of Integer = (80, 73, 64, 55, 47, 39, 33);
  cExpected: array[0..6] of Boolean = (True, True, True, True, True, False, False);
var
  mFileName, mGolden, mText: string;
  mIndex: Integer;
  mAction: TCodeAction;
begin
  mFileName := TTestData.Path(TPath.Combine('Common', TPath.Combine('Pascal',
    'Atlas.Common.Pascal.TryFinallyGolden.pas')));
  Assert.AreNotEqual('', mFileName, 'Golden-Datei nicht gefunden');
  mGolden := TFile.ReadAllText(mFileName, TEncoding.UTF8);
  if (mGolden <> '') and (mGolden[1] = #$FEFF) then
  begin
    Delete(mGolden, 1, 1);
  end;
  mText := cTryFinallyBefore;
  for mIndex := 0 to High(cLines) do
  begin
    Assert.AreEqual(cExpected[mIndex], TPascalTryFinally.Offer(mText, cLines[mIndex], mAction),
      IntToStr(cLines[mIndex]));
    if cExpected[mIndex] then
    begin
      mText := Apply(mText, mAction.Edits[0]);
    end;
  end;
  Assert.AreEqual(mGolden, mText);
  Assert.AreEqual(0, TTestSource.SyntaxErrors(mText));
end;

initialization
  TDUnitX.RegisterTestFixture(TPascalTryFinallyTests);

end.
