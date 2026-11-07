unit Atlas.Common.Rules.Builtin.Performance;

// Performance-Regeln (#278, abgetrennt aus #57). Alle standardmäßig aus:
//   string-concat-in-loop     S := S + … in einer Schleife; in Delphi meist harmlos
//                             (In-place-Vergrößerung), deshalb nur niedrige Konfidenz
//   loop-invariant-call       teurer Aufruf in der Bedingung von while bzw. until, die bei
//                             jedem Durchlauf neu ausgewertet wird (die Grenzen von for nicht)
//   missing-begin-update      Items/Lines/Strings.Add in einer Schleife ohne BeginUpdate; still bei
//                             Menüs (TMenuItem hat kein BeginUpdate) und bei for-Schleifen mit
//                             höchstens FewIterations Durchläufen (feste Grenzen bzw. statisches
//                             Array der Datei)
// Standardmäßig an (#974):
//   setlength-in-loop         SetLength(A, Length(A) + 1) in einer Schleife kopiert das
//                             dynamische Array bei jedem Durchlauf; gemeldet wird nur, wenn A
//                             sicher ein dynamisches Array ist (Typ in der Datei bzw. bekannter
//                             RTL-Typ, nie Strings). Bei einer for-Schleife ist die Anzahl
//                             bekannt; dann setzt die Korrektur die Länge vor der Schleife,
//                             wenn A eine lokale Variable ist, die vorher nicht benutzt wird,
//                             und A in der Schleife nur über A[High(A)] bzw. A[Length(A) - 1]
//                             beschrieben wird.
// managed-param-without-const (#975) steht in Atlas.Common.Rules.Builtin.Performance.ManagedParams und
// wird hier mit angemeldet.
// ParamByName in Schleifen und DisableControls gehören zu #70.

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TStringConcatInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TLoopInvariantCallRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TMissingBeginUpdateRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TSetLengthInLoopRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Performance-Regeln.</summary>
procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  System.RegularExpressions,
  Atlas.Text.Lines,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Editing.ChangeSignature,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Semantics.NameResolver.Symbols,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.Builtin.Performance.DynamicArrays,
  Atlas.Common.Rules.Builtin.Performance.ManagedParams,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TPerformanceText = (ConcatTitle, Concat, ConditionTitle, ConditionString, ConditionCall, BeginUpdateTitle,
    BeginUpdate, SetLengthBefore, SetLengthKnown, SetLengthUnknown, GrowTitle);

const
  cTexts: array[TPerformanceText] of TAtlasText = (
    (De: 'String-Verkettung in einer Schleife'; En: 'String concatenation in a loop'),
    (De: '%s wird in der Schleife schrittweise verlängert; bei vielen Durchläufen ist TStringBuilder schneller';
     En: '%s is extended step by step in the loop; with many iterations TStringBuilder is faster'),
    (De: 'Teurer Aufruf in der Schleifenbedingung'; En: 'Expensive call in the loop condition'),
    (De: '.%s baut bei jeder Prüfung der Bedingung einen neuen String auf; vor der Schleife in eine Variable ' +
      'übernehmen';
     En: '.%s builds a new string on every check of the condition; move it into a variable before the loop'),
    (De: '%s wird bei jeder Prüfung der Bedingung erneut ausgeführt; ändert sich das Ergebnis nicht, vor der ' +
      'Schleife berechnen';
     En: '%s is executed again on every check of the condition; if the result does not change, compute it before the ' +
      'loop'),
    (De: 'Hinzufügen in einer Schleife ohne BeginUpdate'; En: 'Adding in a loop without BeginUpdate'),
    (De: 'Jedes %s in der Schleife zeichnet das Steuerelement neu; die Schleife mit %s.BeginUpdate und try … finally ' +
      '%s.EndUpdate umschließen';
     En: 'Every %s in the loop repaints the control; enclose the loop with %s.BeginUpdate and try … finally ' +
      '%s.EndUpdate'),
    (De: 'Länge von %s vor der Schleife setzen'; En: 'Set the length of %s before the loop'),
    (De: 'SetLength in der Schleife kopiert %s bei jedem Durchlauf; die Anzahl %s ist vorher bekannt.';
     En: 'SetLength in the loop copies %s on every iteration; the count %s is known beforehand.'),
    (De: 'SetLength in der Schleife kopiert %s bei jedem Durchlauf; die Länge vor der Schleife setzen oder die Werte ' +
      'in einer TList<T> sammeln.';
     En: 'SetLength in the loop copies %s on every iteration; set the length before the loop or collect the values ' +
      'in a TList<T>.'),
    (De: 'Dynamisches Array wächst in einer Schleife um je ein Element';
     En: 'Dynamic array grows by one element per loop iteration'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;

  /// <summary>Schleife mit Rumpf und (bei while/repeat) Bedingung als Tokenbereiche.</summary>
  TLoop = record
    Keyword: Integer;
    BodyFirst: Integer;
    BodyLast: Integer;
    /// <summary>Bedingung von while bzw. until; CondFirst > CondLast bei for.</summary>
    CondFirst: Integer;
    CondLast: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

function OpensBlock(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.IsKeyword('begin') or AToken.IsKeyword('try') or AToken.IsKeyword('case') or
    AToken.IsKeyword('asm') or AToken.IsKeyword('repeat');
end;

type
{$SCOPEDENUMS ON}
  /// <summary>Wie es nach einem Token beim Suchen des Anweisungsendes weitergeht.</summary>
  TStatementStep = (Next, StopBefore, StopAt);
{$SCOPEDENUMS OFF}

/// <summary>Ein end bei der Tiefe ADepth: vor ihm endet die Anweisung auf oberster Ebene; beginnt die Anweisung
/// selbst mit dem Block (AFirst), endet sie mit seinem end.</summary>
function EndStep(const AFirst: TPascalToken; var ADepth: Integer): TStatementStep;
begin
  if ADepth = 0 then
  begin
    Exit(TStatementStep.StopBefore);
  end;
  Dec(ADepth);
  Result := TStatementStep.Next;
  if (ADepth = 0) and OpensBlock(AFirst) then
  begin
    Result := TStatementStep.StopAt;
  end;
end;

/// <summary>Token auf oberster Ebene: if öffnet einen möglichen else-Zweig, else ohne offenes if und ;
/// beenden die Anweisung.</summary>
function TopLevelStep(const AToken: TPascalToken; var AOpenIfs: Integer): TStatementStep;
begin
  Result := TStatementStep.Next;
  if AToken.IsKeyword('if') then
  begin
    Inc(AOpenIfs);
  end
  else if AToken.IsKeyword('else') then
  begin
    if AOpenIfs = 0 then
    begin
      Result := TStatementStep.StopBefore;
    end
    else
    begin
      Dec(AOpenIfs);
    end;
  end
  else if AToken.IsSymbol(';') then
  begin
    Result := TStatementStep.StopBefore;
  end;
end;

/// <summary>Letztes Token der Anweisung ab AFirst: bis zum passenden end bzw. vor ; oder end.
/// Ein else gehört zur Anweisung, solange ein if davor noch keinen else-Zweig hat
/// (if … then begin … end else …).</summary>
function StatementEnd(const ATokens: TTokens; AFirst: Integer): Integer;
var
  mIndex, mDepth, mOpenIfs: Integer;
  mStep: TStatementStep;
begin
  mDepth := 0;
  mOpenIfs := 0;
  mIndex := AFirst;
  Result := AFirst;
  while mIndex <= High(ATokens) do
  begin
    mStep := TStatementStep.Next;
    if OpensBlock(ATokens[mIndex]) then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsKeyword('until') then
    begin
      Dec(mDepth);
    end
    else if ATokens[mIndex].IsKeyword('end') then
    begin
      mStep := EndStep(ATokens[AFirst], mDepth);
    end
    else if mDepth = 0 then
    begin
      mStep := TopLevelStep(ATokens[mIndex], mOpenIfs);
    end;
    if mStep = TStatementStep.StopAt then
    begin
      Exit(mIndex);
    end;
    if mStep = TStatementStep.StopBefore then
    begin
      Exit;
    end;
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Result := mIndex;
    end;
    Inc(mIndex);
  end;
end;

/// <summary>Index von do bzw. until ab AFirst auf gleicher Klammerebene; -1 ohne.</summary>
function FindKeyword(const ATokens: TTokens; AFirst: Integer; const AKeyword: string): Integer;
var
  mIndex, mDepth: Integer;
begin
  mDepth := 0;
  for mIndex := AFirst to High(ATokens) do
  begin
    if (mDepth = 0) and ATokens[mIndex].IsKeyword(AKeyword) then
    begin
      Exit(mIndex);
    end
    else if (AKeyword = 'until') and ATokens[mIndex].IsKeyword('repeat') then
    begin
      Inc(mDepth);
    end
    else if (AKeyword = 'until') and ATokens[mIndex].IsKeyword('until') then
    begin
      Dec(mDepth);
    end
    else if (AKeyword = 'do') and ATokens[mIndex].IsSymbol(';') then
    begin
      Exit(-1);
    end;
  end;
  Result := -1;
end;

/// <summary>for- bzw. while-Schleife ab dem Schlüsselwort AIndex; False ohne do oder Rumpf.</summary>
function HeadLoop(const ATokens: TTokens; AIndex: Integer; var ALoop: TLoop): Boolean;
var
  mMark: Integer;
begin
  mMark := FindKeyword(ATokens, AIndex + 1, 'do');
  Result := mMark >= 0;
  if Result then
  begin
    ALoop.BodyFirst := NextCode(ATokens, mMark + 1);
    Result := ALoop.BodyFirst <= High(ATokens);
  end;
  if not Result then
  begin
    Exit;
  end;
  ALoop.BodyLast := StatementEnd(ATokens, ALoop.BodyFirst);
  if ATokens[AIndex].IsKeyword('while') then
  begin
    ALoop.CondFirst := NextCode(ATokens, AIndex + 1);
    ALoop.CondLast := PreviousCode(ATokens, mMark);
  end
  else
  begin
    ALoop.CondFirst := 1;
    ALoop.CondLast := 0;
  end;
end;

/// <summary>repeat-Schleife ab dem Schlüsselwort AIndex; False ohne until.</summary>
function RepeatLoop(const ATokens: TTokens; AIndex: Integer; var ALoop: TLoop): Boolean;
var
  mMark: Integer;
begin
  mMark := FindKeyword(ATokens, AIndex + 1, 'until');
  Result := mMark >= 0;
  if Result then
  begin
    ALoop.BodyFirst := AIndex + 1;
    ALoop.BodyLast := PreviousCode(ATokens, mMark);
    ALoop.CondFirst := NextCode(ATokens, mMark + 1);
    ALoop.CondLast := StatementEnd(ATokens, ALoop.CondFirst);
  end;
end;

/// <summary>Schleife mit dem Schlüsselwort bei AIndex?</summary>
function LoopAt(const ATokens: TTokens; AIndex: Integer; out ALoop: TLoop): Boolean;
begin
  ALoop := Default(TLoop);
  ALoop.Keyword := AIndex;
  if ATokens[AIndex].IsKeyword('for') or ATokens[AIndex].IsKeyword('while') then
  begin
    Result := HeadLoop(ATokens, AIndex, ALoop);
  end
  else if ATokens[AIndex].IsKeyword('repeat') then
  begin
    Result := RepeatLoop(ATokens, AIndex, ALoop);
  end
  else
  begin
    Result := False;
  end;
end;

function Loops(const ATokens: TTokens): TArray<TLoop>;
var
  mIndex: Integer;
  mLoop: TLoop;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if LoopAt(ATokens, mIndex, mLoop) then
    begin
      Result := Result + [mLoop];
    end;
  end;
end;

/// <summary>Liegt Token AIndex im Rumpf einer der Schleifen?</summary>
function InLoopBody(const ALoops: TArray<TLoop>; AIndex: Integer): Boolean;
var
  mLoop: TLoop;
begin
  for mLoop in ALoops do
  begin
    if (AIndex >= mLoop.BodyFirst) and (AIndex <= mLoop.BodyLast) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Beginnt an AIndex ein Bezeichner, dem kein Punkt vorausgeht?</summary>
function StartsDesignator(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and
    ((AIndex = 0) or not ATokens[PreviousCode(ATokens, AIndex)].IsSymbol('.'));
end;

/// <summary>Erstes Token des Rumpfs der innersten Schleife um AIndex; -1 außerhalb jeder Schleife.</summary>
function InnermostBodyFirst(const ALoops: TArray<TLoop>; AIndex: Integer): Integer;
var
  mLoop: TLoop;
begin
  Result := -1;
  for mLoop in ALoops do
  begin
    if (AIndex >= mLoop.BodyFirst) and (AIndex <= mLoop.BodyLast) and (mLoop.BodyFirst > Result) then
    begin
      Result := mLoop.BodyFirst;
    end;
  end;
end;

/// <summary>Blocktiefe vor dem Rumpf ab AFirst: repeat … until steht schon auf der ersten Ebene (1), ein
/// begin … end erreicht sie erst mit seinem begin (0).</summary>
function BodyStartDepth(const ATokens: TTokens; AFirst: Integer): Integer;
var
  mBefore: Integer;
begin
  Result := 0;
  mBefore := PreviousCode(ATokens, AFirst);
  if (mBefore >= 0) and ATokens[mBefore].IsKeyword('repeat') then
  begin
    Result := 1;
  end;
end;

/// <summary>Blocktiefe nach dem Token AToken: begin, try, case, asm, repeat öffnen, end und until schließen.</summary>
procedure StepDepth(const AToken: TPascalToken; var ADepth: Integer);
begin
  if OpensBlock(AToken) then
  begin
    Inc(ADepth);
  end
  else if AToken.IsKeyword('end') or AToken.IsKeyword('until') then
  begin
    Dec(ADepth);
  end;
end;

/// <summary>Beginnt an AIndex eine Anweisung (davor ;, begin oder repeat), nicht hinter then, else oder
/// einer case-Marke?</summary>
function StartsStatement(const ATokens: TTokens; AIndex: Integer): Boolean;
var
  mBefore: Integer;
begin
  mBefore := PreviousCode(ATokens, AIndex);
  Result := (mBefore >= 0) and (ATokens[mBefore].IsSymbol(';') or ATokens[mBefore].IsKeyword('begin') or
    ATokens[mBefore].IsKeyword('repeat'));
end;

/// <summary>Steht an AIndex AName := …, ohne AName vorn rechts (ein Neusetzen, kein Anhängen)?</summary>
function IsResetOf(const ATokens: TTokens; AIndex: Integer; const AName: string): Boolean;
var
  mNext: Integer;
begin
  Result := False;
  if not SameText(ATokens[AIndex].Text, AName) or not StartsDesignator(ATokens, AIndex) then
  begin
    Exit;
  end;
  mNext := NextCode(ATokens, AIndex + 1);
  Result := (mNext < High(ATokens)) and ATokens[mNext].IsSymbol(':=') and
    not SameText(ATokens[NextCode(ATokens, mNext + 1)].Text, AName);
end;

/// <summary>Wird AName im Rumpf der innersten Schleife um AIndex vor AIndex neu gesetzt (AName := … ohne AName
/// vorn)? Dann wächst der String nur innerhalb eines Durchlaufs (mText := Zeile; mText := mText + ', '). Zählt
/// nur eine Zuweisung, die in jedem Durchlauf läuft: direkt im begin … end des Rumpfs, nicht hinter then, else
/// oder einer case-Marke und nicht in einem inneren Block.</summary>
function ResetInLoop(const ATokens: TTokens; const ALoops: TArray<TLoop>; AIndex: Integer;
  const AName: string): Boolean;
var
  mFirst, mIndex, mDepth: Integer;
begin
  Result := False;
  mFirst := InnermostBodyFirst(ALoops, AIndex);
  if mFirst < 0 then
  begin
    Exit;
  end;
  mDepth := BodyStartDepth(ATokens, mFirst);
  for mIndex := mFirst to AIndex - 1 do
  begin
    StepDepth(ATokens[mIndex], mDepth);
    if (mDepth = 1) and StartsStatement(ATokens, mIndex) and IsResetOf(ATokens, mIndex, AName) then
    begin
      Exit(True);
    end;
  end;
end;

/// <summary>Punktkette ab AIndex (A.B.C) als Text in Kleinbuchstaben; ALast = letztes Token.</summary>
function Chain(const ATokens: TTokens; AIndex: Integer; out ALast: Integer): string;
var
  mDot: Integer;
begin
  Result := LowerCase(ATokens[AIndex].Text);
  ALast := AIndex;
  mDot := NextCode(ATokens, ALast + 1);
  while (mDot < High(ATokens)) and ATokens[mDot].IsSymbol('.') and
    (ATokens[NextCode(ATokens, mDot + 1)].Kind = TPascalTokenKind.Identifier) do
  begin
    ALast := NextCode(ATokens, mDot + 1);
    Result := Result + '.' + LowerCase(ATokens[ALast].Text);
    mDot := NextCode(ATokens, ALast + 1);
  end;
end;

{ TStringConcatInLoopRule }

function TStringConcatInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('string-concat-in-loop', TRuleSeverity.Hint,
    cTexts[TPerformanceText.ConcatTitle].Text, True);
end;

procedure TStringConcatInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mFound: TArray<TLoop>;
  mTypes: TDeclaredTypes;
  mIndex, mAssign, mSame, mPlus, mLast: Integer;
  mTypeName: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mFound := Loops(mTokens);
  if mFound = nil then
  begin
    Exit;
  end;
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    for mIndex := 0 to High(mTokens) do
    begin
      // S := S + …
      if not StartsDesignator(mTokens, mIndex) or not InLoopBody(mFound, mIndex) then
      begin
        Continue;
      end;
      mAssign := NextCode(mTokens, mIndex + 1);
      mSame := NextCode(mTokens, mAssign + 1);
      mPlus := NextCode(mTokens, mSame + 1);
      if (mPlus > High(mTokens)) or not mTokens[mAssign].IsSymbol(':=') or
        not SameText(mTokens[mSame].Text, mTokens[mIndex].Text) or not mTokens[mPlus].IsSymbol('+') then
      begin
        Continue;
      end;
      mTypeName := mTypes.DeclaredType(mTokens[mIndex].Text, mTokens[mIndex].StartPos);
      if not MatchText(mTypeName, ['string', 'UnicodeString', 'AnsiString', 'WideString', 'UTF8String',
        'RawByteString']) or ResetInLoop(mTokens, mFound, mIndex, mTokens[mIndex].Text) then
      begin
        Continue;
      end;
      mLast := StatementEnd(mTokens, mIndex);
      AReport.Add(RangeOf(mTokens, mIndex, mLast), cTexts[TPerformanceText.Concat].Fmt([mTokens[mIndex].Text]),
        TRuleConfidence.Low);
    end;
  finally
    mTypes.Free;
  end;
end;

{ TLoopInvariantCallRule }

const
  /// <summary>Routinen, die ihr erstes Argument ändern (Delete(Result, 1, 2) in while Copy(Result, …)).</summary>
  cVarParamRoutines: array[0..5] of string = ('Inc', 'Dec', 'Delete', 'SetLength', 'Include', 'Exclude');

/// <summary>Wird der Bezeichner AName im Rumpf von ALoop zugewiesen oder über VarParamRoutines geändert?</summary>
function ChangedInLoop(const ATokens: TTokens; const ALoop: TLoop; const AName: string): Boolean;
var
  mIndex, mNext, mPrevious: Integer;
begin
  for mIndex := ALoop.BodyFirst to ALoop.BodyLast do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, AName) then
    begin
      mNext := NextCode(ATokens, mIndex + 1);
      if (mNext <= High(ATokens)) and ATokens[mNext].IsSymbol(':=') then
      begin
        Exit(True);
      end;
      mPrevious := PreviousCode(ATokens, mIndex);
      if (mPrevious > 0) and ATokens[mPrevious].IsSymbol('(') and
        MatchText(ATokens[PreviousCode(ATokens, mPrevious)].Text, cVarParamRoutines) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Hängt der Aufruf ab AIndex an einem Bezeichner, den die Schleife ändert? Dann ist er nicht
/// invariant.</summary>
function ArgumentsChange(const ATokens: TTokens; const ALoop: TLoop; AIndex: Integer): Boolean;
var
  mIndex, mDepth: Integer;
begin
  Result := False;
  mIndex := NextCode(ATokens, AIndex + 1);
  if (mIndex > High(ATokens)) or not ATokens[mIndex].IsSymbol('(') then
  begin
    Exit;
  end;
  mDepth := 0;
  while mIndex <= High(ATokens) do
  begin
    if ATokens[mIndex].IsSymbol('(') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(')') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end
    else if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
      ChangedInLoop(ATokens, ALoop, ATokens[mIndex].Text) then
    begin
      Exit(True);
    end;
    Inc(mIndex);
  end;
end;

const
  // Ohne FileExists und DirectoryExists: Das Dateisystem ändert sich ohne die Schleife (Warten auf eine Datei).
  cExpensiveCalls: array[0..15] of string = ('Trim', 'TrimLeft', 'TrimRight', 'LowerCase', 'UpperCase',
    'AnsiLowerCase', 'AnsiUpperCase', 'Format', 'StrToInt', 'StrToFloat', 'IntToStr', 'ExtractFileName',
    'ExtractFilePath', 'StringReplace', 'Copy', 'ComponentCount');
  cExpensiveProperties: array[0..2] of string = ('Text', 'CommaText', 'DelimitedText');

function TLoopInvariantCallRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('loop-invariant-call', TRuleSeverity.Hint,
    cTexts[TPerformanceText.ConditionTitle].Text, True);
end;

/// <summary>Punktkette vor dem Punkt ADot (ASpan in ASpan.Text, FParts.Scanner in FParts.Scanner.Text); '' wenn
/// davor kein einfacher Bezeichner steht (Aufruf, Index).</summary>
function ReceiverBefore(const ATokens: TTokens; ADot: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  mIndex := PreviousCode(ATokens, ADot);
  while (mIndex >= 0) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) do
  begin
    if Result <> '' then
    begin
      Result := '.' + Result;
    end;
    Result := ATokens[mIndex].Text + Result;
    mIndex := PreviousCode(ATokens, mIndex);
    if (mIndex < 0) or not ATokens[mIndex].IsSymbol('.') then
    begin
      Exit;
    end;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
  Result := '';
end;

/// <summary>Ist .AName hinter dem Punkt ADot ein Feld eines Typs dieser Datei (Record TAtlasDocSpan.Text)? Ein
/// Feld zu lesen baut keinen String auf.</summary>
function IsDeclaredField(const ATypes: TDeclaredTypes; const ATokens: TTokens; ADot: Integer;
  const AName: string): Boolean;
var
  mReceiver, mType: string;
begin
  mReceiver := ReceiverBefore(ATokens, ADot);
  Result := (mReceiver <> '') and
    ATypes.FieldType(ATypes.ChainType(mReceiver, ATokens[ADot].StartPos), AName, mType);
end;

/// <summary>Öffnende Klammer zur schließenden ] oder ) bei AClose; unter 0, wenn sie fehlt.</summary>
function GroupStart(const ATokens: TTokens; AClose: Integer): Integer;
var
  mDepth: Integer;
begin
  Result := AClose;
  mDepth := 0;
  repeat
    if ATokens[Result].IsSymbol(']') or ATokens[Result].IsSymbol(')') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol('[') or ATokens[Result].IsSymbol('(') then
    begin
      Dec(mDepth);
    end;
    if mDepth > 0 then
    begin
      Dec(Result);
    end;
  until (mDepth = 0) or (Result < 0);
end;

/// <summary>Erstes Token des Empfängers vor dem Punkt ADot: Bezeichner, Punkte und Klammergruppen
/// (ATokens[mIndex + 1].Text, Token(Result).Text).</summary>
function ReceiverStart(const ATokens: TTokens; ADot: Integer): Integer;
var
  mIndex: Integer;
begin
  Result := ADot;
  mIndex := PreviousCode(ATokens, ADot);
  while mIndex >= 0 do
  begin
    if ATokens[mIndex].IsSymbol(']') or ATokens[mIndex].IsSymbol(')') then
    begin
      mIndex := GroupStart(ATokens, mIndex);
    end
    else if (ATokens[mIndex].Kind <> TPascalTokenKind.Identifier) and not ATokens[mIndex].IsSymbol('.') then
    begin
      Exit;
    end;
    Result := mIndex;
    mIndex := PreviousCode(ATokens, mIndex);
  end;
end;

/// <summary>Ändert die Schleife einen Bezeichner im Empfänger vor ADot (Index ATokens[mIndex])? Dann liest jede
/// Prüfung etwas anderes.</summary>
function ReceiverChanges(const ATokens: TTokens; const ALoop: TLoop; ADot: Integer): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := ReceiverStart(ATokens, ADot) to ADot - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and ChangedInLoop(ATokens, ALoop,
      ATokens[mIndex].Text) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Dateiname für die Namensauflösung: Pfad, sonst relativer Pfad, sonst Unit-Name.</summary>
function ResolverFileName(const AContext: TRuleContext): string;
begin
  Result := AContext.FileName;
  if Result = '' then
  begin
    Result := AContext.RelativePath;
  end;
  if Result = '' then
  begin
    Result := AContext.UnitName + '.pas';
  end;
end;

type
  /// <summary>Prüft die Bedingungen der Schleifen einer Unit (loop-invariant-call).</summary>
  TLoopConditionCheck = class
  private
    FTypes: TDeclaredTypes;
    FTokens: TTokens;
    FTree: TSyntaxTree;
    FFileName: string;
    FResolver: TNameResolver;
    /// <summary>Löst die Namensauflösung .AName bei AIndex als Feld auf oder als Property, die direkt ein Feld
    /// liest (TPascalToken.Text aus einer anderen Unit)? Ein Feld zu lesen baut keinen String auf.</summary>
    function ReadsField(AIndex: Integer): Boolean;
    procedure CheckProperty(const ALoop: TLoop; AIndex, ADot: Integer; const AReport: IRuleReport);
  public
    constructor Create(const AContext: TRuleContext; AResolver: TNameResolver);
    destructor Destroy; override;
    /// <summary>Meldet den Bezeichner an AIndex in der Bedingung von ALoop, wenn er eine teure Eigenschaft (kein
    /// Feld) eines unveränderten Empfängers oder ein teurer Aufruf mit unveränderten Argumenten ist.</summary>
    procedure CheckToken(const ALoop: TLoop; AIndex: Integer; const AReport: IRuleReport);
    /// <summary>Alle Bedingungen von while und until.</summary>
    procedure CheckLoops(const AReport: IRuleReport);
  end;

constructor TLoopConditionCheck.Create(const AContext: TRuleContext; AResolver: TNameResolver);
begin
  inherited Create;
  FTree := AContext.Tree;
  FTokens := FTree.Tokens;
  FTypes := TDeclaredTypes.Create(FTree, AContext.Text);
  FResolver := AResolver;
  FFileName := ResolverFileName(AContext);
end;

destructor TLoopConditionCheck.Destroy;
begin
  FTypes.Free;
  inherited;
end;

function TLoopConditionCheck.ReadsField(AIndex: Integer): Boolean;
var
  mSymbol: TResolvedSymbol;
  mReadsField: Boolean;
begin
  mSymbol := FResolver.Resolve(FTree, FFileName, FTokens[AIndex].StartPos);
  if mSymbol.Kind <> TResolvedKind.Symbol then
  begin
    Exit(False);
  end;
  Result := (mSymbol.SymbolKind = TIndexSymbolKind.Field) or ((mSymbol.SymbolKind = TIndexSymbolKind.Property_) and
    FResolver.PropertyReadsField(mSymbol, mReadsField) and mReadsField);
end;

procedure TLoopConditionCheck.CheckProperty(const ALoop: TLoop; AIndex, ADot: Integer; const AReport: IRuleReport);
var
  mName: string;
begin
  mName := FTokens[AIndex].Text;
  if IsDeclaredField(FTypes, FTokens, ADot, mName) or ReceiverChanges(FTokens, ALoop, ADot) or ReadsField(AIndex) then
  begin
    Exit;
  end;
  AReport.Add(RangeOf(FTokens, AIndex, AIndex), cTexts[TPerformanceText.ConditionString].Fmt([mName]),
    TRuleConfidence.Medium);
end;

procedure TLoopConditionCheck.CheckToken(const ALoop: TLoop; AIndex: Integer; const AReport: IRuleReport);
var
  mName: string;
  mPrevious: Integer;
begin
  mName := FTokens[AIndex].Text;
  mPrevious := PreviousCode(FTokens, AIndex);
  if MatchText(mName, cExpensiveProperties) and (mPrevious >= 0) and FTokens[mPrevious].IsSymbol('.') then
  begin
    CheckProperty(ALoop, AIndex, mPrevious, AReport);
  end
  else if MatchText(mName, cExpensiveCalls) and StartsDesignator(FTokens, AIndex) and
    not ArgumentsChange(FTokens, ALoop, AIndex) then
  begin
    AReport.Add(RangeOf(FTokens, AIndex, AIndex), cTexts[TPerformanceText.ConditionCall].Fmt([mName]),
      TRuleConfidence.Medium);
  end;
end;

procedure TLoopConditionCheck.CheckLoops(const AReport: IRuleReport);
var
  mLoop: TLoop;
  mIndex: Integer;
begin
  FResolver.PinTree(FTree, FFileName);
  try
    for mLoop in Loops(FTokens) do
    begin
      for mIndex := mLoop.CondFirst to mLoop.CondLast do
      begin
        if FTokens[mIndex].Kind = TPascalTokenKind.Identifier then
        begin
          CheckToken(mLoop, mIndex, AReport);
        end;
      end;
    end;
  finally
    FResolver.UnpinTree;
  end;
end;

procedure TLoopInvariantCallRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mCache: IRuleDerivedCache;
  mCheck: TLoopConditionCheck;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mCheck := TLoopConditionCheck.Create(AContext, TRuleDerived.Resolver(mCache, AContext));
  try
    mCheck.CheckLoops(AReport);
  finally
    mCheck.Free;
  end;
end;

{ TMissingBeginUpdateRule }

const
  /// <summary>Bis zu so vielen Durchläufen lohnt BeginUpdate nicht.</summary>
  cFewIterations = 10;
  /// <summary>Menüs: Items ist ein TMenuItem, das kein BeginUpdate kennt.</summary>
  cMenuTypes: array[0..3] of string = ('TMenu', 'TMainMenu', 'TPopupMenu', 'TMenuItem');

/// <summary>Ganzzahl ab AIndex (mit Vorzeichen -); ALast = letztes Token.</summary>
function IntegerAt(const ATokens: TTokens; AIndex: Integer; out AValue: Int64; out ALast: Integer): Boolean;
var
  mNegative: Boolean;
begin
  Result := False;
  AValue := 0;
  ALast := AIndex;
  if AIndex > High(ATokens) then
  begin
    Exit;
  end;
  mNegative := ATokens[AIndex].IsSymbol('-');
  if mNegative then
  begin
    ALast := NextCode(ATokens, AIndex + 1);
  end;
  if (ALast > High(ATokens)) or (ATokens[ALast].Kind <> TPascalTokenKind.Number) or
    not TryStrToInt64(ATokens[ALast].Text, AValue) then
  begin
    Exit;
  end;
  if mNegative then
  begin
    AValue := -AValue;
  end;
  Result := True;
end;

/// <summary>Steht bei AIndex (Code-Token) das Symbol ASymbol?</summary>
function SymbolAt(const ATokens: TTokens; AIndex: Integer; const ASymbol: string): Boolean;
begin
  Result := (AIndex <= High(ATokens)) and ATokens[AIndex].IsSymbol(ASymbol);
end;

/// <summary>": array[A..B]" nach dem Namen bei AIndex; liefert die Grenzen.</summary>
function ArrayBoundsAt(const ATokens: TTokens; AIndex: Integer; out ALow, AHigh: Int64): Boolean;
var
  mNext, mLast: Integer;
begin
  ALow := 0;
  AHigh := -1;
  mLast := AIndex;
  mNext := NextCode(ATokens, AIndex + 1);
  Result := SymbolAt(ATokens, mNext, ':');
  if Result then
  begin
    mNext := NextCode(ATokens, mNext + 1);
    Result := (mNext <= High(ATokens)) and ATokens[mNext].IsKeyword('array');
  end;
  if Result then
  begin
    mNext := NextCode(ATokens, mNext + 1);
    Result := SymbolAt(ATokens, mNext, '[') and IntegerAt(ATokens, NextCode(ATokens, mNext + 1), ALow, mLast);
  end;
  if Result then
  begin
    mNext := NextCode(ATokens, mLast + 1);
    Result := SymbolAt(ATokens, mNext, '..') and IntegerAt(ATokens, NextCode(ATokens, mNext + 1), AHigh, mLast);
  end;
  Result := Result and SymbolAt(ATokens, NextCode(ATokens, mLast + 1), ']');
end;

/// <summary>Grenzen des statischen Arrays AName, das in der Datei als AName: array[A..B] steht.</summary>
function StaticArrayBounds(const ATokens: TTokens; const AName: string; out ALow, AHigh: Int64): Boolean;
var
  mIndex: Integer;
begin
  ALow := 0;
  AHigh := -1;
  for mIndex := 0 to High(ATokens) - 1 do
  begin
    if (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[mIndex].Text, AName) and
      ArrayBoundsAt(ATokens, mIndex, ALow, AHigh) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Low(X) bzw. High(X) ab AIndex, endend vor AStop; AName = Position von X.</summary>
function IsBoundCall(const ATokens: TTokens; AIndex, AStop: Integer; out AName: Integer): Boolean;
var
  mOpen, mClose: Integer;
begin
  mOpen := NextCode(ATokens, AIndex + 1);
  AName := NextCode(ATokens, mOpen + 1);
  mClose := NextCode(ATokens, AName + 1);
  Result := (mClose < AStop) and (NextCode(ATokens, mClose + 1) = AStop) and ATokens[mOpen].IsSymbol('(') and
    (ATokens[AName].Kind = TPascalTokenKind.Identifier) and ATokens[mClose].IsSymbol(')');
end;

/// <summary>Grenze einer for-Schleife ab AIndex bis vor AStop: Zahl, Low(X) oder High(X) mit
/// statischem Array X der Datei.</summary>
function BoundAt(const ATokens: TTokens; AIndex, AStop: Integer; out AValue: Int64): Boolean;
var
  mLast, mName: Integer;
  mFirst, mFinal: Int64;
begin
  if IntegerAt(ATokens, AIndex, AValue, mLast) then
  begin
    Exit(NextCode(ATokens, mLast + 1) = AStop);
  end;
  Result := IsBoundCall(ATokens, AIndex, AStop, mName) and
    StaticArrayBounds(ATokens, ATokens[mName].Text, mFirst, mFinal);
  if not Result then
  begin
    Exit;
  end;
  if SameText(ATokens[AIndex].Text, 'Low') then
  begin
    AValue := mFirst;
  end
  else if SameText(ATokens[AIndex].Text, 'High') then
  begin
    AValue := mFinal;
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Kopf einer for-Schleife: AIndex = Token nach der Laufvariablen (":=" bzw. in), AStop = do.</summary>
function ForHead(const ATokens: TTokens; const ALoop: TLoop; out AIndex, AStop: Integer): Boolean;
begin
  AIndex := -1;
  AStop := -1;
  if not ATokens[ALoop.Keyword].IsKeyword('for') then
  begin
    Exit(False);
  end;
  AStop := FindKeyword(ATokens, ALoop.Keyword + 1, 'do');
  AIndex := NextCode(ATokens, ALoop.Keyword + 1);
  if (AIndex <= High(ATokens)) and ATokens[AIndex].IsKeyword('var') then
  begin
    AIndex := NextCode(ATokens, AIndex + 1);
  end;
  AIndex := NextCode(ATokens, AIndex + 1);
  Result := (AStop >= 0) and (AIndex < AStop);
end;

/// <summary>for X in Werte do mit "in" bei AIndex: Werte ist ein statisches Array der Datei; -1 sonst.</summary>
function InIterations(const ATokens: TTokens; AIndex, AStop: Integer): Int64;
var
  mIndex: Integer;
  mFirst, mLast: Int64;
begin
  Result := -1;
  mIndex := NextCode(ATokens, AIndex + 1);
  if (NextCode(ATokens, mIndex + 1) = AStop) and (ATokens[mIndex].Kind = TPascalTokenKind.Identifier) and
    StaticArrayBounds(ATokens, ATokens[mIndex].Text, mFirst, mLast) then
  begin
    Result := mLast - mFirst + 1;
  end;
end;

/// <summary>for I := A to B do mit ":=" bei AIndex: Durchläufe bei festen Grenzen; -1 sonst.</summary>
function RangeIterations(const ATokens: TTokens; AIndex, AStop: Integer): Int64;
var
  mBound: Integer;
  mFirst, mLast: Int64;
begin
  Result := -1;
  mBound := AIndex + 1;
  while (mBound < AStop) and not ATokens[mBound].IsKeyword('to') and not ATokens[mBound].IsKeyword('downto') do
  begin
    Inc(mBound);
  end;
  if (mBound >= AStop) or not BoundAt(ATokens, NextCode(ATokens, AIndex + 1), mBound, mFirst) or
    not BoundAt(ATokens, NextCode(ATokens, mBound + 1), AStop, mLast) then
  begin
    Exit;
  end;
  if ATokens[mBound].IsKeyword('downto') then
  begin
    Result := mFirst - mLast + 1;
  end
  else
  begin
    Result := mLast - mFirst + 1;
  end;
  if Result < 0 then
  begin
    Result := 0;
  end;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife mit festen Grenzen bzw. über ein statisches
/// Array der Datei; -1 wenn unbekannt (while, repeat, Grenzen erst zur Laufzeit).</summary>
function FixedIterations(const ATokens: TTokens; const ALoop: TLoop): Int64;
var
  mIndex, mStop: Integer;
begin
  Result := -1;
  if not ForHead(ATokens, ALoop, mIndex, mStop) then
  begin
    Exit;
  end;
  if ATokens[mIndex].IsKeyword('in') then
  begin
    Result := InIterations(ATokens, mIndex, mStop);
  end
  else if ATokens[mIndex].IsSymbol(':=') then
  begin
    Result := RangeIterations(ATokens, mIndex, mStop);
  end;
end;

/// <summary>Durchlaufen alle Schleifen um AIndex zusammen höchstens FewIterations Mal?</summary>
function FewInLoops(const ATokens: TTokens; const ALoops: TArray<TLoop>; AIndex: Integer): Boolean;
var
  mLoop: TLoop;
  mTotal, mCount: Int64;
begin
  mTotal := 1;
  for mLoop in ALoops do
  begin
    if (AIndex >= mLoop.BodyFirst) and (AIndex <= mLoop.BodyLast) then
    begin
      mCount := FixedIterations(ATokens, mLoop);
      if mCount < 0 then
      begin
        Exit(False);
      end;
      mTotal := mTotal * mCount;
      if mTotal > cFewIterations then
      begin
        Exit(False);
      end;
    end;
  end;
  Result := True;
end;

/// <summary>Empfänger, für die irgendwo in der Datei BeginUpdate aufgerufen wird (Kleinbuchstaben).</summary>
function UpdatedReceivers(const ATokens: TTokens): TArray<string>;
var
  mIndex, mLast: Integer;
  mText: string;
begin
  Result := nil;
  for mIndex := 0 to High(ATokens) do
  begin
    if StartsDesignator(ATokens, mIndex) then
    begin
      mText := Chain(ATokens, mIndex, mLast);
      if EndsText('.beginupdate', mText) then
      begin
        Result := Result + [Copy(mText, 1, Length(mText) - Length('.beginupdate'))];
      end;
    end;
  end;
end;

/// <summary>Teil vor dem letzten Punkt: listbox1.items → listbox1.</summary>
function OwnerOf(const AReceiver: string): string;
begin
  Result := Copy(AReceiver, 1, LastDelimiter('.', AReceiver) - 1);
end;

/// <summary>Hinzufügen an einer sichtbaren Liste ab AIndex: ListBox1.Items.Add, Memo1.Lines.Append …; der
/// Empfänger hat mindestens zwei Glieder.</summary>
function AddCall(const ATokens: TTokens; AIndex: Integer; out AReceiver: string; out ALast: Integer): Boolean;
var
  mText, mMethod: string;
  mDot: Integer;
begin
  mText := Chain(ATokens, AIndex, ALast);
  mDot := LastDelimiter('.', mText);
  AReceiver := Copy(mText, 1, mDot - 1);
  mMethod := Copy(mText, mDot + 1, MaxInt);
  Result := (mDot > 0) and (Pos('.', AReceiver) > 0) and
    MatchText(Copy(AReceiver, LastDelimiter('.', AReceiver) + 1, MaxInt), ['items', 'lines', 'strings']) and
    MatchText(mMethod, ['add', 'addobject', 'append', 'insert', 'addchild', 'addchildobject', 'addpair']);
end;

/// <summary>Menu.Items ist ein TMenuItem ohne BeginUpdate; auch über Felder (FParts.Menu.Items).</summary>
function IsMenuItems(const ATypes: TDeclaredTypes; const AReceiver: string; const APosition: TTextPosition): Boolean;
begin
  Result := MatchText(ATypes.ChainType(OwnerOf(AReceiver), APosition), cMenuTypes);
end;

const
  /// <summary>Listen ohne Steuerelement und ohne BeginUpdate (TObjectList&lt;T&gt;, TList).</summary>
  cPlainLists: array[0..5] of string = ('TList', 'TObjectList', 'TInterfaceList', 'TStack', 'TQueue',
    'TDictionary');

/// <summary>Typname ohne Typargumente: TObjectList&lt;TNode&gt; → TObjectList.</summary>
function BareTypeName(const ATypeName: string): string;
var
  mAngle: Integer;
begin
  Result := Trim(ATypeName);
  mAngle := Pos('<', Result);
  if mAngle > 0 then
  begin
    Result := Trim(Copy(Result, 1, mAngle - 1));
  end;
end;

/// <summary>Kennt die Namensauflösung den Empfänger AReceiver (bzw. sein Objekt davor) als Typ ohne BeginUpdate:
/// Menü (FParts.Menu: TPopupMenu aus einer anderen Unit), Liste ohne Steuerelement (Items: TObjectList&lt;T&gt;) oder
/// ein Typ im Index ohne Mitglied BeginUpdate? Unbekannt: False.</summary>
function LacksBeginUpdate(const AContext: TRuleContext; AResolver: TNameResolver; const AFileName,
  AReceiver: string; AOffset: Integer): Boolean;
var
  mOwner, mItems: TResolvedSymbol;
  mChain: TResolvedChainType;
  mMember: TResolvedSymbol;
begin
  mOwner := AResolver.ResolveChain(AContext.Tree, AFileName, OwnerOf(AReceiver).Split(['.']), AOffset);
  if (mOwner.Kind <> TResolvedKind.None) and MatchText(BareTypeName(mOwner.TypeName), cMenuTypes) then
  begin
    Exit(True);
  end;
  mItems := AResolver.ResolveChain(AContext.Tree, AFileName, AReceiver.Split(['.']), AOffset);
  if mItems.Kind = TResolvedKind.None then
  begin
    Exit(False);
  end;
  if MatchText(BareTypeName(mItems.TypeName), cPlainLists) or MatchText(BareTypeName(mItems.TypeName),
    cMenuTypes) then
  begin
    Exit(True);
  end;
  Result := AResolver.ChainType(AContext.Tree, AFileName, AReceiver.Split(['.']), AOffset, mChain) and
    mChain.TypeFound and not AResolver.FindMember(mChain.TypeInfo, 'BeginUpdate', mMember);
end;

/// <summary>Steht für den Empfänger schon BeginUpdate in der Datei bzw. ist er schon gemeldet?</summary>
function IsHandled(const AReceiver: string; const AUpdated, AReported: TArray<string>): Boolean;
begin
  Result := MatchText(AReceiver, AUpdated) or MatchText(OwnerOf(AReceiver), AUpdated) or
    MatchText(AReceiver, AReported);
end;

function TMissingBeginUpdateRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('missing-begin-update', TRuleSeverity.Hint,
    cTexts[TPerformanceText.BeginUpdateTitle].Text, True);
end;

/// <summary>Meldet das Hinzufügen ab AIndex bis ALast.</summary>
procedure ReportAdd(const AContext: TRuleContext; const AReport: IRuleReport; const ATokens: TTokens;
  AIndex, ALast: Integer);
var
  mReceiverText: string;
begin
  mReceiverText := Copy(AContext.Text, ATokens[AIndex].Offset + 1,
    ATokens[PreviousCode(ATokens, ALast)].Offset - ATokens[AIndex].Offset);
  AReport.Add(RangeOf(ATokens, AIndex, ALast), cTexts[TPerformanceText.BeginUpdate].Fmt(
    [ATokens[ALast].Text, mReceiverText, mReceiverText]), TRuleConfidence.Medium);
end;

procedure TMissingBeginUpdateRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mFound: TArray<TLoop>;
  mUpdated, mReported: TArray<string>;
  mTypes: TDeclaredTypes;
  mIndex, mLast: Integer;
  mReceiver, mFileName: string;
  mCache: IRuleDerivedCache;
  mResolver: TNameResolver;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mFound := Loops(mTokens);
  if mFound = nil then
  begin
    Exit;
  end;
  // Resolver des Laufs (TRuleDerived.Resolver); gehört dem Cache.
  mCache := TRuleDerived.Open(AContext);
  mResolver := TRuleDerived.Resolver(mCache, AContext);
  mFileName := ResolverFileName(AContext);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  mResolver.PinTree(AContext.Tree, mFileName);
  try
    mUpdated := UpdatedReceivers(mTokens);
    mReported := nil;
    for mIndex := 0 to High(mTokens) do
    begin
      if not StartsDesignator(mTokens, mIndex) or not InLoopBody(mFound, mIndex) or
        not AddCall(mTokens, mIndex, mReceiver, mLast) then
      begin
        Continue;
      end;
      // Wenige Einträge: Das Neuzeichnen fällt nicht ins Gewicht.
      if IsHandled(mReceiver, mUpdated, mReported) or IsMenuItems(mTypes, mReceiver, mTokens[mIndex].StartPos) or
        FewInLoops(mTokens, mFound, mIndex) or
        LacksBeginUpdate(AContext, mResolver, mFileName, mReceiver, mTokens[mIndex].Offset) then
      begin
        Continue;
      end;
      mReported := mReported + [mReceiver];
      ReportAdd(AContext, AReport, mTokens, mIndex, mLast);
    end;
  finally
    mResolver.UnpinTree;
    mTypes.Free;
  end;
end;

{ TSetLengthInLoopRule }

function NodeText(const AText: string; ANode: TSyntaxNode): string;
begin
  Result := Copy(AText, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
end;

/// <summary>Ist ANode der Aufruf AName(X) mit genau einem Argument, dessen Text ATarget ist?</summary>
function IsCallOf(const AText: string; ANode: TSyntaxNode; const AName, ATarget: string): Boolean;
begin
  Result := (ANode <> nil) and (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    SameText(ANode.Name, AName) and SameText(NodeText(AText, ANode[1]), ATarget);
end;

/// <summary>Ganzzahliges Literal ab 1?</summary>
function IsPositiveLiteral(ANode: TSyntaxNode): Boolean;
var
  mValue: Integer;
begin
  Result := (ANode.Kind = TSyntaxKind.Literal) and TryStrToInt(ANode.Name, mValue) and (mValue >= 1);
end;

/// <summary>Vergrößert ALength die Länge von ATarget um einen festen Schritt: Length(A) + n, n + Length(A),
/// Succ(Length(A)) oder High(A) + n mit n ab 2?</summary>
function IsGrowth(const AText: string; ALength: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := False;
  if (ALength.Kind = TSyntaxKind.Call) and SameText(ALength.Name, 'Succ') and (ALength.ChildCount = 2) then
  begin
    Exit(IsCallOf(AText, ALength[1], 'Length', ATarget));
  end;
  if (ALength.Kind <> TSyntaxKind.BinaryExpr) or (ALength.Name <> '+') or (ALength.ChildCount <> 2) then
  begin
    Exit;
  end;
  if IsCallOf(AText, ALength[0], 'Length', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[1]);
  end
  else if IsCallOf(AText, ALength[1], 'Length', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[0]);
  end
  else if IsCallOf(AText, ALength[0], 'High', ATarget) then
  begin
    Result := IsPositiveLiteral(ALength[1]) and (ALength[1].Name <> '1');
  end;
end;

/// <summary>Letztes Element von ATarget als Index: High(A) bzw. Length(A) - 1?</summary>
function IsLastIndex(const AText: string; AIndex: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := IsCallOf(AText, AIndex, 'High', ATarget) or
    ((AIndex.Kind = TSyntaxKind.BinaryExpr) and (AIndex.Name = '-') and (AIndex.ChildCount = 2) and
    IsCallOf(AText, AIndex[0], 'Length', ATarget) and (AIndex[1].Kind = TSyntaxKind.Literal) and
    (AIndex[1].Name = '1'));
end;

function IsLoop(ANode: TSyntaxNode): Boolean;
begin
  Result := ANode.Kind in [TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement, TSyntaxKind.WhileStatement,
    TSyntaxKind.RepeatStatement];
end;

/// <summary>Innerste Schleife um ANode innerhalb derselben Routine; nil ohne.</summary>
function EnclosingLoop(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and not IsLoop(Result) do
  begin
    if Result.Kind in [TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

/// <summary>Rumpf der Schleife; bei repeat nil (mehrere Anweisungen).</summary>
function LoopBody(ALoop: TSyntaxNode): TSyntaxNode;
begin
  Result := nil;
  if (ALoop.Kind <> TSyntaxKind.RepeatStatement) and (ALoop.ChildCount > 0) then
  begin
    Result := ALoop[ALoop.ChildCount - 1];
  end;
end;

/// <summary>Steht AStatement direkt im Rumpf von ALoop, wird es also bei jedem Durchlauf ausgeführt?</summary>
function RunsEveryIteration(ALoop, AStatement: TSyntaxNode): Boolean;
var
  mBody: TSyntaxNode;
begin
  if ALoop.Kind = TSyntaxKind.RepeatStatement then
  begin
    Exit(AStatement.Parent = ALoop);
  end;
  mBody := LoopBody(ALoop);
  Result := (mBody = AStatement) or ((mBody <> nil) and (mBody.Kind = TSyntaxKind.Block) and
    (AStatement.Parent = mBody));
end;

/// <summary>Ergebnistyp der Funktion um ANode als Quelltext; '' ohne.</summary>
function ResultType(const AText: string; ANode: TSyntaxNode): string;
var
  mRoutine, mHeader: TSyntaxNode;
begin
  Result := '';
  mRoutine := ANode.Parent;
  while (mRoutine <> nil) and (mRoutine.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if mRoutine.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit;
    end;
    mRoutine := mRoutine.Parent;
  end;
  if mRoutine = nil then
  begin
    Exit;
  end;
  mHeader := mRoutine.FindChild(TSyntaxKind.RoutineHeader);
  if (mHeader <> nil) and (mHeader.ChildCount > 0) and
    (mHeader[mHeader.ChildCount - 1].Kind <> TSyntaxKind.Parameters) then
  begin
    mHeader := mHeader.FindChild(TSyntaxKind.TypeReference);
    if mHeader <> nil then
    begin
      Result := NodeText(AText, mHeader);
    end;
  end;
end;

/// <summary>Anzahl der Durchläufe einer for-Schleife als Quelltext; '' wenn sie nicht sicher zu bestimmen ist.
/// ALoopIndex: Ausdruck für den Index des I-ten Elements (I bzw. I - Start).</summary>
function ForCount(const AText: string; ALoop: TSyntaxNode; out ALoopIndex: string): string;
var
  mFirst, mLast: TSyntaxNode;
  mLowText, mHighText: string;
begin
  Result := '';
  ALoopIndex := '';
  if (ALoop.Kind <> TSyntaxKind.ForStatement) or (ALoop.ChildCount < 3) then
  begin
    Exit;
  end;
  mFirst := ALoop[ALoop.ChildCount - 3];
  mLast := ALoop[ALoop.ChildCount - 2];
  if ContainsText(Copy(AText, mFirst.EndOffset + 1, mLast.StartOffset - mFirst.EndOffset), 'downto') then
  begin
    Exit;
  end;
  mLowText := Trim(NodeText(AText, mFirst));
  mHighText := Trim(NodeText(AText, mLast));
  if mLowText = '0' then
  begin
    ALoopIndex := ALoop.Name;
    if (mLast.Kind = TSyntaxKind.BinaryExpr) and (mLast.Name = '-') and (mLast.ChildCount = 2) and
      (mLast[1].Kind = TSyntaxKind.Literal) and (mLast[1].Name = '1') then
    begin
      Result := Trim(NodeText(AText, mLast[0]));
    end
    else
    begin
      Result := mHighText + ' + 1';
    end;
  end
  else if mLowText = '1' then
  begin
    Result := mHighText;
    ALoopIndex := ALoop.Name + ' - 1';
  end
  else
  begin
    Result := Format('%s - %s + 1', [mHighText, mLowText]);
    ALoopIndex := Format('%s - %s', [ALoop.Name, mLowText]);
  end;
end;

/// <summary>Routine um ANode; nil ohne oder in einer anonymen Methode.</summary>
function EnclosingRoutine(ANode: TSyntaxNode): TSyntaxNode;
begin
  Result := ANode.Parent;
  while (Result <> nil) and (Result.Kind <> TSyntaxKind.RoutineDecl) do
  begin
    if Result.Kind = TSyntaxKind.AnonymousMethod then
    begin
      Exit(nil);
    end;
    Result := Result.Parent;
  end;
end;

/// <summary>Deklariert der var-Abschnitt ASection den Namen AName?</summary>
function SectionDeclares(ASection: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mName: string;
begin
  for mIndex := 0 to ASection.ChildCount - 1 do
  begin
    for mName in SplitString(ASection[mIndex].Name, ',') do
    begin
      if SameText(Trim(mName), AName) then
      begin
        Exit(True);
      end;
    end;
  end;
  Result := False;
end;

/// <summary>Ist AName eine lokale Variable der Routine ARoutine?</summary>
function DeclaresLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  for mIndex := 0 to ARoutine.ChildCount - 1 do
  begin
    if (ARoutine[mIndex].Kind = TSyntaxKind.VarSection) and SectionDeclares(ARoutine[mIndex], AName) then
    begin
      Exit(True);
    end;
  end;
  Result := False;
end;

/// <summary>Kommt AName in ABody vor der Stelle AOffset vor?</summary>
function UsedBefore(ABody: TSyntaxNode; AOffset: Integer; const AName: string): Boolean;
var
  mUsed: Boolean;
  mName: string;
begin
  mUsed := False;
  mName := AName;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := not mUsed;
      if (ANode.Kind = TSyntaxKind.Identifier) and (ANode.EndOffset <= AOffset) and SameText(ANode.Name, mName) then
      begin
        mUsed := True;
      end;
    end);
  Result := mUsed;
end;

/// <summary>A[High(A)] bzw. A[Length(A) - 1] für A = ATarget?</summary>
function IsLastElement(const AText: string; ANode: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.IndexAccess) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier) and SameText(ANode[0].Name, ATarget) and
    IsLastIndex(AText, ANode[1], ATarget);
end;

/// <summary>Andere Verwendung von ATarget oder ein Sprung (Break, Continue, Exit, goto), der das Array
/// verkürzt?</summary>
function SpoilsCount(ANode: TSyntaxNode; const ATarget: string): Boolean;
begin
  Result := ((ANode.Kind = TSyntaxKind.Identifier) and SameText(ANode.Name, ATarget)) or
    ((ANode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.CallStatement]) and
    MatchText(ANode.Name, ['Break', 'Continue', 'Exit'])) or (ANode.Kind = TSyntaxKind.GotoStatement);
end;

/// <summary>Einzige Anweisung im Block ABody außer AStatement; nil, wenn es nicht genau eine gibt.</summary>
function SoleOther(ABody, AStatement: TSyntaxNode): TSyntaxNode;
var
  mIndex, mRemaining: Integer;
begin
  Result := nil;
  mRemaining := 0;
  if ABody.Kind = TSyntaxKind.Block then
  begin
    for mIndex := 0 to ABody.ChildCount - 1 do
    begin
      if ABody[mIndex] <> AStatement then
      begin
        Inc(mRemaining);
        Result := ABody[mIndex];
      end;
    end;
  end;
  if mRemaining <> 1 then
  begin
    Result := nil;
  end;
end;

/// <summary>Alle SetLength(A, …)-Anweisungen der Datei.</summary>
function SetLengthCalls(ARoot: TSyntaxNode): TArray<TSyntaxNode>;
var
  mCalls: TArray<TSyntaxNode>;
begin
  mCalls := nil;
  ARoot.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := True;
      if (ANode.Kind = TSyntaxKind.CallStatement) and (ANode.ChildCount = 1) and
        (ANode[0].Kind = TSyntaxKind.Call) and SameText(ANode[0].Name, 'SetLength') and (ANode[0].ChildCount = 3) then
      begin
        mCalls := mCalls + [ANode];
      end;
    end);
  Result := mCalls;
end;

type
  /// <summary>Prüft eine Datei auf setlength-in-loop.</summary>
  TSetLengthScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FCache: IRuleDerivedCache;
    FTypes: TDeclaredTypes;
    FArrayTypes: TArray<string>;
    /// <summary>Array der gerade geprüften Anweisung, Anzahl der Durchläufe und Index des I-ten Elements.</summary>
    FTarget: string;
    FCount: string;
    FLoopIndex: string;
    function Range(AStart, AEnd: Integer): TTextRange;
    function LineStart(AOffset: Integer): Integer;
    function Indent(AOffset: Integer): string;
    function SkipBlanks(AOffset: Integer): Integer;
    function WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
    function FreshLocal(ALoop: TSyntaxNode): Boolean;
    function Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
    function OnOwnLine(AOffset: Integer): Boolean;
    function LastIndexUses(ABody, AStatement: TSyntaxNode; out AReplaced: TArray<TSyntaxNode>): Boolean;
    function StatementEdits(AStart, AStop: Integer; const AReplaced: TArray<TSyntaxNode>): TArray<TRuleEdit>;
    function CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
    function TargetType(AStatement, ATargetNode: TSyntaxNode): string;
    procedure ReportCall(ALoop, AStatement: TSyntaxNode);
    procedure CheckCall(AStatement: TSyntaxNode);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

{ TSetLengthScan }

constructor TSetLengthScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
end;

function TSetLengthScan.Range(AStart, AEnd: Integer): TTextRange;
begin
  Result := TRuleDerived.OffsetRange(FCache, FContext, AStart, AEnd);
end;

function TSetLengthScan.LineStart(AOffset: Integer): Integer;
begin
  Result := AOffset;
  while (Result > 0) and not CharInSet(FContext.Text[Result], [#10, #13]) do
  begin
    Dec(Result);
  end;
end;

function TSetLengthScan.Indent(AOffset: Integer): string;
var
  mStart, mIndex: Integer;
begin
  mStart := LineStart(AOffset);
  mIndex := mStart;
  while (mIndex < AOffset) and CharInSet(FContext.Text[mIndex + 1], [' ', #9]) do
  begin
    Inc(mIndex);
  end;
  Result := Copy(FContext.Text, mStart + 1, mIndex - mStart);
end;

/// <summary>Stelle nach Leerzeichen und Tabs ab AOffset.</summary>
function TSetLengthScan.SkipBlanks(AOffset: Integer): Integer;
begin
  Result := AOffset;
  while (Result < Length(FContext.Text)) and CharInSet(FContext.Text[Result + 1], [' ', #9]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Bereich der ganzen Zeile(n) von AStatement samt folgendem ; und Zeilenende; False, wenn mehr in der
/// Zeile steht.</summary>
function TSetLengthScan.WholeLines(AStatement: TSyntaxNode; out AStart, AEnd: Integer): Boolean;
begin
  AStart := LineStart(AStatement.StartOffset);
  Result := Trim(Copy(FContext.Text, AStart + 1, AStatement.StartOffset - AStart)) = '';
  AEnd := SkipBlanks(AStatement.EndOffset);
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = ';') then
  begin
    Inc(AEnd);
  end;
  AEnd := SkipBlanks(AEnd);
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = #13) then
  begin
    Inc(AEnd);
  end;
  if (AEnd < Length(FContext.Text)) and (FContext.Text[AEnd + 1] = #10) then
  begin
    Inc(AEnd);
  end
  else
  begin
    Result := False;
  end;
end;

/// <summary>Lokale Variable FTarget der Routine um ALoop, die vor der Schleife nicht vorkommt?</summary>
function TSetLengthScan.FreshLocal(ALoop: TSyntaxNode): Boolean;
var
  mRoutine, mBody: TSyntaxNode;
begin
  mRoutine := EnclosingRoutine(ALoop);
  if (mRoutine = nil) or not DeclaresLocal(mRoutine, FTarget) then
  begin
    Exit(False);
  end;
  mBody := mRoutine.FindChild(TSyntaxKind.Block);
  Result := (mBody <> nil) and not UsedBefore(mBody, ALoop.StartOffset, FTarget);
end;

/// <summary>Text von AFrom bis ATo mit den Ersetzungen in AEdits (Offsets) darin.</summary>
function TSetLengthScan.Rewrite(AFrom, ATo: Integer; const AReplaced: TArray<TSyntaxNode>; const ANew: string): string;
var
  mIndex: Integer;
begin
  Result := Copy(FContext.Text, AFrom + 1, ATo - AFrom);
  for mIndex := High(AReplaced) downto 0 do
  begin
    if (AReplaced[mIndex].StartOffset >= AFrom) and (AReplaced[mIndex].EndOffset <= ATo) then
    begin
      Result := Copy(Result, 1, AReplaced[mIndex].StartOffset - AFrom) + ANew +
        Copy(Result, AReplaced[mIndex].EndOffset - AFrom + 1, MaxInt);
    end;
  end;
end;

function TSetLengthScan.OnOwnLine(AOffset: Integer): Boolean;
begin
  Result := Trim(Copy(FContext.Text, LineStart(AOffset) + 1, AOffset - LineStart(AOffset))) = '';
end;

/// <summary>Jede andere Stelle mit FTarget im Rumpf muss A[High(A)] bzw. A[Length(A) - 1] sein; Sprünge verkürzen
/// das Array. AReplaced: die Indexausdrücke dieser Stellen.</summary>
function TSetLengthScan.LastIndexUses(ABody, AStatement: TSyntaxNode; out AReplaced: TArray<TSyntaxNode>): Boolean;
var
  mSafe: Boolean;
  mReplaced: TArray<TSyntaxNode>;
  mText, mTarget: string;
begin
  mSafe := True;
  mReplaced := nil;
  mText := FContext.Text;
  mTarget := FTarget;
  ABody.Walk(
    function(ANode: TSyntaxNode): Boolean
    begin
      Result := mSafe and (ANode <> AStatement);
      if not Result then
      begin
        Exit;
      end;
      if IsLastElement(mText, ANode, mTarget) then
      begin
        mReplaced := mReplaced + [ANode[1]];
        Exit(False);
      end;
      if SpoilsCount(ANode, mTarget) then
      begin
        mSafe := False;
      end;
    end);
  AReplaced := mReplaced;
  Result := mSafe and (mReplaced <> nil);
end;

/// <summary>SetLength-Zeilen AStart bis AStop entfernen, die Indexausdrücke durch FLoopIndex ersetzen.</summary>
function TSetLengthScan.StatementEdits(AStart, AStop: Integer; const AReplaced: TArray<TSyntaxNode>): TArray<TRuleEdit>;
var
  mIndex: Integer;
begin
  Result := [TRuleEdit.Create(Range(AStart, AStop), '')];
  for mIndex := 0 to High(AReplaced) do
  begin
    Result := Result + [TRuleEdit.Create(Range(AReplaced[mIndex].StartOffset, AReplaced[mIndex].EndOffset),
      FLoopIndex)];
  end;
end;

/// <summary>Korrektur: Länge vor der Schleife setzen, SetLength entfernen, A[High(A)] durch A[I] ersetzen.
/// Bleibt im begin … end nur eine Anweisung, entfällt der Block.</summary>
function TSetLengthScan.CountFix(ALoop, AStatement: TSyntaxNode): TArray<TRuleFix>;
var
  mBody, mOther: TSyntaxNode;
  mEdits: TArray<TRuleEdit>;
  mReplaced: TArray<TSyntaxNode>;
  mStart, mStop: Integer;
begin
  Result := nil;
  mBody := LoopBody(ALoop);
  if (FLoopIndex = '') or (mBody = nil) or not FreshLocal(ALoop) or not WholeLines(AStatement, mStart, mStop) or
    not LastIndexUses(mBody, AStatement, mReplaced) then
  begin
    Exit;
  end;
  mEdits := [TRuleEdit.Create(Range(LineStart(ALoop.StartOffset), LineStart(ALoop.StartOffset)),
    Indent(ALoop.StartOffset) + Format('SetLength(%s, %s);', [FTarget, FCount]) +
    TTextLines.LineBreakOf(FContext.Text))];
  mOther := SoleOther(mBody, AStatement);
  if (mOther <> nil) and OnOwnLine(mBody.StartOffset) and OnOwnLine(mBody.EndOffset - 3) and
    OnOwnLine(mOther.StartOffset) and (mOther.StartOffset > AStatement.StartOffset) then
  begin
    // Die Anweisung steht schon zwei Zeichen tiefer als begin, also dort, wo sie ohne Block hingehört.
    mEdits := mEdits + [TRuleEdit.Create(Range(LineStart(mBody.StartOffset), mBody.EndOffset),
      Rewrite(LineStart(mOther.StartOffset), mOther.EndOffset, mReplaced, FLoopIndex))];
  end
  else
  begin
    mEdits := mEdits + StatementEdits(mStart, mStop, mReplaced);
  end;
  Result := [TRuleFix.Create(cTexts[TPerformanceText.SetLengthBefore].Fmt([FTarget]), mEdits)];
end;

/// <summary>Deklarierter Typ des Arrays bzw. Ergebnistyp bei Result.</summary>
function TSetLengthScan.TargetType(AStatement, ATargetNode: TSyntaxNode): string;
begin
  Result := FTypes.DeclaredType(FTarget, ATargetNode.StartPos);
  if (Result = '') and SameText(FTarget, 'Result') then
  begin
    Result := ResultType(FContext.Text, AStatement);
  end;
end;

procedure TSetLengthScan.ReportCall(ALoop, AStatement: TSyntaxNode);
begin
  if FCount <> '' then
  begin
    FReport.Add(Range(AStatement.StartOffset, AStatement.EndOffset),
      cTexts[TPerformanceText.SetLengthKnown].Fmt([FTarget, FCount]), CountFix(ALoop, AStatement));
  end
  else
  begin
    FReport.Add(Range(AStatement.StartOffset, AStatement.EndOffset), cTexts[TPerformanceText.SetLengthUnknown].Fmt(
      [FTarget]));
  end;
end;

procedure TSetLengthScan.CheckCall(AStatement: TSyntaxNode);
var
  mCall, mLoop: TSyntaxNode;
begin
  mCall := AStatement[0];
  if mCall[1].Kind <> TSyntaxKind.Identifier then
  begin
    Exit;
  end;
  FTarget := mCall[1].Name;
  mLoop := EnclosingLoop(AStatement);
  if (mLoop = nil) or not IsGrowth(FContext.Text, mCall[2], FTarget) or
    not TDynamicArrayTypes.IsDynamic(TargetType(AStatement, mCall[1]), FArrayTypes) then
  begin
    Exit;
  end;
  FCount := '';
  FLoopIndex := '';
  if RunsEveryIteration(mLoop, AStatement) then
  begin
    FCount := ForCount(FContext.Text, mLoop, FLoopIndex);
  end;
  ReportCall(mLoop, AStatement);
end;

procedure TSetLengthScan.Run;
var
  mCalls: TArray<TSyntaxNode>;
  mStatement: TSyntaxNode;
begin
  mCalls := SetLengthCalls(FContext.Tree.Root);
  if mCalls = nil then
  begin
    Exit;
  end;
  FCache := TRuleDerived.Open(FContext);
  FArrayTypes := TDynamicArrayTypes.DeclaredIn(FContext.Text, FContext.Tree.Root);
  FTypes := TDeclaredTypes.Create(FContext.Tree, FContext.Text);
  try
    for mStatement in mCalls do
    begin
      CheckCall(mStatement);
    end;
  finally
    FreeAndNil(FTypes);
  end;
end;

function TSetLengthInLoopRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('setlength-in-loop', TRuleSeverity.Hint,
    cTexts[TPerformanceText.GrowTitle].Text);
end;

procedure TSetLengthInLoopRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TSetLengthScan;
begin
  // Vorfilter: ohne SetLength keine Arbeit.
  if (AContext.Tree = nil) or not ContainsText(AContext.Text, 'SetLength') then
  begin
    Exit;
  end;
  mScan := TSetLengthScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

procedure RegisterPerformanceRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TStringConcatInLoopRule.Create);
  ARegistry.Register(TLoopInvariantCallRule.Create);
  ARegistry.Register(TMissingBeginUpdateRule.Create);
  ARegistry.Register(TSetLengthInLoopRule.Create);
  ARegistry.Register(TManagedParamWithoutConstRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Performance', cTexts);

end.
