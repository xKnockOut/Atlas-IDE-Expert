unit Atlas.Common.Rules.Builtin.Migration.Win64;

// Regeln für die Umstellung auf 64 Bit (#112, Gruppe „Migration“). Unter Win64 sind Zeiger, Objekte, Handles,
// WPARAM, LPARAM und LRESULT 8 Byte groß, Integer, LongInt, Cardinal und DWORD bleiben 4 Byte:
//   pointer-integer-cast
//                     Integer(P), Cardinal(Obj), LongInt(@X) … mit einem Zeiger, einem Objekt, einer
//                     Klassenreferenz oder einem Interface als Argument: Die obere Hälfte geht verloren.
//                     Umgekehrt TKunde(I) bzw. IKunde(I) mit I: Integer: I hat einen Zeiger in 32 Bit gehalten.
//                     Pointer(I) meldet die Regel nicht (Zahlen in Zeigerlisten sind gewollt und verlustfrei).
//                     Korrektur: NativeInt bzw. NativeUInt statt des 32-Bit-Typs.
//   handle-as-integer Parameter wParam bzw. lParam (auch AWParam, ALParam) mit einem 32-Bit-Typ und das
//                     32-Bit-Funktionsergebnis einer solchen Routine (Fensterprozedur; mit WPARAM bzw. NativeInt
//                     als Parametertyp bleibt das Ergebnis still): Korrektur WPARAM, LPARAM bzw.
//                     LRESULT. Zuweisung eines Handles, WPARAM, LPARAM oder LRESULT (Typ der Deklaration) an eine
//                     Variable mit 32-Bit-Typ; Funktionsergebnisse nur bei Handles (Count := SendMessage(…) bleibt
//                     still). Korrektur bei einer lokalen Variablen, die allein deklariert ist: den Typ der Quelle
//                     übernehmen.
//   window-long-ptr   SetWindowLong, GetWindowLong, SetClassLong, GetClassLong (auch …A/…W) mit einem Index, der
//                     einen Zeiger oder ein Handle liest bzw. schreibt (GWL_WNDPROC, GWL_USERDATA, GWL_HINSTANCE,
//                     GWL_HWNDPARENT, DWL_*, GCL_HICON …). Korrektur: …LongPtr samt GWLP_/DWLP_/GCLP_-Index,
//                     eine 32-Bit-Umwandlung des neuen Werts wird LONG_PTR.
//   asm-without-win64 asm-Block ohne Zweig nach Plattform ({$IFDEF CPUX86}, {$IFNDEF PUREPASCAL} …): dcc64
//                     übersetzt keinen x86-Assembler und kein asm innerhalb von begin … end (E1025). Routinen,
//                     deren asm 64-Bit-Register (rax, r8 …) verwendet, sind schon Win64-Code. Dateien für Free
//                     Pascal ({$MODE …}, {$ASMMODE …}) bleiben still.
// Alle vier melden nichts in inaktiven Zweigen und in Zweigen, deren Bedingung nach Plattform oder Zeigerbreite
// fragt (Migration.Shared), und nichts für Delphi-Versionen vor XE2. Typen gelten nur, wenn sie sicher aufgelöst
// sind und ihre Deklaration immer mit der Stelle übersetzt wird (TTypedScope.SureType).

interface

uses
  Atlas.Common.Rules.Contract;

const
  cPointerIntegerCastRuleId = 'pointer-integer-cast';
  cHandleAsIntegerRuleId = 'handle-as-integer';
  cWindowLongPtrRuleId = 'window-long-ptr';
  cAsmWithoutWin64RuleId = 'asm-without-win64';

type
  TPointerIntegerCastRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
  end;

  THandleAsIntegerRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Parametername einer Fensterprozedur: 'WPARAM' bei wParam/AWParam, 'LPARAM' bei lParam/ALParam,
    /// sonst ''.</summary>
    class function MessageParamType(const AName: string): string; static;
  end;

  TWindowLongPtrRule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Index für …LongPtr zu AIndex (GWL_WNDPROC → GWLP_WNDPROC); '' für Indizes mit 32-Bit-Werten.
    /// </summary>
    class function PtrIndex(const AIndex: string): string; static;
    /// <summary>Name der …LongPtr-Funktion zu ARoutine (SetWindowLongW → SetWindowLongPtrW); '' sonst.</summary>
    class function PtrRoutine(const ARoutine: string): string; static;
  end;

  TAsmWithoutWin64Rule = class(TInterfacedObject, IRule)
  public
    function Descriptor: TRuleDescriptor;
    procedure Check(const AContext: TRuleContext; const AReport: IRuleReport);
    /// <summary>Register nur unter x64 (rax, r8, r10d …)?</summary>
    class function Is64BitRegister(const AName: string): Boolean; static;
  end;

implementation

uses
  System.SysUtils,
  System.StrUtils,
  System.Generics.Collections,
  Atlas.Common.Documents.Contract,
  Atlas.Common.Configuration.Contract,
  Atlas.Common.Pascal.Contract,
  Atlas.Common.Pascal.SyntaxTree,
  Atlas.Common.Pascal.Lexer,
  Atlas.Common.Index.Contract,
  Atlas.Common.Semantics.NameResolver,
  Atlas.Common.Rules.TypedScope,
  Atlas.Common.Rules.Builtin.Migration.Shared,
  Atlas.Common.Localization.Texts;

{$SCOPEDENUMS ON}

type
  /// <summary>Texte der Befundmeldungen in beiden Sprachen (#1458).</summary>
  TMigrationWin64Text = (CastTitle, CastTruncates, CastStored, UseNative, HandleTitle, ParamTruncates,
    ResultTruncates, AssignTruncates, UseType, DeclareAs, LongTitle, LongTruncates, UseLongPtr, AsmTitle,
    AsmRoutine, AsmStatement);

const
  cTexts: array[TMigrationWin64Text] of TAtlasText = (
    (De: 'Zeiger in einer 32-Bit-Zahl'; En: 'Pointer in a 32-bit integer'),
    (De: '%s(%s): %s ist %s; unter Win64 gehen die oberen 32 Bit verloren.';
     En: '%s(%s): %s is %s; under Win64 the upper 32 bits are lost.'),
    (De: '%s(%s): %s ist %s und kann unter Win64 keinen Zeiger halten.';
     En: '%s(%s): %s is %s and cannot hold a pointer under Win64.'),
    (De: '%s statt %s verwenden'; En: 'Use %s instead of %s'),
    (De: 'Handle oder Nachrichtenparameter in einer 32-Bit-Zahl';
     En: 'Handle or message parameter in a 32-bit integer'),
    (De: 'Parameter %s ist %s; unter Win64 ist %s 64 Bit breit.';
     En: 'Parameter %s is %s; under Win64 %s is 64 bits wide.'),
    (De: 'Ergebnis von %s ist %s; unter Win64 ist LRESULT 64 Bit breit.';
     En: 'Result of %s is %s; under Win64 LRESULT is 64 bits wide.'),
    (De: '%s ist %s, %s ist %s; unter Win64 gehen die oberen 32 Bit verloren.';
     En: '%s is %s, %s is %s; under Win64 the upper 32 bits are lost.'),
    (De: 'Typ %s verwenden'; En: 'Use type %s'),
    (De: '%s als %s deklarieren'; En: 'Declare %s as %s'),
    (De: '%s statt %s für Zeiger und Handles'; En: '%s instead of %s for pointers and handles'),
    (De: '%s mit %s liest bzw. schreibt unter Win64 nur 32 Bit eines Zeigers oder Handles.';
     En: '%s with %s reads or writes only 32 bits of a pointer or handle under Win64.'),
    (De: '%s mit %s verwenden'; En: 'Use %s with %s'),
    (De: 'Assembler ohne Win64-Variante'; En: 'Assembler without Win64 variant'),
    (De: 'Routine %s besteht aus x86-Assembler ohne Zweig für Win64 ({$IFDEF CPUX64} bzw. PUREPASCAL).';
     En: 'Routine %s consists of x86 assembler without a branch for Win64 ({$IFDEF CPUX64} or PUREPASCAL).'),
    (De: 'asm innerhalb von begin … end übersetzt dcc64 nicht (E1025); ein Zweig nach Plattform fehlt.';
     En: 'dcc64 does not compile asm inside begin … end (E1025); a branch by platform is missing.'));

{$SCOPEDENUMS OFF}

type
  TLongIndex = record
    Name: string;
    PtrName: string;
  end;

const
  cLongIndices: array[0..13] of TLongIndex = (
    (Name: 'GWL_WNDPROC'; PtrName: 'GWLP_WNDPROC'), (Name: 'GWL_HINSTANCE'; PtrName: 'GWLP_HINSTANCE'),
    (Name: 'GWL_HWNDPARENT'; PtrName: 'GWLP_HWNDPARENT'), (Name: 'GWL_USERDATA'; PtrName: 'GWLP_USERDATA'),
    (Name: 'DWL_MSGRESULT'; PtrName: 'DWLP_MSGRESULT'), (Name: 'DWL_DLGPROC'; PtrName: 'DWLP_DLGPROC'),
    (Name: 'DWL_USER'; PtrName: 'DWLP_USER'), (Name: 'GCL_MENUNAME'; PtrName: 'GCLP_MENUNAME'),
    (Name: 'GCL_HBRBACKGROUND'; PtrName: 'GCLP_HBRBACKGROUND'), (Name: 'GCL_HCURSOR'; PtrName: 'GCLP_HCURSOR'),
    (Name: 'GCL_HICON'; PtrName: 'GCLP_HICON'), (Name: 'GCL_HMODULE'; PtrName: 'GCLP_HMODULE'),
    (Name: 'GCL_WNDPROC'; PtrName: 'GCLP_WNDPROC'), (Name: 'GCL_HICONSM'; PtrName: 'GCLP_HICONSM'));

function NodeRange(ANode: TSyntaxNode): TTextRange;
begin
  Result := TTextRange.Create(ANode.StartPos, ANode.EndPos);
end;

/// <summary>Alle Knoten unter ARoot der Art AKind, in Quelltextreihenfolge, ohne Rekursion.</summary>
function NodesOf(ARoot: TSyntaxNode; AKind: TSyntaxKind): TArray<TSyntaxNode>;
var
  mPending: TStack<TSyntaxNode>;
  mNode: TSyntaxNode;
  mIndex: Integer;
begin
  Result := nil;
  mPending := TStack<TSyntaxNode>.Create;
  try
    mPending.Push(ARoot);
    while mPending.Count > 0 do
    begin
      mNode := mPending.Pop;
      if mNode.Kind = AKind then
      begin
        Result := Result + [mNode];
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

/// <summary>Aufruf F(X) mit einem einfachen Bezeichner F und genau einem Argument?</summary>
function IsSingleCast(ANode: TSyntaxNode): Boolean;
begin
  Result := (ANode.Kind = TSyntaxKind.Call) and (ANode.ChildCount = 2) and
    (ANode[0].Kind = TSyntaxKind.Identifier);
end;

/// <summary>Bestimmt der Ausdruck ANode ohne Typauflösung einen Zeiger: @X, Pointer(X), PChar(X) …?</summary>
function SyntacticPointer(ANode: TSyntaxNode; out ATypeName: string): Boolean;
begin
  Result := False;
  if ANode.Kind = TSyntaxKind.AddressOf then
  begin
    ATypeName := 'Pointer';
    Result := True;
  end
  else if IsSingleCast(ANode) and MatchText(ANode.Name, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar', 'PByte']) then
  begin
    ATypeName := ANode.Name;
    Result := True;
  end;
end;

/// <summary>Typ eines Zeigers, Objekts, einer Klassenreferenz oder eines Interfaces (aufgelöst)?</summary>
function IsPointerType(const ASymbol, AType: TResolvedSymbol): Boolean;
begin
  Result := (AType.Builtin and MatchText(AType.Name, ['Pointer', 'PChar', 'PAnsiChar', 'PWideChar'])) or
    (AType.SymbolKind in [TIndexSymbolKind.ClassType, TIndexSymbolKind.InterfaceType]) or
    StartsStr('^', Trim(ASymbol.TypeName));
end;

{ TPointerIntegerCastRule }

function TPointerIntegerCastRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cPointerIntegerCastRuleId, TRuleSeverity.Warning,
    cTexts[TMigrationWin64Text.CastTitle].Text);
end;

procedure TPointerIntegerCastRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMigration: TMigrationScope;

  procedure CheckToInteger(ANode, AArgument: TSyntaxNode);
  var
    mSymbol, mType: TResolvedSymbol;
    mTypeName, mNative: string;
  begin
    if not SyntacticPointer(AArgument, mTypeName) then
    begin
      if not mScope.SureType(AArgument, mSymbol, mType) or not IsPointerType(mSymbol, mType) then
      begin
        Exit;
      end;
      mTypeName := mType.Name;
      if StartsStr('^', Trim(mSymbol.TypeName)) then
      begin
        mTypeName := Trim(mSymbol.TypeName);
      end;
    end;
    if TMigrationTypes.IsUnsigned32(ANode.Name) then
    begin
      mNative := 'NativeUInt';
    end
    else
    begin
      mNative := 'NativeInt';
    end;
    AReport.Add(NodeRange(ANode), cTexts[TMigrationWin64Text.CastTruncates].Fmt([ANode.Name, mScope.Text(AArgument),
      mScope.Text(AArgument), mTypeName]), TRuleConfidence.High,
      [TRuleFix.Create(cTexts[TMigrationWin64Text.UseNative].Fmt([mNative, ANode.Name]),
      [TTextEdit.Create(NodeRange(ANode[0]), mNative)])]);
  end;

  procedure CheckFromInteger(ANode, AArgument: TSyntaxNode);
  var
    mTarget, mSymbol, mType: TResolvedSymbol;
  begin
    mTarget := mScope.Resolver.Resolve(AContext.Tree, mScope.FileName, ANode[0].StartPos);
    if not mTarget.Found or not mTarget.IsType or not (mTarget.SymbolKind in [TIndexSymbolKind.ClassType,
      TIndexSymbolKind.InterfaceType]) or not mScope.DeclarationSure(mTarget, ANode) then
    begin
      Exit;
    end;
    if mScope.SureType(AArgument, mSymbol, mType) and mType.Builtin and
      TMigrationTypes.Is32BitInteger(mType.Name) then
    begin
      AReport.Add(NodeRange(ANode), cTexts[TMigrationWin64Text.CastStored].Fmt([ANode.Name, mScope.Text(AArgument),
        mScope.Text(AArgument), mType.Name]), TRuleConfidence.High);
    end;
  end;

var
  mNode, mArgument: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not TMigrationTypes.Win64Available(AContext.DelphiVersion) then
  begin
    Exit;
  end;
  mMigration := TMigrationScope.Create(AContext);
  mScope := TTypedScope.Create(AContext);
  try
    for mNode in NodesOf(AContext.Tree.Root, TSyntaxKind.Call) do
    begin
      if not IsSingleCast(mNode) or not mMigration.Reportable(mNode.StartPos) then
      begin
        Continue;
      end;
      mArgument := Unwrapped(mNode[1]);
      if TMigrationTypes.Is32BitInteger(mNode.Name) then
      begin
        CheckToInteger(mNode, mArgument);
      end
      else
      begin
        CheckFromInteger(mNode, mArgument);
      end;
    end;
  finally
    mScope.Free;
    mMigration.Free;
  end;
end;

{ THandleAsIntegerRule }

function THandleAsIntegerRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cHandleAsIntegerRuleId, TRuleSeverity.Warning,
    cTexts[TMigrationWin64Text.HandleTitle].Text);
end;

class function THandleAsIntegerRule.MessageParamType(const AName: string): string;
begin
  Result := '';
  if MatchText(AName, ['wParam', 'AWParam']) then
  begin
    Result := 'WPARAM';
  end
  else if MatchText(AName, ['lParam', 'ALParam']) then
  begin
    Result := 'LPARAM';
  end;
end;

procedure THandleAsIntegerRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mScope: TTypedScope;
  mMigration: TMigrationScope;
  mTokens: TArray<TPascalToken>;

  function TypeOfParameter(AParameter: TSyntaxNode): TSyntaxNode;
  begin
    Result := AParameter.FindChild(TSyntaxKind.TypeReference);
  end;

  /// <summary>Prüft die Parameter eines Routinenkopfs; True, wenn einer wParam oder lParam heißt und einen
  /// 32-Bit-Typ hat (alte Fensterprozedur).</summary>
  function CheckParameters(AHeader: TSyntaxNode): Boolean;
  var
    mParameters, mParameter, mType: TSyntaxNode;
    mIndex: Integer;
    mName, mWanted: string;
  begin
    Result := False;
    mParameters := AHeader.FindChild(TSyntaxKind.Parameters);
    if mParameters = nil then
    begin
      Exit;
    end;
    for mIndex := 0 to mParameters.ChildCount - 1 do
    begin
      mParameter := mParameters[mIndex];
      for mName in mParameter.Name.Split([',']) do
      begin
        mWanted := MessageParamType(Trim(mName));
        mType := TypeOfParameter(mParameter);
        Result := Result or ((mWanted <> '') and (mType <> nil) and TMigrationTypes.Is32BitInteger(mType.Name));
        // Nur "wParam: Longint", nicht "wParam, lParam: Longint" (die Korrektur träfe beide).
        if (mWanted <> '') and (mType <> nil) and not ContainsStr(mParameter.Name, ',') and
          TMigrationTypes.Is32BitInteger(mType.Name) and mMigration.Reportable(mParameter.StartPos) then
        begin
          AReport.Add(NodeRange(mType), cTexts[TMigrationWin64Text.ParamTruncates].Fmt([Trim(mName), mType.Name,
            mWanted]), TRuleConfidence.High, [TRuleFix.Create(cTexts[TMigrationWin64Text.UseType].Fmt([mWanted]),
            [TTextEdit.Create(NodeRange(mType), mWanted)])]);
        end;
      end;
    end;
  end;

  procedure CheckHeader(AHeader: TSyntaxNode);
  var
    mResult: TSyntaxNode;
  begin
    if not CheckParameters(AHeader) then
    begin
      Exit;
    end;
    mResult := AHeader.FindChild(TSyntaxKind.TypeReference);
    if (mResult <> nil) and TMigrationTypes.Is32BitInteger(mResult.Name) and
      mMigration.Reportable(mResult.StartPos) then
    begin
      AReport.Add(NodeRange(mResult), cTexts[TMigrationWin64Text.ResultTruncates].Fmt([AHeader.Name,
        mResult.Name]), TRuleConfidence.High, [TRuleFix.Create(cTexts[TMigrationWin64Text.UseType].Fmt(['LRESULT']),
        [TTextEdit.Create(NodeRange(mResult), 'LRESULT')])]);
    end;
  end;

  function NextToken(AIndex: Integer): Integer;
  begin
    Result := AIndex;
    while (Result <= High(mTokens)) and (mTokens[Result].Kind = TPascalTokenKind.Comment) do
    begin
      Inc(Result);
    end;
  end;

  /// <summary>Korrektur „X als T deklarieren“ für eine lokale Variable dieser Datei, die allein mit "X: Typ;"
  /// deklariert ist.</summary>
  function DeclarationFix(const ASymbol: TResolvedSymbol; const ATypeName: string; out AFix: TRuleFix): Boolean;
  var
    mIndex, mNext: Integer;
  begin
    Result := False;
    if ASymbol.IsParameter or (ASymbol.SymbolKind <> TIndexSymbolKind.Variable) or
      (ASymbol.Kind <> TResolvedKind.Local) then
    begin
      Exit;
    end;
    mIndex := mMigration.TokenAt(ASymbol.SelectionRange.StartPos);
    if (mIndex > High(mTokens)) or not SameText(mTokens[mIndex].Text, ASymbol.Name) or
      ((mIndex > 0) and (mTokens[mIndex - 1].Text = ',')) then
    begin
      Exit;
    end;
    mIndex := NextToken(mIndex + 1);
    if (mIndex > High(mTokens)) or (mTokens[mIndex].Text <> ':') then
    begin
      Exit;
    end;
    mIndex := NextToken(mIndex + 1);
    if (mIndex > High(mTokens)) or (mTokens[mIndex].Kind <> TPascalTokenKind.Identifier) then
    begin
      Exit;
    end;
    mNext := NextToken(mIndex + 1);
    if (mNext > High(mTokens)) or (mTokens[mNext].Text <> ';') then
    begin
      Exit;
    end;
    AFix := TRuleFix.Create(cTexts[TMigrationWin64Text.DeclareAs].Fmt([ASymbol.Name, ATypeName]),
      [TTextEdit.Create(TTextRange.Create(mTokens[mIndex].StartPos, mTokens[mIndex].EndPos), ATypeName)]);
    Result := True;
  end;

  procedure CheckAssignment(ANode: TSyntaxNode);
  var
    mTarget, mTargetType, mSource, mSourceType: TResolvedSymbol;
    mTypeFound: Boolean;
    mSourceNode: TSyntaxNode;
    mFix: TRuleFix;
    mFixes: TArray<TRuleFix>;
  begin
    if (ANode.ChildCount < 2) or not mMigration.Reportable(ANode.StartPos) then
    begin
      Exit;
    end;
    mSourceNode := Unwrapped(ANode[1]);
    if not (mSourceNode.Kind in [TSyntaxKind.Identifier, TSyntaxKind.MemberAccess, TSyntaxKind.Call]) or
      not mScope.SureType(ANode[0], mTarget, mTargetType) or not mTargetType.Builtin or
      not TMigrationTypes.Is32BitInteger(mTargetType.Name) then
    begin
      Exit;
    end;
    // Die Quelle über den deklarierten Typnamen: HWND, WPARAM … sind ohne Winapi-Quelltext nicht aufgelöst.
    if not mScope.Resolver.NodeType(AContext.Tree, mScope.FileName, mSourceNode, mSource, mSourceType,
      mTypeFound) or not mScope.DeclarationSure(mSource, mSourceNode) or
      not TMigrationTypes.IsPointerSizedAlias(Trim(mSource.TypeName)) then
    begin
      Exit;
    end;
    // Count := SendMessage(…): Ergebnisse von Nachrichten sind meist kleine Zahlen; gemeldet werden bei Aufrufen
    // nur Handles.
    if (mSource.SymbolKind in [TIndexSymbolKind.Routine, TIndexSymbolKind.Method]) and
      MatchText(Trim(mSource.TypeName), ['LRESULT', 'WPARAM', 'LPARAM']) then
    begin
      Exit;
    end;
    mFixes := nil;
    if DeclarationFix(mTarget, Trim(mSource.TypeName), mFix) then
    begin
      mFixes := [mFix];
    end;
    AReport.Add(NodeRange(ANode), cTexts[TMigrationWin64Text.AssignTruncates].Fmt([mScope.Text(ANode[0]),
      mTargetType.Name, mScope.Text(mSourceNode), Trim(mSource.TypeName)]), TRuleConfidence.High, mFixes);
  end;

var
  mNode: TSyntaxNode;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not TMigrationTypes.Win64Available(AContext.DelphiVersion) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  mMigration := TMigrationScope.Create(AContext);
  mScope := TTypedScope.Create(AContext);
  try
    for mNode in NodesOf(AContext.Tree.Root, TSyntaxKind.RoutineHeader) do
    begin
      CheckHeader(mNode);
    end;
    for mNode in NodesOf(AContext.Tree.Root, TSyntaxKind.AssignStatement) do
    begin
      CheckAssignment(mNode);
    end;
  finally
    mScope.Free;
    mMigration.Free;
  end;
end;

{ TWindowLongPtrRule }

function TWindowLongPtrRule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cWindowLongPtrRuleId, TRuleSeverity.Warning,
    cTexts[TMigrationWin64Text.LongTitle].Fmt(['…LongPtr', '…Long']));
end;

class function TWindowLongPtrRule.PtrIndex(const AIndex: string): string;
var
  mEntry: TLongIndex;
begin
  Result := '';
  for mEntry in cLongIndices do
  begin
    if SameText(mEntry.Name, AIndex) then
    begin
      Exit(mEntry.PtrName);
    end;
  end;
end;

class function TWindowLongPtrRule.PtrRoutine(const ARoutine: string): string;
var
  mBase, mSuffix: string;
begin
  Result := '';
  mBase := ARoutine;
  mSuffix := '';
  if EndsText('A', mBase) or EndsText('W', mBase) then
  begin
    mSuffix := Copy(mBase, Length(mBase), 1);
    mBase := Copy(mBase, 1, Length(mBase) - 1);
  end;
  if MatchText(mBase, ['SetWindowLong', 'GetWindowLong', 'SetClassLong', 'GetClassLong']) then
  begin
    Result := mBase + 'Ptr' + mSuffix;
  end;
end;

procedure TWindowLongPtrRule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMigration: TMigrationScope;
  mNode, mIndexNode, mValue: TSyntaxNode;
  mRoutine, mIndex: string;
  mEdits: TArray<TTextEdit>;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not TMigrationTypes.Win64Available(AContext.DelphiVersion) then
  begin
    Exit;
  end;
  mMigration := TMigrationScope.Create(AContext);
  try
    for mNode in NodesOf(AContext.Tree.Root, TSyntaxKind.Call) do
    begin
      // F(Handle, Index[, Wert]): Callee und zwei bzw. drei Argumente.
      if (mNode[0].Kind <> TSyntaxKind.Identifier) or (mNode.ChildCount < 3) or
        not mMigration.Reportable(mNode.StartPos) then
      begin
        Continue;
      end;
      mRoutine := PtrRoutine(mNode.Name);
      mIndexNode := Unwrapped(mNode[2]);
      if (mRoutine = '') or (mIndexNode.Kind <> TSyntaxKind.Identifier) then
      begin
        Continue;
      end;
      mIndex := PtrIndex(mIndexNode.Name);
      if mIndex = '' then
      begin
        Continue;
      end;
      mEdits := [TTextEdit.Create(NodeRange(mNode[0]), mRoutine), TTextEdit.Create(NodeRange(mIndexNode), mIndex)];
      if mNode.ChildCount > 3 then
      begin
        mValue := Unwrapped(mNode[3]);
        if IsSingleCast(mValue) and TMigrationTypes.Is32BitInteger(mValue.Name) then
        begin
          mEdits := mEdits + [TTextEdit.Create(NodeRange(mValue[0]), 'LONG_PTR')];
        end;
      end;
      AReport.Add(NodeRange(mNode), cTexts[TMigrationWin64Text.LongTruncates].Fmt([mNode.Name, mIndexNode.Name]),
        TRuleConfidence.High, [TRuleFix.Create(cTexts[TMigrationWin64Text.UseLongPtr].Fmt([mRoutine, mIndex]),
        mEdits)]);
    end;
  finally
    mMigration.Free;
  end;
end;

{ TAsmWithoutWin64Rule }

function TAsmWithoutWin64Rule.Descriptor: TRuleDescriptor;
begin
  Result := TRuleDescriptor.Create(cAsmWithoutWin64RuleId, TRuleSeverity.Warning,
    cTexts[TMigrationWin64Text.AsmTitle].Text);
end;

class function TAsmWithoutWin64Rule.Is64BitRegister(const AName: string): Boolean;
var
  mName: string;
  mNumber: Integer;
begin
  mName := LowerCase(AName);
  Result := MatchStr(mName, ['rax', 'rbx', 'rcx', 'rdx', 'rsi', 'rdi', 'rbp', 'rsp', 'rip']);
  if not Result and (Length(mName) >= 2) and (mName[1] = 'r') then
  begin
    // r8 … r15, auch r8d, r8w, r8b
    mName := Copy(mName, 2, MaxInt);
    if (mName <> '') and CharInSet(mName[Length(mName)], ['d', 'w', 'b']) then
    begin
      mName := Copy(mName, 1, Length(mName) - 1);
    end;
    Result := TryStrToInt(mName, mNumber) and (mNumber >= 8) and (mNumber <= 15);
  end;
end;

procedure TAsmWithoutWin64Rule.Check(const AContext: TRuleContext; const AReport: IRuleReport);
var
  mMigration: TMigrationScope;
  mTokens: TArray<TPascalToken>;

  /// <summary>Datei für Free Pascal ({$MODE …} bzw. {$ASMMODE …})?</summary>
  function FreePascalFile: Boolean;
  var
    mToken: TPascalToken;
  begin
    Result := False;
    for mToken in mTokens do
    begin
      if (mToken.Kind = TPascalTokenKind.Directive) and
        MatchStr(TPascalLexer.DirectiveName(mToken.Text), ['MODE', 'ASMMODE']) then
      begin
        Exit(True);
      end;
    end;
  end;

  /// <summary>Verwendet der Block ANode Register, die es nur unter x64 gibt?</summary>
  function Uses64BitRegisters(ANode: TSyntaxNode): Boolean;
  var
    mIndex: Integer;
  begin
    Result := False;
    mIndex := mMigration.TokenAt(ANode.StartPos);
    while (mIndex <= High(mTokens)) and (ANode.EndOffset > mTokens[mIndex].Offset) do
    begin
      if (mTokens[mIndex].Kind = TPascalTokenKind.Identifier) and Is64BitRegister(mTokens[mIndex].Text) then
      begin
        Exit(True);
      end;
      Inc(mIndex);
    end;
  end;

var
  mNode: TSyntaxNode;
  mRoutine: Boolean;
begin
  if (AContext.Tree = nil) or (AContext.Tree.Root = nil) or
    not TMigrationTypes.Win64Available(AContext.DelphiVersion) then
  begin
    Exit;
  end;
  mTokens := AContext.Tree.Tokens;
  if FreePascalFile then
  begin
    Exit;
  end;
  mMigration := TMigrationScope.Create(AContext);
  try
    for mNode in NodesOf(AContext.Tree.Root, TSyntaxKind.AsmBlock) do
    begin
      mRoutine := (mNode.Parent <> nil) and (mNode.Parent.Kind = TSyntaxKind.RoutineDecl);
      if not mMigration.Reportable(mNode.StartPos) or (mRoutine and Uses64BitRegisters(mNode)) then
      begin
        Continue;
      end;
      if mRoutine then
      begin
        AReport.Add(TTextRange.Create(mNode.StartPos, TTextPosition.Create(mNode.StartPos.Line,
          mNode.StartPos.Character + 3)), cTexts[TMigrationWin64Text.AsmRoutine].Fmt([mNode.Parent.Name]),
          TRuleConfidence.High);
      end
      else
      begin
        AReport.Add(TTextRange.Create(mNode.StartPos, TTextPosition.Create(mNode.StartPos.Line,
          mNode.StartPos.Character + 3)), cTexts[TMigrationWin64Text.AsmStatement].Text, TRuleConfidence.High);
      end;
    end;
  finally
    mMigration.Free;
  end;
end;

initialization
  TAtlasTextTables.Add('Atlas.Common.Rules.Builtin.Migration.Win64', cTexts);

end.
