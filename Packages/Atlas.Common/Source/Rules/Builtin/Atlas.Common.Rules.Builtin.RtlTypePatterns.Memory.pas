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
  Atlas.Common.Rules.Builtin.RtlTypePatterns.Tokens;

{ TManagedTypeRawMemoryRule }

function TManagedTypeRawMemoryRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('managed-type-raw-memory', TRuleSeverity.Error,
    'FillChar, Move oder GetMem auf verwaltete Typen');
end;

procedure TManagedTypeRawMemoryRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  Tokens: TTokens;
  Types: TDeclaredTypes;
  Managed: TManagedTypes;
  Index, Call, Open, Close: Integer;
  Starts, Stops: TArray<Integer>;
  Routine: string;

  // Argumente auf oberster Ebene: Start- und Endtoken.
  procedure SplitArguments;
  var
    Inner, Depth, First: Integer;
  begin
    Starts := nil;
    Stops := nil;
    Depth := 0;
    First := NextCode(Tokens, Open + 1);
    for Inner := Open + 1 to Close do
    begin
      if (Inner = Close) or ((Depth = 0) and Tokens[Inner].IsSymbol(',')) then
      begin
        if First < Inner then
        begin
          Starts := Starts + [First];
          Stops := Stops + [PreviousCode(Tokens, Inner)];
        end;
        First := NextCode(Tokens, Inner + 1);
      end
      else if Tokens[Inner].IsSymbol('(') or Tokens[Inner].IsSymbol('[') then
      begin
        Inc(Depth);
      end
      else if Tokens[Inner].IsSymbol(')') or Tokens[Inner].IsSymbol(']') then
      begin
        Dec(Depth);
      end;
    end;
  end;

  // Argument AIndex als X, @X oder X^: Name (Tokenindex) und ob dereferenziert; -1 sonst.
  function Target(AArgument: Integer; out ADeref: Boolean): Integer;
  var
    First, Last: Integer;
  begin
    Result := -1;
    ADeref := False;
    if AArgument > High(Starts) then
    begin
      Exit;
    end;
    First := Starts[AArgument];
    Last := Stops[AArgument];
    if Tokens[First].IsSymbol('@') then
    begin
      First := NextCode(Tokens, First + 1);
    end;
    if (Last > First) and Tokens[Last].IsSymbol('^') and (NextCode(Tokens, First + 1) = Last) then
    begin
      ADeref := True;
      Last := First;
    end;
    if (First = Last) and (Tokens[First].Kind = TPascalTokenKind.Identifier) then
    begin
      Result := First;
    end;
  end;

  // Typ der Daten hinter dem Argument; bei AAsPointer (GetMem, FreeMem, X^) der Zieltyp des Zeigers.
  function DataType(AName: Integer; AAsPointer: Boolean): string;
  begin
    Result := Types.DeclaredType(Tokens[AName].Text, Tokens[AName].StartPos);
    if AAsPointer then
    begin
      Result := Managed.Pointee(Result);
    end;
  end;

  function Subject(const ATypeName, AKind: string): string;
  begin
    if Managed.IsPrimitive(ATypeName) then
    begin
      Result := Format('%s ist ein verwalteter Typ', [ATypeName]);
    end
    else
    begin
      Result := Format('%s enthält %s', [ATypeName, AKind]);
    end;
  end;

  // Anweisung: davor ;, begin, then, else, do, try, finally, except oder repeat; danach ;, end oder else.
  function IsStatement: Boolean;
  var
    Before, After: Integer;
  begin
    Before := PreviousCode(Tokens, Call);
    After := NextCode(Tokens, Close + 1);
    Result := (Before >= 0) and (Tokens[Before].IsSymbol(';') or Tokens[Before].IsKeyword('begin') or
      Tokens[Before].IsKeyword('then') or Tokens[Before].IsKeyword('else') or Tokens[Before].IsKeyword('do') or
      Tokens[Before].IsKeyword('try') or Tokens[Before].IsKeyword('finally') or Tokens[Before].IsKeyword('except') or
      Tokens[Before].IsKeyword('repeat')) and (After <= High(Tokens)) and (Tokens[After].IsSymbol(';') or
      Tokens[After].IsKeyword('end') or Tokens[After].IsKeyword('else'));
  end;

  // Argument ist SizeOf(X) oder SizeOf(T) mit X bzw. T wie angegeben.
  function IsSizeOf(AArgument: Integer; const AName, ATypeName: string): Boolean;
  var
    First, Inner, Last: Integer;
  begin
    Result := False;
    if AArgument > High(Starts) then
    begin
      Exit;
    end;
    First := Starts[AArgument];
    Inner := NextCode(Tokens, NextCode(Tokens, First + 1) + 1);
    Last := Stops[AArgument];
    Result := SameText(Tokens[First].Text, 'SizeOf') and (NextCode(Tokens, Inner + 1) = Last) and
      Tokens[Last].IsSymbol(')') and (SameText(Tokens[Inner].Text, AName) or SameText(Tokens[Inner].Text, ATypeName));
  end;

  function IsZero(AArgument: Integer): Boolean;
  begin
    Result := (AArgument <= High(Starts)) and (Starts[AArgument] = Stops[AArgument]) and
      MatchText(Tokens[Starts[AArgument]].Text, ['0', '#0', '$0', '$00']);
  end;

  procedure Report(const ATypeName, AKind, AText: string; const AFixes: TArray<TRuleFix>);
  begin
    AReport.Add(RangeOf(Tokens, Call, Close), Format('%s; %s %s', [Subject(ATypeName, AKind), Routine, AText]),
      TRuleConfidence.High, AFixes);
  end;

  procedure CheckOverwrite;
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
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    // FillChar(X, SizeOf(X), 0) bzw. ZeroMemory(@X, SizeOf(X)): X := Default(T).
    if IsStatement and not Deref and IsSizeOf(1, Tokens[Name].Text, TypeName) and
      (SameText(Routine, 'ZeroMemory') or IsZero(2)) then
    begin
      Fixes := [TRuleFix.Create(Format('%s := Default(%s)', [Tokens[Name].Text, TypeName]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := Default(%s)', [Tokens[Name].Text,
        TypeName]))], True)];
    end;
    Report(TypeName, Kind, 'überschreibt die Referenzen ohne Freigabe (Leck, ggf. Zugriffsverletzung).',
      Fixes);
  end;

  procedure CheckCopy(ASource, ADestination: Integer);
  var
    Source, Destination: Integer;
    SourceDeref, DestinationDeref: Boolean;
    SourceType, DestinationType, Kind, TypeName: string;
    Fixes: TArray<TRuleFix>;
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
    Kind := Managed.Managed(DestinationType, 0);
    if Kind = '' then
    begin
      TypeName := SourceType;
      Kind := Managed.Managed(SourceType, 0);
    end;
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    // Move(A, B, SizeOf(T)) mit gleichem Typ: B := A.
    if IsStatement and (Source >= 0) and (Destination >= 0) and not SourceDeref and not DestinationDeref and
      SameText(SourceType, DestinationType) and IsSizeOf(2, Tokens[Source].Text, SourceType) then
    begin
      Fixes := [TRuleFix.Create(Format('%s := %s', [Tokens[Destination].Text, Tokens[Source].Text]),
        [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Format('%s := %s', [Tokens[Destination].Text,
        Tokens[Source].Text]))], True)];
    end;
    Report(TypeName, Kind, 'kopiert die Referenzen ohne Referenzzählung (doppelte Freigabe, ' +
      'ggf. Zugriffsverletzung).', Fixes);
  end;

  procedure CheckMemory(AAllocate: Boolean);
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
    Kind := Managed.Managed(TypeName, 0);
    if Kind = '' then
    begin
      Exit;
    end;
    Fixes := nil;
    if AAllocate then
    begin
      Replacement := Format('New(%s)', [Tokens[Name].Text]);
    end
    else
    begin
      Replacement := Format('Dispose(%s)', [Tokens[Name].Text]);
    end;
    // GetMem(P, SizeOf(T)) bzw. FreeMem(P) oder FreeMem(P, SizeOf(T)): New bzw. Dispose.
    if IsStatement and ((Length(Starts) = 1) and not AAllocate or IsSizeOf(1, '', TypeName)) then
    begin
      Fixes := [TRuleFix.Create(Replacement, [TRuleEdit.Create(RangeOf(Tokens, Call, Close), Replacement)], True)];
    end;
    if AAllocate then
    begin
      Report(TypeName, Kind, 'lässt die Referenzen uninitialisiert (Zugriffsverletzung beim ersten ' +
        'Zuweisen); New oder Initialize verwenden.', Fixes);
    end
    else
    begin
      Report(TypeName, Kind, 'gibt die Referenzen nicht frei (Leck); Dispose oder Finalize verwenden.', Fixes);
    end;
  end;

begin
  if AContext.Tree = nil then
  begin
    Exit;
  end;
  Tokens := AContext.Tree.Tokens;
  Types := TDeclaredTypes.Create(AContext.Tree, AContext.Text);
  Managed := TManagedTypes.Create(AContext.Tree, AContext.Text, AContext.Index);
  try
    for Index := 0 to High(Tokens) do
    begin
      if (Tokens[Index].Kind <> TPascalTokenKind.Identifier) or not MatchText(Tokens[Index].Text, ['FillChar',
        'ZeroMemory', 'FillMemory', 'Move', 'CopyMemory', 'GetMem', 'FreeMem']) then
      begin
        Continue;
      end;
      // Methoden anderer Objekte (Stream.Move) sind nicht gemeint.
      if (PreviousCode(Tokens, Index) >= 0) and Tokens[PreviousCode(Tokens, Index)].IsSymbol('.') then
      begin
        Continue;
      end;
      Open := NextCode(Tokens, Index + 1);
      if (Open > High(Tokens)) or not Tokens[Open].IsSymbol('(') then
      begin
        Continue;
      end;
      Close := Closing(Tokens, Open);
      if Close < 0 then
      begin
        Continue;
      end;
      Call := Index;
      SplitArguments;
      Routine := Tokens[Index].Text;
      if MatchText(Routine, ['FillChar', 'ZeroMemory', 'FillMemory']) then
      begin
        CheckOverwrite;
      end
      else if SameText(Routine, 'Move') then
      begin
        CheckCopy(0, 1);
      end
      else if SameText(Routine, 'CopyMemory') then
      begin
        CheckCopy(1, 0);
      end
      else
      begin
        CheckMemory(SameText(Routine, 'GetMem'));
      end;
    end;
  finally
    Managed.Free;
    Types.Free;
  end;
end;

{ TThreadvarManagedRule }

function TThreadvarManagedRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create('threadvar-managed', TRuleSeverity.Warning, 'threadvar mit verwaltetem Typ');
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
      Shown := Format('%s (enthält %s)', [TypeName, Kind]);
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
          AReport.Add(RangeOf(Tokens, Index, Index), Format('threadvar mit %s wird beim Thread-Ende nicht ' +
            'finalisiert (Leck je Thread).', [Shown]), TRuleConfidence.High);
          Break;
        end;
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
          for Index := 0 to Node.ChildCount - 1 do
          begin
            if Node[Index].Kind = TSyntaxKind.VarDecl then
            begin
              CheckDecl(Node[Index]);
            end;
          end;
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
    'PChar auf einen temporären String');
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
      while Pending.Count > 0 do
      begin
        Node := Pending.Pop;
        case Node.Kind of
          TSyntaxKind.Literal:
            if (Node.Name <> '') and CharInSet(Node.Name[1], ['''', '#']) then
            begin
              Exit(True);
            end;
          TSyntaxKind.Identifier:
            if MatchText(Types.DeclaredType(Node.Name, Node.StartPos), StringCasts) then
            begin
              Exit(True);
            end;
          TSyntaxKind.Call:
            if not MatchText(Node.Name, PCharCasts) and not MatchText(Node.Name, PassThroughCasts) then
            begin
              Exit(True);
            end;
          TSyntaxKind.ParenExpr:
            if Node.ChildCount = 1 then
            begin
              Pending.Push(Node[0]);
            end;
          TSyntaxKind.BinaryExpr:
            if (Node.Name = '+') and (Node.ChildCount = 2) then
            begin
              Pending.Push(Node[1]);
              Pending.Push(Node[0]);
            end;
        else
          // Übrige Werte bewusst ohne Wirkung.
        end;
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

  function IsLocal(ARoutine: TSyntaxNode; const AName: string): Boolean;
  var
    Index, Inner: Integer;
    Section: TSyntaxNode;
    Name: string;
  begin
    Result := False;
    if ARoutine = nil then
    begin
      Exit;
    end;
    for Index := 0 to ARoutine.ChildCount - 1 do
    begin
      Section := ARoutine[Index];
      if (Section.Kind <> TSyntaxKind.VarSection) or not SameText(Section.Name, 'var') then
      begin
        Continue;
      end;
      for Inner := 0 to Section.ChildCount - 1 do
      begin
        if Section[Inner].Kind = TSyntaxKind.VarDecl then
        begin
          for Name in SplitString(Section[Inner].Name, ',') do
          begin
            if SameText(Trim(Name), AName) then
            begin
              Exit(True);
            end;
          end;
        end;
      end;
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
      IsLocal(ARoutine, Target) then
    begin
      Name := FreshName(ARoutine, Target);
      Indent := StringOfChar(' ', AStatement.StartPos.Character);
      Fixes := [TRuleFix.Create(Format('Zwischenergebnis in %s ablegen', [Name]),
        [TRuleEdit.Create(TTextRange.Create(AStatement.StartPos, AStatement.StartPos),
        Format('var %s: string := %s;', [Name, Trim(Text(Expression))]) + LineBreak + Indent),
        TRuleEdit.Create(TTextRange.Create(Expression.StartPos, Expression.EndPos), Name)])];
    end;
    AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist temporär; ' +
      '%s zeigt nach dieser Zeile auf freigegebenen Speicher.', [Trim(Text(Expression)), Target]),
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
        AReport.Add(TTextRange.Create(Expression.StartPos, Expression.EndPos), Format('Der Ausdruck %s ist ' +
          'temporär; %s liest den Zeiger erst später aus freigegebenem Speicher.', [Trim(Text(Expression)),
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
    'CreateProcess mit unveränderlicher Befehlszeile');
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
      Result := [TRuleFix.Create('UniqueString(' + AValue.Name + ') davor aufrufen',
        [TRoutineBody.InsertBefore(AContext.Text, Statement, 'UniqueString(' + AValue.Name + ');')])];
      Exit;
    end;
    Name := TRoutineBody.UniqueName(AContext.Tree.Tokens, AContext.NewNames.Local('Befehl'));
    Indent := TTextLines.IndentOf(AContext.Text, Statement.StartPos.Line);
    Result := [TRuleFix.Create('Befehlszeile in eine lokale Variable kopieren und UniqueString aufrufen',
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
        Message := ACall.Name + ' schreibt in die Befehlszeile; ein konstanter String ist nicht beschreibbar.';
      TCommandLineKind.Concatenation:
        Message := ACall.Name + ' schreibt in die Befehlszeile; ist der andere Teil leer, liefert die Verkettung ' +
          'das konstante Literal, das nicht beschreibbar ist.';
      TCommandLineKind.Variable:
        Message := Format('%s schreibt in die Befehlszeile; %s kann auf einen konstanten String verweisen und ist ohne ' +
          'UniqueString nicht beschreibbar.', [ACall.Name, Value.Name]);
      TCommandLineKind.Parameter:
        begin
          Message := Format('%s schreibt in die Befehlszeile; der Parameter %s kann ein konstanter String sein und ' +
            'ist ohne UniqueString nicht beschreibbar.', [ACall.Name, Value.Name]);
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

end.
