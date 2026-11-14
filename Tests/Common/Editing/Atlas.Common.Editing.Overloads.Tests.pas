unit Atlas.Common.Editing.Overloads.Tests;

// Tests für „Überladung anlegen“ (#674): Kopie für Methode, Klassenmethode
// und freie Routine (nur implementation, mit interface-Deklaration),
// Weiterleitung für Prozedur und Funktion samt Standardwerten, override wird
// nicht kopiert und bringt einen Hinweis, ///-Kommentar ohne den <param> des
// weggelassenen Parameters, Platzhalter in Deklaration und Implementierung,
// leerer Rumpf, die richtige Überladung als Ziel und die Gründe, aus denen es
// nicht geht. Jedes Ergebnis parst fehlerfrei.

interface

uses
  DUnitX.TestFramework;

type
  [TestFixture]
  TOverloadsTests = class
  public
    [Test]
    procedure CopyMethod;
    [Test]
    procedure CopyClassMethodKeepsStatic;
    [Test]
    procedure CopyRoutineOnlyInImplementation;
    [Test]
    procedure CopyRoutineWithInterfaceDeclaration;
    [Test]
    procedure CopyEmptyBody;
    [Test]
    procedure ForwardProcedureDropsOverride;
    [Test]
    procedure ForwardFunctionUsesResult;
    [Test]
    procedure ForwardDefaultFromLookup;
    [Test]
    procedure TargetPicksMatchingOverload;
    [Test]
    procedure Reasons;
    [Test]
    procedure DefaultValues;
  end;

implementation

uses
  System.SysUtils,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Parser,
  Atlas.Common.Editing.Overloads;

const
  cLogUnit =
    'unit Log;'#10 +                                                         // 0
    'interface'#10 +                                                         // 1
    'type'#10 +                                                              // 2
    '  TLog = class(TBase)'#10 +                                             // 3
    '  public'#10 +                                                          // 4
    '    /// <summary>Schreibt.</summary>'#10 +                              // 5
    '    /// <param name="AText">Text</param>'#10 +                          // 6
    '    /// <param name="ALevel">'#10 +                                     // 7
    '    /// Stufe</param>'#10 +                                             // 8
    '    procedure Write(const AText: string; ALevel: TLogLevel); override;'#10 + // 9
    '    class function Make(A: Integer; const B: string): TLog; static;'#10 + // 10
    '    destructor Destroy; override;'#10 +                                 // 11
    '    procedure Clear;'#10 +                                              // 12
    '    procedure Read(var ABuffer: string);'#10 +                          // 13
    '  end;'#10 +                                                            // 14
    'implementation'#10 +                                                    // 15
    'procedure TLog.Write(const AText: string; ALevel: TLogLevel);'#10 +     // 16
    'var'#10 +                                                               // 17
    '  X: Integer;'#10 +                                                     // 18
    'begin'#10 +                                                             // 19
    '  X := 1;'#10 +                                                         // 20
    '  Emit(AText, X);'#10 +                                                 // 21
    'end;'#10 +                                                              // 22
    'class function TLog.Make(A: Integer; const B: string): TLog;'#10 +      // 23
    'begin'#10 +                                                             // 24
    '  Result := nil;'#10 +                                                  // 25
    'end;'#10 +                                                              // 26
    'destructor TLog.Destroy;'#10 +                                          // 27
    'begin'#10 +                                                             // 28
    'end;'#10 +                                                              // 29
    'procedure TLog.Clear;'#10 +                                             // 30
    'begin'#10 +                                                             // 31
    'end;'#10 +                                                              // 32
    'procedure TLog.Read(var ABuffer: string);'#10 +                         // 33
    'begin'#10 +                                                             // 34
    'end;'#10 +                                                              // 35
    'end.'#10;

function Parse(const AText: string): TSyntaxTree;
begin
  Result := TPascalParser.Parse(AText);
end;

/// <summary>Überladung an Zeile/Zeichen; prüft, dass das Ergebnis fehlerfrei parst.</summary>
function Run(const AText: string; ALine, ACharacter: Integer; AKind: TOverloadKind;
  const ADefault: TOverloadDefaultFunc): TOverloadResult;
var
  mTree, mAfter: TSyntaxTree;
  mTarget: TOverloadTarget;
  mReason: string;
begin
  mTree := Parse(AText);
  try
    Assert.IsTrue(TOverloads.Target(AText, mTree, TTextPosition.Create(ALine, ACharacter), mTarget), 'Ziel');
    Assert.IsTrue(TOverloads.Build(AText, mTree, mTarget, TOverloadRequest.Create(AKind, ADefault), Result, mReason),
      mReason);
  finally
    mTree.Free;
  end;
  mAfter := Parse(Result.NewText);
  try
    Assert.AreEqual(0, Integer(Length(mAfter.Diagnostics)), Result.NewText);
  finally
    mAfter.Free;
  end;
end;

function RunPlain(const AText: string; ALine, ACharacter: Integer; AKind: TOverloadKind): TOverloadResult;
begin
  Result := Run(AText, ALine, ACharacter, AKind, nil);
end;

/// <summary>Text des Platzhalters AIndex im Ergebnis.</summary>
function FieldText(const AResult: TOverloadResult; AIndex: Integer): string;
var
  mLines: TArray<string>;
  mRange: TTextRange;
begin
  mLines := AResult.NewText.Split([#10]);
  mRange := AResult.Placeholders[AIndex].Range;
  Assert.AreEqual(mRange.StartPos.Line, mRange.EndPos.Line, 'einzeilig');
  Result := Copy(mLines[mRange.StartPos.Line], mRange.StartPos.Character + 1,
    mRange.EndPos.Character - mRange.StartPos.Character);
end;

function Numbers(const AResult: TOverloadResult): string;
var
  mPlaceholder: TOverloadPlaceholder;
begin
  Result := '';
  for mPlaceholder in AResult.Placeholders do
  begin
    Result := Result + IntToStr(mPlaceholder.Number);
  end;
end;

procedure TOverloadsTests.CopyMethod;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cLogUnit, 16, 18, TOverloadKind.Copy);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload; override;'#10 +
    '    /// <summary>Schreibt.</summary>'#10 +
    '    /// <param name="AText">Text</param>'#10 +
    '    /// <param name="ALevel">'#10 +
    '    /// Stufe</param>'#10 +
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload;'#10 +
    '    class function'), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '  Emit(AText, X);'#10'end;'#10#10 +
    'procedure TLog.Write(const AText: string; ALevel: TLogLevel);'#10 +
    'var'#10'  X: Integer;'#10'begin'#10'  X := 1;'#10'  Emit(AText, X);'#10'end;'#10 +
    'class function'), mOutcome.NewText);
  // Parameterliste in Deklaration und Implementierung verknüpft, dann der Rumpf, dann das Ende.
  Assert.AreEqual('1120', Numbers(mOutcome));
  Assert.AreEqual('const AText: string; ALevel: TLogLevel', FieldText(mOutcome, 0));
  Assert.AreEqual('const AText: string; ALevel: TLogLevel', FieldText(mOutcome, 1));
  Assert.AreEqual(35, mOutcome.Placeholders[3].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(mOutcome.Warnings)));
  // overload hinter dem Kopf (vor override), Deklaration, Implementierung.
  Assert.AreEqual(3, Integer(Length(mOutcome.Edits)));
end;

procedure TOverloadsTests.CopyClassMethodKeepsStatic;
var
  mOutcome: TOverloadResult;
begin
  // Cursor in der Deklaration in der Klasse.
  mOutcome := RunPlain(cLogUnit, 10, 22, TOverloadKind.Copy);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    class function Make(A: Integer; const B: string): TLog; overload; static;'#10 +
    '    class function Make(A: Integer; const B: string): TLog; overload; static;'#10), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains(
    'end;'#10#10'class function TLog.Make(A: Integer; const B: string): TLog;'#10'begin'#10 +
    '  Result := nil;'#10'end;'#10'destructor'), mOutcome.NewText);
  Assert.AreEqual(0, Integer(Length(mOutcome.Warnings)));
end;

procedure TOverloadsTests.CopyRoutineOnlyInImplementation;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '/// <summary>Rechnet.</summary>'#10 +
    'function Sum(A, B: Integer): Integer; inline;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'end.'#10;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cSource, 4, 10, TOverloadKind.Copy);
  Assert.AreEqual(
    'unit U;'#10 +
    'interface'#10 +
    'implementation'#10 +
    '/// <summary>Rechnet.</summary>'#10 +
    'function Sum(A, B: Integer): Integer; overload; inline;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10#10 +
    '/// <summary>Rechnet.</summary>'#10 +
    'function Sum(A, B: Integer): Integer; overload; inline;'#10 +
    'begin'#10 +
    '  Result := A + B;'#10 +
    'end;'#10 +
    'end.'#10, mOutcome.NewText);
  Assert.AreEqual('120', Numbers(mOutcome));
  Assert.AreEqual('A, B: Integer', FieldText(mOutcome, 0));
  Assert.AreEqual('Result := A + B;', FieldText(mOutcome, 1));
end;

procedure TOverloadsTests.CopyRoutineWithInterfaceDeclaration;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'procedure Run(const AName: string);'#10 +
    'implementation'#10 +
    'procedure Run(const AName: string);'#10 +
    'begin'#10 +
    '  Go(AName);'#10 +
    'end;'#10 +
    'end.'#10;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cSource, 4, 11, TOverloadKind.Copy);
  Assert.AreEqual(
    'unit U;'#10 +
    'interface'#10 +
    'procedure Run(const AName: string); overload;'#10 +
    'procedure Run(const AName: string); overload;'#10 +
    'implementation'#10 +
    'procedure Run(const AName: string);'#10 +
    'begin'#10 +
    '  Go(AName);'#10 +
    'end;'#10#10 +
    'procedure Run(const AName: string);'#10 +
    'begin'#10 +
    '  Go(AName);'#10 +
    'end;'#10 +
    'end.'#10, mOutcome.NewText);
  Assert.AreEqual('1120', Numbers(mOutcome));
end;

procedure TOverloadsTests.CopyEmptyBody;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cLogUnit, 12, 16, TOverloadKind.Copy);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    procedure Clear; overload;'#10'    procedure Clear(); overload;'#10), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains(
    'procedure TLog.Clear;'#10'begin'#10'end;'#10#10'procedure TLog.Clear();'#10'begin'#10'  '#10'end;'#10),
    mOutcome.NewText);
  Assert.AreEqual('1120', Numbers(mOutcome));
  Assert.AreEqual('', FieldText(mOutcome, 0));
  Assert.AreEqual('', FieldText(mOutcome, 2));
  Assert.AreEqual(2, mOutcome.Placeholders[2].Range.StartPos.Character);
end;

procedure TOverloadsTests.ForwardProcedureDropsOverride;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cLogUnit, 9, 15, TOverloadKind.Forward);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload; override;'#10 +
    '    /// <summary>Schreibt.</summary>'#10 +
    '    /// <param name="AText">Text</param>'#10 +
    '    procedure Write(const AText: string); overload;'#10), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains(
    'end;'#10#10'procedure TLog.Write(const AText: string);'#10'begin'#10 +
    '  Write(AText, Default(TLogLevel));'#10'end;'#10), mOutcome.NewText);
  Assert.AreEqual('1120', Numbers(mOutcome));
  Assert.AreEqual('const AText: string', FieldText(mOutcome, 1));
  Assert.AreEqual('Default(TLogLevel)', FieldText(mOutcome, 2));
  Assert.AreEqual(1, Integer(Length(mOutcome.Warnings)));
  Assert.IsTrue(mOutcome.Warnings[0].Contains('nicht virtuell'), mOutcome.Warnings[0]);
end;

procedure TOverloadsTests.ForwardFunctionUsesResult;
var
  mOutcome: TOverloadResult;
begin
  mOutcome := RunPlain(cLogUnit, 23, 22, TOverloadKind.Forward);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    class function Make(A: Integer): TLog; overload; static;'#10), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains(
    'class function TLog.Make(A: Integer): TLog;'#10'begin'#10'  Result := Make(A, '''');'#10'end;'#10),
    mOutcome.NewText);
  Assert.AreEqual('''''', FieldText(mOutcome, 2));
end;

procedure TOverloadsTests.ForwardDefaultFromLookup;
var
  mOutcome: TOverloadResult;
  mSeen: string;
  mSeenOffset: Integer;
begin
  mSeen := '';
  mSeenOffset := -1;
  mOutcome := Run(cLogUnit, 9, 15, TOverloadKind.Forward,
    function(const ATypeName: string; ATypeOffset: Integer): string
    begin
      mSeen := ATypeName;
      mSeenOffset := ATypeOffset;
      Result := 'llInfo';
    end);
  Assert.AreEqual('TLogLevel', mSeen);
  Assert.AreEqual(Pos('TLogLevel); override', cLogUnit) - 1, mSeenOffset);
  Assert.IsTrue(mOutcome.NewText.Contains('  Write(AText, llInfo);'), mOutcome.NewText);
end;

procedure TOverloadsTests.TargetPicksMatchingOverload;
const
  cSource =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    procedure Put(A: Integer); overload;'#10 +
    '    procedure Put(const S: string; N: Integer); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TA.Put(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Put(const S: string; N: Integer);'#10 +
    'begin'#10 +
    '  Put(N);'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTree: TSyntaxTree;
  mTarget: TOverloadTarget;
  mOutcome: TOverloadResult;
begin
  mTree := Parse(cSource);
  try
    Assert.IsTrue(TOverloads.Target(cSource, mTree, TTextPosition.Create(11, 14), mTarget));
    Assert.AreEqual(2, Integer(Length(mTarget.Decl.Parameters)));
    Assert.AreEqual('TA', mTarget.Container);
    Assert.AreEqual('Put', mTarget.Name);
    // Die Weiterleitung ergäbe Put(const S: string), die gibt es nicht; von Put(A) aus gäbe es Put() nicht.
    Assert.AreEqual('', mTarget.ForwardReason);
  finally
    mTree.Free;
  end;
  mOutcome := RunPlain(cSource, 5, 14, TOverloadKind.Forward);
  Assert.IsTrue(mOutcome.NewText.Contains(
    '    procedure Put(const S: string; N: Integer); overload;'#10 +
    '    procedure Put(const S: string); overload;'#10), mOutcome.NewText);
  Assert.IsTrue(mOutcome.NewText.Contains('  Put(N);'#10'end;'#10#10'procedure TA.Put(const S: string);'#10 +
    'begin'#10'  Put(S, 0);'#10'end;'#10), mOutcome.NewText);
  // Das Original hat schon overload: nur Deklaration und Implementierung.
  Assert.AreEqual(2, Integer(Length(mOutcome.Edits)));
end;

procedure TOverloadsTests.Reasons;
const
  cTwice =
    'unit U;'#10 +
    'interface'#10 +
    'type'#10 +
    '  TA = class'#10 +
    '    procedure Put; overload;'#10 +
    '    procedure Put(A: Integer); overload;'#10 +
    '  end;'#10 +
    'implementation'#10 +
    'procedure TA.Put;'#10 +
    'begin'#10 +
    'end;'#10 +
    'procedure TA.Put(A: Integer);'#10 +
    'begin'#10 +
    'end;'#10 +
    'end.'#10;
var
  mTree: TSyntaxTree;
  mTarget: TOverloadTarget;
  mOutcome: TOverloadResult;
  mReason: string;
begin
  mTree := Parse(cLogUnit);
  try
    Assert.IsTrue(TOverloads.Target(cLogUnit, mTree, TTextPosition.Create(11, 16), mTarget));
    Assert.AreEqual(TOverloads.DestructorReason, mTarget.CopyReason);
    Assert.AreEqual(TOverloads.DestructorReason, mTarget.ForwardReason);
    Assert.IsFalse(TOverloads.Build(cLogUnit, mTree, mTarget, TOverloadKind.Copy, mOutcome, mReason));
    Assert.AreEqual(TOverloads.DestructorReason, mReason);
    Assert.IsTrue(TOverloads.Target(cLogUnit, mTree, TTextPosition.Create(12, 16), mTarget));
    Assert.AreEqual('', mTarget.CopyReason);
    Assert.AreEqual(TOverloads.NoParameterReason, mTarget.ForwardReason);
    Assert.IsTrue(TOverloads.Target(cLogUnit, mTree, TTextPosition.Create(33, 16), mTarget));
    Assert.AreEqual(Format(TOverloads.VarParameterReason, ['ABuffer']), mTarget.ForwardReason);
    // Nicht im Kopf: kein Ziel.
    Assert.IsFalse(TOverloads.Target(cLogUnit, mTree, TTextPosition.Create(20, 3), mTarget));
    Assert.IsFalse(TOverloads.Target(cLogUnit, mTree, TTextPosition.Create(3, 4), mTarget));
  finally
    mTree.Free;
  end;
  mTree := Parse(cTwice);
  try
    Assert.IsTrue(TOverloads.Target(cTwice, mTree, TTextPosition.Create(11, 14), mTarget));
    Assert.AreEqual(Format(TOverloads.ExistsReason, ['Put', '']), mTarget.ForwardReason);
    Assert.AreEqual(TOverloads.ForwardTitle, mTarget.Title(TOverloadKind.Forward));
    Assert.AreEqual(TOverloads.CopyTitle, mTarget.Title(TOverloadKind.Copy));
  finally
    mTree.Free;
  end;
end;

procedure TOverloadsTests.DefaultValues;
begin
  Assert.AreEqual('0', TOverloads.DefaultValue('Integer'));
  Assert.AreEqual('0', TOverloads.DefaultValue('Double'));
  Assert.AreEqual('''''', TOverloads.DefaultValue('string'));
  Assert.AreEqual('#0', TOverloads.DefaultValue('Char'));
  Assert.AreEqual('False', TOverloads.DefaultValue('Boolean'));
  Assert.AreEqual('nil', TOverloads.DefaultValue('TObject'));
  Assert.AreEqual('[]', TOverloads.DefaultValue('array of Integer'));
  Assert.AreEqual('0', TOverloads.DefaultValue('System.Int64'));
  Assert.AreEqual('', TOverloads.DefaultValue('TKunde'));
end;

initialization
  TDUnitX.RegisterTestFixture(TOverloadsTests);

end.
