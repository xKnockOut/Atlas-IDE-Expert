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
  LogUnit =
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
  Tree, After: TSyntaxTree;
  Target: TOverloadTarget;
  Reason: string;
begin
  Tree := Parse(AText);
  try
    Assert.IsTrue(TOverloads.Target(AText, Tree, TTextPosition.Create(ALine, ACharacter), Target), 'Ziel');
    Assert.IsTrue(TOverloads.Build(AText, Tree, Target, AKind, ADefault, Result, Reason), Reason);
  finally
    Tree.Free;
  end;
  After := Parse(Result.NewText);
  try
    Assert.AreEqual(0, Integer(Length(After.Diagnostics)), Result.NewText);
  finally
    After.Free;
  end;
end;

function RunPlain(const AText: string; ALine, ACharacter: Integer; AKind: TOverloadKind): TOverloadResult;
begin
  Result := Run(AText, ALine, ACharacter, AKind, nil);
end;

/// <summary>Text des Platzhalters AIndex im Ergebnis.</summary>
function FieldText(const AResult: TOverloadResult; AIndex: Integer): string;
var
  Lines: TArray<string>;
  Range: TTextRange;
begin
  Lines := AResult.NewText.Split([#10]);
  Range := AResult.Placeholders[AIndex].Range;
  Assert.AreEqual(Range.StartPos.Line, Range.EndPos.Line, 'einzeilig');
  Result := Copy(Lines[Range.StartPos.Line], Range.StartPos.Character + 1,
    Range.EndPos.Character - Range.StartPos.Character);
end;

function Numbers(const AResult: TOverloadResult): string;
var
  Placeholder: TOverloadPlaceholder;
begin
  Result := '';
  for Placeholder in AResult.Placeholders do
    Result := Result + IntToStr(Placeholder.Number);
end;

procedure TOverloadsTests.CopyMethod;
var
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(LogUnit, 16, 18, TOverloadKind.Copy);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload; override;'#10 +
    '    /// <summary>Schreibt.</summary>'#10 +
    '    /// <param name="AText">Text</param>'#10 +
    '    /// <param name="ALevel">'#10 +
    '    /// Stufe</param>'#10 +
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload;'#10 +
    '    class function'), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains(
    '  Emit(AText, X);'#10'end;'#10#10 +
    'procedure TLog.Write(const AText: string; ALevel: TLogLevel);'#10 +
    'var'#10'  X: Integer;'#10'begin'#10'  X := 1;'#10'  Emit(AText, X);'#10'end;'#10 +
    'class function'), Outcome.NewText);
  // Parameterliste in Deklaration und Implementierung verknüpft, dann der Rumpf, dann das Ende.
  Assert.AreEqual('1120', Numbers(Outcome));
  Assert.AreEqual('const AText: string; ALevel: TLogLevel', FieldText(Outcome, 0));
  Assert.AreEqual('const AText: string; ALevel: TLogLevel', FieldText(Outcome, 1));
  Assert.AreEqual(35, Outcome.Placeholders[3].Range.StartPos.Line);
  Assert.AreEqual(1, Integer(Length(Outcome.Warnings)));
  // overload hinter dem Kopf (vor override), Deklaration, Implementierung.
  Assert.AreEqual(3, Integer(Length(Outcome.Edits)));
end;

procedure TOverloadsTests.CopyClassMethodKeepsStatic;
var
  Outcome: TOverloadResult;
begin
  // Cursor in der Deklaration in der Klasse.
  Outcome := RunPlain(LogUnit, 10, 22, TOverloadKind.Copy);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    class function Make(A: Integer; const B: string): TLog; overload; static;'#10 +
    '    class function Make(A: Integer; const B: string): TLog; overload; static;'#10), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains(
    'end;'#10#10'class function TLog.Make(A: Integer; const B: string): TLog;'#10'begin'#10 +
    '  Result := nil;'#10'end;'#10'destructor'), Outcome.NewText);
  Assert.AreEqual(0, Integer(Length(Outcome.Warnings)));
end;

procedure TOverloadsTests.CopyRoutineOnlyInImplementation;
const
  Source =
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
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(Source, 4, 10, TOverloadKind.Copy);
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
    'end.'#10, Outcome.NewText);
  Assert.AreEqual('120', Numbers(Outcome));
  Assert.AreEqual('A, B: Integer', FieldText(Outcome, 0));
  Assert.AreEqual('Result := A + B;', FieldText(Outcome, 1));
end;

procedure TOverloadsTests.CopyRoutineWithInterfaceDeclaration;
const
  Source =
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
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(Source, 4, 11, TOverloadKind.Copy);
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
    'end.'#10, Outcome.NewText);
  Assert.AreEqual('1120', Numbers(Outcome));
end;

procedure TOverloadsTests.CopyEmptyBody;
var
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(LogUnit, 12, 16, TOverloadKind.Copy);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    procedure Clear; overload;'#10'    procedure Clear(); overload;'#10), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains(
    'procedure TLog.Clear;'#10'begin'#10'end;'#10#10'procedure TLog.Clear();'#10'begin'#10'  '#10'end;'#10),
    Outcome.NewText);
  Assert.AreEqual('1120', Numbers(Outcome));
  Assert.AreEqual('', FieldText(Outcome, 0));
  Assert.AreEqual('', FieldText(Outcome, 2));
  Assert.AreEqual(2, Outcome.Placeholders[2].Range.StartPos.Character);
end;

procedure TOverloadsTests.ForwardProcedureDropsOverride;
var
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(LogUnit, 9, 15, TOverloadKind.Forward);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    procedure Write(const AText: string; ALevel: TLogLevel); overload; override;'#10 +
    '    /// <summary>Schreibt.</summary>'#10 +
    '    /// <param name="AText">Text</param>'#10 +
    '    procedure Write(const AText: string); overload;'#10), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains(
    'end;'#10#10'procedure TLog.Write(const AText: string);'#10'begin'#10 +
    '  Write(AText, Default(TLogLevel));'#10'end;'#10), Outcome.NewText);
  Assert.AreEqual('1120', Numbers(Outcome));
  Assert.AreEqual('const AText: string', FieldText(Outcome, 1));
  Assert.AreEqual('Default(TLogLevel)', FieldText(Outcome, 2));
  Assert.AreEqual(1, Integer(Length(Outcome.Warnings)));
  Assert.IsTrue(Outcome.Warnings[0].Contains('nicht virtuell'), Outcome.Warnings[0]);
end;

procedure TOverloadsTests.ForwardFunctionUsesResult;
var
  Outcome: TOverloadResult;
begin
  Outcome := RunPlain(LogUnit, 23, 22, TOverloadKind.Forward);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    class function Make(A: Integer): TLog; overload; static;'#10), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains(
    'class function TLog.Make(A: Integer): TLog;'#10'begin'#10'  Result := Make(A, '''');'#10'end;'#10),
    Outcome.NewText);
  Assert.AreEqual('''''', FieldText(Outcome, 2));
end;

procedure TOverloadsTests.ForwardDefaultFromLookup;
var
  Outcome: TOverloadResult;
  Seen: string;
  SeenOffset: Integer;
begin
  Seen := '';
  SeenOffset := -1;
  Outcome := Run(LogUnit, 9, 15, TOverloadKind.Forward,
    function(const ATypeName: string; ATypeOffset: Integer): string
    begin
      Seen := ATypeName;
      SeenOffset := ATypeOffset;
      Result := 'llInfo';
    end);
  Assert.AreEqual('TLogLevel', Seen);
  Assert.AreEqual(Pos('TLogLevel); override', LogUnit) - 1, SeenOffset);
  Assert.IsTrue(Outcome.NewText.Contains('  Write(AText, llInfo);'), Outcome.NewText);
end;

procedure TOverloadsTests.TargetPicksMatchingOverload;
const
  Source =
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
  Tree: TSyntaxTree;
  Target: TOverloadTarget;
  Outcome: TOverloadResult;
begin
  Tree := Parse(Source);
  try
    Assert.IsTrue(TOverloads.Target(Source, Tree, TTextPosition.Create(11, 14), Target));
    Assert.AreEqual(2, Integer(Length(Target.Decl.Parameters)));
    Assert.AreEqual('TA', Target.Container);
    Assert.AreEqual('Put', Target.Name);
    // Die Weiterleitung ergäbe Put(const S: string), die gibt es nicht; von Put(A) aus gäbe es Put() nicht.
    Assert.AreEqual('', Target.ForwardReason);
  finally
    Tree.Free;
  end;
  Outcome := RunPlain(Source, 5, 14, TOverloadKind.Forward);
  Assert.IsTrue(Outcome.NewText.Contains(
    '    procedure Put(const S: string; N: Integer); overload;'#10 +
    '    procedure Put(const S: string); overload;'#10), Outcome.NewText);
  Assert.IsTrue(Outcome.NewText.Contains('  Put(N);'#10'end;'#10#10'procedure TA.Put(const S: string);'#10 +
    'begin'#10'  Put(S, 0);'#10'end;'#10), Outcome.NewText);
  // Das Original hat schon overload: nur Deklaration und Implementierung.
  Assert.AreEqual(2, Integer(Length(Outcome.Edits)));
end;

procedure TOverloadsTests.Reasons;
const
  Twice =
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
  Tree: TSyntaxTree;
  Target: TOverloadTarget;
  Outcome: TOverloadResult;
  Reason: string;
begin
  Tree := Parse(LogUnit);
  try
    Assert.IsTrue(TOverloads.Target(LogUnit, Tree, TTextPosition.Create(11, 16), Target));
    Assert.AreEqual(TOverloads.DestructorReason, Target.CopyReason);
    Assert.AreEqual(TOverloads.DestructorReason, Target.ForwardReason);
    Assert.IsFalse(TOverloads.Build(LogUnit, Tree, Target, TOverloadKind.Copy, Outcome, Reason));
    Assert.AreEqual(TOverloads.DestructorReason, Reason);
    Assert.IsTrue(TOverloads.Target(LogUnit, Tree, TTextPosition.Create(12, 16), Target));
    Assert.AreEqual('', Target.CopyReason);
    Assert.AreEqual(TOverloads.NoParameterReason, Target.ForwardReason);
    Assert.IsTrue(TOverloads.Target(LogUnit, Tree, TTextPosition.Create(33, 16), Target));
    Assert.AreEqual(Format(TOverloads.VarParameterReason, ['ABuffer']), Target.ForwardReason);
    // Nicht im Kopf: kein Ziel.
    Assert.IsFalse(TOverloads.Target(LogUnit, Tree, TTextPosition.Create(20, 3), Target));
    Assert.IsFalse(TOverloads.Target(LogUnit, Tree, TTextPosition.Create(3, 4), Target));
  finally
    Tree.Free;
  end;
  Tree := Parse(Twice);
  try
    Assert.IsTrue(TOverloads.Target(Twice, Tree, TTextPosition.Create(11, 14), Target));
    Assert.AreEqual(Format(TOverloads.ExistsReason, ['Put', '']), Target.ForwardReason);
    Assert.AreEqual(TOverloads.ForwardTitle, Target.Title(TOverloadKind.Forward));
    Assert.AreEqual(TOverloads.CopyTitle, Target.Title(TOverloadKind.Copy));
  finally
    Tree.Free;
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
