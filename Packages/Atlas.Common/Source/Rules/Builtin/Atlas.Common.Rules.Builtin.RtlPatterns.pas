unit Atlas.Common.Rules.Builtin.RtlPatterns;

// Regeln für fehleranfällige RTL-Muster, Stufe 1 aus #153 (syntaktisch, ohne Typen):
//   self-assignment           X := X
//   for-high-to-low           for I := High(A) to Low(A) bzw. Count - 1 to 0 ohne downto; konstante
//                             Grenzen, die nie laufen (10 to 1, wie H2135, #1023)
//   exception-not-raised      Exception erzeugt, aber nicht ausgelöst
//   assert-side-effect        Assert mit Seiteneffekt im Argument; fällt mit {$C-} weg
//   ifthen-side-effect        IfThen wertet beide Zweige aus: Nil-Zugriff oder Funktionsaufruf darin
//   random-without-randomize  Random ohne Randomize in der Unit (Standard aus, niedrige Konfidenz)

interface

uses
  Atlas.Common.Rules.Contract,
  Atlas.Common.Rules.Registry;

type
  TSelfAssignmentRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TForHighToLowRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TExceptionNotRaisedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TAssertSideEffectRule = class(TInterfacedObject, IRule)
  public const
    cDefaultMutatingMethods: array[0..5] of string = ('Add', 'Delete', 'Remove', 'Extract', 'Clear', 'Insert');
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Option "mutatingMethods" aus den Regeloptionen; ohne Angabe die Vorgabe.</summary>
    class function MutatingMethods(const AOptions: string): TArray<string>; static;
  end;

  TIfThenSideEffectRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TRandomWithoutRandomizeRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

/// <summary>Registriert die Regeln für RTL-Muster.</summary>
procedure RegisterRtlPatternRules(const ARegistry: TRuleRegistry);

implementation

uses
  Atlas.Common.Rules.Derived,
  System.Generics.Collections,
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Pascal.PureRoutines,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRtlPatternsText = (SelfAssignTitle, SelfAssignHidden, AddSelf, SelfAssign, RemoveStatement, ForToTitle, ToDownto,
    ForTo, NeverRuns, NotRaisedTitle, NotRaised, PrependRaise, AssertTitle, AssertSideEffect, IfThenTitle,
    ToIfStatement, IfThen, RandomTitle, Random);

const
  cTexts: array[TRtlPatternsText] of TAtlasText = (
    (De: 'Zuweisung an sich selbst'; En: 'Assignment to itself'),
    (De: '%s wird sich selbst zugewiesen: %s verdeckt %s; gemeint ist vermutlich Self.%s := %s';
     En: '%s is assigned to itself: %s hides %s; Self.%s := %s is probably meant'),
    (De: 'Self. ergänzen'; En: 'Add Self.'),
    (De: '%s wird sich selbst zugewiesen; gemeint ist vermutlich ein anderer Wert';
     En: '%s is assigned to itself; another value is probably meant'),
    (De: 'Anweisung entfernen'; En: 'Remove statement'),
    (De: 'for-Schleife zählt mit to vom oberen zum unteren Wert';
     En: 'for loop counts with to from the upper to the lower value'),
    (De: 'to durch downto ersetzen'; En: 'Replace to with downto'),
    (De: 'Die Schleife läuft vom oberen zum unteren Wert mit to und wird daher nie ausgeführt; downto verwenden';
     En: 'The loop runs from the upper to the lower value with to and is therefore never executed; use downto'),
    (De: 'Die Schleife läuft nie (%s to %s); gemeint war downto (wie H2135).';
     En: 'The loop never runs (%s to %s); downto was meant (like H2135).'),
    (De: 'Exception erzeugt, aber nicht ausgelöst'; En: 'Exception created but not raised'),
    (De: '%s wird erzeugt, aber nicht ausgelöst; raise fehlt'; En: '%s is created but not raised; raise is missing'),
    (De: 'raise voranstellen'; En: 'Prepend raise'),
    (De: 'Assert mit Seiteneffekt'; En: 'Assert with side effect'),
    (De: '%s im Assert verändert Daten; mit {$C-} entfällt der ganze Aufruf samt Seiteneffekt. Vorher ausführen und ' +
      'nur das Ergebnis prüfen';
     En: '%s in the Assert changes data; with {$C-} the whole call including the side effect is dropped. Execute it ' +
      'before and only check the result'),
    (De: 'IfThen wertet beide Zweige aus'; En: 'IfThen evaluates both branches'),
    (De: 'In if-Anweisung umwandeln'; En: 'Convert to if statement'),
    (De: 'IfThen wertet beide Zweige aus, auch den nicht gewählten; Seiteneffekte und Nil-Zugriffe darin treten ' +
      'immer auf. if-Anweisung verwenden';
     En: 'IfThen evaluates both branches, also the one not chosen; side effects and nil accesses in them always ' +
      'occur. Use an if statement'),
    (De: 'Random ohne Randomize'; En: 'Random without Randomize'),
    (De: 'Random ohne Randomize in dieser Unit liefert bei jedem Start dieselbe Folge; Randomize einmal beim ' +
      'Programmstart aufrufen';
     En: 'Random without Randomize in this unit returns the same sequence on every start; call Randomize once at ' +
      'program start'));

{$SCOPEDENUMS OFF}

type
  TTokens = TArray<TPascalToken>;
  /// <summary>Token eines Arguments, erstes und letztes.</summary>
  TSpan = record
    First: Integer;
    Last: Integer;
  end;

function IsTrivia(const AToken: TPascalToken): Boolean;
begin
  Result := AToken.Kind in [TPascalTokenKind.Comment, TPascalTokenKind.Directive];
end;

/// <summary>Nächstes Code-Token ab AIndex; Length(ATokens) ohne.</summary>
function NextCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex;
  while (Result <= High(ATokens)) and IsTrivia(ATokens[Result]) do
  begin
    Inc(Result);
  end;
end;

/// <summary>Vorheriges Code-Token vor AIndex; -1 ohne.</summary>
function PreviousCode(const ATokens: TTokens; AIndex: Integer): Integer;
begin
  Result := AIndex - 1;
  while (Result >= 0) and IsTrivia(ATokens[Result]) do
  begin
    Dec(Result);
  end;
end;

/// <summary>Beginnt hinter ATokens[AIndex] eine Anweisung?</summary>
function EndsStatement(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  if AIndex < 0 then
  begin
    Exit(False);
  end;
  Result := ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsKeyword('begin') or
    ATokens[AIndex].IsKeyword('then') or ATokens[AIndex].IsKeyword('else') or ATokens[AIndex].IsKeyword('do') or
    ATokens[AIndex].IsKeyword('try') or ATokens[AIndex].IsKeyword('finally') or
    ATokens[AIndex].IsKeyword('except') or ATokens[AIndex].IsKeyword('repeat');
end;

/// <summary>Endet vor ATokens[AIndex] eine Anweisung (;, end, else, until, except, finally)?</summary>
function IsStatementEnd(const ATokens: TTokens; AIndex: Integer): Boolean;
begin
  if AIndex > High(ATokens) then
  begin
    Exit(True);
  end;
  Result := ATokens[AIndex].IsSymbol(';') or ATokens[AIndex].IsKeyword('end') or
    ATokens[AIndex].IsKeyword('else') or ATokens[AIndex].IsKeyword('until') or
    ATokens[AIndex].IsKeyword('except') or ATokens[AIndex].IsKeyword('finally');
end;

/// <summary>Index der zur öffnenden Klammer bei AOpen passenden schließenden; -1 ohne.</summary>
function Closing(const ATokens: TTokens; AOpen: Integer): Integer;
var
  mDepth: Integer;
begin
  mDepth := 0;
  for Result := AOpen to High(ATokens) do
  begin
    if ATokens[Result].IsSymbol('(') or ATokens[Result].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[Result].IsSymbol(')') or ATokens[Result].IsSymbol(']') then
    begin
      Dec(mDepth);
      if mDepth = 0 then
      begin
        Exit;
      end;
    end;
  end;
  Result := -1;
end;

/// <summary>Code der Token AFirst..ALast ohne Kommentare, Wörter klein, mit Leerzeichen getrennt.</summary>
function Normalized(const ATokens: TTokens; AFirst, ALast: Integer): string;
var
  mIndex: Integer;
begin
  Result := '';
  for mIndex := AFirst to ALast do
  begin
    if not IsTrivia(ATokens[mIndex]) then
    begin
      Result := Result + ' ' + LowerCase(ATokens[mIndex].Text);
    end;
  end;
end;

/// <summary>Bezeichnerkette aus Bezeichnern, Punkten, Indizes und ^?</summary>
function IsDesignator(const ATokens: TTokens; AFirst, ALast: Integer): Boolean;
var
  mIndex, mDepth: Integer;
begin
  if (AFirst > ALast) or (ATokens[AFirst].Kind <> TPascalTokenKind.Identifier) then
  begin
    Exit(False);
  end;
  mDepth := 0;
  for mIndex := AFirst to ALast do
  begin
    if IsTrivia(ATokens[mIndex]) then
    begin
      Continue;
    end;
    if ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if ATokens[mIndex].IsSymbol(']') then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and not ((ATokens[mIndex].Kind = TPascalTokenKind.Identifier) or
      ATokens[mIndex].IsSymbol('.') or ATokens[mIndex].IsSymbol('^')) then
    begin
      Exit(False);
    end;
  end;
  Result := mDepth = 0;
end;

function RangeOf(const ATokens: TTokens; AFirst, ALast: Integer): TTextRange;
begin
  Result := TTextRange.Create(ATokens[AFirst].StartPos, ATokens[ALast].EndPos);
end;

/// <summary>Grenzen der Argumente zwischen AOpen und AClose (Klammern) auf oberster Ebene.</summary>
function Arguments(const ATokens: TTokens; AOpen, AClose: Integer): TArray<TSpan>;
var
  mIndex, mDepth, mStart: Integer;
  mSpan: TSpan;
begin
  Result := nil;
  mDepth := 0;
  mStart := AOpen + 1;
  for mIndex := AOpen + 1 to AClose do
  begin
    if ATokens[mIndex].IsSymbol('(') or ATokens[mIndex].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if (ATokens[mIndex].IsSymbol(')') or ATokens[mIndex].IsSymbol(']')) and (mIndex < AClose) then
    begin
      Dec(mDepth);
    end
    else if (mDepth = 0) and (ATokens[mIndex].IsSymbol(',') or (mIndex = AClose)) then
    begin
      mSpan.First := mStart;
      mSpan.Last := mIndex - 1;
      Result := Result + [mSpan];
      mStart := mIndex + 1;
    end;
  end;
end;

{ TSelfAssignmentRule }

function TSelfAssignmentRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('self-assignment', TRuleSeverity.Warning,
    cTexts[TRtlPatternsText.SelfAssignTitle].Text);
end;

/// <summary>Quelltext der Token AFirst..ALast wie geschrieben.</summary>
function SourceText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Trim(Copy(AText, ATokens[AFirst].Offset + 1,
    ATokens[ALast].Offset + Length(ATokens[ALast].Text) - ATokens[AFirst].Offset));
end;

/// <summary>Beginn der linken Seite der Zuweisung bei AAssign (bis zum Anweisungsbeginn zurück); False, wenn davor
/// kein Anweisungsende steht.</summary>
function AssignmentStart(const ATokens: TTokens; AAssign: Integer; out AStart: Integer): Boolean;
var
  mBefore: Integer;
begin
  AStart := PreviousCode(ATokens, AAssign);
  mBefore := PreviousCode(ATokens, AStart);
  while (mBefore >= 0) and not EndsStatement(ATokens, mBefore) and not ATokens[mBefore].IsKeyword('var') and
    not ATokens[mBefore].IsSymbol(':') and not ATokens[mBefore].IsSymbol(':=') do
  begin
    AStart := mBefore;
    mBefore := PreviousCode(ATokens, AStart);
  end;
  Result := (mBefore >= 0) and EndsStatement(ATokens, mBefore);
end;

/// <summary>Token, das die Anweisung nach AFrom beendet.</summary>
function StatementStop(const ATokens: TTokens; AFrom: Integer): Integer;
begin
  Result := NextCode(ATokens, AFrom + 1);
  while not IsStatementEnd(ATokens, Result) do
  begin
    Result := NextCode(ATokens, Result + 1);
  end;
end;

/// <summary>Weist die Anweisung AStart..AStop mit := bei AAssign einen Bezeichner sich selbst zu?</summary>
function IsSelfAssignment(const ATokens: TTokens; AStart, AAssign, AStop: Integer): Boolean;
begin
  Result := (AStop <= High(ATokens)) and IsDesignator(ATokens, AStart, PreviousCode(ATokens, AAssign)) and
    (Normalized(ATokens, AStart, AAssign - 1) = Normalized(ATokens, AAssign + 1, AStop - 1));
end;

type
  /// <summary>Ein Lauf von self-assignment über eine Datei.</summary>
  TSelfAssignmentScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TTokens;
    FCache: IRuleDerivedCache;
    FResolver: TNameResolver;
    /// <summary>Resolver des Laufs (TRuleDerived.Resolver), erst bei Bedarf; gehört dem Cache.</summary>
    function Resolver: TNameResolver;
    /// <summary>Name := Name, wenn ein Parameter oder eine lokale Variable das gleichnamige Feld verdeckt: gemeint
    /// ist fast immer Self.Name := Name.</summary>
    procedure AddShadowFix(AStart: Integer; const AName: string; var AMessage: string; var AFixes: TArray<TRuleFix>);
    procedure CheckAssign(AAssign: Integer);
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    procedure Run;
  end;

constructor TSelfAssignmentScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FResolver := nil;
end;

function TSelfAssignmentScan.Resolver: TNameResolver;
begin
  if FResolver = nil then
  begin
    FCache := TRuleDerived.Open(FContext);
    FResolver := TRuleDerived.Resolver(FCache, FContext);
  end;
  Result := FResolver;
end;

procedure TSelfAssignmentScan.AddShadowFix(AStart: Integer; const AName: string; var AMessage: string;
  var AFixes: TArray<TRuleFix>);
var
  mLocal, mMember: TResolvedSymbol;
  mInsert: TTextRange;
begin
  mLocal := Resolver.ResolveChain(FContext.Tree, FContext.RelativePath, [AName], FTokens[AStart].Offset, False);
  if mLocal.Kind <> TResolvedKind.Local then
  begin
    Exit;
  end;
  mMember := Resolver.ResolveChain(FContext.Tree, FContext.RelativePath, ['Self', AName], FTokens[AStart].Offset,
    False);
  if (mMember.Kind <> TResolvedKind.Symbol) or
    not (mMember.SymbolKind in [TIndexSymbolKind.Field, TIndexSymbolKind.Property_]) then
  begin
    Exit;
  end;
  AMessage := cTexts[TRtlPatternsText.SelfAssignHidden].Fmt(
    [AName, mLocal.ShadowText, mMember.ShadowText, AName, AName]);
  mInsert := TTextRange.Create(FTokens[AStart].StartPos, FTokens[AStart].StartPos);
  AFixes := [TRuleFix.Create(cTexts[TRtlPatternsText.AddSelf].Text, [TRuleEdit.Create(mInsert, 'Self.')])] + AFixes;
end;

procedure TSelfAssignmentScan.CheckAssign(AAssign: Integer);
var
  mStart, mStop, mLeftEnd: Integer;
  mRemoval: TTextRange;
  mName, mMessage: string;
  mFixes: TArray<TRuleFix>;
begin
  if not AssignmentStart(FTokens, AAssign, mStart) then
  begin
    Exit;
  end;
  mStop := StatementStop(FTokens, AAssign);
  if not IsSelfAssignment(FTokens, mStart, AAssign, mStop) then
  begin
    Exit;
  end;
  if FTokens[mStop].IsSymbol(';') then
  begin
    mRemoval := RangeOf(FTokens, mStart, mStop);
  end
  else
  begin
    mRemoval := RangeOf(FTokens, mStart, PreviousCode(FTokens, mStop));
  end;
  mLeftEnd := PreviousCode(FTokens, AAssign);
  mName := SourceText(FContext.Text, FTokens, mStart, mLeftEnd);
  mMessage := cTexts[TRtlPatternsText.SelfAssign].Fmt([mName]);
  mFixes := [TRuleFix.Create(cTexts[TRtlPatternsText.RemoveStatement].Text, [TRuleEdit.Create(mRemoval, '')])];
  if (mStart = mLeftEnd) and (FTokens[mStart].Kind = TPascalTokenKind.Identifier) and (FContext.Index <> nil) then
  begin
    AddShadowFix(mStart, mName, mMessage, mFixes);
  end;
  FReport.Add(RangeOf(FTokens, mStart, PreviousCode(FTokens, mStop)), mMessage, TRuleConfidence.High, mFixes);
end;

procedure TSelfAssignmentScan.Run;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FTokens) do
  begin
    if FTokens[mIndex].IsSymbol(':=') then
    begin
      CheckAssign(mIndex);
    end;
  end;
end;

procedure TSelfAssignmentRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScan: TSelfAssignmentScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mScan := TSelfAssignmentScan.Create(AContext, AReport);
  try
    mScan.Run;
  finally
    mScan.Free;
  end;
end;

{ TForHighToLowRule }

function TForHighToLowRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('for-high-to-low', TRuleSeverity.Warning,
    cTexts[TRtlPatternsText.ForToTitle].Text);
end;

/// <summary>Beginnt der Ausdruck bei AIndex mit dem Aufruf AName( und endet er vor AStop?</summary>
function IsCallUntil(const ATokens: TTokens; AIndex, AStop: Integer; const AName: string): Boolean;
var
  mOpen: Integer;
begin
  Result := False;
  if (AIndex > High(ATokens)) or not SameText(ATokens[AIndex].Text, AName) then
  begin
    Exit;
  end;
  mOpen := NextCode(ATokens, AIndex + 1);
  if (mOpen > High(ATokens)) or not ATokens[mOpen].IsSymbol('(') then
  begin
    Exit;
  end;
  Result := NextCode(ATokens, Closing(ATokens, mOpen) + 1) = AStop;
end;

/// <summary>Wert eines einzelnen Zeichens (#13 bzw. 'a'); False für anderes.</summary>
function CharValue(const AToken: TPascalToken; out AValue: Int64): Boolean;
var
  mText: string;
begin
  mText := AToken.Text;
  AValue := 0;
  case AToken.Kind of
    TPascalTokenKind.CharLiteral:
      Result := (Length(mText) > 1) and TryStrToInt64(Copy(mText, 2, MaxInt), AValue);
    TPascalTokenKind.StringLiteral:
      begin
        Result := (Length(mText) = 3) and (mText[1] = '''') and (mText[3] = '''') and (mText[2] <> '''');
        if Result then
        begin
          AValue := Ord(mText[2]);
        end;
      end;
  else
    Result := False;
  end;
end;

/// <summary>Ist der Ausdruck von AFirst bis vor AStop ein ganzzahliges Literal (mit Vorzeichen) bzw. ein
/// einzelnes Zeichen? AIsChar unterscheidet beides; andere Ausdrücke liefern False.</summary>
function LiteralBound(const ATokens: TTokens; AFirst, AStop: Integer; out AValue: Int64;
  out AIsChar: Boolean): Boolean;
var
  mSign: Int64;
begin
  Result := False;
  AValue := 0;
  AIsChar := False;
  mSign := 1;
  if (AFirst <= High(ATokens)) and (ATokens[AFirst].IsSymbol('-') or ATokens[AFirst].IsSymbol('+')) then
  begin
    if ATokens[AFirst].IsSymbol('-') then
    begin
      mSign := -1;
    end;
    AFirst := NextCode(ATokens, AFirst + 1);
  end;
  if (AFirst > High(ATokens)) or (NextCode(ATokens, AFirst + 1) <> AStop) then
  begin
    Exit;
  end;
  if ATokens[AFirst].Kind = TPascalTokenKind.Number then
  begin
    // $-Hex versteht TryStrToInt64; %-Binär und Gleitkommazahlen bleiben still.
    Result := TryStrToInt64(ATokens[AFirst].Text, AValue);
    AValue := mSign * AValue;
  end
  else if mSign = 1 then
  begin
    Result := CharValue(ATokens[AFirst], AValue);
    AIsChar := Result;
  end;
end;

type
  /// <summary>Token einer for-Schleife mit to: for, Beginn des Startwerts, to, Beginn des Endwerts, do.</summary>
  TForBounds = record
    ForToken: Integer;
    StartExpr: Integer;
    ToToken: Integer;
    EndExpr: Integer;
    DoToken: Integer;
  end;

/// <summary>Token := der for-Schleife bei AFor (for I := …, for var I := …, for var I: Integer := …).</summary>
function ForAssign(const ATokens: TTokens; AFor: Integer): Integer;
begin
  Result := NextCode(ATokens, AFor + 1);
  if (Result <= High(ATokens)) and ATokens[Result].IsKeyword('var') then
  begin
    Result := NextCode(ATokens, Result + 1);
  end;
  Result := NextCode(ATokens, Result + 1);
  if (Result <= High(ATokens)) and ATokens[Result].IsSymbol(':') then
  begin
    while (Result <= High(ATokens)) and not ATokens[Result].IsSymbol(':=') and
      not ATokens[Result].IsKeyword('do') do
    begin
      Result := NextCode(ATokens, Result + 1);
    end;
  end;
end;

/// <summary>Liest die Grenzen der for-Schleife bei AFor; False ohne := oder ohne to.</summary>
function ReadForBounds(const ATokens: TTokens; AFor: Integer; out ABounds: TForBounds): Boolean;
var
  mAssign: Integer;
begin
  ABounds := Default(TForBounds);
  ABounds.ForToken := AFor;
  mAssign := ForAssign(ATokens, AFor);
  if (mAssign > High(ATokens)) or not ATokens[mAssign].IsSymbol(':=') then
  begin
    Exit(False);
  end;
  ABounds.StartExpr := NextCode(ATokens, mAssign + 1);
  ABounds.ToToken := ABounds.StartExpr;
  while (ABounds.ToToken <= High(ATokens)) and not ATokens[ABounds.ToToken].IsKeyword('to') and
    not ATokens[ABounds.ToToken].IsKeyword('downto') and not ATokens[ABounds.ToToken].IsKeyword('do') do
  begin
    Inc(ABounds.ToToken);
  end;
  if (ABounds.ToToken > High(ATokens)) or not ATokens[ABounds.ToToken].IsKeyword('to') then
  begin
    Exit(False);
  end;
  ABounds.EndExpr := NextCode(ATokens, ABounds.ToToken + 1);
  ABounds.DoToken := ABounds.EndExpr;
  while (ABounds.DoToken <= High(ATokens)) and not ATokens[ABounds.DoToken].IsKeyword('do') do
  begin
    Inc(ABounds.DoToken);
  end;
  Result := ABounds.DoToken <= High(ATokens);
end;

/// <summary>High(A) to Low(A) bzw. … Count - 1 to 0?</summary>
function RunsHighToLow(const ATokens: TTokens; const ABounds: TForBounds): Boolean;
var
  mLast: Integer;
begin
  if IsCallUntil(ATokens, ABounds.StartExpr, ABounds.ToToken, 'High') and
    IsCallUntil(ATokens, ABounds.EndExpr, ABounds.DoToken, 'Low') then
  begin
    Exit(True);
  end;
  mLast := PreviousCode(ATokens, ABounds.ToToken);
  Result := (mLast > ABounds.StartExpr + 1) and (ATokens[mLast].Text = '1') and
    ATokens[PreviousCode(ATokens, mLast)].IsSymbol('-') and
    SameText(ATokens[PreviousCode(ATokens, PreviousCode(ATokens, mLast))].Text, 'Count');
  Result := Result and (ATokens[ABounds.EndExpr].Text = '0') and
    (NextCode(ATokens, ABounds.EndExpr + 1) = ABounds.DoToken);
end;

/// <summary>Konstante Grenzen, bei denen die Schleife nie läuft: 10 to 1, -1 to -5, 'z' to 'a', #13 to #10
/// (#1023, wie H2135).</summary>
function NeverRuns(const ATokens: TTokens; const ABounds: TForBounds): Boolean;
var
  mStartValue, mEndValue: Int64;
  mStartIsChar, mEndIsChar: Boolean;
begin
  Result := LiteralBound(ATokens, ABounds.StartExpr, ABounds.ToToken, mStartValue, mStartIsChar) and
    LiteralBound(ATokens, ABounds.EndExpr, ABounds.DoToken, mEndValue, mEndIsChar) and
    (mStartIsChar = mEndIsChar) and (mStartValue > mEndValue);
end;

/// <summary>Quelltext eines Ausdrucks von AFirst bis vor AStop.</summary>
function BoundText(const AText: string; const ATokens: TTokens; AFirst, AStop: Integer): string;
begin
  Result := Trim(Copy(AText, ATokens[AFirst].Offset + 1, ATokens[AStop].Offset - ATokens[AFirst].Offset));
end;

procedure TForHighToLowRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex: Integer;
  mBounds: TForBounds;
  mFix: TRuleFix;
  mRange: TTextRange;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if not mTokens[mIndex].IsKeyword('for') or not ReadForBounds(mTokens, mIndex, mBounds) then
    begin
      Continue;
    end;
    mFix := TRuleFix.Create(cTexts[TRtlPatternsText.ToDownto].Text, [TRuleEdit.Create(RangeOf(mTokens, mBounds.ToToken,
      mBounds.ToToken), 'downto')], True);
    mRange := RangeOf(mTokens, mIndex, mBounds.DoToken);
    if RunsHighToLow(mTokens, mBounds) then
    begin
      AReport.Add(mRange, cTexts[TRtlPatternsText.ForTo].Text, TRuleConfidence.High, [mFix]);
    end
    else if NeverRuns(mTokens, mBounds) then
    begin
      AReport.Add(mRange, cTexts[TRtlPatternsText.NeverRuns].Fmt(
        [BoundText(AContext.Text, mTokens, mBounds.StartExpr, mBounds.ToToken), BoundText(AContext.Text, mTokens,
        mBounds.EndExpr, mBounds.DoToken)]), TRuleConfidence.High, [mFix]);
    end;
  end;
end;

{ TExceptionNotRaisedRule }

function TExceptionNotRaisedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('exception-not-raised', TRuleSeverity.Warning,
    cTexts[TRtlPatternsText.NotRaisedTitle].Text);
end;

function IsExceptionClass(const AName: string): Boolean;
begin
  Result := SameText(AName, 'Exception') or ((Length(AName) > 1) and (AName[1] = 'E') and
    CharInSet(AName[2], ['A'..'Z']));
end;

procedure TExceptionNotRaisedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex, mDot, mCtor, mStop, mBefore: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) or not IsExceptionClass(mTokens[mIndex].Text) then
    begin
      Continue;
    end;
    mBefore := PreviousCode(mTokens, mIndex);
    if not EndsStatement(mTokens, mBefore) then
    begin
      Continue;
    end;
    mDot := NextCode(mTokens, mIndex + 1);
    mCtor := NextCode(mTokens, mDot + 1);
    if (mCtor > High(mTokens)) or not mTokens[mDot].IsSymbol('.') or not StartsText('Create', mTokens[mCtor].Text) then
    begin
      Continue;
    end;
    mStop := NextCode(mTokens, mCtor + 1);
    if (mStop <= High(mTokens)) and mTokens[mStop].IsSymbol('(') then
    begin
      mStop := NextCode(mTokens, Closing(mTokens, mStop) + 1);
    end;
    if not IsStatementEnd(mTokens, mStop) then
    begin
      Continue;
    end;
    AReport.Add(RangeOf(mTokens, mIndex, PreviousCode(mTokens, mStop)),
      cTexts[TRtlPatternsText.NotRaised].Fmt([mTokens[mIndex].Text]), TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TRtlPatternsText.PrependRaise].Text,
        [TRuleEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos,
      mTokens[mIndex].StartPos), 'raise ')], True)]);
  end;
end;

{ TAssertSideEffectRule }

function TAssertSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('assert-side-effect', TRuleSeverity.Warning,
    cTexts[TRtlPatternsText.AssertTitle].Text);
end;

class function TAssertSideEffectRule.MutatingMethods(const AOptions: string): TArray<string>;
var
  mValue: TJSONValue;
  mItems: TJSONArray;
  mItem: TJSONValue;
  mIndex: Integer;
begin
  SetLength(Result, Length(cDefaultMutatingMethods));
  for mIndex := 0 to High(cDefaultMutatingMethods) do
  begin
    Result[mIndex] := cDefaultMutatingMethods[mIndex];
  end;
  if Trim(AOptions) = '' then
  begin
    Exit;
  end;
  mValue := TJSONObject.ParseJSONValue(AOptions);
  try
    if (mValue is TJSONObject) and TJSONObject(mValue).TryGetValue<TJSONArray>('mutatingMethods', mItems) then
    begin
      Result := nil;
      for mItem in mItems do
      begin
        if mItem is TJSONString then
        begin
          Result := Result + [mItem.Value];
        end;
      end;
    end;
  finally
    mValue.Free;
  end;
end;

/// <summary>Steht bei AIndex der Bezeichner AName mit Klammern? AOpen und AClose: die Klammern.</summary>
function CallAt(const ATokens: TTokens; AIndex: Integer; const AName: string; out AOpen, AClose: Integer): Boolean;
begin
  AClose := -1;
  AOpen := NextCode(ATokens, AIndex + 1);
  Result := (ATokens[AIndex].Kind = TPascalTokenKind.Identifier) and SameText(ATokens[AIndex].Text, AName) and
    (AOpen <= High(ATokens)) and ATokens[AOpen].IsSymbol('(');
  if Result then
  begin
    AClose := Closing(ATokens, AOpen);
    Result := AClose >= 0;
  end;
end;

/// <summary>Try…-Funktion (TryStrToInt): Sie gibt ihr Ergebnis über einen out-Parameter zurück.</summary>
function IsTryCall(const AName: string): Boolean;
begin
  Result := StartsText('Try', AName) and (Length(AName) > 3) and CharInSet(AName[4], ['A'..'Z']);
end;

/// <summary>Seiteneffekt am Token AInner im Assert mit den Klammern AOpen und AClose; '' ohne.</summary>
function EffectAt(const ATokens: TTokens; AInner, AOpen, AClose: Integer; const AMethods: TArray<string>): string;
var
  mNext: Integer;
  mText: string;
begin
  Result := '';
  if ATokens[AInner].Kind <> TPascalTokenKind.Identifier then
  begin
    Exit;
  end;
  mText := ATokens[AInner].Text;
  mNext := NextCode(ATokens, AInner + 1);
  if (mNext < AClose) and ATokens[mNext].IsSymbol('(') and (MatchText(mText, ['Inc', 'Dec']) or IsTryCall(mText)) then
  begin
    Result := mText;
  end
  else if MatchText(mText, AMethods) and (AInner > AOpen + 1) and ATokens[PreviousCode(ATokens, AInner)].IsSymbol('.')
    then
  begin
    Result := mText;
  end;
end;

/// <summary>Erster Seiteneffekt zwischen den Klammern AOpen und AClose; '' ohne.</summary>
function AssertEffect(const ATokens: TTokens; AOpen, AClose: Integer; const AMethods: TArray<string>): string;
var
  mInner: Integer;
begin
  Result := '';
  mInner := AOpen + 1;
  while (Result = '') and (mInner < AClose) do
  begin
    Result := EffectAt(ATokens, mInner, AOpen, AClose, AMethods);
    Inc(mInner);
  end;
end;

procedure TAssertSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mMethods: TArray<string>;
  mIndex, mOpen, mClose: Integer;
  mEffect: string;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mMethods := MutatingMethods(AContext.Options);
  for mIndex := 0 to High(mTokens) do
  begin
    if not CallAt(mTokens, mIndex, 'Assert', mOpen, mClose) then
    begin
      Continue;
    end;
    mEffect := AssertEffect(mTokens, mOpen, mClose, mMethods);
    if mEffect <> '' then
    begin
      AReport.Add(RangeOf(mTokens, mIndex, mClose), cTexts[TRtlPatternsText.AssertSideEffect].Fmt([mEffect]),
        TRuleConfidence.High);
    end;
  end;
end;

{ TIfThenSideEffectRule }

function TIfThenSideEffectRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('ifthen-side-effect', TRuleSeverity.Warning,
    cTexts[TRtlPatternsText.IfThenTitle].Text);
end;

/// <summary>Namen, die die Bedingung auf nil prüft: Assigned(X), X &lt;&gt; nil.</summary>
function CheckedNames(const ATokens: TTokens; AFirst, ALast: Integer): TArray<string>;
var
  mIndex, mNext, mName: Integer;
begin
  Result := nil;
  for mIndex := AFirst to ALast do
  begin
    mNext := NextCode(ATokens, mIndex + 1);
    if SameText(ATokens[mIndex].Text, 'Assigned') and (mNext <= ALast) and ATokens[mNext].IsSymbol('(') then
    begin
      mName := NextCode(ATokens, mNext + 1);
      if mName <= ALast then
      begin
        Result := Result + [LowerCase(ATokens[mName].Text)];
      end;
    end
    else if ATokens[mIndex].IsKeyword('nil') then
    begin
      mName := PreviousCode(ATokens, PreviousCode(ATokens, mIndex));
      if (mName >= AFirst) and (ATokens[mName].Kind = TPascalTokenKind.Identifier) then
      begin
        Result := Result + [LowerCase(ATokens[mName].Text)];
      end;
    end;
  end;
end;

/// <summary>Ruft ATokens[AName] eine Standardroutine ohne Seiteneffekte auf (Copy, Format, string.Join; #1109)?
/// Methoden eines Objekts (X.Name()) zählen nicht dazu.</summary>
function PureCall(const ATokens: TTokens; AName: Integer): Boolean;
var
  mDot, mOwner: Integer;
begin
  mDot := PreviousCode(ATokens, AName);
  if (mDot < 0) or not ATokens[mDot].IsSymbol('.') then
  begin
    Exit(TPureRoutines.IsPure(ATokens[AName].Text));
  end;
  mOwner := PreviousCode(ATokens, mDot);
  Result := (mOwner >= 0) and TPureRoutines.IsPure(ATokens[mOwner].Text + '.' + ATokens[AName].Text);
end;

/// <summary>Quelltext der Token AFirst..ALast ungekürzt.</summary>
function RawText(const AText: string; const ATokens: TTokens; AFirst, ALast: Integer): string;
begin
  Result := Copy(AText, ATokens[AFirst].Offset + 1, ATokens[ALast].Offset + Length(ATokens[ALast].Text) -
    ATokens[AFirst].Offset);
end;

/// <summary>Zugriff auf einen in der Bedingung geprüften Bezeichner (X.Name oder X^) am Token AInner?</summary>
function IsCheckedAccess(const ATokens: TTokens; AInner, ANext: Integer; const ASpan: TSpan;
  const AChecked: TArray<string>): Boolean;
begin
  Result := MatchText(ATokens[AInner].Text, AChecked) and (ANext <= ASpan.Last) and
    (ATokens[ANext].IsSymbol('.') or ATokens[ANext].IsSymbol('^'));
  Result := Result and ((AInner = ASpan.First) or not ATokens[PreviousCode(ATokens, AInner)].IsSymbol('.'));
end;

/// <summary>Durchsucht einen Zweig nach Aufrufen mit Seiteneffekt (AFound) und Zugriffen auf geprüfte Namen
/// (dann AConfidence hoch).</summary>
procedure ScanBranch(const ATokens: TTokens; const ASpan: TSpan; const AChecked: TArray<string>; var AFound: Boolean;
  var AConfidence: TRuleConfidence);
var
  mInner, mNext: Integer;
begin
  for mInner := ASpan.First to ASpan.Last do
  begin
    mNext := NextCode(ATokens, mInner + 1);
    if ATokens[mInner].Kind <> TPascalTokenKind.Identifier then
    begin
      Continue;
    end;
    if IsCheckedAccess(ATokens, mInner, mNext, ASpan, AChecked) then
    begin
      AFound := True;
      AConfidence := TRuleConfidence.High;
    end
    else if (mNext <= ASpan.Last) and ATokens[mNext].IsSymbol('(') and not PureCall(ATokens, mInner) then
    begin
      AFound := True;
    end;
  end;
end;

/// <summary>Hat einer der beiden Zweige einen Seiteneffekt? AConfidence: hoch bei Zugriff auf geprüfte Namen.
/// </summary>
function BranchEffects(const ATokens: TTokens; const AArgs: TArray<TSpan>; out AConfidence: TRuleConfidence): Boolean;
var
  mChecked: TArray<string>;
  mArg: Integer;
begin
  mChecked := CheckedNames(ATokens, AArgs[0].First, AArgs[0].Last);
  Result := False;
  AConfidence := TRuleConfidence.Medium;
  for mArg := 1 to 2 do
  begin
    ScanBranch(ATokens, AArgs[mArg], mChecked, Result, AConfidence);
  end;
end;

/// <summary>V := IfThen(B, X, Y); → if B then V := X else V := Y; nil, wenn IfThen nicht so steht.</summary>
function IfStatementFix(const AText: string; const ATokens: TTokens; AIndex, AClose: Integer;
  const AArgs: TArray<TSpan>): TArray<TRuleFix>;
var
  mAssign, mStop, mTarget: Integer;
  mTargetText, mStatement: string;
begin
  Result := nil;
  mAssign := PreviousCode(ATokens, AIndex);
  mStop := NextCode(ATokens, AClose + 1);
  if (mAssign < 0) or not ATokens[mAssign].IsSymbol(':=') or (mStop > High(ATokens)) or
    not ATokens[mStop].IsSymbol(';') then
  begin
    Exit;
  end;
  mTarget := PreviousCode(ATokens, mAssign);
  while (mTarget > 0) and not EndsStatement(ATokens, PreviousCode(ATokens, mTarget)) do
  begin
    mTarget := PreviousCode(ATokens, mTarget);
  end;
  if (mTarget < 0) or not IsDesignator(ATokens, mTarget, PreviousCode(ATokens, mAssign)) then
  begin
    Exit;
  end;
  mTargetText := RawText(AText, ATokens, mTarget, PreviousCode(ATokens, mAssign));
  mStatement := 'if ' + RawText(AText, ATokens, AArgs[0].First, AArgs[0].Last) + ' then ' + mTargetText + ' := ' +
    RawText(AText, ATokens, AArgs[1].First, AArgs[1].Last) + ' else ' + mTargetText + ' := ' +
    RawText(AText, ATokens, AArgs[2].First, AArgs[2].Last) + ';';
  Result := [TRuleFix.Create(cTexts[TRtlPatternsText.ToIfStatement].Text, [TRuleEdit.Create(RangeOf(ATokens, mTarget,
    mStop),
    mStatement)])];
end;

procedure TIfThenSideEffectRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mArgs: TArray<TSpan>;
  mIndex, mOpen, mClose: Integer;
  mConfidence: TRuleConfidence;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  for mIndex := 0 to High(mTokens) do
  begin
    if not CallAt(mTokens, mIndex, 'IfThen', mOpen, mClose) then
    begin
      Continue;
    end;
    mArgs := Arguments(mTokens, mOpen, mClose);
    if (Length(mArgs) = 3) and BranchEffects(mTokens, mArgs, mConfidence) then
    begin
      AReport.Add(RangeOf(mTokens, mIndex, mClose), cTexts[TRtlPatternsText.IfThen].Text, mConfidence,
        IfStatementFix(AContext.Text, mTokens, mIndex, mClose, mArgs));
    end;
  end;
end;

{ TRandomWithoutRandomizeRule }

function TRandomWithoutRandomizeRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('random-without-randomize', TRuleSeverity.Hint,
    cTexts[TRtlPatternsText.RandomTitle].Text,
    True);
end;

procedure TRandomWithoutRandomizeRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mIndex, mFirst: Integer;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mFirst := -1;
  for mIndex := 0 to High(mTokens) do
  begin
    if mTokens[mIndex].Kind = TPascalTokenKind.Identifier then
    begin
      if SameText(mTokens[mIndex].Text, 'Randomize') then
      begin
        Exit;
      end
      else if (mFirst < 0) and SameText(mTokens[mIndex].Text, 'Random') and
        ((mIndex = 0) or not mTokens[PreviousCode(mTokens, mIndex)].IsSymbol('.')) then
      begin
        mFirst := mIndex;
      end;
    end;
  end;
  if mFirst >= 0 then
  begin
    AReport.Add(RangeOf(mTokens, mFirst, mFirst), cTexts[TRtlPatternsText.Random].Text, TRuleConfidence.Low);
  end;
end;

procedure RegisterRtlPatternRules(const ARegistry: TRuleRegistry);
begin
  ARegistry.Register(TSelfAssignmentRule.Create);
  ARegistry.Register(TForHighToLowRule.Create);
  ARegistry.Register(TExceptionNotRaisedRule.Create);
  ARegistry.Register(TAssertSideEffectRule.Create);
  ARegistry.Register(TIfThenSideEffectRule.Create);
  ARegistry.Register(TRandomWithoutRandomizeRule.Create);
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlPatterns', cTexts);

end.
