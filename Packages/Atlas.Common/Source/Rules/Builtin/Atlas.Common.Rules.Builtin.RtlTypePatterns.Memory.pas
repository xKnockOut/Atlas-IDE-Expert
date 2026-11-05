unit Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory;

// Regeln für Speicher und Lebensdauer verwalteter Typen aus Atlas.Common.Rules.Builtin.RtlTypePatterns (Stufe 2 aus #153, angemeldet in
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
  Atlas.Common.Editing.UsesClause,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Rules.Options,
  Atlas.Common.Rules.Derived,
  Atlas.Common.Rules.ManagedTypes,
  Atlas.Common.Semantics.NameResolver,
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
  Inner, Depth, First: Integer;
begin
  FStarts := nil;
  FStops := nil;
  Depth := 0;
  First := NextCode(FTokens, FOpen + 1);
  for Inner := FOpen + 1 to FClose do
  begin
    if (Inner = FClose) or ((Depth = 0) and FTokens[Inner].IsSymbol(',')) then
    begin
      if First < Inner then
      begin
        FStarts := FStarts + [First];
        FStops := FStops + [PreviousCode(FTokens, Inner)];
      end;
      First := NextCode(FTokens, Inner + 1);
    end
    else if FTokens[Inner].IsSymbol('(') or FTokens[Inner].IsSymbol('[') then
    begin
      Inc(Depth);
    end
    else if FTokens[Inner].IsSymbol(')') or FTokens[Inner].IsSymbol(']') then
    begin
      Dec(Depth);
    end;
  end;
end;

// Argument AIndex als X, @X oder X^: Name (Tokenindex) und ob dereferenziert; -1 sonst.
function TRawMemoryScan.Target(AArgument: Integer; out ADeref: Boolean): Integer;
var
  First, Last: Integer;
begin
  Result := -1;
  ADeref := False;
  if AArgument > High(FStarts) then
  begin
    Exit;
  end;
  First := FStarts[AArgument];
  Last := FStops[AArgument];
  if FTokens[First].IsSymbol('@') then
  begin
    First := NextCode(FTokens, First + 1);
  end;
  if (Last > First) and FTokens[Last].IsSymbol('^') and (NextCode(FTokens, First + 1) = Last) then
  begin
    ADeref := True;
    Last := First;
  end;
  if (First = Last) and (FTokens[First].Kind = TPascalTokenKind.Identifier) then
  begin
    Result := First;
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
  Before, After: Integer;
begin
  Before := PreviousCode(FTokens, FCall);
  After := NextCode(FTokens, FClose + 1);
  Result := (Before >= 0) and (FTokens[Before].IsSymbol(';') or FTokens[Before].IsKeyword('begin') or
    FTokens[Before].IsKeyword('then') or FTokens[Before].IsKeyword('else') or FTokens[Before].IsKeyword('do') or
    FTokens[Before].IsKeyword('try') or FTokens[Before].IsKeyword('finally') or FTokens[Before].IsKeyword('except') or
    FTokens[Before].IsKeyword('repeat')) and (After <= High(FTokens)) and (FTokens[After].IsSymbol(';') or
    FTokens[After].IsKeyword('end') or FTokens[After].IsKeyword('else'));
end;

// Argument ist SizeOf(X) oder SizeOf(T) mit X bzw. T wie angegeben.
function TRawMemoryScan.IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
var
  First, Inner, Last: Integer;
begin
  Result := False;
  if AArgument > High(FStarts) then
  begin
    Exit;
  end;
  First := FStarts[AArgument];
  Inner := NextCode(FTokens, NextCode(FTokens, First + 1) + 1);
  Last := FStops[AArgument];
  Result := SameText(FTokens[First].Text, 'SizeOf') and (NextCode(FTokens, Inner + 1) = Last) and
    FTokens[Last].IsSymbol(')') and (SameText(FTokens[Inner].Text, AName) or SameText(FTokens[Inner].Text, ATypeName));
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
  Name: Integer;
  Deref: Boolean;
  TypeName, Kind: string;
  Fixes: TArray<TRuleFix>;
begin
  Name := Target(0, Deref);
  if Name < 0 then
  begin
    Exit;
  end;
  TypeName := DataType(Name, Deref);
  Kind := FManaged.Managed(TypeName, 0);
  if Kind = '' then
  begin
    Exit;
  end;
  Fixes := nil;
  // FillChar(X, SizeOf(X), 0) bzw. ZeroMemory(@X, SizeOf(X)): X := Default(T).
  if IsStatement and not Deref and IsSizeOf(1, FTokens[Name].Text, TypeName) and
    (SameText(FRoutine, 'ZeroMemory') or IsZero(2)) then
  begin
    Fixes := [TRuleFix.Create(Format('%s := Default(%s)', [FTokens[Name].Text, TypeName]),
      [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), Format('%s := Default(%s)', [FTokens[Name].Text,
      TypeName]))], True)];
  end;
  Report(TypeName, Kind, cTexts[TRtlTypePatternsMemoryText.Overwrites].Text,
    Fixes);
end;

procedure TRawMemoryScan.CheckCopy(ASource, ADestination: Integer);
var
  Source, Destination: Integer;
  SourceDeref, DestinationDeref: Boolean;
  SourceType, DestinationType, Kind, TypeName: string;
  Fixes: TArray<TRuleFix>;
  mPlain: Boolean;
begin
  Source := Target(ASource, SourceDeref);
  Destination := Target(ADestination, DestinationDeref);
  SourceType := '';
  DestinationType := '';
  if Source >= 0 then
  begin
    SourceType := DataType(Source, SourceDeref);
  end;
  if Destination >= 0 then
  begin
    DestinationType := DataType(Destination, DestinationDeref);
  end;
  TypeName := DestinationType;
  Kind := FManaged.Managed(DestinationType, 0);
  if Kind = '' then
  begin
    TypeName := SourceType;
    Kind := FManaged.Managed(SourceType, 0);
  end;
  if Kind = '' then
  begin
    Exit;
  end;
  Fixes := nil;
  // Move(A, B, SizeOf(T)) mit gleichem Typ: B := A.
  mPlain := (Source >= 0) and (Destination >= 0) and not SourceDeref and not DestinationDeref;
  if mPlain and IsStatement and SameText(SourceType, DestinationType) and
    IsSizeOf(2, FTokens[Source].Text, SourceType) then
  begin
    Fixes := [TRuleFix.Create(Format('%s := %s', [FTokens[Destination].Text, FTokens[Source].Text]),
      [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), Format('%s := %s', [FTokens[Destination].Text,
      FTokens[Source].Text]))], True)];
  end;
  Report(TypeName, Kind, cTexts[TRtlTypePatternsMemoryText.CopiesRefs].Text, Fixes);
end;

procedure TRawMemoryScan.CheckMemory(AAllocate: Boolean);
var
  Name: Integer;
  Deref: Boolean;
  TypeName, Kind, Replacement: string;
  Fixes: TArray<TRuleFix>;
begin
  Name := Target(0, Deref);
  if (Name < 0) or Deref then
  begin
    Exit;
  end;
  TypeName := DataType(Name, True);
  Kind := FManaged.Managed(TypeName, 0);
  if Kind = '' then
  begin
    Exit;
  end;
  Fixes := nil;
  if AAllocate then
  begin
    Replacement := Format('New(%s)', [FTokens[Name].Text]);
  end
  else
  begin
    Replacement := Format('Dispose(%s)', [FTokens[Name].Text]);
  end;
  // GetMem(P, SizeOf(T)) bzw. FreeMem(P) oder FreeMem(P, SizeOf(T)): New bzw. Dispose.
  if IsStatement and ((Length(FStarts) = 1) and not AAllocate or IsSizeOf(1, '', TypeName)) then
  begin
    Fixes := [TRuleFix.Create(Replacement, [TRuleEdit.Create(RangeOf(FTokens, FCall, FClose), Replacement)], True)];
  end;
  if AAllocate then
  begin
    Report(TypeName, Kind, cTexts[TRtlTypePatternsMemoryText.Uninitialized].Text, Fixes);
  end
  else
  begin
    Report(TypeName, Kind, cTexts[TRtlTypePatternsMemoryText.NotReleased].Text, Fixes);
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
    FClose := Closing(FTokens, FOpen);
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
  Tokens: TTokens;
  Managed: TManagedTypes;

  procedure CheckDecl(ADecl: TSyntaxNode);
  var
    TypeName, Kind, Name, Shown: string;
    Index: Integer;
  begin
    TypeName := Managed.NodeTypeText(ADecl);
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Shown := TypeName;
    if not Managed.IsPrimitive(TypeName) then
    begin
      Shown := cTexts[TRtlTypePatternsMemoryText.ContainsParen].Fmt([TypeName, Kind]);
    end;
    for Name in SplitString(ADecl.Name, ',') do
    begin
      for Index := TSyntaxTree.FirstTokenOf(Tokens, ADecl.StartOffset) to High(Tokens) do
      begin
        if Tokens[Index].Offset >= ADecl.EndOffset then
        begin
          Break;
        end;
        if (Tokens[Index].Offset >= ADecl.StartOffset) and (Tokens[Index].Kind = TPascalTokenKind.Identifier) and
          SameText(Tokens[Index].Text, Trim(Name)) then
        begin
          AReport.Add(RangeOf(Tokens, Index, Index), cTexts[TRtlTypePatternsMemoryText.ThreadvarLeak].Fmt([Shown]),
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
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.VarSection) and SameText(Node.Name, 'threadvar') then
        begin
          CheckSection(Node);
          Continue;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    Visit(AContext.Tree.Root);
  finally
    Managed.Free;
  end;
end;

{ TPCharOfTemporaryRule }

const
  PCharCasts: array[0..2] of string = ('PChar', 'PWideChar', 'PAnsiChar');
  // Umwandlungen, durch die die Regel hindurchsieht: LPARAM(PChar(…)).
  PassThroughCasts: array[0..9] of string = ('LPARAM', 'WPARAM', 'NativeInt', 'NativeUInt', 'Pointer', 'Integer',
    'Cardinal', 'Int64', 'UInt64', 'IntPtr');
  StringCasts: array[0..4] of string = ('string', 'UnicodeString', 'AnsiString', 'WideString', 'RawByteString');
  // Asynchrone Nachrichten: der Empfänger liest den Zeiger erst nach der Anweisung.
  AsyncMessages: array[0..3] of string = ('PostMessage', 'PostThreadMessage', 'SendNotifyMessage',
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
      Result := MatchText(ATypes.DeclaredType(ANode.Name, ANode.StartPos), StringCasts);
    TSyntaxKind.Call:
      Result := not MatchText(ANode.Name, PCharCasts) and not MatchText(ANode.Name, PassThroughCasts);
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
  Types: TDeclaredTypes;
  Tokens: TTokens;
  LineBreak: string;

  function Text(ANode: TSyntaxNode): string;
  begin
    Result := Copy(AContext.Text, ANode.StartOffset + 1, ANode.EndOffset - ANode.StartOffset);
  end;

  // Ist einer der Bausteine (über + und Klammern) ein String? Iterativ (Bericht M1): die Verkettung ist eine
  // Oder-Verknüpfung, die Reihenfolge bleibt links vor rechts.
  function IsStringValue(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := False;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while not Result and (Pending.Count > 0) do
      begin
        Node := Pending.Pop;
        Result := IsStringLeaf(Types, Node);
        PushStringParts(Pending, Node);
      end;
    finally
      Pending.Free;
    end;
  end;

  // Nur Literale: der Compiler legt den String als Konstante ab. Iterativ (Bericht M1): Und-Verknüpfung über
  // Klammern und zweistellige Ausdrücke.
  function IsConstant(ANode: TSyntaxNode): Boolean;
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    Result := True;
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Literal:
            ;
          TSyntaxKind.ParenExpr:
            if Node.ChildCount = 1 then
            begin
              Pending.Push(Node[0]);
            end
            else
            begin
              Exit(False);
            end;
          TSyntaxKind.BinaryExpr:
            if Node.ChildCount = 2 then
            begin
              Pending.Push(Node[1]);
              Pending.Push(Node[0]);
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
      Pending.Free;
    end;
  end;

  // Temporärer String: Verkettung mit einem String oder Ergebnis eines Funktionsaufrufs.
  function IsTemporary(ANode: TSyntaxNode): Boolean;
  var
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch String-Umwandlungen und Klammern hindurch.
    Node := ANode;
    while True do
    begin
      if (Node.Kind = TSyntaxKind.Call) and MatchText(Node.Name, StringCasts) and (Node.ChildCount = 2) then
      begin
        Node := Node[1];
      end
      else if Node.Kind = TSyntaxKind.ParenExpr then
      begin
        if Node.ChildCount <> 1 then
        begin
          Exit(False);
        end;
        Node := Node[0];
      end
      else
      begin
        Break;
      end;
    end;
    Result := not IsConstant(Node) and (((Node.Kind = TSyntaxKind.BinaryExpr) and IsStringValue(Node)) or
      ((Node.Kind = TSyntaxKind.Call) and IsStringValue(Node)));
  end;

  // PChar(temporär) in AValue, auch hinter LPARAM(…) und ähnlichen Umwandlungen; sonst nil.
  function TemporaryPChar(AValue: TSyntaxNode): TSyntaxNode;
  var
    Value: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): durch die Umwandlungen hindurch.
    Result := nil;
    Value := AValue;
    while (Value <> nil) and (Value.Kind = TSyntaxKind.Call) and (Value.ChildCount = 2) do
    begin
      if MatchText(Value.Name, PCharCasts) and IsTemporary(Value[1]) then
      begin
        Exit(Value[1]);
      end;
      if not MatchText(Value.Name, PassThroughCasts) then
      begin
        Exit;
      end;
      Value := Value[1];
    end;
  end;

  // Neuer Name AName + 'Text', der in der Routine noch nicht vorkommt.
  function FreshName(ARoutine: TSyntaxNode; const ABase: string): string;
  var
    Number: Integer;

    function Used(const AName: string): Boolean;
    var
      mIndex: Integer;
    begin
      // Binär zum ersten Token der Routine statt ab Dateianfang (#1323).
      mIndex := TRoutineBody.TokenAt(Tokens, ARoutine.StartOffset);
      while (mIndex <= High(Tokens)) and (Tokens[mIndex].Offset < ARoutine.EndOffset) do
      begin
        if (Tokens[mIndex].Kind = TPascalTokenKind.Identifier) and SameText(Tokens[mIndex].Text, AName) then
        begin
          Exit(True);
        end;
        Inc(mIndex);
      end;
      Result := False;
    end;

  begin
    Result := ABase + 'Text';
    Number := 2;
    while Used(Result) do
    begin
      Result := ABase + 'Text' + IntToStr(Number);
      Inc(Number);
    end;
  end;

  procedure CheckAssign(AStatement, ARoutine, AParent: TSyntaxNode);
  var
    Expression: TSyntaxNode;
    Target, Name, Indent: string;
    Fixes: TArray<TRuleFix>;
  begin
    Expression := TemporaryPChar(AStatement[1]);
    if Expression = nil then
    begin
      Exit;
    end;
    Target := Trim(Text(AStatement[0]));
    Fixes := nil;
    // Lokale Variable direkt in einem Block: das Zwischenergebnis in eine Inline-Variable legen.
    if (AStatement[0].Kind = TSyntaxKind.Identifier) and (AParent <> nil) and (AParent.Kind = TSyntaxKind.Block) and
      IsLocalVariable(ARoutine, Target) then
    begin
      Name := FreshName(ARoutine, Target);
      Indent := StringOfChar(' ', AStatement.StartPos.Character);
      Fixes := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.StoreIntermediate].Fmt([Name]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
        Format('var %s: string := %s;', [Name, Trim(Text(Expression))]) + LineBreak + Indent),
        TRuleEdit.Create(TTextRange.Create(Expression.StartPos, Expression.EndPos), Name)])];
    end;
    AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos),
      cTexts[TRtlTypePatternsMemoryText.TemporaryNow].Fmt([Trim(Text(Expression)), Target]),
      TRuleConfidence.High, Fixes);
  end;

  procedure CheckAsync(ACall: TSyntaxNode);
  var
    Index: Integer;
    Expression: TSyntaxNode;
  begin
    for Index := 1 to ACall.ChildCount - 1 do
    begin
      Expression := TemporaryPChar(ACall[Index]);
      if Expression <> nil then
      begin
        AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos),
          cTexts[TRtlTypePatternsMemoryText.TemporaryLater].Fmt([Trim(Text(Expression)),
          ACall.Name]), TRuleConfidence.High);
      end;
    end;
  end;

  procedure Visit(ANode, ARoutine, AParent: TSyntaxNode);
  var
    Pending, RoutineStack, Parents: TStack<TSyntaxNode>;
    Node, Routine, Parent: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1); parallele Stapel führen ARoutine und AParent je Knoten mit.
    Pending := TStack<TSyntaxNode>.Create;
    RoutineStack := TStack<TSyntaxNode>.Create;
    Parents := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      RoutineStack.Push(ARoutine);
      Parents.Push(AParent);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        Routine := RoutineStack.Pop;
        Parent := Parents.Pop;
        if Node.Kind = TSyntaxKind.RoutineDecl then
        begin
          Routine := Node;
        end;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) then
        begin
          CheckAssign(Node, Routine, Parent);
        end
        else if (Node.Kind = TSyntaxKind.Call) and MatchText(Node.Name, AsyncMessages) then
        begin
          CheckAsync(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
          RoutineStack.Push(Routine);
          Parents.Push(Node);
        end;
      end;
    finally
      Parents.Free;
      RoutineStack.Free;
      Pending.Free;
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root, nil, nil);
  finally
    Types.Free;
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
  Types: TDeclaredTypes;
  Local: TUnitIndex;
  LineBreak: string;

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
    Symbol: TIndexSymbol;
    Location: TSymbolLocation;
  begin
    for Symbol in Local.Symbols do
    begin
      if (Symbol.Kind = TIndexSymbolKind.Constant) and SameText(Symbol.Name, ANode.Name) then
      begin
        Exit(True);
      end;
    end;
    if Types.DeclaredType(ANode.Name, ANode.StartPos) <> '' then
    begin
      Exit(False);
    end;
    if AContext.Index <> nil then
    begin
      for Location in AContext.Index.FindSymbols(ANode.Name) do
      begin
        if Location.Symbol.Kind = TIndexSymbolKind.Constant then
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
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
  begin
    // Iterativ (Bericht M1): die Glieder der Verkettung von links nach rechts.
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if (Node.Kind = TSyntaxKind.BinaryExpr) and (Node.Name = '+') and (Node.ChildCount = 2) then
        begin
          Pending.Push(Node[1]);
          Pending.Push(Node[0]);
        end
        else
        begin
          AList := AList + [Node];
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  // 'notepad.exe ' + Datei: Ist Datei leer, liefert die Verkettung das Literal selbst zurück.
  function IsLiteralConcatenation(ANode: TSyntaxNode): Boolean;
  var
    List: TArray<TSyntaxNode>;
  begin
    List := nil;
    Operands(ANode, List);
    Result := (Length(List) = 2) and (IsReadonly(List[0]) <> IsReadonly(List[1]));
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
    Header, Params: TSyntaxNode;
    Index: Integer;
    Name: string;
  begin
    Result := nil;
    Header := ARoutine.FindChild(TSyntaxKind.RoutineHeader);
    if Header = nil then
    begin
      Exit;
    end;
    Params := Header.FindChild(TSyntaxKind.Parameters);
    if Params = nil then
    begin
      Exit;
    end;
    for Index := 0 to Params.ChildCount - 1 do
    begin
      for Name in SplitString(Params[Index].Name, ',') do
      begin
        if SameText(Trim(Name), AName) then
        begin
          Exit(Params[Index]);
        end;
      end;
    end;
  end;

  // Letzte Zuweisung an AName vor AOffset in ANode (Baumreihenfolge) und UniqueString(AName) danach.
  procedure Assignments(ANode: TSyntaxNode; const AName: string; AOffset: Integer; var ALast: TSyntaxNode;
    var AUnique: Integer);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1), Baumreihenfolge wie die frühere Rekursion (die letzte Zuweisung zählt).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.StartOffset >= AOffset then
        begin
          Continue;
        end;
        if (Node.Kind = TSyntaxKind.AssignStatement) and (Node.ChildCount = 2) and
          (Node[0].Kind = TSyntaxKind.Identifier) and SameText(Node[0].Name, AName) then
        begin
          ALast := Node;
        end;
        if (Node.Kind = TSyntaxKind.Call) and SameText(Node.Name, 'UniqueString') and (Node.ChildCount = 2) and
          (Node[1].Kind = TSyntaxKind.Identifier) and SameText(Node[1].Name, AName) then
        begin
          AUnique := Node.StartOffset;
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

  function ClassifyIdentifier(ARoutine, ANode: TSyntaxNode; AOffset: Integer): TCommandLineKind;
  var
    Last: TSyntaxNode;
    Unique: Integer;
  begin
    Result := TCommandLineKind.None;
    if not IsUnicodeString(Types.DeclaredType(ANode.Name, ANode.StartPos)) then
    begin
      Exit;
    end;
    Last := nil;
    Unique := -1;
    Assignments(ARoutine, ANode.Name, AOffset, Last, Unique);
    if Last <> nil then
    begin
      if (Unique < Last.StartOffset) and (Classify(Last[1]) <> TCommandLineKind.None) then
      begin
        Result := TCommandLineKind.Variable;
      end;
    end
    else if (Unique < 0) and (FindParameter(ARoutine, ANode.Name) <> nil) then
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
    Statement: TSyntaxNode;
    Name, Indent: string;
  begin
    Result := nil;
    Statement := StatementOf(AValue);
    if Statement = nil then
    begin
      Exit;
    end;
    if AKind = TCommandLineKind.Variable then
    begin
      Result := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.CallUniqueString].Fmt([AValue.Name]),
        [TRoutineBody.InsertBefore(AContext.Text, Statement, 'UniqueString(' + AValue.Name + ');')])];
      Exit;
    end;
    Name := TRoutineBody.UniqueName(AContext.Tree.Tokens, AContext.NewNames.Local('Befehl'));
    Indent := TTextLines.IndentOf(AContext.Text, Statement.StartPos.Line);
    Result := [TRuleFix.Create(cTexts[TRtlTypePatternsMemoryText.CopyCommandLine].Text,
      [TRoutineBody.AddVariable(AContext.Text, ARoutine, Name, 'string', AContext.Formatting),
      TRoutineBody.InsertBefore(AContext.Text, Statement, Name + ' := ' + Text(AValue) + ';' + LineBreak + Indent +
      'UniqueString(' + Name + ');'),
      TTextEdit.Create(TTextRange.Create(AValue.StartPos, AValue.EndPos), Name)])];
  end;

  procedure CheckCall(ACall: TSyntaxNode);
  var
    Index: Integer;
    Argument, Value, Routine: TSyntaxNode;
    Kind: TCommandLineKind;
    Message: string;
    Confidence: TRuleConfidence;
  begin
    Index := CommandLineIndex(ACall.Name);
    if (Index < 0) or (ACall.ChildCount <= Index + 1) then
    begin
      Exit;
    end;
    Argument := ACall[Index + 1];
    if (Argument.Kind <> TSyntaxKind.Call) or not MatchText(Argument.Name, ['PChar', 'PWideChar']) or
      (Argument.ChildCount <> 2) then
    begin
      Exit;
    end;
    Value := Argument[1];
    Routine := TRoutineBody.RoutineAt(AContext.Tree, ACall.StartOffset);
    Kind := Classify(Value);
    if (Kind = TCommandLineKind.None) and (Value.Kind = TSyntaxKind.Identifier) and (Routine <> nil) then
    begin
      Kind := ClassifyIdentifier(Routine, Value, ACall.StartOffset);
    end;
    Confidence := TRuleConfidence.High;
    case Kind of
      TCommandLineKind.Constant:
        Message := cTexts[TRtlTypePatternsMemoryText.ConstantCommandLine].Fmt([ACall.Name]);
      TCommandLineKind.Concatenation:
        Message := cTexts[TRtlTypePatternsMemoryText.ConcatCommandLine].Fmt([ACall.Name]);
      TCommandLineKind.Variable:
        Message := cTexts[TRtlTypePatternsMemoryText.MayBeConstant].Fmt([ACall.Name, Value.Name]);
      TCommandLineKind.Parameter:
        begin
          Message := cTexts[TRtlTypePatternsMemoryText.ParamConstant].Fmt([ACall.Name, Value.Name]);
          Confidence := TRuleConfidence.Medium;
        end;
    else
      Exit;
    end;
    if Routine = nil then
    begin
      AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos), Message, Confidence);
    end
    else
    begin
      AReport.Add(TTextRange.Create(Value.StartPos, Value.EndPos), Message, Confidence,
        Fixes(Routine, Value, Kind));
    end;
  end;

  procedure Visit(ANode: TSyntaxNode);
  var
    Pending: TStack<TSyntaxNode>;
    Node: TSyntaxNode;
    Index: Integer;
  begin
    // Iterativ (Bericht M1).
    Pending := TStack<TSyntaxNode>.Create;
    try
      Pending.Push(ANode);
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        if Node.Kind = TSyntaxKind.Call then
        begin
          CheckCall(Node);
        end;
        for Index := Node.ChildCount - 1 downto 0 do
        begin
          Pending.Push(Node[Index]);
        end;
      end;
    finally
      Pending.Free;
    end;
  end;

var
  Cache: IRuleDerivedCache;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or not ContainsText(AContext.Text, 'CreateProcess') then
  begin
    Exit;
  end;
  LineBreak := TTextLines.LineBreakOf(AContext.Text);
  Cache := TRuleDerived.Open(AContext);
  Local := TRuleDerived.UnitIndex(Cache, AContext);
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  try
    Visit(AContext.Tree.Root);
  finally
    Types.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.RtlTypePatterns.Memory', cTexts);

end.
