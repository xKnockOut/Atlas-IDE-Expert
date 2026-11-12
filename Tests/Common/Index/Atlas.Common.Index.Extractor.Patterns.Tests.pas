unit Atlas.Common.Index.Extractor.Patterns.Tests;

// Tests der Folgemuster für die gelernten Vorschläge (#1890): Auslöser und
// Schlüssel, Normalisierung mit $S und $A, Vorlagen für try … finally und
// while, Zählung je Unit, Cache und Builder.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TIndexFollowPatternsTests = class
  public
    [Test]
    procedure ConstructorWithTryFinally;
    [Test]
    procedure BeginUpdateWithReceiverChain;
    [Test]
    procedure CallWithoutReceiverUsesArgument;
    [Test]
    procedure WhileLoopKeepsLastStatement;
    [Test]
    procedure WhileBeginOnOwnLine;
    [Test]
    procedure OtherFollowCountsWithoutTemplate;
    [Test]
    procedure FinallyKeepsOnlyStatementsNamingTheSubject;
    [Test]
    procedure CommentsAndSpacesNormalized;
    [Test]
    procedure HexLiteralIsNoTemplate;
    [Test]
    procedure EvidenceLinesAtMostThree;
    [Test]
    procedure NormalizeTextKeepsMarkers;
    [Test]
    procedure CacheKeepsPatterns;
    [Test]
    procedure ExtractTextOnlyWithPatterns;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.TreeCache,
  Atlas.Common.Index.Contract,
  Atlas.Common.Index.Cache,
  Atlas.Common.Index.Extractor,
  Atlas.Common.Index.Extractor.Patterns;

/// <summary>Unit mit ABody als Rumpf einer Prozedur.</summary>
function UnitWith(const ABody: string): string;
begin
  Result := 'unit U;'#10'interface'#10'implementation'#10'procedure P;'#10'begin'#10 + ABody + 'end;'#10'end.';
end;

function PatternsOf(const AText: string): TArray<TIndexFollowPattern>;
var
  mTree: TSyntaxTree;
begin
  mTree := TSyntaxTreeCache.Parse(AText);
  try
    Result := TIndexFollowPatterns.Collect(mTree);
  finally
    mTree.Free;
  end;
end;

/// <summary>Eintrag mit Trigger und Folge; Count 0, wenn es ihn nicht gibt.</summary>
function Find(const APatterns: TArray<TIndexFollowPattern>; const ATrigger, AFollow: string): TIndexFollowPattern;
var
  mPattern: TIndexFollowPattern;
begin
  Result := Default(TIndexFollowPattern);
  for mPattern in APatterns do
  begin
    if SameText(mPattern.Trigger, ATrigger) and (mPattern.Follow = AFollow) then
    begin
      Exit(mPattern);
    end;
  end;
end;

const
  cTryFree = 'try'#10'>$|'#10'finally'#10'>$S.Free;'#10'end;';

procedure TIndexFollowPatternsTests.ConstructorWithTryFinally;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  X := TFoo.Create;'#10 +
    '  try'#10 +
    '    X.Add(1);'#10 +
    '  finally'#10 +
    '    X.Free;'#10 +
    '  end;'#10 +
    '  Y := TBar.Create(Self);'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    Y.Free;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S := TFoo.Create', cTryFree).Count);
  Assert.AreEqual(1, Find(mPatterns, '$S := TBar.Create', cTryFree).Count);
  Assert.AreEqual(2, Find(mPatterns, '$S := $T.Create', cTryFree).Count);
  Assert.AreEqual(5, Find(mPatterns, '$S := $T.Create', cTryFree).Lines[0], 'Zeile des ersten Auslösers');
end;

procedure TIndexFollowPatternsTests.BeginUpdateWithReceiverChain;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  L.Items.BeginUpdate;'#10 +
    '  try'#10 +
    '    L.Items.Clear;'#10 +
    '  finally'#10 +
    '    L.Items.EndUpdate;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S.BeginUpdate', 'try'#10'>$|'#10'finally'#10'>$S.EndUpdate;'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.CallWithoutReceiverUsesArgument;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  EnterCriticalSection(FLock);'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    LeaveCriticalSection(FLock);'#10 +
    '  end;'#10 +
    '  TMonitor.Enter(Self);'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    TMonitor.Exit(Self);'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, 'EnterCriticalSection($A)',
    'try'#10'>$|'#10'finally'#10'>LeaveCriticalSection($A);'#10'end;').Count);
  Assert.AreEqual(1, Find(mPatterns, '$S.Enter', 'try'#10'>$|'#10'finally'#10'>$S.Exit($A);'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.WhileLoopKeepsLastStatement;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  Q.Open;'#10 +
    '  while not Q.Eof do begin'#10 +
    '    Zeige(Q);'#10 +
    '    Q.Next;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S.Open', 'while not $S.Eof do begin'#10'>$|'#10'>$S.Next;'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.WhileBeginOnOwnLine;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  Q.Open;'#10 +
    '  while not Q.Eof do'#10 +
    '  begin'#10 +
    '    Q.Next;'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S.Open', 'while not $S.Eof do'#10'begin'#10'>$|'#10'>$S.Next;'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.OtherFollowCountsWithoutTemplate;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  X := TFoo.Create;'#10 +
    '  X.Add(1);'#10 +
    '  Y := TFoo.Create;'#10));
  Assert.AreEqual(2, Find(mPatterns, '$S := TFoo.Create', '').Count);
  Assert.AreEqual(0, Integer(Length(Find(mPatterns, '$S := TFoo.Create', '').Lines)), 'Ohne Folge keine Belege');
end;

procedure TIndexFollowPatternsTests.FinallyKeepsOnlyStatementsNamingTheSubject;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  X := TFoo.Create;'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    Fertig := True;'#10 +
    '    FreeAndNil(X);'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S := TFoo.Create', 'try'#10'>$|'#10'finally'#10'>FreeAndNil($S);'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.CommentsAndSpacesNormalized;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  Log . Enter ( ''a'' ) ;'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    Log.Leave { Ende };'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S.Enter', 'try'#10'>$|'#10'finally'#10'>$S.Leave;'#10'end;').Count);
end;

procedure TIndexFollowPatternsTests.HexLiteralIsNoTemplate;
var
  mPatterns: TArray<TIndexFollowPattern>;
begin
  mPatterns := PatternsOf(UnitWith(
    '  X.BeginUpdate;'#10 +
    '  try'#10 +
    '  finally'#10 +
    '    X.EndUpdate($A);'#10 +
    '  end;'#10));
  Assert.AreEqual(1, Find(mPatterns, '$S.BeginUpdate', '').Count, '$A aus dem Quelltext wäre ein Marker');
end;

procedure TIndexFollowPatternsTests.EvidenceLinesAtMostThree;
var
  mBody: string;
  mIndex: Integer;
  mPattern: TIndexFollowPattern;
begin
  mBody := '';
  for mIndex := 1 to 5 do
  begin
    mBody := mBody + '  X.BeginUpdate;'#10'  try'#10'  finally'#10'    X.EndUpdate;'#10'  end;'#10;
  end;
  mPattern := Find(PatternsOf(UnitWith(mBody)), '$S.BeginUpdate', 'try'#10'>$|'#10'finally'#10'>$S.EndUpdate;'#10'end;');
  Assert.AreEqual(5, mPattern.Count);
  Assert.AreEqual(3, Integer(Length(mPattern.Lines)));
end;

procedure TIndexFollowPatternsTests.NormalizeTextKeepsMarkers;
begin
  Assert.AreEqual('$S := $T.Create', TIndexFollowPatterns.NormalizeText('$S:=$T.Create'));
  Assert.AreEqual('Log.Enter', TIndexFollowPatterns.NormalizeText(' Log . Enter '));
  Assert.AreEqual('EnterCriticalSection($A)', TIndexFollowPatterns.NormalizeText('EnterCriticalSection( $a )'));
end;

procedure TIndexFollowPatternsTests.CacheKeepsPatterns;
var
  mUnit: TUnitIndex;
  mRead: TArray<TUnitIndex>;
  mPattern: TIndexFollowPattern;
begin
  mUnit := TIndexExtractor.ExtractText(UnitWith('  X.BeginUpdate;'#10'  try'#10'  finally'#10'    X.EndUpdate;'#10 +
    '  end;'#10), 'C:\P\U.pas', nil, nil, False, True);
  mRead := TIndexCache.Deserialize(TIndexCache.Serialize([mUnit]));
  Assert.AreEqual(1, Integer(Length(mRead)));
  // X.BeginUpdate mit Folge, X.EndUpdate im finally als Auslöser ohne Folge.
  Assert.AreEqual(2, Integer(Length(mRead[0].Patterns)));
  mPattern := Find(mRead[0].Patterns, '$S.BeginUpdate', mUnit.Patterns[0].Follow);
  Assert.AreEqual(1, mPattern.Count);
  Assert.AreEqual(5, mPattern.Lines[0]);
  Assert.AreEqual(1, Find(mRead[0].Patterns, '$S.EndUpdate', '').Count);
end;

procedure TIndexFollowPatternsTests.ExtractTextOnlyWithPatterns;
var
  mText: string;
begin
  mText := UnitWith('  X.BeginUpdate;'#10);
  Assert.AreEqual(0, Integer(Length(TIndexExtractor.ExtractText(mText, 'C:\P\U.pas', nil, nil, True).Patterns)));
  Assert.AreEqual(1, Integer(Length(TIndexExtractor.ExtractText(mText, 'C:\P\U.pas', nil, nil, False, True).Patterns)));
end;

initialization
  TDUnitX.RegisterTestFixture(TIndexFollowPatternsTests);

end.
