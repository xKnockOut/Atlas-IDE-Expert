unit Atlas.Common.Editing.NestedRoutines;

// Lokale Routine und Methode ineinander umwandeln (#663):
//   In private Methode umwandeln (auf dem Kopf einer lokalen Routine in einer
//     Methode): Der Rumpf wandert hinter die äußere Methode als TKlasse.Name,
//     die Deklaration in den private-Abschnitt der Klasse (legt ihn an, wenn
//     er fehlt). Variablen, Konstanten und Parameter der äußeren Routine, die
//     die lokale nutzt, werden Parameter: var, wenn sie geschrieben werden
//     (auch als var-Argument), const bei reinem Lesen von Strings, Records
//     und Interfaces, sonst ohne Modifizierer. Untypisierte Konstanten
//     wandern als Konstanten mit. Die Aufrufe bekommen die neuen Argumente,
//     ein vergebener Name bekommt eine Nummer.
//   Aus Routine herauslösen: dasselbe für eine lokale Routine einer freien
//     Routine; sie steht danach vor ihr in der Unit.
//   Als lokale Routine einbetten (auf einer privaten Methode mit genau einem
//     Aufruf, und zwar im Rumpf einer anderen Methode derselben Klasse; nicht
//     virtual, dynamic, override, abstract, message, overload, nicht als
//     Ereignis oder Methodenzeiger benutzt): Der Rumpf wird lokale Routine des
//     Aufrufers, die Deklaration verschwindet aus der Klasse.
//   In lokale Routine umwandeln: dasselbe für eine freie Routine der
//     Implementierung, die nicht im interface steht.
//   Mit „durchgereichte Parameter entfernen“ fallen Parameter weg, denen der
//     Aufruf nur eine Variable oder einen Parameter des Aufrufers übergibt;
//     der Rumpf nutzt dann diese direkt.
// Nicht angeboten wird, wenn sich die Bedeutung eines Namens ändern könnte:
// die lokale Routine nutzt Result, eine andere lokale Routine oder einen
// lokalen Typ der äußeren, enthält with, fängt einen künftigen var-Parameter
// in einer anonymen Methode ein oder wird anders als aufgerufen benutzt; beim
// Einbetten verdeckt ein Name des Aufrufers einen Namen des Rumpfs. Liegt die
// lokale Routine in einer anderen lokalen Routine, gibt es statt der Aktion
// einen Hinweis. Jede Aktion ist ein Rückgängig-Schritt und trägt eine
// Vorschau mit der neuen Signatur und der Zahl der geänderten Aufrufe.

interface

uses
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Semantics.ControlFlow,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Editing.CodeActions;

type
  /// <summary>Ist der Typ ATypeName an AOffset ein Record oder Interface (dann const beim reinen Lesen)?</summary>
  TConstTypeFunc = reference to function(const ATypeName: string; AOffset: Integer): Boolean;

  TNestedRoutineLookup = record
    ConstType: TConstTypeFunc;
    /// <summary>Art der Argumente bekannter Aufrufe (var-Argumente schreiben).</summary>
    Flow: TFlowSignatureLookup;
    /// <summary>Ohne Namensauflösung: Aufrufe aus der Datei, Records und Interfaces unbekannt.</summary>
    class function FromTree(ATree: TSyntaxTree): TNestedRoutineLookup; static;
    /// <summary>Typen über AResolver für ATree der Datei AFileName (Baum festhalten, solange gebraucht).</summary>
    class function FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
      const AFileName: string): TNestedRoutineLookup; static;
  end;

  TNestedRoutines = class
  public const
    ToMethodTitle = 'In private Methode umwandeln';
    ToUnitRoutineTitle = 'Aus Routine herauslösen';
    EmbedMethodTitle = 'Als lokale Routine einbetten';
    EmbedRoutineTitle = 'In lokale Routine umwandeln';
    PassThroughSuffix = ' (durchgereichte Parameter entfernen)';
  public
    /// <summary>„In private Methode umwandeln“ bzw. „Aus Routine herauslösen“ für die lokale Routine, deren Kopf
    /// APosition enthält. Liegt sie in einer anderen lokalen Routine, ist AAction.Disabled der Hinweis.</summary>
    class function Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
      overload; static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
      out AReason: string): Boolean; overload; static;
    /// <summary>„Als lokale Routine einbetten“ bzw. „In lokale Routine umwandeln“ für die Routine, deren Kopf
    /// (Implementierung oder Klassendeklaration) APosition enthält; mit ARemovePassThrough ohne die
    /// durchgereichten Parameter (False, wenn es keine gibt).</summary>
    class function Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
      out AAction: TCodeAction): Boolean; overload; static;
    /// <summary>Wie oben; AReason nennt, warum es nicht geht.</summary>
    class function Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
      out AAction: TCodeAction; out AReason: string): Boolean; overload; static;
    /// <summary>Alle passenden Aktionen an APosition.</summary>
    class function Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
      const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Math,
  System.Generics.Collections,
  Atlas.Text.Lines,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Index.Contract,
  Atlas.Common.Editing.RoutineBody,
  Atlas.Common.Editing.RoutineLocals,
  Atlas.Common.Editing.RoutineParts,
  Atlas.Common.Editing.CreateMethod;

type
  /// <summary>Name der äußeren Routine, den die lokale nutzt.</summary>
  TCaptured = record
    Local: TRoutineLocal;
    Written: Boolean;
    /// <summary>In einer anonymen Methode benutzt (darf kein var-Parameter werden).</summary>
    InAnonymous: Boolean;
  end;

{ Hilfen }

function Fail(const AReason: string; out AOut: string): Boolean;
begin
  AOut := AReason;
  Result := False;
end;

{ TNestedRoutineLookup }

class function TNestedRoutineLookup.FromTree(ATree: TSyntaxTree): TNestedRoutineLookup;
begin
  Result.ConstType := nil;
  Result.Flow := nil;
  if (ATree <> nil) and (ATree.Root <> nil) then
    Result.Flow := TFlowSignatures.FromTree(ATree.Root);
end;

class function TNestedRoutineLookup.FromResolver(AResolver: TNameResolver; ATree: TSyntaxTree;
  const AFileName: string): TNestedRoutineLookup;
var
  FileName: string;
begin
  Result := FromTree(ATree);
  FileName := AFileName;
  Result.ConstType :=
    function(const ATypeName: string; AOffset: Integer): Boolean
    var
      Resolved: TResolvedSymbol;
      Base: string;
    begin
      Base := ATypeName;
      if Pos('<', Base) > 0 then
        Base := Copy(Base, 1, Pos('<', Base) - 1);
      Resolved := AResolver.ResolveChain(ATree, FileName, Trim(Base).Split(['.']), AOffset);
      Result := Resolved.Found and Resolved.IsType and (Resolved.SymbolKind in [TIndexSymbolKind.RecordType,
        TIndexSymbolKind.ObjectType, TIndexSymbolKind.InterfaceType]);
    end;
end;

{ Umwandlung: lokale Routine heraus }

/// <summary>Modifizierer des neuen Parameters für den Namen ACaptured.</summary>
function ModeOf(const ACaptured: TCaptured; const ALookup: TNestedRoutineLookup; AOffset: Integer): string;
begin
  Result := '';
  if ACaptured.Written then
    Result := 'var'
  else if TCreateMethod.WantsConst(ACaptured.Local.TypeText, False, False) or
    (Assigned(ALookup.ConstType) and ALookup.ConstType(ACaptured.Local.TypeText, AOffset)) then
    Result := 'const';
end;

/// <summary>Bearbeitung, die AArguments an den Aufruf des Bezeichners ANode anhängt bzw. ihn in ANewName
/// umbenennt; False, wenn die Routine dort nicht aufgerufen, sondern anders benutzt wird.</summary>
function CallEdit(const ATokens: TArray<TPascalToken>; ANode: TSyntaxNode; AIsFunction: Boolean;
  const ANewName, AArguments: string; var AEdits: TArray<TOffsetEdit>): Boolean;
var
  Parent: TSyntaxNode;
  Close: Integer;
begin
  Result := True;
  Parent := ANode.Parent;
  if (Parent <> nil) and (Parent.Kind = TSyntaxKind.Call) and (Parent[0] = ANode) then
  begin
    if not SameText(ANode.Name, ANewName) then
      AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
    if AArguments = '' then
      Exit;
    if Parent.ChildCount > 1 then
      AEdits := AEdits + [TOffsetEdit.Create(Parent[Parent.ChildCount - 1].EndOffset,
        Parent[Parent.ChildCount - 1].EndOffset, ', ' + AArguments)]
    else
    begin
      Close := TRoutineBody.PreviousToken(ATokens, TRoutineBody.TokenAt(ATokens, Parent.EndOffset));
      if (Close < 0) or not ATokens[Close].IsSymbol(')') then
        Exit(False);
      AEdits := AEdits + [TOffsetEdit.Create(ATokens[Close].Offset, ATokens[Close].Offset, AArguments)];
    end;
    Exit;
  end;
  // Ohne Klammern: als Anweisung, bei Funktionen auch in Ausdrücken; nicht als Wert (@X, Argument, Zuweisung).
  if (Parent = nil) or (Parent.Kind in [TSyntaxKind.AddressOf, TSyntaxKind.Call, TSyntaxKind.MemberAccess]) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and (Parent[0] = ANode)) or
    ((Parent.Kind <> TSyntaxKind.CallStatement) and not AIsFunction) or
    ((Parent.Kind = TSyntaxKind.AssignStatement) and not AIsFunction) then
    Exit(False);
  if AArguments = '' then
  begin
    if not SameText(ANode.Name, ANewName) then
      AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName)];
    Exit;
  end;
  AEdits := AEdits + [TOffsetEdit.Create(ANode.StartOffset, ANode.EndOffset, ANewName + '(' + AArguments + ')')];
end;

/// <summary>Kommt ein Bezeichner AName unter AIdentifiers vor?</summary>
function UsesName(const AIdentifiers: TArray<TSyntaxNode>; const AName: string): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
    if SameText(Node.Name, AName) then
      Exit(True);
  Result := False;
end;

/// <summary>Schreibt der Rumpf von ARoutine den eigenen Namen AName (Zuweisung, var-Argument, @)?</summary>
function WritesName(ACache: TLocalsCache; const AIdentifiers: TArray<TSyntaxNode>; ARoutine: TSyntaxNode;
  const AName: string; const AFlow: TFlowSignatureLookup): Boolean;
var
  Node: TSyntaxNode;
begin
  for Node in AIdentifiers do
    if SameText(Node.Name, AName) and not TRoutineParts.Shadowed(ACache, Node, ARoutine, AName, False) and
      (TRoutineLocals.AccessOf(Node, AFlow) <> TLocalAccess.Read) then
      Exit(True);
  Result := False;
end;

function ExtractCore(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
var
  Lines: TLineTable;
  TextLines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Inner, Outer, Header, OuterHeader, Node, TypeBody, Child: TSyntaxNode;
  Cache: TLocalsCache;
  OuterLocals: TArray<TRoutineLocal>;
  Local: TRoutineLocal;
  Captured: TArray<TCaptured>;
  Identifiers: TList<TSyntaxNode>;
  Index, Found, Calls, FirstLine, LastLine, RemoveStart, RemoveEnd, InsertLine, NameFirst, NameLast: Integer;
  ClassName, NewName, Name, Arguments, LineBreak, Indent, InnerIndent, Moved, Declaration, ConstLines,
    Mode: string;
  Parameters: TArray<TParameterText>;
  Parameter: TParameterText;
  InnerEdits, OuterEdits: TArray<TOffsetEdit>;
  Edits: TArray<TTextEdit>;
  Edit: TTextEdit;
  Taken: TArray<string>;
  IsMethod, IsClass, InnerIsFunction: Boolean;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(AText);
  Inner := TRoutineParts.RoutineWithHeaderAt(ATree, Lines.OffsetAt(APosition));
  if (Inner = nil) or (Inner.Parent = nil) or (Inner.Parent.Kind <> TSyntaxKind.RoutineDecl) then
    Exit(Fail('keine lokale Routine', AReason));
  Outer := Inner.Parent;
  ClassName := TRoutineBody.QualifierOf(Outer.Name);
  IsMethod := ClassName <> '';
  if IsMethod then
    AAction.Title := TNestedRoutines.ToMethodTitle
  else
    AAction.Title := TNestedRoutines.ToUnitRoutineTitle;
  AAction.Kind := RewriteKind;
  if (Outer.Parent <> nil) and (Outer.Parent.Kind = TSyntaxKind.RoutineDecl) then
  begin
    // Hinweis statt Aktion: Die mittlere Routine müsste erst selbst heraus.
    AAction.Disabled := Format('%s liegt in der lokalen Routine %s; erst diese umwandeln', [Inner.Name, Outer.Name]);
    Exit(True);
  end;
  Tokens := ATree.Tokens;
  Header := TRoutineParts.HeaderOf(Inner);
  OuterHeader := TRoutineParts.HeaderOf(Outer);
  if (Header = nil) or (OuterHeader = nil) or (TRoutineBody.BodyOf(Inner) = nil) then
    Exit(Fail('Routine ohne Rumpf', AReason));
  if TRoutineParts.HasWord(Tokens, Header, ['forward', 'external', 'overload', 'assembler']) or
    TRoutineLocals.HasKind(Inner, TSyntaxKind.WithStatement) or (Pos('<', ClassName) > 0) then
    Exit(Fail('nicht unterstützte Form', AReason));
  IsClass := TRoutineParts.IsClassHeader(Tokens, OuterHeader);
  InnerIsFunction := TRoutineParts.IsFunction(Inner);
  TypeBody := nil;
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(ATree.Root, TRoutineBody.ShortNameOf(ClassName));
    if TypeBody = nil then
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
  end;
  Cache := TLocalsCache.Create(AText, ATree);
  Identifiers := TList<TSyntaxNode>.Create;
  try
    OuterLocals := Cache.Locals(Outer);
    Captured := nil;
    InnerEdits := nil;
    OuterEdits := nil;
    // Namen der lokalen Routine, die die äußere deklariert.
    TRoutineLocals.CollectKind(Inner, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      if TRoutineParts.Shadowed(Cache, Node, Inner, Node.Name, True) then
        Continue;
      if SameText(Node.Name, Inner.Name) then
        Continue;
      if SameText(Node.Name, 'Result') and TRoutineParts.IsFunction(Outer) then
        Exit(Fail('Result der äußeren Routine', AReason));
      if not IsMethod and SameText(Node.Name, Outer.Name) then
        Exit(Fail('ruft die äußere Routine auf', AReason));
      Found := -1;
      for Index := 0 to High(OuterLocals) do
        if SameText(OuterLocals[Index].Name, Node.Name) and ((OuterLocals[Index].Kind =
          TRoutineLocalKind.Parameter) or ((OuterLocals[Index].Kind in [TRoutineLocalKind.Variable,
          TRoutineLocalKind.Constant]) and (OuterLocals[Index].Decl.StartOffset < Inner.StartOffset))) then
          Found := Index;
      if Found < 0 then
      begin
        for Index := 0 to Outer.ChildCount - 1 do
        begin
          Child := Outer[Index];
          if (Child <> Inner) and (Child.Kind = TSyntaxKind.RoutineDecl) and SameText(Child.Name, Node.Name) and
            (Child.StartOffset < Inner.StartOffset) then
            Exit(Fail('nutzt die lokale Routine ' + Child.Name, AReason));
          if (Child.Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name, TRoutineParts.ChildNames(Child)) >= 0) and
            (Child.StartOffset < Inner.StartOffset) then
            Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
        end;
        Continue;
      end;
      Index := 0;
      while (Index <= High(Captured)) and not SameText(Captured[Index].Local.Name, OuterLocals[Found].Name) do
        Inc(Index);
      if Index > High(Captured) then
      begin
        SetLength(Captured, Length(Captured) + 1);
        Captured[Index].Local := OuterLocals[Found];
        Captured[Index].Written := False;
        Captured[Index].InAnonymous := False;
      end;
      if TRoutineLocals.AccessOf(Node, ALookup.Flow) <> TLocalAccess.Read then
        Captured[Index].Written := True;
      if TRoutineParts.InAnonymous(Node, Inner) then
        Captured[Index].InAnonymous := True;
    end;
    // Lokale Typen der äußeren Routine auch in Typangaben.
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Inner, TSyntaxKind.TypeReference, Identifiers);
    for Node in Identifiers do
      for Index := 0 to Outer.ChildCount - 1 do
        if (Outer[Index].Kind = TSyntaxKind.TypeSection) and (IndexText(Node.Name, TRoutineParts.ChildNames(Outer[Index])) >= 0) and
          not TRoutineParts.Shadowed(Cache, Node, Inner, Node.Name, True) then
          Exit(Fail('nutzt den lokalen Typ ' + Node.Name, AReason));
    // Neue Parameter; untypisierte Konstanten wandern als Konstanten mit.
    Parameters := TRoutineParts.ParameterTexts(AText, Header);
    if (Parameters = nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) and
      (Header.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
      Exit(Fail('nicht unterstützte Parameter', AReason));
    Arguments := '';
    ConstLines := '';
    LineBreak := TTextLines.LineBreakOf(AText);
    InnerIndent := TTextLines.IndentOf(AText, Inner.StartPos.Line);
    for Index := 0 to High(Captured) do
    begin
      Local := Captured[Index].Local;
      if Local.Kind = TRoutineLocalKind.Constant then
      begin
        if Captured[Index].Written then
          Exit(Fail('schreibt die Konstante ' + Local.Name, AReason));
        if ConstLines = '' then
          ConstLines := LineBreak + InnerIndent + 'const';
        ConstLines := ConstLines + LineBreak + InnerIndent + TRoutineBody.IndentUnit(AStyle) +
          TRoutineBody.TextOf(AText, Local.Decl);
        Continue;
      end;
      if Local.TypeText = '' then
        Exit(Fail(Local.Name + ' hat keinen Typ', AReason));
      Mode := ModeOf(Captured[Index], ALookup, Inner.StartOffset);
      if (Mode = 'var') and Captured[Index].InAnonymous then
        Exit(Fail('eine anonyme Methode fängt ' + Local.Name + ' ein', AReason));
      Parameter.Modifier := Mode;
      Parameter.Name := Local.Name;
      Parameter.Rest := ': ' + Local.TypeText;
      Parameters := Parameters + [Parameter];
      if Arguments <> '' then
        Arguments := Arguments + ', ';
      Arguments := Arguments + Local.Name;
    end;
    // Freier Name.
    if IsMethod then
      Taken := TRoutineBody.MemberNames(TypeBody)
    else
      Taken := TRoutineParts.UnitNames(ATree.Root);
    NewName := TRoutineParts.FreeName(Inner.Name, Taken);
    // Aufrufe in der äußeren Routine (auch in den anderen lokalen Routinen) und in der lokalen selbst.
    Calls := 0;
    Identifiers.Clear;
    TRoutineLocals.CollectKind(Outer, TSyntaxKind.Identifier, Identifiers);
    for Node in Identifiers do
    begin
      if not SameText(Node.Name, Inner.Name) then
        Continue;
      if TRoutineBody.Within(Node, Inner) then
      begin
        // Rekursion: Ein innerer Name verdeckt die Routine oder ein neues Argument.
        if TRoutineParts.Shadowed(Cache, Node, Inner, Node.Name, True) then
          Continue;
        for Index := 0 to High(Captured) do
          if TRoutineParts.Shadowed(Cache, Node, Inner, Captured[Index].Local.Name, False) then
            Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
        if not CallEdit(Tokens, Node, InnerIsFunction, NewName, Arguments, InnerEdits) then
          Exit(Fail(Inner.Name + ' wird nicht nur aufgerufen', AReason));
        Continue;
      end;
      if TRoutineParts.Shadowed(Cache, Node, Outer, Node.Name, False) then
        Continue;
      // Eine Inline- oder Schleifenvariable gleichen Namens verdeckt die Routine.
      Found := TRoutineLocals.IndexOf(OuterLocals, Node.Name, Node.StartOffset);
      if (Found >= 0) and (OuterLocals[Found].Kind in [TRoutineLocalKind.InlineVariable,
        TRoutineLocalKind.LoopVariable]) then
        Continue;
      for Index := 0 to High(Captured) do
      begin
        if TRoutineParts.Shadowed(Cache, Node, Outer, Captured[Index].Local.Name, False) then
          Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
        Found := TRoutineLocals.IndexOf(OuterLocals, Captured[Index].Local.Name, Node.StartOffset);
        if (Found >= 0) and (OuterLocals[Found].Decl <> Captured[Index].Local.Decl) then
          Exit(Fail('ein Name verdeckt ' + Captured[Index].Local.Name, AReason));
      end;
      if not CallEdit(Tokens, Node, InnerIsFunction, NewName, Arguments, OuterEdits) then
        Exit(Fail(Inner.Name + ' wird nicht nur aufgerufen', AReason));
      Inc(Calls);
    end;
    // Kopf der neuen Routine.
    if not TRoutineParts.NameTokens(Tokens, Header, NameFirst, NameLast) then
      Exit(Fail('Kopf nicht lesbar', AReason));
    Name := NewName;
    if IsMethod then
      Name := ClassName + '.' + NewName;
    InnerEdits := InnerEdits + [TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
      TRoutineParts.HeadText(AText, Header, Name, Parameters, IsClass) + ConstLines)];
    Declaration := TRoutineParts.HeadText(AText, Header, NewName, Parameters, IsClass);
    // Eine statische Klassenmethode hat kein Self: die neue auch nicht.
    if IsClass then
      for Index := 0 to TypeBody.ChildCount - 1 do
        if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeBody[Index].Name,
          TRoutineBody.ShortNameOf(Outer.Name)) and TRoutineParts.HasWord(Tokens, TypeBody[Index], ['static']) then
        begin
          Declaration := Declaration + ' static;';
          Break;
        end;
    // Text: ganze Zeilen samt Kommentaren darüber, eingerückt wie die äußere Routine.
    FirstLine := TRoutineBody.RoutineInsertLine(AText, Inner);
    LastLine := Inner.EndPos.Line;
    TextLines := TTextLines.SplitLines(AText);
    Indent := TTextLines.IndentOf(AText, Outer.StartPos.Line);
    Moved := TRoutineParts.ApplyEdits(Copy(AText, Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)) + 1,
      Inner.EndOffset - Lines.OffsetAt(TTextPosition.Create(FirstLine, 0))),
      Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)), InnerEdits);
    Moved := TRoutineBody.Reindent(TrimLeft(Moved), InnerIndent, Indent, LineBreak);
    Edits := nil;
    // Entfernen, mit einer der Leerzeilen um die Routine.
    // Folgt dann begin, auch die Leerzeile davor.
    RemoveStart := FirstLine;
    RemoveEnd := LastLine + 1;
    if TRoutineParts.LineIsBlank(TextLines, FirstLine - 1) and TRoutineParts.LineIsBlank(TextLines, RemoveEnd) then
      Inc(RemoveEnd);
    if TRoutineParts.LineIsBlank(TextLines, RemoveStart - 1) and (RemoveEnd = TRoutineBody.BodyOf(Outer).StartPos.Line) then
      Dec(RemoveStart);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(RemoveStart, 0, RemoveEnd, 0), '')];
    for Index := 0 to High(OuterEdits) do
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Lines.PositionAt(OuterEdits[Index].Start),
        Lines.PositionAt(OuterEdits[Index].Stop)), OuterEdits[Index].Text)];
    if IsMethod then
    begin
      InsertLine := Outer.EndPos.Line + 1;
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
        LineBreak + Moved + LineBreak)];
      if not TRoutineBody.MemberDeclaration(AText, ATree, TypeBody, 'private', Declaration, AStyle, Edit) then
        Exit(Fail('Klassendeklaration nicht erweiterbar', AReason));
      Edits := Edits + [Edit];
    end
    else
    begin
      InsertLine := TRoutineBody.RoutineInsertLine(AText, Outer);
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(InsertLine, 0, InsertLine, 0),
        Moved + LineBreak + LineBreak)];
    end;
    AAction.Edits := Edits;
    AAction.Preview := Format('Neue Signatur: %s', [TRoutineParts.HeadText(AText, Header, Name, Parameters, IsClass)]) +
      LineBreak + Format('Geänderte Aufrufe: %d', [Calls]);
    Result := True;
  finally
    Identifiers.Free;
    Cache.Free;
  end;
end;

{ Umwandlung: Routine hinein }

function EmbedCore(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction; out AReason: string): Boolean;
var
  Lines: TLineTable;
  TextLines: TArray<string>;
  Tokens: TArray<TPascalToken>;
  Routine, Declaration, Header, TypeBody, Node, Reference, Caller, Call, CallerBody, Section, Child: TSyntaxNode;
  References, Identifiers, Arguments, Sections: TArray<TSyntaxNode>;
  Collected: TList<TSyntaxNode>;
  Cache: TLocalsCache;
  CallerLocals: TArray<TRoutineLocal>;
  Parameters, Kept: TArray<TParameterText>;
  Removed: TArray<Boolean>;
  Renamed: TDictionary<string, string>;
  Short, ClassName, LineBreak, Indent, Moved, Target, ArgumentText, ParameterType: string;
  IsMethod, IsClass, Recursive, Any: Boolean;
  Index, Found, FirstLine, RemoveEnd, BeginLine: Integer;
  RoutineEdits: TArray<TOffsetEdit>;
  Edits: TArray<TTextEdit>;
  Members: TArray<string>;
begin
  AAction := Default(TCodeAction);
  AReason := '';
  Result := False;
  if (ATree = nil) or (ATree.Root = nil) then
    Exit(Fail('kein Baum', AReason));
  Lines := TLineTable.Build(AText);
  Tokens := ATree.Tokens;
  Routine := TRoutineParts.TopRoutineAt(ATree, Lines.OffsetAt(APosition), Declaration);
  if (Routine = nil) or (Routine.Parent = nil) or (Routine.Parent.Kind <> TSyntaxKind.ImplementationSection) then
    Exit(Fail('keine Routine der Implementierung', AReason));
  Header := TRoutineParts.HeaderOf(Routine);
  if (Header = nil) or (TRoutineBody.BodyOf(Routine) = nil) then
    Exit(Fail('Routine ohne Rumpf', AReason));
  Short := TRoutineBody.ShortNameOf(Routine.Name);
  ClassName := TRoutineBody.QualifierOf(Routine.Name);
  IsMethod := ClassName <> '';
  IsClass := TRoutineParts.IsClassHeader(Tokens, Header);
  if TRoutineParts.HasWord(Tokens, Header, ['overload', 'forward', 'external', 'export', 'assembler']) or (Pos('<', ClassName) > 0) or
    (Pos('.', ClassName) > 0) then
    Exit(Fail('nicht unterstützte Form', AReason));
  TypeBody := nil;
  if IsMethod then
  begin
    TypeBody := TRoutineBody.TypeBody(ATree.Root, ClassName);
    if TypeBody = nil then
      Exit(Fail('Klasse ' + ClassName + ' nicht in der Datei', AReason));
    Declaration := nil;
    for Index := 0 to TypeBody.ChildCount - 1 do
      if (TypeBody[Index].Kind = TSyntaxKind.RoutineHeader) and SameText(TypeBody[Index].Name, Short) then
      begin
        if Declaration <> nil then
          Exit(Fail('überladen', AReason));
        Declaration := TypeBody[Index];
      end;
    if Declaration = nil then
      Exit(Fail('Deklaration fehlt', AReason));
    if not MatchText(TRoutineBody.VisibilityOf(TypeBody, Declaration), ['private', 'strict private']) then
      Exit(Fail('nicht privat', AReason));
    if TRoutineParts.HasWord(Tokens, Declaration, ['virtual', 'dynamic', 'override', 'abstract', 'message', 'overload',
      'reintroduce', 'final', 'static']) then
      Exit(Fail('virtuell, Botschaft oder überladen', AReason));
  end
  else
  begin
    // Im interface oder vorab deklariert: von außen bzw. vor der Implementierung sichtbar.
    Sections := [ATree.Root.FindChild(TSyntaxKind.InterfaceSection), Routine.Parent];
    for Section in Sections do
      if Section <> nil then
        for Index := 0 to Section.ChildCount - 1 do
        begin
          Child := Section[Index];
          if (Child <> Routine) and (Child.Kind in [TSyntaxKind.RoutineHeader, TSyntaxKind.RoutineDecl]) and
            SameText(Child.Name, Short) then
            Exit(Fail('auch anderswo deklariert', AReason));
        end;
  end;
  Cache := TLocalsCache.Create(AText, ATree);
  Collected := TList<TSyntaxNode>.Create;
  Renamed := TDictionary<string, string>.Create;
  try
    // Bezüge: genau ein Aufruf außerhalb der Routine.
    References := nil;
    Recursive := False;
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.Identifier, Collected);
    TRoutineLocals.CollectKind(ATree.Root, TSyntaxKind.MemberAccess, Collected);
    for Node in Collected do
    begin
      if not SameText(Node.Name, Short) then
        Continue;
      if Node.Kind = TSyntaxKind.MemberAccess then
      begin
        if not IsMethod or (Node[0].Kind <> TSyntaxKind.Identifier) or not SameText(Node[0].Name, 'Self') then
          Exit(Fail('über ein anderes Objekt benutzt', AReason));
      end
      else if TRoutineParts.Shadowed(Cache, Node, nil, Short, False) then
        Continue;
      if TRoutineBody.Within(Node, Routine) then
      begin
        Recursive := True;
        Continue;
      end;
      References := References + [Node];
    end;
    if Length(References) <> 1 then
      Exit(Fail('nicht genau ein Aufruf', AReason));
    Reference := References[0];
    Caller := Reference.Parent;
    while (Caller <> nil) and (Caller.Kind <> TSyntaxKind.RoutineDecl) do
      Caller := Caller.Parent;
    if (Caller = nil) or (Caller = Routine) or (Caller.Parent <> Routine.Parent) or
      not TRoutineBody.Within(Reference, TRoutineBody.BodyOf(Caller)) then
      Exit(Fail('Aufrufer ist keine Routine der Implementierung', AReason));
    if IsMethod and (not SameText(TRoutineBody.QualifierOf(Caller.Name), ClassName) or
      (TRoutineParts.IsClassHeader(Tokens, TRoutineParts.HeaderOf(Caller)) <> IsClass)) then
      Exit(Fail('Aufrufer ist keine Methode derselben Art', AReason));
    // Nur Aufrufe, kein Methodenzeiger oder Ereignis.
    Call := nil;
    Node := Reference.Parent;
    if (Node.Kind = TSyntaxKind.Call) and (Node[0] = Reference) then
      Call := Node
    else if (Node.Kind <> TSyntaxKind.CallStatement) and (not TRoutineParts.IsFunction(Routine) or
      (Node.Kind in [TSyntaxKind.AssignStatement, TSyntaxKind.Call, TSyntaxKind.AddressOf])) then
      Exit(Fail('nicht als Aufruf benutzt', AReason));
    Arguments := nil;
    if Call <> nil then
      for Index := 1 to Call.ChildCount - 1 do
        Arguments := Arguments + [Call[Index]];
    Parameters := TRoutineParts.ParameterTexts(AText, Header);
    if (Parameters = nil) and (Header.FindChild(TSyntaxKind.Parameters) <> nil) and
      (Header.FindChild(TSyntaxKind.Parameters).ChildCount > 0) then
      Exit(Fail('nicht unterstützte Parameter', AReason));
    SetLength(Removed, Length(Parameters));
    for Index := 0 to High(Removed) do
      Removed[Index] := False;
    Identifiers := nil;
    Collected.Clear;
    TRoutineLocals.CollectKind(TRoutineBody.BodyOf(Routine), TSyntaxKind.Identifier, Collected);
    Identifiers := Collected.ToArray;
    CallerLocals := Cache.Locals(Caller);
    // Durchgereichte Parameter: Argument ist eine Variable oder ein Parameter des Aufrufers mit demselben Typ.
    if ARemovePassThrough then
    begin
      if Recursive then
        Exit(Fail('rekursiv', AReason));
      Any := False;
      for Index := 0 to Min(High(Parameters), High(Arguments)) do
      begin
        if Arguments[Index].Kind <> TSyntaxKind.Identifier then
          Continue;
        Found := TRoutineLocals.IndexOf(CallerLocals, Arguments[Index].Name, Arguments[Index].StartOffset);
        if (Found < 0) or not (CallerLocals[Found].Kind in [TRoutineLocalKind.Parameter,
          TRoutineLocalKind.Variable]) then
          Continue;
        ParameterType := Trim(Copy(Parameters[Index].Rest, 2, MaxInt));
        if (ParameterType = '') or not SameText(ParameterType, CallerLocals[Found].TypeText) then
          Continue;
        Target := CallerLocals[Found].Name;
        if not SameText(Target, Parameters[Index].Name) and (Cache.Declares(Routine, Target, MaxInt) or
          UsesName(Identifiers, Target)) then
          Continue;
        if (Parameters[Index].Modifier = '') and WritesName(Cache, Identifiers, Routine, Parameters[Index].Name,
          ALookup.Flow) then
          Continue;
        Removed[Index] := True;
        Renamed.AddOrSetValue(LowerCase(Parameters[Index].Name), Target);
        Any := True;
      end;
      if not Any then
        Exit(Fail('keine durchgereichten Parameter', AReason));
    end;
    // Namen des Rumpfs, die der Aufrufer anders belegt, änderten ihre Bedeutung.
    CallerBody := TRoutineBody.BodyOf(Caller);
    if Cache.Declares(Caller, Short, CallerBody.StartOffset - 1) then
      Exit(Fail(Caller.Name + ' kennt schon ' + Short, AReason));
    Members := nil;
    if not IsMethod and (TRoutineBody.QualifierOf(Caller.Name) <> '') and (TRoutineBody.TypeBody(ATree.Root,
      TRoutineBody.QualifierOf(Caller.Name)) <> nil) then
      Members := TRoutineBody.MemberNames(TRoutineBody.TypeBody(ATree.Root, TRoutineBody.QualifierOf(Caller.Name)));
    for Node in Identifiers do
    begin
      if TRoutineParts.Shadowed(Cache, Node, Routine, Node.Name, True) then
        Continue;
      if Renamed.ContainsValue(Node.Name) then
        Continue;
      if Cache.Declares(Caller, Node.Name, CallerBody.StartOffset - 1) and not SameText(Node.Name, 'Result') then
        Exit(Fail(Caller.Name + ' verdeckt ' + Node.Name, AReason));
      if IndexText(Node.Name, Members) >= 0 then
        Exit(Fail('ein Mitglied der Klasse verdeckt ' + Node.Name, AReason));
    end;
    // Typangaben samt Kopf: ein lokaler Typ des Aufrufers verdeckte sie.
    Collected.Clear;
    TRoutineLocals.CollectKind(Routine, TSyntaxKind.TypeReference, Collected);
    for Node in Collected do
      if not TRoutineParts.Shadowed(Cache, Node, Routine, Node.Name, True) and Cache.Declares(Caller, Node.Name,
        CallerBody.StartOffset - 1) then
        Exit(Fail(Caller.Name + ' verdeckt ' + Node.Name, AReason));
    if SameText(Short, 'Result') then
      Exit(Fail('Name Result', AReason));
    // Rumpf: Kopf ohne Klasse, durchgereichte Parameter durch die Namen des Aufrufers ersetzt.
    Kept := nil;
    for Index := 0 to High(Parameters) do
      if not Removed[Index] then
        Kept := Kept + [Parameters[Index]];
    RoutineEdits := [TOffsetEdit.Create(Header.StartOffset, Header.EndOffset,
      TRoutineParts.HeadText(AText, Header, Short, Kept, False))];
    for Node in Identifiers do
      if Renamed.TryGetValue(LowerCase(Node.Name), Target) and not TRoutineParts.Shadowed(Cache, Node, Routine, Node.Name, False) and
        not SameText(Node.Name, Target) then
        RoutineEdits := RoutineEdits + [TOffsetEdit.Create(Node.StartOffset, Node.EndOffset, Target)];
    LineBreak := TTextLines.LineBreakOf(AText);
    TextLines := TTextLines.SplitLines(AText);
    FirstLine := TRoutineBody.RoutineInsertLine(AText, Routine);
    Moved := TRoutineParts.ApplyEdits(Copy(AText, Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)) + 1,
      Routine.EndOffset - Lines.OffsetAt(TTextPosition.Create(FirstLine, 0))),
      Lines.OffsetAt(TTextPosition.Create(FirstLine, 0)), RoutineEdits);
    Indent := TTextLines.IndentOf(AText, Caller.StartPos.Line) + TRoutineBody.IndentUnit(AStyle);
    Moved := TRoutineBody.Reindent(TrimLeft(Moved), TTextLines.IndentOf(AText, Routine.StartPos.Line), Indent,
      LineBreak);
    BeginLine := CallerBody.StartPos.Line;
    if CallerBody.StartPos.Character <> Length(TTextLines.IndentOf(AText, BeginLine)) then
      Exit(Fail('begin des Aufrufers steht nicht am Zeilenanfang', AReason));
    Edits := nil;
    RemoveEnd := Routine.EndPos.Line + 1;
    if TRoutineParts.LineIsBlank(TextLines, FirstLine - 1) and TRoutineParts.LineIsBlank(TextLines, RemoveEnd) then
      Inc(RemoveEnd);
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(FirstLine, 0, RemoveEnd, 0), '')];
    if Declaration <> nil then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Declaration.StartPos.Line, 0,
        Declaration.EndPos.Line + 1, 0), '')];
    if TRoutineParts.LineIsBlank(TextLines, BeginLine - 1) then
      Moved := Moved + LineBreak + LineBreak
    else
      Moved := LineBreak + Moved + LineBreak + LineBreak;
    Edits := Edits + [TTextEdit.Create(TTextRange.Create(BeginLine, 0, BeginLine, 0), Moved)];
    // Aufruf: Self. entfällt, durchgereichte Argumente auch.
    if Reference.Kind = TSyntaxKind.MemberAccess then
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Reference.StartPos, Reference.EndPos), Short)];
    if ARemovePassThrough then
    begin
      ArgumentText := '';
      for Index := 0 to High(Arguments) do
        if (Index > High(Removed)) or not Removed[Index] then
        begin
          if ArgumentText <> '' then
            ArgumentText := ArgumentText + ', ';
          ArgumentText := ArgumentText + TRoutineBody.TextOf(AText, Arguments[Index]);
        end;
      if ArgumentText <> '' then
        ArgumentText := '(' + ArgumentText + ')';
      Edits := Edits + [TTextEdit.Create(TTextRange.Create(Call[0].EndPos, Call.EndPos), ArgumentText)];
    end;
    if IsMethod then
      AAction.Title := TNestedRoutines.EmbedMethodTitle
    else
      AAction.Title := TNestedRoutines.EmbedRoutineTitle;
    if ARemovePassThrough then
      AAction.Title := AAction.Title + TNestedRoutines.PassThroughSuffix;
    AAction.Kind := RewriteKind;
    AAction.Edits := Edits;
    AAction.Preview := Format('Neue lokale Routine in %s: %s', [Caller.Name,
      TRoutineParts.HeadText(AText, Header, Short, Kept, False)]) + LineBreak + 'Geänderte Aufrufe: 1';
    Result := True;
  finally
    Renamed.Free;
    Collected.Free;
    Cache.Free;
  end;
end;

{ TNestedRoutines }

class function TNestedRoutines.Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := ExtractCore(AText, ATree, APosition, ALookup, AStyle, AAction, Reason);
end;

class function TNestedRoutines.Extract(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; out AAction: TCodeAction;
  out AReason: string): Boolean;
begin
  Result := ExtractCore(AText, ATree, APosition, ALookup, AStyle, AAction, AReason);
end;

class function TNestedRoutines.Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction; out AReason: string): Boolean;
begin
  Result := EmbedCore(AText, ATree, APosition, ALookup, AStyle, ARemovePassThrough, AAction, AReason);
end;

class function TNestedRoutines.Embed(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle; ARemovePassThrough: Boolean;
  out AAction: TCodeAction): Boolean;
var
  Reason: string;
begin
  Result := EmbedCore(AText, ATree, APosition, ALookup, AStyle, ARemovePassThrough, AAction, Reason);
end;

class function TNestedRoutines.Actions(const AText: string; ATree: TSyntaxTree; const APosition: TTextPosition;
  const ALookup: TNestedRoutineLookup; const AStyle: TFormatStyle): TArray<TCodeAction>;
var
  Action: TCodeAction;
begin
  Result := nil;
  if Extract(AText, ATree, APosition, ALookup, AStyle, Action) then
    Result := Result + [Action];
  if Embed(AText, ATree, APosition, ALookup, AStyle, False, Action) then
  begin
    Result := Result + [Action];
    if Embed(AText, ATree, APosition, ALookup, AStyle, True, Action) then
      Result := Result + [Action];
  end;
end;

end.
