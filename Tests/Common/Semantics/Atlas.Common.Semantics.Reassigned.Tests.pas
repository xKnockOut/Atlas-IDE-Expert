unit Atlas.Common.Semantics.Reassigned.Tests;

// Tests der neu zugewiesenen Variablen (#712): Zählung schreibender Stellen
// (:=, var-/out-Argument, Inc/Dec, Include/Exclude, Read/ReadLn), mögliche
// Änderungen, Inline-Variablen, Schleifenzähler, Parametermodifizierer,
// Felder, jede Kombination der Ziele und der Kandidat "Konstante".
// Ausschnitt (nur Routinen im Zeilenbereich, Felder nur auf Wunsch) und Abbruch.

interface

uses
  DUnitX.TestFramework,
  Atlas.Common.Semantics.ControlFlow.Signatures,
  Atlas.Common.Semantics.Reassigned;

type
  [TestFixture]
  TReassignedTests = class
  private
    /// <summary>Je Name "Name=Art:sicher/Schleife/moeglich", sortiert, mit Leerzeichen getrennt.</summary>
    class function Counts(const ASource: string): string; overload; static;
    class function Counts(const ASource: string; const ALookup: TFlowSignatureLookup): string; overload; static;
    /// <summary>Namen der neu zugewiesenen Einträge für ATargets, sortiert.</summary>
    class function Marked(const ASource: string; ATargets: TReassignedTargets): string; static;
    /// <summary>Stellen des Namens AName als "Zeile:Zeichen" mit w (schreibt), l (Schleife), m (womöglich).</summary>
    class function Places(const ASource, AName: string): string; static;
  public
    [Test]
    procedure AssignmentsAndIncDec;
    [Test]
    procedure VarAndOutArguments;
    [Test]
    procedure IncludeExcludeAndRead;
    [Test]
    procedure PossibleWritesDoNotCount;
    [Test]
    procedure ResolvedSignaturesFromLookup;
    [Test]
    procedure InlineVariables;
    [Test]
    procedure LoopCounters;
    [Test]
    procedure ParameterModifiers;
    [Test]
    procedure FieldsWrittenInOneMethod;
    [Test]
    procedure NestedRoutinesAndAnonymousMethods;
    [Test]
    procedure EveryTargetCombination;
    [Test]
    procedure ConstCandidates;
    [Test]
    procedure OccurrencesInTextOrder;
    [Test]
    procedure TargetNamesAndSymbolAt;
    [Test]
    procedure ScopeKeepsRoutinesInRange;
    [Test]
    procedure ScopeCountsFieldsInWholeFile;
    [Test]
    procedure ScopeCancellationRaises;
  end;

implementation

uses
  System.SysUtils,
  System.Generics.Collections,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser;

const
  cLB = #13#10;
  cWriteCodes: array[TReassignedWrite] of string = ('', 'w', 'l', 'm');

  cScopeSource =
    'unit U;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TBox = class' + cLB +
    '    FA, FB: Integer;' + cLB +
    '    procedure One;' + cLB +
    '    procedure Two;' + cLB +
    '  end;' + cLB +
    'implementation' + cLB +
    'procedure TBox.One;' + cLB +                      // 9
    'var' + cLB +
    '  X: Integer;' + cLB +
    'begin' + cLB +
    '  X := 1;' + cLB +
    '  X := 2;' + cLB +
    '  FA := X;' + cLB +
    'end;' + cLB +                                     // 16
    'procedure TBox.Two;' + cLB +                      // 17
    'var' + cLB +
    '  Y, FB: Integer;' + cLB +
    'begin' + cLB +
    '  Y := 1;' + cLB +
    '  Y := 2;' + cLB +
    '  FB := Y;' + cLB +
    '  FA := Y;' + cLB +
    'end;' + cLB +                                     // 25
    'end.';

type
  /// <summary>Abbruch, der immer gilt.</summary>
  TAlwaysCancelled = class(TInterfacedObject, IPascalCancellation)
  public
    function IsCancelled: Boolean;
  end;

function TAlwaysCancelled.IsCancelled: Boolean;
begin
  Result := True;
end;

/// <summary>Namen aus ASource im Ausschnitt AScope als "Name=Art:sicher", sortiert.</summary>
function ScopeNames(const ASource: string; const AScope: TReassignedScope): string;
var
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mItems: TList<string>;
begin
  mItems := TList<string>.Create;
  mTree := TPascalParser.Parse(ASource);
  try
    for mSymbol in TReassigned.Analyze(ASource, mTree, nil, AScope) do
    begin
      mItems.Add(Format('%s=%s:%d', [mSymbol.Name, TReassigned.cKindNames[mSymbol.Kind], mSymbol.Writes]));
    end;
    mItems.Sort;
    Result := string.Join(' ', mItems.ToArray);
  finally
    mTree.Free;
    mItems.Free;
  end;
end;

function Wrap(const ABody: string): string;
begin
  Result := 'unit U;' + cLB + 'interface' + cLB + 'implementation' + cLB + ABody + cLB + 'end.';
end;

class function TReassignedTests.Counts(const ASource: string): string;
begin
  Result := Counts(ASource, nil);
end;

class function TReassignedTests.Counts(const ASource: string; const ALookup: TFlowSignatureLookup): string;
var
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mItems: TList<string>;
begin
  mItems := TList<string>.Create;
  mTree := TPascalParser.Parse(ASource);
  try
    for mSymbol in TReassigned.Analyze(ASource, mTree, ALookup) do
    begin
      mItems.Add(Format('%s=%s:%d/%d/%d', [mSymbol.Name, TReassigned.cKindNames[mSymbol.Kind], mSymbol.Writes,
        mSymbol.LoopWrites, mSymbol.MaybeWrites]));
    end;
    mItems.Sort;
    Result := string.Join(' ', mItems.ToArray);
  finally
    mTree.Free;
    mItems.Free;
  end;
end;

class function TReassignedTests.Marked(const ASource: string; ATargets: TReassignedTargets): string;
var
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mItems: TList<string>;
begin
  mItems := TList<string>.Create;
  mTree := TPascalParser.Parse(ASource);
  try
    for mSymbol in TReassigned.Filter(TReassigned.Analyze(ASource, mTree, nil), ATargets) do
    begin
      mItems.Add(mSymbol.Name);
    end;
    mItems.Sort;
    Result := string.Join(' ', mItems.ToArray);
  finally
    mTree.Free;
    mItems.Free;
  end;
end;

/// <summary>Stellen von ASymbol als "Zeile:Spalte" mit Schreibkennung, mit Leerzeichen getrennt.</summary>
function OccurrencesText(const ASymbol: TReassignedSymbol): string;
var
  mOccurrence: TReassignedOccurrence;
begin
  Result := '';
  for mOccurrence in ASymbol.Occurrences do
  begin
    if Result <> '' then
    begin
      Result := Result + ' ';
    end;
    Result := Result + Format('%d:%d%s', [mOccurrence.Range.StartPos.Line, mOccurrence.Range.StartPos.Character,
      cWriteCodes[mOccurrence.Write]]);
  end;
end;

class function TReassignedTests.Places(const ASource, AName: string): string;
var
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mText: string;
begin
  Result := '';
  mTree := TPascalParser.Parse(ASource);
  try
    for mSymbol in TReassigned.Analyze(ASource, mTree, nil) do
    begin
      if SameText(mSymbol.Name, AName) then
      begin
        mText := OccurrencesText(mSymbol);
        if (Result <> '') and (mText <> '') then
        begin
          Result := Result + ' ';
        end;
        Result := Result + mText;
      end;
    end;
  finally
    mTree.Free;
  end;
end;

procedure TReassignedTests.AssignmentsAndIncDec;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A, B, C, D: Integer;' + cLB +
    'begin' + cLB +
    '  A := 1;' + cLB +
    '  A := A + 1;' + cLB +
    '  B := 2;' + cLB +
    '  C := 3;' + cLB +
    '  Inc(C);' + cLB +
    '  Dec(D, 2);' + cLB +
    '  Writeln(A, B, C, D);' + cLB +
    'end;';
begin
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0 C=local:2/0/0 D=local:1/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('A C', Marked(Wrap(cSource), TReassigned.cDefaultTargets));
end;

procedure TReassignedTests.VarAndOutArguments;
const
  cSource =
    'procedure Fill(var AValue: Integer; out AText: string; ACount: Integer);' + cLB +
    'begin' + cLB +
    'end;' + cLB +
    'procedure P;' + cLB +
    'var' + cLB +
    '  N, M: Integer;' + cLB +
    '  S: string;' + cLB +
    'begin' + cLB +
    '  N := 0;' + cLB +
    '  Fill(N, S, M);' + cLB +
    'end;';
begin
  // N: Zuweisung und var-Argument; S: out-Argument; M nur gelesen (Wertparameter).
  Assert.AreEqual('ACount=valueParameter:0/0/0 AText=varParameter:0/0/0 AValue=varParameter:0/0/0 ' +
    'M=local:0/0/0 N=local:2/0/0 S=local:1/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('N', Marked(Wrap(cSource), TReassigned.cDefaultTargets));
end;

procedure TReassignedTests.IncludeExcludeAndRead;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  Flags: TFlags;' + cLB +
    '  F: TextFile;' + cLB +
    '  Line: string;' + cLB +
    '  I: Integer;' + cLB +
    'begin' + cLB +
    '  Flags := [];' + cLB +
    '  Include(Flags, fA);' + cLB +
    '  Exclude(Flags, fB);' + cLB +
    '  ReadLn(F, Line);' + cLB +
    '  Read(F, I);' + cLB +
    '  Line := Line + ''x'';' + cLB +
    'end;';
begin
  Assert.AreEqual('F=local:2/0/0 Flags=local:3/0/0 I=local:1/0/0 Line=local:2/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('F Flags Line', Marked(Wrap(cSource), TReassigned.cDefaultTargets));
end;

procedure TReassignedTests.PossibleWritesDoNotCount;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A, B, C, D: TRec;' + cLB +
    'begin' + cLB +
    '  A := Default(TRec);' + cLB +
    '  Ptr := @A;' + cLB +
    '  B := Default(TRec);' + cLB +
    '  B.X := 1;' + cLB +
    '  C := Default(TRec);' + cLB +
    '  Unbekannt(C);' + cLB +
    '  D := Default(TRec);' + cLB +
    '  D.Liste.Add(1);' + cLB +
    'end;';
begin
  // Adresse, Teilzuweisung und unbekannte Signatur: womöglich, nicht gezählt; Methodenaufruf liest.
  Assert.AreEqual('A=local:1/0/1 B=local:1/0/1 C=local:1/0/1 D=local:1/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('', Marked(Wrap(cSource), TReassigned.cDefaultTargets));
end;

procedure TReassignedTests.ResolvedSignaturesFromLookup;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A, B: Integer;' + cLB +
    'begin' + cLB +
    '  A := 1;' + cLB +
    '  Liste.Fill(A);' + cLB +
    '  B := 1;' + cLB +
    '  Liste.Show(B);' + cLB +
    'end;';
var
  mLookup: TFlowSignatureLookup;
begin
  // Ohne Typauflösung ist Obj.Methode unbekannt; die Namensauflösung kennt die Signatur.
  Assert.AreEqual('A=local:1/0/1 B=local:1/0/1', Counts(Wrap(cSource)));
  mLookup :=
    function(ACall: TSyntaxNode; AArgument: Integer): TFlowArgumentMode
    begin
      Result := TFlowArgumentMode.Value;
      if SameText(ACall.Name, 'Fill') then
      begin
        Result := TFlowArgumentMode.Reference;
      end;
    end;
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0', Counts(Wrap(cSource), mLookup));
end;

procedure TReassignedTests.InlineVariables;
const
  cSource =
    'procedure P;' + cLB +
    'begin' + cLB +
    '  var A := 1;' + cLB +
    '  A := 2;' + cLB +
    '  var B: Integer := 3;' + cLB +
    '  var C: Integer;' + cLB +
    '  C := B;' + cLB +
    '  C := C * 2;' + cLB +
    '  const K = 5;' + cLB +
    '  Writeln(A, C, K);' + cLB +
    'end;';
begin
  // Der Startwert zählt als erste Zuweisung; Inline-Konstanten zählen nicht.
  Assert.AreEqual('A=inlineVariable:2/0/0 B=inlineVariable:1/0/0 C=inlineVariable:2/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('A C', Marked(Wrap(cSource), [TReassignedTarget.Locals]));
end;

procedure TReassignedTests.LoopCounters;
const
  cSource =
    'procedure P(const L: TList);' + cLB +
    'var' + cLB +
    '  I, Total: Integer;' + cLB +
    'begin' + cLB +
    '  Total := 0;' + cLB +
    '  for I := 0 to 9 do' + cLB +
    '    Total := Total + I;' + cLB +
    '  for var X in L do' + cLB +
    '    Writeln(X);' + cLB +
    'end;';
begin
  // L ist ein const-Parameter und zählt nicht.
  Assert.AreEqual('I=loopVariable:0/1/0 Total=local:2/0/0 X=loopVariable:0/1/0', Counts(Wrap(cSource)));
  Assert.AreEqual('Total', Marked(Wrap(cSource), [TReassignedTarget.Locals]));
  Assert.AreEqual('I X', Marked(Wrap(cSource), [TReassignedTarget.LoopVars]));
end;

procedure TReassignedTests.ParameterModifiers;
const
  cSource =
    'procedure P(A: Integer; const B: Integer; var C: Integer; out D: Integer; constref E: Integer;' + cLB +
    '  F: Integer; var G: Integer);' + cLB +
    'begin' + cLB +
    '  A := A + 1;' + cLB +
    '  C := B;' + cLB +
    '  D := E + F;' + cLB +
    '  Writeln(G);' + cLB +
    'end;';
begin
  // const und constref lassen sich nicht beschreiben und zählen nicht.
  Assert.AreEqual('A=valueParameter:1/0/0 C=varParameter:1/0/0 D=varParameter:1/0/0 F=valueParameter:0/0/0 ' +
    'G=varParameter:0/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('A', Marked(Wrap(cSource), [TReassignedTarget.ValueParams]));
  Assert.AreEqual('C D', Marked(Wrap(cSource), [TReassignedTarget.VarParams]));
end;

procedure TReassignedTests.FieldsWrittenInOneMethod;
const
  cSource =
    'unit U;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TZaehler = class' + cLB +
    '  private' + cLB +
    '    FCount, FName: string;' + cLB +
    '    FTwice: Integer;' + cLB +
    '    FSelf: Integer;' + cLB +
    '    FRead: Integer;' + cLB +
    '  public' + cLB +
    '    constructor Create;' + cLB +
    '    procedure Add;' + cLB +
    '    procedure Rename(const AName: string);' + cLB +
    '  end;' + cLB +
    'implementation' + cLB +
    'constructor TZaehler.Create;' + cLB +
    'begin' + cLB +
    '  FName := ''x'';' + cLB +
    'end;' + cLB +
    'procedure TZaehler.Add;' + cLB +
    'begin' + cLB +
    '  Inc(FCount);' + cLB +
    '  FTwice := 1;' + cLB +
    '  Self.FSelf := FSelf + 1;' + cLB +
    '  Writeln(FRead);' + cLB +
    'end;' + cLB +
    'procedure TZaehler.Rename(const AName: string);' + cLB +
    'begin' + cLB +
    '  FName := AName;' + cLB +
    '  FTwice := 2;' + cLB +
    'end;' + cLB +
    'end.';
begin
  Assert.AreEqual('FCount=field:1/0/0 FName=field:2/0/0 FRead=field:0/0/0 FSelf=field:1/0/0 FTwice=field:2/0/0',
    Counts(cSource));
  // FName schreibt auch der Konstruktor, FTwice zwei Methoden, FRead niemand.
  Assert.AreEqual('FCount FSelf', Marked(cSource, [TReassignedTarget.Fields]));
  Assert.AreEqual('', Marked(cSource, TReassigned.cDefaultTargets));
  Assert.AreEqual('7:4 23:7w 23:16', Places(cSource, 'FSelf'));
end;

procedure TReassignedTests.NestedRoutinesAndAnonymousMethods;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A, B: Integer;' + cLB +
    '  procedure Inner;' + cLB +
    '  var' + cLB +
    '    B: Integer;' + cLB +
    '  begin' + cLB +
    '    A := 2;' + cLB +
    '    B := 1;' + cLB +
    '  end;' + cLB +
    'begin' + cLB +
    '  A := 1;' + cLB +
    '  B := 1;' + cLB +
    '  Run(procedure(X: Integer)' + cLB +
    '    begin' + cLB +
    '      X := X + A;' + cLB +
    '      B := 2;' + cLB +
    '    end);' + cLB +
    'end;';
begin
  // A schreibt die verschachtelte Routine mit; ihr B ist ein eigener Name. Die anonyme Methode schreibt das
  // äußere B und ihren Parameter X.
  Assert.AreEqual('A=local:2/0/0 B=local:1/0/0 B=local:2/0/0 X=valueParameter:1/0/0', Counts(Wrap(cSource)));
  Assert.AreEqual('A B X', Marked(Wrap(cSource), TReassigned.cDefaultTargets));
end;

procedure TReassignedTests.EveryTargetCombination;
const
  cSource =
    'unit U;' + cLB +
    'interface' + cLB +
    'type' + cLB +
    '  TFoo = class' + cLB +
    '    FField: Integer;' + cLB +
    '    procedure Run(AValue: Integer; var AOut: Integer);' + cLB +
    '  end;' + cLB +
    'implementation' + cLB +
    'procedure TFoo.Run(AValue: Integer; var AOut: Integer);' + cLB +
    'var' + cLB +
    '  L, I: Integer;' + cLB +
    'begin' + cLB +
    '  L := 1;' + cLB +
    '  L := 2;' + cLB +
    '  for I := 1 to 2 do' + cLB +
    '    AValue := I;' + cLB +
    '  AOut := L;' + cLB +
    '  FField := 3;' + cLB +
    'end;' + cLB +
    'end.';
  cExpected: array[TReassignedTarget] of string = ('L', 'I', 'AValue', 'AOut', 'FField');
var
  mMask: Integer;
  mTargets: TReassignedTargets;
  mTarget: TReassignedTarget;
  mNames: TList<string>;
begin
  mNames := TList<string>.Create;
  try
    for mMask := 0 to (1 shl (Ord(High(TReassignedTarget)) + 1)) - 1 do
    begin
      mTargets := [];
      mNames.Clear;
      for mTarget := Low(TReassignedTarget) to High(TReassignedTarget) do
      begin
        if (mMask and (1 shl Ord(mTarget))) <> 0 then
        begin
          Include(mTargets, mTarget);
          mNames.Add(cExpected[mTarget]);
        end;
      end;
      mNames.Sort;
      Assert.AreEqual(string.Join(' ', mNames.ToArray), Marked(cSource, mTargets), 'Maske ' + IntToStr(mMask));
    end;
  finally
    mNames.Free;
  end;
end;

procedure TReassignedTests.ConstCandidates;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A, B, C: Integer;' + cLB +
    'begin' + cLB +
    '  A := 1;' + cLB +
    '  B := 1;' + cLB +
    '  B := 2;' + cLB +
    '  C := 1;' + cLB +
    '  Unbekannt(C);' + cLB +
    '  var D := A;' + cLB +
    '  for var I := 0 to 1 do' + cLB +
    '    Writeln(I, D);' + cLB +
    'end;';
var
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mNames: string;
begin
  mNames := '';
  mTree := TPascalParser.Parse(Wrap(cSource));
  try
    for mSymbol in TReassigned.Analyze(Wrap(cSource), mTree, nil) do
    begin
      if mSymbol.IsConstCandidate then
      begin
        mNames := mNames + mSymbol.Name + ' ';
      end;
    end;
  finally
    mTree.Free;
  end;
  Assert.AreEqual('A D', Trim(mNames));
end;

procedure TReassignedTests.OccurrencesInTextOrder;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  I: Integer;' + cLB +
    'begin' + cLB +
    '  I := 1;' + cLB +
    '  for I := I to 5 do' + cLB +
    '    Inc(Total, I);' + cLB +
    'end;';
begin
  // Zeilen ab 0 in der eingepackten Unit: Deklaration, Zuweisung, Schleife, Lesen.
  Assert.AreEqual('5:2 7:2w 8:6l 8:11 9:15', Places(Wrap(cSource), 'I'));
end;

procedure TReassignedTests.TargetNamesAndSymbolAt;
const
  cSource =
    'procedure P;' + cLB +
    'var' + cLB +
    '  A: Integer;' + cLB +
    'begin' + cLB +
    '  A := 1;' + cLB +
    '  A := 2;' + cLB +
    'end;';
var
  mTarget: TReassignedTarget;
  mTree: TSyntaxTree;
  mSymbol: TReassignedSymbol;
  mSymbols: TArray<TReassignedSymbol>;
begin
  Assert.IsTrue(TReassigned.TryParseTarget('valueParams', mTarget));
  Assert.AreEqual<TReassignedTarget>(TReassignedTarget.ValueParams, mTarget);
  Assert.IsTrue(TReassigned.TryParseTarget(' LOOPVARS ', mTarget));
  Assert.AreEqual<TReassignedTarget>(TReassignedTarget.LoopVars, mTarget);
  Assert.IsFalse(TReassigned.TryParseTarget('globals', mTarget));
  Assert.AreEqual<TReassignedTargets>([TReassignedTarget.Locals, TReassignedTarget.Fields],
    TReassigned.TargetsOf(TArray<string>.Create('locals', 'fields', 'x')));
  mTree := TPascalParser.Parse(Wrap(cSource));
  try
    mSymbols := TReassigned.Analyze(Wrap(cSource), mTree, nil);
    Assert.IsTrue(TReassigned.SymbolAt(mSymbols, TTextPosition.Create(8, 3), mSymbol));
    Assert.AreEqual('A', mSymbol.Name);
    Assert.AreEqual(2, mSymbol.WriteCount);
    Assert.AreEqual(2, Integer(Length(mSymbol.WriteLines)));
    Assert.AreEqual(7, mSymbol.WriteLines[0]);
    Assert.IsTrue(TReassigned.SymbolAt(mSymbols, TTextPosition.Create(5, 2), mSymbol), 'Deklaration');
    Assert.IsFalse(TReassigned.SymbolAt(mSymbols, TTextPosition.Create(7, 6), mSymbol));
  finally
    mSymbols := nil;
    mTree.Free;
  end;
end;

procedure TReassignedTests.ScopeKeepsRoutinesInRange;
var
  mScope: TReassignedScope;
begin
  mScope := TReassignedScope.Whole;
  Assert.AreEqual('FA=field:2 FB=field:0 FB=local:1 X=local:2 Y=local:2', ScopeNames(cScopeSource, mScope));
  // Nur Two reicht in den Bereich; ohne Ziel Fields keine Felder.
  mScope.Targets := [TReassignedTarget.Locals];
  mScope.FirstLine := 21;
  mScope.LastLine := 22;
  Assert.AreEqual('FB=local:1 Y=local:2', ScopeNames(cScopeSource, mScope));
  // Der Kopf von One genügt.
  mScope.FirstLine := 9;
  mScope.LastLine := 9;
  Assert.AreEqual('X=local:2', ScopeNames(cScopeSource, mScope));
end;

procedure TReassignedTests.ScopeCountsFieldsInWholeFile;
var
  mScope: TReassignedScope;
begin
  mScope := TReassignedScope.Whole;
  mScope.FirstLine := 21;
  mScope.LastLine := 24;
  // FA wird in One und Two geschrieben; das lokale FB in Two verdeckt das Feld, auch wenn One außen liegt.
  Assert.AreEqual('FA=field:2 FB=field:0 FB=local:1 Y=local:2', ScopeNames(cScopeSource, mScope));
  mScope.FirstLine := 13;
  mScope.LastLine := 13;
  Assert.AreEqual('FA=field:2 FB=field:0 X=local:2', ScopeNames(cScopeSource, mScope));
end;

procedure TReassignedTests.ScopeCancellationRaises;
var
  mScope: TReassignedScope;
begin
  mScope := TReassignedScope.Whole;
  mScope.Cancellation := TAlwaysCancelled.Create;
  Assert.WillRaise(
    procedure
    begin
      ScopeNames(cScopeSource, mScope);
    end,
    EReassignedCancelled);
end;

initialization
  TDUnitX.RegisterTestFixture(TReassignedTests);

end.
