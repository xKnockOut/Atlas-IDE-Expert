unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory;

// Regeln für Speicher und Lebensdauer verwalteter Typen aus Atlas.Common.Rules.Builtin.RtlTypePatterns (Stufe 2 aus
// #153, angemeldet in
// RegisterRtlTypePatternRules):
//   managed-type-raw-memory  FillChar, ZeroMemory, Move, CopyMemory, GetMem oder FreeMem auf Variablen,
//                            deren Typ Strings, Interfaces, dynamische Arrays oder Variants enthält
//                            (#921). Records und Aliasse werden in der Datei und im Index aufgelöst.
//   threadvar-managed        threadvar mit verwaltetem Typ: Delphi finalisiert ihn am Thread-Ende
//                            nicht (#922)
//   pchar-of-temporary       PChar(S + '.bak'), PChar(IntToStr(N)) … in einer Variablen, einem Feld oder
//                            Result gemerkt bzw. an PostMessage übergeben (#923): der temporäre String
//                            ist nach der Anweisung weg
//   createprocess-readonly-commandline
//                            CreateProcess(W) bzw. CreateProcessAsUser(W) mit PChar(…) als Befehlszeile, die auf
//                            schreibgeschützten Speicher zeigen kann (#955): Literal oder Konstante, Verkettung aus
//                            genau einem Literal und einem Wert (ist er leer, bleibt das Literal), eine Variable mit
//                            einer solchen letzten Zuweisung ohne UniqueString danach, ein String-Parameter (mittlere
//                            Konfidenz). CreateProcessW schreibt in den Puffer. Korrektur: lokale Kopie mit
//                            UniqueString bzw. UniqueString(Variable) vor der Anweisung

interface

uses
  Atlas.Common.Rules.Contract;

type
  TManagedTypeRawMemoryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TThreadvarManagedRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TPCharOfTemporaryRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  TCreateProcessReadonlyCommandLineRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Stelle der Befehlszeile (ab 0) bei CreateProcess, CreateProcessW, CreateProcessAsUser(W); -1 sonst.
    /// </summary>
    class function CommandLineIndex(const AName: string): Integer; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.JSON,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.DeclaredTypes,
  Atlas.Common.Pascal.FormatStrings,
  Atlas.Common.Index.Contract,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Pascal.TokenCursor,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Text.Lines,
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TRtlTypePatternsMemoryText = (Title, IsManaged, Contains, Overwrites, CopiesRefs, Uninitialized, NotReleased,
    ThreadvarTitle, ContainsParen, ThreadvarLeak, PCharTitle, StoreIntermediate, TemporaryNow, TemporaryLater,
    CreateProcessTitle, CopyCommandLine, MayBeConstant, ParamConstant, ConstantCommandLine, ConcatCommandLine,
    CallUniqueString);

const
  cTexts: array[TRtlTypePatternsMemoryText] of TAtlasText = (
    (De: 'FillChar, Move oder GetMem auf verwaltete Typen'; En: 'FillChar, Move or GetMem on managed types'),
    (De: '%s ist ein verwalteter Typ'; En: '%s is a managed type'),
    (De: '%s enthält %s'; En: '%s contains %s'),
    (De: 'überschreibt die Referenzen ohne Freigabe (Leck, ggf. Zugriffsverletzung).';
     En: 'overwrites the references without release (leak, possibly access violation).'),
    (De: 'kopiert die Referenzen ohne Referenzzählung (doppelte Freigabe, ggf. Zugriffsverletzung).';
     En: 'copies the references without reference counting (double release, possibly access violation).'),
    (De: 'lässt die Referenzen uninitialisiert (Zugriffsverletzung beim ersten Zuweisen); New oder Initialize ' +
      'verwenden.';
     En: 'leaves the references uninitialized (access violation on the first assignment); use New or Initialize.'),
    (De: 'gibt die Referenzen nicht frei (Leck); Dispose oder Finalize verwenden.';
     En: 'does not release the references (leak); use Dispose or Finalize.'),
    (De: 'threadvar mit verwaltetem Typ'; En: 'threadvar with managed type'),
    (De: '%s (enthält %s)'; En: '%s (contains %s)'),
    (De: 'threadvar mit %s wird beim Thread-Ende nicht finalisiert (Leck je Thread).';
     En: 'threadvar with %s is not finalized at thread end (leak per thread).'),
    (De: 'PChar auf einen temporären String'; En: 'PChar to a temporary string'),
    (De: 'Zwischenergebnis in %s ablegen'; En: 'Store intermediate result in %s'),
    (De: 'Der Ausdruck %s ist temporär; %s zeigt nach dieser Zeile auf freigegebenen Speicher.';
     En: 'The expression %s is temporary; %s points to released memory after this line.'),
    (De: 'Der Ausdruck %s ist temporär; %s liest den Zeiger erst später aus freigegebenem Speicher.';
     En: 'The expression %s is temporary; %s reads the pointer later from released memory.'),
    (De: 'CreateProcess mit unveränderlicher Befehlszeile'; En: 'CreateProcess with immutable command line'),
    (De: 'Befehlszeile in eine lokale Variable kopieren und UniqueString aufrufen';
     En: 'Copy the command line into a local variable and call UniqueString'),
    (De: '%s schreibt in die Befehlszeile; %s kann auf einen konstanten String verweisen und ist ohne UniqueString ' +
      'nicht beschreibbar.';
     En: '%s writes to the command line; %s can refer to a constant string and is not writable without UniqueString.'),
    (De: '%s schreibt in die Befehlszeile; der Parameter %s kann ein konstanter String sein und ist ohne ' +
      'UniqueString nicht beschreibbar.';
     En: '%s writes to the command line; the parameter %s can be a constant string and is not writable without ' +
      'UniqueString.'),
    (De: '%s schreibt in die Befehlszeile; ein konstanter String ist nicht beschreibbar.';
     En: '%s writes to the command line; a constant string is not writable.'),
    (De: '%s schreibt in die Befehlszeile; ist der andere Teil leer, liefert die Verkettung das konstante Literal, ' +
      'das nicht beschreibbar ist.';
     En: '%s writes to the command line; if the other part is empty, the concatenation returns the constant literal, ' +
      'which is not writable.'),
    (De: 'UniqueString(%s) davor aufrufen'; En: 'Call UniqueString(%s) before it'));

{$SCOPEDENUMS OFF}

{ TManagedTypeRawMemoryRule }

function TManagedTypeRawMemoryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('managed-type-raw-memory', TRuleSeverity.Error,
    cTexts[TRtlTypePatternsMemoryText.Title].Text);
end;

type
  /// <summary>Arbeitsklasse von managed-type-raw-memory: prüft FillChar, Move, GetMem und Verwandte auf Variablen
  /// verwalteter Typen.</summary>
  TRawMemoryScan = class
  private
    FContext: TRuleContext;
    FReport: IRuleReport;
    FTokens: TTokens;
    FTypes: TDeclaredTypes;
    FManaged: TManagedTypes;
    FCall: Integer;
    FOpen: Integer;
    FClose: Integer;
    FStarts: TArray<Integer>;
    FStops: TArray<Integer>;
    FRoutine: string;
    procedure SplitArguments;
    function Target(AArgument: Integer; out ADeref: Boolean): Integer;
    function DataType(AName: Integer; AAsPointer: Boolean): string;
    function Subject(const ATypeName, AKind: string): string;
    function IsStatement: Boolean;
    function IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
    function IsZero(AArgument: Integer): Boolean;
    procedure Report(const ATypeName, AKind, AText: string; const AFixes: TArray<TRuleFix>);
    procedure CheckOverwrite;
    procedure CheckCopy(ASource, ADestination: Integer);
    procedure CheckMemory(AAllocate: Boolean);
    function IsCallAt(AIndex: Integer): Boolean;
    procedure CheckCall;
  public
    constructor Create(const AContext: TRuleContext; const AReport: IRuleReport);
    destructor Destroy; override;
    procedure Run;
  end;

{ TRawMemoryScan }

constructor TRawMemoryScan.Create(const AContext: TRuleContext; const AReport: IRuleReport);
begin
  inherited Create;
  FContext := AContext;
  FReport := AReport;
  FTokens := AContext.Tree.Tokens;
  FTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  FManaged := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
end;

destructor TRawMemoryScan.Destroy;
begin
  FManaged.Free;
  FTypes.Free;
  inherited Destroy;
end;

// Argumente auf oberster Ebene: Start- und Endtoken.
procedure TRawMemoryScan.SplitArguments;
var
  mInner, mDepth, mFirst: Integer;
begin
  FStarts := nil;
  FStops := nil;
  mDepth := 0;
  mFirst := NextCode(FTokens, FOpen + 1);
  for mInner := FOpen + 1 to FClose do
  begin
    if (mInner = FClose) or ((mDepth = 0) and FTokens[mInner].IsSymbol(',')) then
    begin
      if mFirst < mInner then
      begin
        FStarts := FStarts + [mFirst];
        FStops := FStops + [PreviousCode(FTokens, mInner)];
      end;
      mFirst := NextCode(FTokens, mInner + 1);
    end
    else if FTokens[mInner].IsSymbol('(') or FTokens[mInner].IsSymbol('[') then
    begin
      Inc(mDepth);
    end
    else if FTokens[mInner].IsSymbol(')') or FTokens[mInner].IsSymbol(']') then
    begin
      Dec(mDepth);
    end;
  end;
end;

// Argument AIndex als X, @X oder X^: Name (Tokenindex) und ob dereferenziert; -1 sonst.
function TRawMemoryScan.Target(AArgument: Integer; out ADeref: Boolean): Integer;
var
  mFirst, mLast: Integer;
begin
  Result := -1;
  ADeref := False;
  if AArgument > High(FStarts) then
  begin
    Exit;
  end;
  mFirst := FStarts[AArgument];
  mLast := FStops[AArgument];
  if FTokens[mFirst].IsSymbol('@') then
  begin
    mFirst := NextCode(FTokens, mFirst + 1);
  end;
  if (mLast > mFirst) and FTokens[mLast].IsSymbol('^') and (NextCode(FTokens, mFirst + 1) = mLast) then
  begin
    ADeref := True;
    mLast := mFirst;
  end;
  if (mFirst = mLast) and (FTokens[mFirst].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := mFirst;
  end;
end;

// Typ der Daten hinter dem Argument; bei AAsPointer (GetMem, FreeMem, X^) der Zieltyp des Zeigers.
function TRawMemoryScan.DataType(AName: Integer; AAsPointer: Boolean): string;
begin
  Result := FTypes.DeclaredType(FTokens[AName].Text, FTokens[AName].StartPos);
  if AAsPointer then
  begin
    Result := FManaged.Pointee(Result);
  end;
end;

function TRawMemoryScan.Subject(const ATypeName, AKind: string): string;
begin
  if FManaged.IsPrimitive(ATypeName) then
  begin
    Result := cTexts[TRtlTypePatternsMemoryText.IsManaged].Fmt([ATypeName]);
  end
  else
  begin
    Result := cTexts[TRtlTypePatternsMemoryText.Contains].Fmt([ATypeName, AKind]);
  end;
end;

// Anweisung: davor ;, begin, then, else, do, try, finally, except oder repeat; danach ;, end oder else.
function TRawMemoryScan.IsStatement: Boolean;
var
  mBefore, mAfter: Integer;
begin
  mBefore := PreviousCode(FTokens, FCall);
  mAfter := NextCode(FTokens, FClose + 1);
  Result := (mBefore >= 0) and (FTokens[mBefore].IsSymbol(';') or FTokens[mBefore].IsKeyword('begin') or
    FTokens[mBefore].IsKeyword('then') or FTokens[mBefore].IsKeyword('else') or FTokens[mBefore].IsKeyword('do') or
    FTokens[mBefore].IsKeyword('try') or FTokens[mBefore].IsKeyword('finally') or FTokens[mBefore].IsKeyword('except') or
    FTokens[mBefore].IsKeyword('repeat')) and (mAfter <= High(FTokens)) and (FTokens[mAfter].IsSymbol(';') or
    FTokens[mAfter].IsKeyword('end') or FTokens[mAfter].IsKeyword('else'));
end;

// Argument ist SizeOf(X) oder SizeOf(T) mit X bzw. T wie angegeben.
function TRawMemoryScan.IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
var
  mFirst, mInner, mLast: Integer;
begin
  Result := False;
  if AArgument > High(FStarts) then
  begin
    Exit;
  end;
  mFirst := FStarts[AArgument];
  mInner := NextCode(FTokens, NextCode(FTokens, mFirst + 1) + 1);
  mLast := FStops[AArgument];
  Result := SameText(FTokens[mFirst].Text, 'SizeOf') and (NextCode(FTokens, mInner + 1) = mLast) and
    FTokens[mLast].IsSymbol(')') and (SameText(FTokens[mInner].Text, AName) or SameText(FTokens[mInner].Text,
      ATypeName));
end;

function TRawMemoryScan.IsZero(AArgument: Integer): Boolean;
begin
  Result := (AArgument <= High(FStarts)) and (FStarts[AArgument] = FStops[AArgument]) and
    MatchText(FTokens[FStarts[AArgument]].Text, ['0', '#0', '$0', '$00']);
end;

procedure TRawMemoryScan.Report(const ATypeName, AKind, AText: string; const AFixes: TArray<TRuleFix>);
begin
  FReport.Add(RangeOf(FTokens, FCall, FClose), Format('%s; %s %s', [Subject(ATypeName, AKind), FRoutine, AText]),
    TRuleConfidence.High, AFixes);
end;

procedure TRawMemoryScan.CheckOverwrite;
var
  mName: Integer;
  mDeref: Boolean;
  mTypeName, mKind: string;
  mFixes: TArray<TRuleFix>;
begin
  mName := Target(0, mDeref);
  if mName < 0 then
  begin
    Exit;
  end;
  mTypeName := DataType(mName, mDeref);
  mKind := FManaged.Managed(mTypeName, 0);
  if mKind = '' then
  begin
    Exit;
  end;
  mFixes := nil;
  // FillChar(X, SizeOf(X), 0) bzw. ZeroMemory(@X, SizeOf(X)): X := Default(T).
  if IsStatement and not mDeref and IsSizeOf(1, FTokens[mName].Text, mTypeName) and
    (SameText(FRoutine, 'ZeroMemory') or IsZero(2)) then
  begin
    mFixes := [TRuleFix.Create(Format('%s := Default(%s)', [FTokens[mName].Text, mTypeName]),
      [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), Format('%s := Default(%s)', [FTokens[mName].Text,
      mTypeName]))], True)];
  end;
  Report(mTypeName, mKind, cTexts[TRtlTypePatternsMemoryText.Overwrites].Text,
    mFixes);
end;

procedure TRawMemoryScan.CheckCopy(ASource, ADestination: Integer);
var
  mSource, mDestination: Integer;
  mSourceDeref, mDestinationDeref: Boolean;
  mSourceType, mDestinationType, mKind, mTypeName: string;
  mFixes: TArray<TRuleFix>;
  mPlain: Boolean;
begin
  mSource := Target(ASource, mSourceDeref);
  mDestination := Target(ADestination, mDestinationDeref);
  mSourceType := '';
  mDestinationType := '';
  if mSource >= 0 then
  begin
    mSourceType := DataType(mSource, mSourceDeref);
  end;
  if mDestination >= 0 then
  begin
    mDestinationType := DataType(mDestination, mDestinationDeref);
  end;
  mTypeName := mDestinationType;
  mKind := FManaged.Managed(mDestinationType, 0);
  if mKind = '' then
  begin
    mTypeName := mSourceType;
    mKind := FManaged.Managed(mSourceType, 0);
  end;
  if mKind = '' then
  begin
    Exit;
  end;
  mFixes := nil;
  // Move(A, B, SizeOf(T)) mit gleichem Typ: B := A.
  mPlain := (mSource >= 0) and (mDestination >= 0) and not mSourceDeref and not mDestinationDeref;
  if mPlain and IsStatement and SameText(mSourceType, mDestinationType) and
    IsSizeOf(2, FTokens[mSource].Text, mSourceType) then
  begin
    mFixes := [TRuleFix.Create(Format('%s := %s', [FTokens[mDestination].Text, FTokens[mSource].Text]),
      [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), Format('%s := %s', [FTokens[mDestination].Text,
      FTokens[mSource].Text]))], True)];
  end;
  Report(mTypeName, mKind, cTexts[TRtlTypePatternsMemoryText.CopiesRefs].Text, mFixes);
end;

procedure TRawMemoryScan.CheckMemory(AAllocate: Boolean);
var
  mName: Integer;
  mDeref: Boolean;
  mTypeName, mKind, mReplacement: string;
  mFixes: TArray<TRuleFix>;
begin
  mName := Target(0, mDeref);
  if (mName < 0) or mDeref then
  begin
    Exit;
  end;
  mTypeName := DataType(mName, True);
  mKind := FManaged.Managed(mTypeName, 0);
  if mKind = '' then
  begin
    Exit;
  end;
  mFixes := nil;
  if AAllocate then
  begin
    mReplacement := Format('New(%s)', [FTokens[mName].Text]);
  end
  else
  begin
    mReplacement := Format('Dispose(%s)', [FTokens[mName].Text]);
  end;
  // GetMem(P, SizeOf(T)) bzw. FreeMem(P) oder FreeMem(P, SizeOf(T)): New bzw. Dispose.
  if IsStatement and ((Length(FStarts) = 1) and not AAllocate or IsSizeOf(1, '', mTypeName)) then
  begin
    mFixes := [TRuleFix.Create(mReplacement, [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), mReplacement)], True)];
  end;
  if AAllocate then
  begin
    Report(mTypeName, mKind, cTexts[TRtlTypePatternsMemoryText.Uninitialized].Text, mFixes);
  end
  else
  begin
    Report(mTypeName, mKind, cTexts[TRtlTypePatternsMemoryText.NotReleased].Text, mFixes);
  end;
end;

/// <summary>Aufruf von FillChar, Move, GetMem … bei AIndex mit vollständiger Argumentliste (FOpen, FClose);
/// Methoden anderer Objekte (Stream.Move) sind nicht gemeint.</summary>
function TRawMemoryScan.IsCallAt(AIndex: Integer): Boolean;
var
  mPrev: Integer;
begin
  mPrev := PreviousCode(FTokens, AIndex);
  FOpen := NextCode(FTokens, AIndex + 1);
  Result := (FTokens[AIndex].Kind = TPascalTokenKind.Identifier) and MatchText(FTokens[AIndex].Text, ['FillChar',
    'ZeroMemory', 'FillMemory', 'Move', 'CopyMemory', 'GetMem', 'FreeMem']) and
    not ((mPrev >= 0) and FTokens[mPrev].IsSymbol('.'));
  Result := Result and (FOpen <= High(FTokens)) and FTokens[FOpen].IsSymbol('(');
  if Result then
  begin
    FClose := MatchingParen(FTokens, FOpen);
    Result := FClose >= 0;
  end;
end;

procedure TRawMemoryScan.CheckCall;
begin
  if MatchText(FRoutine, ['FillChar', 'ZeroMemory', 'FillMemory']) then
  begin
    CheckOverwrite;
  end
  else if SameText(FRoutine, 'Move') then
  begin
    CheckCopy(0, 1);
  end
  else if SameText(FRoutine, 'CopyMemory') then
  begin
    CheckCopy(1, 0);
  end
  else
  begin
    CheckMemory(SameText(FRoutine, 'GetMem'));
  end;
end;

procedure TRawMemoryScan.Run;
var
  mIndex: Integer;
begin
  for mIndex := 0 to High(FTokens) do
  begin
    if IsCallAt(mIndex) then
    begin
      FCall := mIndex;
      SplitArguments;
      FRoutine := FTokens[mIndex].Text;
      CheckCall;
    end;
  end;
end;

{ TManagedTypeRawMemoryRule }

procedure TManagedTypeRawMemoryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mWorker: TRawMemoryScan;
begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mWorker := TRawMemoryScan.Create(AContext, AReport);
  try
    mWorker.Run;
  finally
    mWorker.Free;
  end;
end;

{ TThreadvarManagedRule }

function TThreadvarManagedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('threadvar-managed', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsMemoryText.ThreadvarTitle].Text);
end;

procedure TThreadvarManagedRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTokens: TTokens;
  mManaged: TManagedTypes;

  procedure CheckDecl(ADecl: TSyntaxNode);
  var
    mTypeName, mKind, mName, mShown: string;
    mIndex: Integer;
  begin
    mTypeName := mManaged.NodeTypeText(ADecl);
    mKind := mManaged.Managed(mTypeName, 0);
    if mKind = '' then
    begin
      Exit;
    end;
    mShown := mTypeName;
    if not mManaged.IsPrimitive(mTypeName) then
    begin
      mShown := cTexts[TRtlTypePatternsMemoryText.ContainsParen].Fmt([mTypeName, mKind]);
    end;
    for mName in SplitString(ADecl.Name, ',') do
    begin
      for mIndex := TSyntaxTree.FirstTokenOf(mTokens, ADecl.StartOffset) to High(mTokens) do
      begin
        if mTokens[mIndex].Offset >= ADecl.EndOffset then
        begin
          Break;
        end;
        if (mTokens[mIndex].Offset >= ADecl.StartOffset) and (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and
          SameText(mTokens[mIndex].Text, Trim(mName)) then
        begin
          AReport.Add(RangeOf(mTokens, mIndex, mIndex), cTexts[TRtlTypePatternsMemoryText.ThreadvarLeak].Fmt([mShown]),
            TRuleConfidence.High);
          Break;
        end;
      end;
    end;
  end;

  procedure CheckSection(ASection: TSyntaxNode);
  var
    mIndex: Integer;
  begin
    for mIndex := 0 to ASection.ChildCount - 1 do
    begin
      if ASection[mIndex].Kind = TSyntaxKind.VarDecl then
      begin
        CheckDecl(ASection[mIndex]);
      end;
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.VarSection) and SameText(mNode.Name, 'threadvar') then
        begin
          CheckSection(mNode);
          Continue;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mManaged := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    Visit(AContext.Tree.Root);
  finally
    mManaged.Free;
  end;
end;

{ TPCharOfTemporaryRule }

const
  cPCharCasts: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');
  // Umwandlungen, durch die die Regel hindurchsieht: LPARAM(PChar(…)).
  cPassThroughCasts: array[0..9] of string = ('LPARAM', 'WPARAM', 'NativeInt', 'NativeUInt', 'Pointer', 'Integer',
    'Cardinal', 'Int64', 'UInt64', 'IntPtr');
  cStringCasts: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString');
  // Asynchrone Nachrichten: der Empfänger liest den Zeiger erst nach der Anweisung.
  cAsyncMessages: array[0..3] of string = ('PostMessage', 'PostThreadMessage', 'SendNotifyMessage',
    'SendMessageCallback');

function TPCharOfTemporaryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('pchar-of-temporary', TRuleSeverity.Warning,
    cTexts[TRtlTypePatternsMemoryText.PCharTitle].Text);
end;

/// <summary>Ist ANode selbst ein String: String-Literal, Bezeichner mit String-Typ oder Aufruf einer Funktion (keine
/// Umwandlung nach PChar oder durch LPARAM(…) und Verwandte)?</summary>
function IsStringLeaf(ATypes: TDeclaredTypes; ANode: TSyntaxNode): Boolean;
begin
  case ANode.Kind of
    TSyntaxKind.Literal:
      Result := (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']);
    TSyntaxKind.Identifier:
      Result := MatchText(ATypes.DeclaredType(ANode.Name, ANode.StartPos), cStringCasts);
    TSyntaxKind.Call:
      Result := not MatchText(ANode.Name, cPCharCasts) and not MatchText(ANode.Name, cPassThroughCasts);
  else
    Result := False;
  end;
end;

/// <summary>Legt die Bausteine von ANode (über + und Klammern) links vor rechts auf APending.</summary>
procedure PushStringParts(APending: TStack<TSyntaxNode>; ANode: TSyntaxNode);
begin
  if (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) then
  begin
    APending.Push(ANode[0]);
  end
  else if (ANode.Kind = TSyntaxKind.BinaryExpr) and (ANode.Name = '+') and (ANode.ChildCount = 2) then
  begin
    APending.Push(ANode[1]);
    APending.Push(ANode[0]);
  end;
end;

/// <summary>Deklariert ein Element von ASection den Namen AName?</summary>
function SectionDeclares(ASection: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
begin
  Result := False;
  mIndex := 0;
  while not Result and (mIndex < ASection.ChildCount) do
  begin
    Result := (ASection[mIndex].Kind = TSyntaxKind.VarDecl) and ListsName(ASection[mIndex].Name, AName);
    Inc(mIndex);
  end;
end;

/// <summary>Deklariert ein var-Abschnitt der Routine ARoutine (nicht verschachtelt) die Variable AName?</summary>
function IsLocalVariable(ARoutine: TSyntaxNode; const AName: string): Boolean;
var
  mIndex: Integer;
  mSection: TSyntaxNode;
begin
  Result := False;
  mIndex := 0;
  while not Result and (ARoutine <> nil) and (mIndex < ARoutine.ChildCount) do
  begin
    mSection := ARoutine[mIndex];
    Result := (mSection.Kind = TSyntaxKind.VarSection) and SameText(mSection.Name, 'var') and
      SectionDeclares(mSection, AName);
    Inc(mIndex);
  end;
end;

procedure TPCharOfTemporaryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTypes: TDeclaredTypes;
  mTokens: TTokens;
  mLineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Ist einer der Bausteine (über + und Klammern) ein String? Iterativ (Bericht M1): die Verkettung ist eine
  // Oder-Verknüpfung, die Reihenfolge bleibt links vor rechts.
  function IsStringValue(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    Result := False;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while not Result and (mPending.Count > 0) do
      begin
        mNode := mPending.Pop;
        Result := IsStringLeaf(mTypes, mNode);
        PushStringParts(mPending, mNode);
      end;
    finally
      mPending.Free;
    end;
  end;

  // Nur Literale: der Compiler legt den String als Konstante ab. Iterativ (Bericht M1): Und-Verknüpfung über
  // Klammern und zweistellige Ausdrücke.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    Result := True;
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        case mNode.Kind of
          TSyntaxKind.Literal:
            ;
          TSyntaxKind.ParenExpr:
            if mNode.ChildCount = 1 then
            begin
              mPending.Push(mNode[0]);
            end
            else
            begin
              Exit(False);
            end;
          TSyntaxKind.BinaryExpr:
            if mNode.ChildCount = 2 then
            begin
              mPending.Push(mNode[1]);
              mPending.Push(mNode[0]);
            end
            else
            begin
              Exit(False);
            end;
        else
          Exit(False);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // Temporärer String: Verkettung mit einem String oder Ergebnis eines Funktionsaufrufs.
  function IsTemporary(ANode: TSyntaxNode): Boolean;
  var
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch String-Umwandlungen und Klammern hindurch.
    mNode := ANode;
    while True do
    begin
      if (mNode.Kind = TSyntaxKind.Call) and MatchText(mNode.Name, cStringCasts) and (mNode.ChildCount = 2) then
      begin
        mNode := mNode[1];
      end
      else if mNode.Kind = TSyntaxKind.ParenExpr then
      begin
        if mNode.ChildCount <> 1 then
        begin
          Exit(False);
        end;
        mNode := mNode[0];
      end
      else
      begin
        Break;
      end;
    end;
    Result := not IsConstant(mNode) and (((mNode.Kind = TSyntaxKind.BinaryExpr) and IsStringValue(mNode)) or
      ((mNode.Kind = TSyntaxKind.Call) and IsStringValue(mNode)));
  end;

  // PChar(temporär) in AValue, auch hinter LPARAM(…) und ähnlichen Umwandlungen; sonst nil.
  function TemporaryPChar(AValue: TSyntaxNode): TSyntaxNode;
  var
    mValue: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch die Umwandlungen hindurch.
    Result := nil;
    mValue := AValue;
    while (mValue <> nil) and (mValue.Kind = TSyntaxKind.Call) and (mValue.ChildCount = 2) do
    begin
      if MatchText(mValue.Name, cPCharCasts) and IsTemporary(mValue[1]) then
      begin
        Exit(mValue[1]);
      end;
      if not MatchText(mValue.Name, cPassThroughCasts) then
      begin
        Exit;
      end;
      mValue := mValue[1];
    end;
  end;

  // Neuer Name AName + 'Text', der in der Routine noch nicht vorkommt.
  function FreshName(ARoutine: TSyntaxNode; const ABase: string): string;
  var
    mNumber: Integer;

    function Used(const AName: string): Boolean;
    var
      mIndex: Integer;
    begin
      // Binär zum ersten Token der Routine statt ab Dateianfang (#1323).
      mIndex := TRoutineBody.TokenAt(mTokens, ARoutine.StartOffset);
      while (mIndex <= High(mTokens)) and (mTokens[mIndex].Offset < ARoutine.EndOffset) do
      begin
        if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(mTokens[mIndex].Text, AName) then
        begin
          Exit(True);
        end;
        Inc(mIndex);
      end;
      Result := False;
    end;

  begin
    Result := ABase + 'Text';
    mNumber := 2;
    while Used(Result) do
    begin
      Result := ABase + 'Text' + IntToStr(mNumber);
      Inc(mNumber);
    end;
  end;

  procedure CheckAssign(AStatement, ARoutine, AParent: TSyntaxNode);
  var
    mExpression: TSyntaxNode;
    mTarget, mName, mIndent: string;
    mFixes: TArray<TRuleFix>;
  begin
    mExpression := TemporaryPChar(AStatement[1]);
    if mExpression = nil then
    begin
      Exit;
    end;
    mTarget := Trim(Text(AStatement[0]));
    mFixes := nil;
    // Lokale Variable direkt in einem Block: das Zwischenergebnis in eine Inline-Variable legen.
    if (AStatement[0].Kind = TSyntaxKind.Identifier) and (AParent <> nil) and (AParent.Kind = TSyntaxKind.Block) and
      IsLocalVariable(ARoutine, mTarget) then
    begin
      mName := FreshName(ARoutine, mTarget);
      mIndent := StringOfChar(' ', AStatement.StartPos.Character);
      mFixes := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.StoreIntermediate].Fmt([mName]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
        Format('var %s: string := %s;', [mName, Trim(Text(mExpression))]) + mLineBreak + mIndent),
        TRuleEdit.Create(TTextRange.Create(mExpression.StartPos, mExpression.EndPos), mName)])];
    end;
    AReport.Add(TTextRange.Create(mExpression.StartPos, mExpression.EndPos),
      cTexts[TRtlTypePatternsMemoryText.TemporaryNow].Fmt([Trim(Text(mExpression)), mTarget]),
      TRuleConfidence.High, mFixes);
  end;

  procedure CheckAsync(ACall: TSyntaxNode);
  var
    mIndex: Integer;
    mExpression: TSyntaxNode;
  begin
    for mIndex := 1 to ACall.ChildCount - 1 do
    begin
      mExpression := TemporaryPChar(ACall[mIndex]);
      if mExpression <> nil then
      begin
        AReport.Add(TTextRange.Create(mExpression.StartPos, mExpression.EndPos),
          cTexts[TRtlTypePatternsMemoryText.TemporaryLater].Fmt([Trim(Text(mExpression)),
          ACall.Name]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure Visit(ANode, ARoutine, AParent: TSyntaxNode);
  var
    mPending, mRoutineStack, mParents: TStack<TSyntaxNode>;
    mNode, mRoutine, mParent: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und AParent je Knoten mit.
    mPending := TStack<TSyntaxNode>.Create;
    mRoutineStack := TStack<TSyntaxNode>.Create;
    mParents := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      mRoutineStack.Push(ARoutine);
      mParents.Push(AParent);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        mRoutine := mRoutineStack.Pop;
        mParent := mParents.Pop;
        if mNode.Kind = TSyntaxKind.RoutineDecl then
        begin
          mRoutine := mNode;
        end;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount = 2) then
        begin
          CheckAssign(mNode, mRoutine, mParent);
        end
        else if (mNode.Kind = TSyntaxKind.Call) and MatchText(mNode.Name, cAsyncMessages) then
        begin
          CheckAsync(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
          mRoutineStack.Push(mRoutine);
          mParents.Push(mNode);
        end;
      end;
    finally
      mParents.Free;
      mRoutineStack.Free;
      mPending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    mTypes.Free;
  end;
end;

{ TCreateProcessReadonlyCommandLineRule }

type
  /// <summary>Warum die Befehlszeile nicht beschreibbar ist.</summary>
{$SCOPEDENUMS ON}
  TCommandLineKind = (None, Constant, Concatenation, Variable, Parameter);
{$SCOPEDENUMS OFF}

function TCreateProcessReadonlyCommandLineRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('createprocess-readonly-commandline', TRuleSeverity.Error,
    cTexts[TRtlTypePatternsMemoryText.CreateProcessTitle].Text);
end;

class function TCreateProcessReadonlyCommandLineRule.CommandLineIndex(const AName: string): Integer;
begin
  // CreateProcessA kopiert die Befehlszeile selbst in einen Puffer; nur die Unicode-Fassung schreibt hinein.
  if MatchText(AName, ['CreateProcess', 'CreateProcessW']) then
  begin
    Result := 1;
  end
  else if MatchText(AName, ['CreateProcessAsUser', 'CreateProcessAsUserW']) then
  begin
    Result := 2;
  end
  else
  begin
    Result := -1;
  end;
end;

procedure TCreateProcessReadonlyCommandLineRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mTypes: TDeclaredTypes;
  mLocal: TUnitIndex;
  mLineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Trim(Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset));
  end;

  function IsStringLiteral(ANode: TSyntaxNode): Boolean;
  begin
    Result := (ANode.Kind = TSyntaxKind.Literal) and (ANode.Name <> '') and CharInSet(ANode.Name[1], ['''', '#']);
  end;

  function IsUnicodeString(const AType: string): Boolean;
  begin
    Result := MatchText(Trim(AType), ['string', 'UnicodeString', 'System.string', 'System.UnicodeString']);
  end;

  // Konstante (auch typisierte) aus Datei oder Index; eine gleichnamige Variable der Datei verdeckt sie.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  var
    mSymbol: TIndexSymbol;
    mLocation: TSymbolLocation;
  begin
    for mSymbol in mLocal.Symbols do
    begin
      if (mSymbol.Kind = TIndexSymbolKind.Constant) and SameText(mSymbol.Name, ANode.Name) then
      begin
        Exit(True);
      end;
    end;
    if mTypes.DeclaredType(ANode.Name, ANode.StartPos) <> '' then
    begin
      Exit(False);
    end;
    if AContext.Index <> nil then
    begin
      for mLocation in AContext.Index.FindSymbols(ANode.Name) do
      begin
        if mLocation.Symbol.Kind = TIndexSymbolKind.Constant then
        begin
          Exit(True);
        end;
      end;
    end;
    Result := False;
  end;

  // Literal oder Konstante: zeigt auf schreibgeschützten Speicher (Referenzzähler -1).
  function IsReadonly(ANode: TSyntaxNode): Boolean;
  begin
    while (ANode.Kind = TSyntaxKind.ParenExpr) and (ANode.ChildCount = 1) do
    begin
      ANode := ANode[0];
    end;
    Result := IsStringLiteral(ANode) or ((ANode.Kind = TSyntaxKind.Identifier) and IsConstant(ANode));
  end;

  procedure Operands(ANode: TSyntaxNode; var AList: TArray<TSyntaxNode>);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): die Glieder der Verkettung von links nach rechts.
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if (mNode.Kind = TSyntaxKind.BinaryExpr) and (mNode.Name = '+') and (mNode.ChildCount = 2) then
        begin
          mPending.Push(mNode[1]);
          mPending.Push(mNode[0]);
        end
        else
        begin
          AList := AList + [mNode];
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  // 'notepad.exe ' + Datei: Ist Datei leer, liefert die Verkettung das Literal selbst zurück.
  function IsLiteralConcatenation(ANode: TSyntaxNode): Boolean;
  var
    mList: TArray<TSyntaxNode>;
  begin
    mList := nil;
    Operands(ANode, mList);
    Result := (Length(mList) = 2) and (IsReadonly(mList[0]) <> IsReadonly(mList[1]));
  end;

  function Classify(ANode: TSyntaxNode): TCommandLineKind;
  begin
    if IsReadonly(ANode) then
    begin
      Result := TCommandLineKind.Constant;
    end
    else if (ANode.Kind = TSyntaxKind.BinaryExpr) and IsLiteralConcatenation(ANode) then
    begin
      Result := TCommandLineKind.Concatenation;
    end
    else
    begin
      Result := TCommandLineKind.None;
    end;
  end;

  // Parameter AName der Routine (Name, Modifizierer)?
  function FindParameter(ARoutine: TSyntaxNode; const AName: string): TSyntaxNode;
  var
    mHeader, mParams: TSyntaxNode;
    mIndex: Integer;
    mName: string;
  begin
    Result := nil;
    mHeader := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if mHeader = nil then
    begin
      Exit;
    end;
    mParams := mHeader.FindChild(TSyntaxKind.Parameters);
    if mParams = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mParams.ChildCount - 1 do
    begin
      for mName in SplitString(mParams[mIndex].Name, ',') do
      begin
        if SameText(Trim(mName), AName) then
        begin
          Exit(mParams[mIndex]);
        end;
      end;
    end;
  end;

  // Letzte Zuweisung an AName vor AOffset in ANode (Baumreihenfolge) und UniqueString(AName) danach.
  procedure Assignments(ANode: TSyntaxNode; const AName: string; AOffset: Integer; var ALast: TSyntaxNode;
    var AUnique: Integer);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1), Baumreihenfolge wie die frühere Rekursion (die letzte Zuweisung zählt).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.StartOffset >= AOffset then
        begin
          Continue;
        end;
        if (mNode.Kind = TSyntaxKind.AssignStatement) and (mNode.ChildCount = 2) and
          (mNode[0].Kind = TSyntaxKind.Identifier) and SameText(mNode[0].Name, AName) then
        begin
          ALast := mNode;
        end;
        if (mNode.Kind = TSyntaxKind.Call) and SameText(mNode.Name, 'UniqueString') and (mNode.ChildCount = 2) and
          (mNode[1].Kind = TSyntaxKind.Identifier) and SameText(mNode[1].Name, AName) then
        begin
          AUnique := mNode.StartOffset;
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

  function ClassifyIdentifier(ARoutine, ANode: TSyntaxNode; AOffset: Integer): TCommandLineKind;
  var
    mLast: TSyntaxNode;
    mUnique: Integer;
  begin
    Result := TCommandLineKind.None;
    if not IsUnicodeString(mTypes.DeclaredType(ANode.Name, ANode.StartPos)) then
    begin
      Exit;
    end;
    mLast := nil;
    mUnique := -1;
    Assignments(ARoutine, ANode.Name, AOffset, mLast, mUnique);
    if mLast <> nil then
    begin
      if (mUnique < mLast.StartOffset) and (Classify(mLast[1]) <> TCommandLineKind.None) then
      begin
        Result := TCommandLineKind.Variable;
      end;
    end
    else if (mUnique < 0) and (FindParameter(ARoutine, ANode.Name) <> nil) then
    begin
      Result := TCommandLineKind.Parameter;
    end;
  end;

  // Anweisung in einer Anweisungsliste, vor der die Korrektur einfügen darf; nil in Schleifenbedingungen.
  function StatementOf(ANode: TSyntaxNode): TSyntaxNode;
  begin
    Result := ANode.Parent;
    while (Result <> nil) and not (TRoutineBody.IsStatement(Result) and TRoutineBody.InList(Result)) do
    begin
      if Result.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement, TSyntaxKind.ForStatement,
        TSyntaxKind.ForInStatement, TSyntaxKind.RoutineDecl, TSyntaxKind.AnonymousMethod] then
      begin
        Exit(nil);
      end;
      Result := Result.Parent;
    end;
    if (Result <> nil) and (Result.Kind in [TSyntaxKind.WhileStatement, TSyntaxKind.RepeatStatement,
      TSyntaxKind.ForStatement, TSyntaxKind.ForInStatement]) then
    begin
      Result := nil;
    end;
  end;

  function Fixes(ARoutine, AValue: TSyntaxNode; AKind: TCommandLineKind): TArray<TRuleFix>;
  var
    mStatement: TSyntaxNode;
    mName, mIndent: string;
  begin
    Result := nil;
    mStatement := StatementOf(AValue);
    if mStatement = nil then
    begin
      Exit;
    end;
    if AKind = TCommandLineKind.Variable then
    begin
      Result := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.CallUniqueString].Fmt([AValue.Name]),
        [TRoutineBody.InsertBefore(AContext.Text, mStatement, 'UniqueString(' + AValue.Name + ');')])];
      Exit;
    end;
    mName := TRoutineBody.UniqueName(AContext.Tree.Tokens, AContext.NewNames.Local('Befehl'));
    mIndent := TTextLines.IndentOf(AContext.Text, mStatement.StartPos.Line);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.CopyCommandLine].Text,
      [TRoutineBody.AddVariable(AContext.Text, ARoutine, mName, 'string', AContext.Formatting),
      TRoutineBody.InsertBefore(AContext.Text, mStatement, mName + ' := ' + Text(AValue) + ';' + mLineBreak + mIndent +
      'UniqueString(' + mName + ');'),
      TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos), mName)])];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    mIndex: Integer;
    mArgument, mValue, mRoutine: TSyntaxNode;
    mKind: TCommandLineKind;
    mMessage: string;
    mConfidence: TRuleConfidence;
  begin
    mIndex := CommandLineIndex(ACall.Name);
    if (mIndex < 0) or (ACall.ChildCount <= mIndex + 1) then
    begin
      Exit;
    end;
    mArgument := ACall[mIndex + 1];
    if (mArgument.Kind <> TSyntaxKind.Call) or not MatchText(mArgument.Name, ['PChar', 'PWideChar']) or
      (mArgument.ChildCount <> 2) then
    begin
      Exit;
    end;
    mValue := mArgument[1];
    mRoutine := TRoutineBody.RoutineAt(AContext.Tree, ACall.StartOffset);
    mKind := Classify(mValue);
    if (mKind = TCommandLineKind.None) and (mValue.Kind = TSyntaxKind.Identifier) and (mRoutine <> nil) then
    begin
      mKind := ClassifyIdentifier(mRoutine, mValue, ACall.StartOffset);
    end;
    mConfidence := TRuleConfidence.High;
    case mKind of
      TCommandLineKind.Constant:
        mMessage := cTexts[TRtlTypePatternsMemoryText.ConstantCommandLine].Fmt([ACall.Name]);
      TCommandLineKind.Concatenation:
        mMessage := cTexts[TRtlTypePatternsMemoryText.ConcatCommandLine].Fmt([ACall.Name]);
      TCommandLineKind.Variable:
        mMessage := cTexts[TRtlTypePatternsMemoryText.MayBeConstant].Fmt([ACall.Name, mValue.Name]);
      TCommandLineKind.Parameter:
        begin
          mMessage := cTexts[TRtlTypePatternsMemoryText.ParamConstant].Fmt([ACall.Name, mValue.Name]);
          mConfidence := TRuleConfidence.Medium;
        end;
    else
      Exit;
    end;
    if mRoutine = nil then
    begin
      AReport.Add(TTextRange.Create(mValue.StartPos, mValue.EndPos), mMessage, mConfidence);
    end
    else
    begin
      AReport.Add(TTextRange.Create(mValue.StartPos, mValue.EndPos), mMessage, mConfidence,
        Fixes(mRoutine, mValue, mKind));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    mPending: TStack<TSyntaxNode>;
    mNode: TSyntaxNode;
    mIndex: Integer;
  begin
    // Iterativ (Bericht M1).
    mPending := TStack<TSyntaxNode>.Create;
    try
      mPending.Push(ANode);
      while mPending.Count > 0 do
      begin
        mNode := mPending.Pop;
        if mNode.Kind = TSyntaxKind.Call then
        begin
          CheckCall(mNode);
        end;
        for mIndex := mNode.ChildCount - 1 downto 0 do
        begin
          mPending.Push(mNode[mIndex]);
        end;
      end;
    finally
      mPending.Free;
    end;
  end;

var
  mCache: IRuleDerivedCache;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'CreateProcess') then
  begin
    Exit;
  end;
  mLineBreak := TTextLines.LineBreakOf(AContext.Text);
  mCache := TRuleDerived.Open(AContext);
  mLocal := TRuleDerived.UnitIndex(mCache, AContext);
  mTypes := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    mTypes.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory', cTexts);

end.
